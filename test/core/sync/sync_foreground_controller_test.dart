import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/sync/sync_activity.dart';
import 'package:uhis_next/core/sync/sync_foreground_controller.dart';
import 'package:uhis_next/core/sync/sync_foreground_notifier.dart';
import 'package:uhis_next/core/sync/sync_progress.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

class _FakeNotifier implements SyncForegroundNotifier {
  _FakeNotifier({
    this.startSucceeds = true,
    this.throwOnEverything = false,
    this.startLatency = Duration.zero,
  });

  /// Time the platform channel takes to answer `start`. The production bug —
  /// stopSelf overtaking startForeground — only exists when this is non-zero.
  final Duration startLatency;

  /// Simulates Android refusing a background foreground-service start.
  final bool startSucceeds;
  final bool throwOnEverything;

  int startCalls = 0;
  int stopCalls = 0;
  final List<String> updates = <String>[];
  final List<DateTime> startedAt = <DateTime>[];
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
    if (startLatency > Duration.zero) await Future<void>.delayed(startLatency);
    startedAt.add(DateTime.fromMillisecondsSinceEpoch(startCalls));
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
  // These assert English copy, so pin the language. AppLocale defaults to
  // Bangla (BD-first), and Bangla localizes digits — '12 days' becomes
  // '১২ days' — so an unpinned test is really asserting the default locale.
  setUp(() => AppLocale.current = AppLanguage.english);

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
      startDelay: Duration.zero,
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

  group('short syncs (regression: observed on device 2026-08-10)', () {
    // logcat showed SYNC_START at .438 and SYNC_STOP at .614 — a 176 ms
    // "Nothing pending to sync" pass — and Android answering
    // "Bringing down service while still waiting for start foreground".
    SyncForegroundController attachDebounced(
      _FakeNotifier notifier, {
      Duration startDelay = const Duration(milliseconds: 50),
    }) {
      final controller = SyncForegroundController(
        progress: progress.stream,
        notifier: notifier,
        startDelay: startDelay,
      );
      controller.attach();
      return controller;
    }

    test('a sync shorter than the debounce never starts the service', () async {
      final notifier = _FakeNotifier();
      attachDebounced(notifier);

      SyncActivity.pullInFlight = true;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      SyncActivity.pullInFlight = false; // done well inside the debounce
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifier.startCalls, 0,
          reason: 'no notification flicker, and no stopSelf/startForeground race');
      expect(notifier.stopCalls, 0);
    });

    test('a sync outlasting the debounce does start the service', () async {
      final notifier = _FakeNotifier();
      attachDebounced(notifier);

      SyncActivity.pullInFlight = true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(notifier.startCalls, 1);

      SyncActivity.pullInFlight = false;
      await pumpEventQueue();
      expect(notifier.stopCalls, 1);
    });

    test('stop waits for an in-flight start instead of overtaking it', () async {
      // The actual defect: stopSelf reaching Android before startForeground.
      final notifier = _FakeNotifier(
        startLatency: const Duration(milliseconds: 80),
      );
      attachDebounced(notifier, startDelay: Duration.zero);

      SyncActivity.pullInFlight = true;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Sync ends while the start round-trip is still in flight.
      SyncActivity.pullInFlight = false;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(notifier.startCalls, 1);
      expect(notifier.stopCalls, 1,
          reason: 'the stop must still happen — just only after the start lands');
    });

    test('progress arriving during the start round-trip is replayed', () async {
      // Device log showed 0 SYNC_UPDATE: every event during the start window
      // was dropped as "not running", so the notification never showed counts.
      final notifier = _FakeNotifier(
        startLatency: const Duration(milliseconds: 60),
      );
      attachDebounced(notifier, startDelay: Duration.zero);

      SyncActivity.pullInFlight = true;
      progress.add(const SyncProgress(
        entityName: 'households',
        itemsDone: 240,
        itemsTotal: 1200,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(notifier.updates, isNotEmpty,
          reason: 'buffered progress must reach the notification once it is up');
      expect(notifier.updates.last, contains('240'));
    });
  });
}
