import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/sync/sync_activity.dart';

/// The foreground service is driven off these edges, so "fires once when the
/// first operation starts, once when the last one finishes" is the contract
/// that keeps a service from being torn down while a sync is still running.
void main() {
  setUp(SyncActivity.resetForTest);
  tearDown(SyncActivity.resetForTest);

  test('fires true on the first operation and false on the last', () {
    final events = <bool>[];
    SyncActivity.onActiveChanged = events.add;

    SyncActivity.pullInFlight = true;
    SyncActivity.pullInFlight = false;

    expect(events, [true, false]);
  });

  test('overlapping operations produce exactly one start and one stop', () {
    final events = <bool>[];
    SyncActivity.onActiveChanged = events.add;

    SyncActivity.pullInFlight = true;              // start
    SyncActivity.assessmentPushInFlight = true;    // still active — no event
    SyncActivity.householdMemberPushInFlight = true;
    SyncActivity.pullInFlight = false;             // still active — no event
    SyncActivity.assessmentPushInFlight = false;   // still active — no event
    SyncActivity.householdMemberPushInFlight = false; // last one out

    expect(events, [true, false]);
  });

  test('re-asserting a flag that is already set fires nothing', () {
    final events = <bool>[];
    SyncActivity.onActiveChanged = events.add;

    SyncActivity.pullInFlight = true;
    SyncActivity.pullInFlight = true;

    expect(events, [true]);
  });

  test('anyInFlight reflects the union of all three flags', () {
    expect(SyncActivity.anyInFlight, isFalse);
    SyncActivity.assessmentPushInFlight = true;
    expect(SyncActivity.anyInFlight, isTrue);
    SyncActivity.assessmentPushInFlight = false;
    expect(SyncActivity.anyInFlight, isFalse);
  });

  test('a null listener is safe — flags still track', () {
    SyncActivity.onActiveChanged = null;
    SyncActivity.pullInFlight = true;
    expect(SyncActivity.pullInFlight, isTrue);
    expect(SyncActivity.anyInFlight, isTrue);
  });
}
