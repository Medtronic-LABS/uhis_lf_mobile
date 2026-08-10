import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/app/post_sync_refresher.dart';
import 'package:uhis_next/core/sync/sync_progress.dart';
import 'package:uhis_next/features/dashboard/mission_dashboard_repository.dart';
import 'package:uhis_next/features/referral/referral_repository.dart';
import 'package:uhis_next/features/worklist/worklist_repository.dart';

/// Records call order and can stall, so the overlap guard is observable.
class _FakeWorklist implements WorklistRepository {
  _FakeWorklist(this.log, {this.delay = Duration.zero});
  final List<String> log;
  final Duration delay;
  int calls = 0;

  @override
  Future<int> recomputeAllAfterSync() async {
    calls++;
    log.add('worklist');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeReferrals implements ReferralRepository {
  _FakeReferrals(this.log, {this.throws = false});
  final List<String> log;
  final bool throws;
  int calls = 0;

  @override
  Future<int> recomputeAllAfterSync() async {
    calls++;
    log.add('referrals');
    if (throws) throw StateError('recompute exploded');
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMission implements MissionDashboardRepository {
  _FakeMission(this.log);
  final List<String> log;
  int calls = 0;

  @override
  Future<void> refresh() async {
    calls++;
    log.add('mission');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late StreamController<SyncProgress> progress;
  late List<String> log;
  late _FakeWorklist worklist;
  late _FakeReferrals referrals;
  late _FakeMission mission;

  setUp(() {
    progress = StreamController<SyncProgress>.broadcast();
    log = <String>[];
    worklist = _FakeWorklist(log);
    referrals = _FakeReferrals(log);
    mission = _FakeMission(log);
  });

  tearDown(() => progress.close());

  PostSyncRefresher attach({WorklistRepository? worklistOverride}) {
    final refresher = PostSyncRefresher(
      progress: progress.stream,
      worklist: worklistOverride ?? worklist,
      referrals: referrals,
      mission: mission,
    );
    refresher.attach();
    return refresher;
  }

  test('a completed sync triggers the recompute and dashboard refresh',
      () async {
    attach();
    progress.add(SyncProgress.completed());
    await pumpEventQueue();

    expect(worklist.calls, 1);
    expect(referrals.calls, 1);
    expect(mission.calls, 1);
  });

  test('recompute runs before the dashboard refresh', () async {
    // The worklist recompute writes the risk/next-due columns the mission
    // queue reads; refreshing first would render pre-sync ordering.
    attach();
    progress.add(SyncProgress.completed());
    await pumpEventQueue();

    expect(log, ['worklist', 'referrals', 'mission']);
  });

  test('a completed sync that wrote nothing skips the recompute', () async {
    // The measured case: a 1.3 s warm pull with an empty bundle triggering a
    // 19 s walk over 3566 patients, on every network flap.
    attach();
    progress.add(SyncProgress.completed(hasChanges: false));
    await pumpEventQueue();

    expect(worklist.calls, 0);
    expect(referrals.calls, 0);
    expect(mission.calls, 0);
  });

  test('an explicit refreshNow still runs even when the sync wrote nothing',
      () async {
    // The gate belongs to the stream hook, not to the method: the sync screen
    // calls refreshNow() directly and must still prepare the dashboard.
    final refresher = attach();
    progress.add(SyncProgress.completed(hasChanges: false));
    await pumpEventQueue();
    expect(worklist.calls, 0);

    await refresher.refreshNow(trigger: 'syncScreen');
    expect(worklist.calls, 1);
  });

  test('in-progress events do not trigger a refresh', () async {
    attach();
    progress.add(const SyncProgress(currentStep: SyncStep.fetchingPatients));
    progress.add(const SyncProgress(currentStep: SyncStep.processingData));
    await pumpEventQueue();

    expect(worklist.calls, 0);
    expect(mission.calls, 0);
  });

  test('a failed sync does not trigger a refresh', () async {
    attach();
    progress.add(SyncProgress.failed('Connection timed out'));
    await pumpEventQueue();

    expect(worklist.calls, 0);
  });

  test('overlapping passes are skipped, not queued', () async {
    // A recompute walks every patient; two in flight would duplicate the work
    // and interleave their writes.
    final slow = _FakeWorklist(log, delay: const Duration(milliseconds: 80));
    final refresher = attach(worklistOverride: slow);

    unawaited(refresher.refreshNow());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await refresher.refreshNow(); // lands while the first is still running
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(slow.calls, 1, reason: 'the second call must be dropped');
  });

  test('a throwing repository never escapes — a stale dashboard beats a crash',
      () async {
    // This runs fire-and-forget off a stream: an unhandled error would surface
    // as an unrelated crash long after the sync it belongs to.
    referrals = _FakeReferrals(log, throws: true);
    final refresher = PostSyncRefresher(
      progress: progress.stream,
      worklist: worklist,
      referrals: referrals,
      mission: mission,
    )..attach();

    await refresher.refreshNow();

    expect(referrals.calls, 1);
    expect(mission.calls, 0, reason: 'it failed before reaching the refresh');
  });

  test('the guard is released after a failure, so the next sync still runs',
      () async {
    referrals = _FakeReferrals(log, throws: true);
    final refresher = PostSyncRefresher(
      progress: progress.stream,
      worklist: worklist,
      referrals: referrals,
      mission: mission,
    )..attach();

    await refresher.refreshNow();
    await refresher.refreshNow();

    expect(worklist.calls, 2, reason: '_running must be cleared in finally');
  });
}
