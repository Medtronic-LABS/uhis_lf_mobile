import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_state.dart';
import '../../features/visit/assessment_repository.dart';
import 'offline_sync_service.dart';

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
///   (`offline-sync/fetch-synced-data`).
/// - It checks [AuthState.status] before touching the network; sync never
///   runs when the user is logged out or the session is locked.
/// - Failures are swallowed and logged — the next connectivity event will retry.
class SyncConnectivityService {
  SyncConnectivityService({
    required AssessmentRepository assessmentRepo,
    required OfflineSyncService syncService,
    required AuthState authState,
  })  : _assessmentRepo = assessmentRepo,
        _syncService = syncService,
        _authState = authState;

  final AssessmentRepository _assessmentRepo;
  final OfflineSyncService _syncService;
  final AuthState _authState;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _wasOffline = false;

  /// Begin listening. Safe to call multiple times (idempotent after first call).
  void start() {
    _subscription ??= Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
    debugPrint('[SyncConnectivity] Connectivity monitoring started');
  }

  /// Stop listening. Called from widget dispose.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
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

    // Push pending assessments first (outbound), then pull fresh data (inbound).
    // Both are fire-and-forget; errors are logged but not propagated.
    _assessmentRepo
        .syncPendingAssessments(syncMode: 'AutomaticSync')
        .then((n) {
          if (n > 0) {
            debugPrint('[SyncConnectivity] AutomaticSync pushed $n assessment(s)');
          }
          // Warm pull after push so the worklist refreshes with any server updates.
          return _syncService.warmSync();
        })
        .then((_) => debugPrint('[SyncConnectivity] AutomaticSync warm pull complete'))
        .catchError((Object e) {
          debugPrint('[SyncConnectivity] AutomaticSync error (will retry on next connectivity): $e');
        });
  }
}
