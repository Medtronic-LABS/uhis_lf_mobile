import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_state.dart';
import '../../features/training/coaching_repository.dart';
import '../../features/visit/assessment_repository.dart';
import 'offline_sync_service.dart';

const _retryDelay = Duration(seconds: 30);

/// Monitors network connectivity and automatically triggers offline sync
/// when connectivity is restored, matching Android's `ScheduledSyncWork`
/// behaviour (WorkManager with `NetworkType.CONNECTED` constraint).
///
/// Wiring:
/// 1. [start] in `_UhisNextAppState.initState`.
/// 2. [dispose] in `_UhisNextAppState.dispose`.
///
/// The service is intentionally simple:
/// - When the device moves from *offline → online*, it fires both the outbound
///   assessment push (`offline-sync/create`) and the inbound warm pull
///   (`offline-sync/fetch-synced-data`), then refreshes micro-coaching modules.
/// - It checks [AuthState.status] before touching the network; sync never
///   runs when the user is logged out or the session is locked.
/// - Failures are swallowed and logged — the next connectivity event will retry.
class SyncConnectivityService {
  SyncConnectivityService({
    required AssessmentRepository assessmentRepo,
    required OfflineSyncService syncService,
    required AuthState authState,
    required CoachingRepository coachingRepo,
  })  : _assessmentRepo = assessmentRepo,
        _syncService = syncService,
        _authState = authState,
        _coachingRepo = coachingRepo;

  final AssessmentRepository _assessmentRepo;
  final OfflineSyncService _syncService;
  final AuthState _authState;
  final CoachingRepository _coachingRepo;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  bool _wasOffline = false;

  /// Begin listening. Safe to call multiple times (idempotent after first call).
  void start() {
    _subscription ??= Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
    // Probe current connectivity. Without this, assessments saved while the
    // app was offline (or from a prior session) never auto-push when the app
    // opens already online — `_wasOffline` stays false until an offline→online
    // transition is observed in *this* process.
    unawaited(_probeAndSyncIfNeeded());
    debugPrint('[SyncConnectivity] Connectivity monitoring started');
  }

  Future<void> _probeAndSyncIfNeeded() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (!isOnline) {
        _wasOffline = true;
        debugPrint(
            '[SyncConnectivity] Started offline — will sync when reconnected');
        return;
      }
      debugPrint(
          '[SyncConnectivity] Started online — pushing any pending assessments');
      _triggerSync();
    } catch (e) {
      debugPrint('[SyncConnectivity] Initial connectivity probe failed: $e');
    }
  }

  /// Stop listening. Called from widget dispose.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    debugPrint('[SyncConnectivity] Connectivity monitoring stopped');
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);

    if (!isOnline) {
      _wasOffline = true;
      debugPrint('[SyncConnectivity] Offline — pending assessments will sync when reconnected');
      return;
    }

    // Connectivity restored after being offline — trigger sync.
    if (_wasOffline) {
      _wasOffline = false;
      _retryTimer?.cancel();
      _retryTimer = null;
      debugPrint('[SyncConnectivity] Connectivity restored — triggering automatic sync');
      _triggerSync();
    }
  }

  void _triggerSync() {
    // Only sync when the user has an active authenticated session.
    if (_authState.status != AuthStatus.signedIn || _authState.locked) {
      debugPrint('[SyncConnectivity] Skipping auto-sync — not signed-in or session locked');
      return;
    }

    // Push pending assessments first (outbound), then pull fresh data (inbound),
    // then refresh micro-coaching. Fire-and-forget; errors are logged.
    _assessmentRepo
        .syncPendingAssessments(syncMode: 'AutomaticSync')
        .then((n) {
          if (n > 0) {
            debugPrint('[SyncConnectivity] AutomaticSync pushed $n assessment(s)');
          }
          // Warm pull after push so the worklist refreshes with any server updates.
          return _syncService.warmSync();
        })
        .then((_) {
          debugPrint('[SyncConnectivity] AutomaticSync warm pull complete');
          return _coachingRepo.refresh();
        })
        .then((_) => debugPrint('[SyncConnectivity] Coaching refresh complete'))
        .catchError((Object e) {
          debugPrint('[SyncConnectivity] AutomaticSync error — scheduling retry in ${_retryDelay.inSeconds}s: $e');
          _retryTimer?.cancel();
          _retryTimer = Timer(_retryDelay, () {
            _retryTimer = null;
            debugPrint('[SyncConnectivity] Retrying sync after network error');
            _triggerSync();
          });
        });
  }
}
