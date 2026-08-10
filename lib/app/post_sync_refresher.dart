import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/sync/sync_progress.dart';
import '../features/dashboard/mission_dashboard_repository.dart';
import '../features/referral/referral_repository.dart';
import '../features/worklist/worklist_repository.dart';

/// Recomputes derived data and refreshes the dashboard when a sync finishes.
///
/// A sync writes rows; it does not recompute what the worklist and CCE derive
/// from them — risk scores, next-due-at, referral SLA and priority. Until this
/// existed that recompute ran only from `SyncProgressScreen`, so a
/// connectivity-triggered sync completing while the SK worked the dashboard
/// left the mission queue ordered by pre-sync scores. `rosterRevision` already
/// covers the household list, but nothing covered this.
///
/// Lives in `app/` rather than `core/`: it composes three feature repositories,
/// and `core` must not depend on `features`.
class PostSyncRefresher {
  PostSyncRefresher({
    required Stream<SyncProgress> progress,
    required WorklistRepository worklist,
    required ReferralRepository referrals,
    required MissionDashboardRepository mission,
  })  : _progress = progress,
        _worklist = worklist,
        _referrals = referrals,
        _mission = mission;

  final Stream<SyncProgress> _progress;
  final WorklistRepository _worklist;
  final ReferralRepository _referrals;
  final MissionDashboardRepository _mission;

  StreamSubscription<SyncProgress>? _sub;

  /// Guards against overlapping passes. A recompute walks every patient, so
  /// two in flight would duplicate the work and interleave their writes.
  bool _running = false;

  void attach() {
    _sub = _progress.listen((p) {
      if (p.isComplete) unawaited(refreshNow());
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Recompute, then refresh the dashboard.
  ///
  /// Public so `SyncProgressScreen` can call it directly for the post-login
  /// path instead of keeping a second copy of this sequence — the two must not
  /// drift, and running both would recompute twice per login.
  Future<void> refreshNow() async {
    if (_running) {
      debugPrint('[PostSync] refresh already running — skipped');
      return;
    }
    _running = true;
    final watch = Stopwatch()..start();
    try {
      // Order matters: the worklist recompute writes the risk/next-due columns
      // the mission queue reads, so refreshing the dashboard first would show
      // pre-sync ordering.
      await _worklist.recomputeAllAfterSync();
      await _referrals.recomputeAllAfterSync();
      await _mission.refresh();
      debugPrint('[PostSync] refresh done in ${watch.elapsedMilliseconds}ms');
    } catch (e) {
      // Never rethrow: this runs fire-and-forget off a stream, so an
      // unhandled error here would surface as an unrelated crash long after
      // the sync it belongs to. A stale dashboard is recoverable; a crash is
      // not.
      debugPrint('[PostSync] refresh failed: $e');
    } finally {
      _running = false;
    }
  }
}
