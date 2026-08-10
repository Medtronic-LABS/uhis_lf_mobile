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

  /// Set when a sync completes while a pass is already running.
  ///
  /// Without it the request is simply dropped, and the rows that sync wrote
  /// keep their pre-sync risk scores, next-due dates and SLA until some later
  /// sync happens to complete at a moment when nothing is running. Observed on
  /// device: a pass ran 17:33:30–17:33:53 while another sync completed at
  /// 17:33:38, squarely inside it. With a ~20 s recompute and syncs seconds
  /// apart, that overlap is likely rather than theoretical.
  ///
  /// A flag, not a queue: five syncs landing during one pass coalesce into a
  /// single re-run. The recompute is a full walk, so running it once per
  /// dropped request would be pure waste.
  bool _dirty = false;

  void attach() {
    debugPrint('[PostSync] attached — listening for sync completion');
    _sub = _progress.listen((p) {
      if (!p.isComplete) return;
      // A sync that wrote nothing cannot have changed anything derived from it.
      // Measured: the recompute walks every patient and took 19 s for 3566
      // patients after a 1.3 s no-op warm pull. Connectivity changes fire a
      // sync on every network flap, so running it ungated would burn CPU and
      // battery continuously for a CHW moving in and out of signal.
      if (!p.hasChanges) {
        debugPrint('[PostSync] sync wrote nothing — recompute skipped');
        return;
      }
      unawaited(refreshNow(trigger: 'syncCompleted'));
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
  Future<void> refreshNow({String trigger = 'manual'}) async {
    if (_running) {
      _dirty = true;
      debugPrint(
          '[PostSync] refresh already running — will re-run after ($trigger)');
      return;
    }
    _running = true;
    // Logged on ENTRY, not just completion: the recompute walks every patient
    // and can run for tens of seconds, so an end-only log is indistinguishable
    // from never having started.
    debugPrint('[PostSync] refresh start ($trigger)');
    final watch = Stopwatch()..start();
    try {
      // Order matters: the worklist recompute writes the risk/next-due columns
      // the mission queue reads, so refreshing the dashboard first would show
      // pre-sync ordering.
      await _worklist.recomputeAllAfterSync();
      debugPrint('[PostSync] worklist recompute ${watch.elapsedMilliseconds}ms');
      await _referrals.recomputeAllAfterSync();
      debugPrint('[PostSync] referral recompute ${watch.elapsedMilliseconds}ms');
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

    // A sync landed while the pass above was running. Re-run once to pick it
    // up. Clearing the flag before recursing means a sync arriving during the
    // re-run sets it again and is honoured too, rather than being lost.
    if (_dirty) {
      _dirty = false;
      debugPrint('[PostSync] re-running for a sync that landed mid-refresh');
      await refreshNow(trigger: 'coalesced');
    }
  }
}
