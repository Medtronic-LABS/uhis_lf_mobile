import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/sync/sync_activity.dart';
import 'package:uhis_next/core/sync/sync_foreground_controller.dart';
import 'package:uhis_next/core/sync/sync_foreground_notifier.dart';
import 'package:uhis_next/core/sync/sync_progress.dart';

class _FakeNotifier implements SyncForegroundNotifier {
  _FakeNotifier({this.startSucceeds = true, this.throwOnEverything = false});

  /// Simulates Android refusing a background foreground-service start.
  final bool startSucceeds;
  final bool throwOnEverything;

  int startCalls = 0;
  int stopCalls = 0;
  final List<String> updates = <String>[];
  final List<String> failures = <String>[];

  void _maybeThrow() {
    if (throwOnEverything) {
      throw PlatformException(code: 'ERR', message: 'channel exploded');
    }
  }

  @override
  Future<bool> start({
    required String channelName,
    required String title,
    required String text,
  }) async {
    startCalls++;
    _maybeThrow();
    return startSucceeds;
  }

  @override
  Future<void> update({
    required String text,
    int done = 0,
    int total = 0,
  }) async {
    _maybeThrow();
    updates.add(text);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _maybeThrow();
  }

  @override
  Future<void> showFailure({
    required String title,
    required String text,
  }) async {
    _maybeThrow();
    failures.add(text);
  }
}

void main() {
  late StreamController<SyncProgress> progress;

  setUp(() {
    SyncActivity.resetForTest();
    progress = StreamController<SyncProgress>.broadcast();
  });

  tearDown(() async {
    SyncActivity.resetForTest();
    await progress.close();
  });

  SyncForegroundController attach(_FakeNotifier notifier) {
    final controller = SyncForegroundController(
      progress: progress.stream,
      notifier: notifier,
    );
    controller.attach();
    return controller;
  }

  test('starts the service when sync begins and stops when it ends', () async {
    final notifier = _FakeNotifier();
    attach(notifier);

    SyncActivity.pullInFlight = true;
    await pumpEventQueue();
    expect(notifier.startCalls, 1);

    SyncActivity.pullInFlight = false;
    await pumpEventQueue();
    expect(notifier.stopCalls, 1);
  });

  test('overlapping operations start and stop the service once', () async {
    final notifier = _FakeNotifier();
    attach(notifier);

    SyncActivity.pullInFlight = true;
    SyncActivity.assessmentPushInFlight = true;
    await pumpEventQueue();
    SyncActivity.pullInFlight = false;
    await pumpEventQueue();
    expect(notifier.stopCalls, 0, reason: 'a push is still running');

    SyncActivity.assessmentPushInFlight = false;
    await pumpEventQueue();

    expect(notifier.startCalls, 1);
    expect(notifier.stopCalls, 1);
  });

  test('forwards progress to the notification while running', () async {
    final notifier = _FakeNotifier();
    attach(notifier);

    SyncActivity.pullInFlight = true;
    await pumpEventQueue();
    progress.add(const SyncProgress(
      currentStep: SyncStep.fetchingPatients,
      entityName: 'households',
      itemsDone: 240,
      itemsTotal: 1200,
    ));
    await pumpEventQueue();

    expect(notifier.updates.single, contains('households'));
    expect(notifier.updates.single, contains('240'));
    expect(notifier.updates.single, contains('1200'));
  });

  test('when Android refuses the start, no update or stop is attempted',
      () async {
    // Android 12+ blocks starting a foreground service from the background;
    // the sync must carry on regardless, just without a notification.
    final notifier = _FakeNotifier(startSucceeds: false);
    attach(notifier);

    SyncActivity.pullInFlight = true;
    await pumpEventQueue();
    progress.add(const SyncProgress(entityName: 'households'));
    await pumpEventQueue();
    SyncActivity.pullInFlight = false;
    await pumpEventQueue();

    expect(notifier.startCalls, 1);
    expect(notifier.updates, isEmpty);
    expect(notifier.stopCalls, 0);
  });

  test('a failed sync posts a dismissible failure notice after stopping',
      () async {
    final notifier = _FakeNotifier();
    attach(notifier);

    SyncActivity.pullInFlight = true;
    await pumpEventQueue();
    progress.add(const SyncProgress(error: 'Connection timed out'));
    await pumpEventQueue();
    SyncActivity.pullInFlight = false;
    await pumpEventQueue();

    expect(notifier.stopCalls, 1);
    expect(notifier.failures.single, 'Connection timed out');
  });

  test('a throwing notifier never escapes the controller', () async {
    // A notification is an aid; failing to draw one must not fail a sync.
    final notifier = _FakeNotifier(throwOnEverything: true);
    attach(notifier);

    SyncActivity.pullInFlight = true;
    await pumpEventQueue();
    progress.add(const SyncProgress(entityName: 'households'));
    await pumpEventQueue();
    SyncActivity.pullInFlight = false;
    await pumpEventQueue();

    // Reaching here without an unhandled exception is the assertion.
    expect(notifier.startCalls, 1);
  });
}
