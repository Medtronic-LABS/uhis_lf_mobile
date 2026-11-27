import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:uhis_next/core/errors/domain_exceptions.dart';
import 'package:uhis_next/core/version/app_update_controller.dart';
import 'package:uhis_next/core/version/app_version_service.dart';
import 'package:uhis_next/core/version/play_update_client.dart';
import 'package:uhis_next/core/version/required_update_guard.dart';

class _FakePlay implements PlayUpdateClient {
  PlayUpdateSnapshot snapshot = _snap();
  Object? checkError;
  AppUpdateResult immediateResult = AppUpdateResult.success;
  int checks = 0;
  int immediateCalls = 0;
  int flexibleStarts = 0;
  int completes = 0;
  int listenerSubscriptions = 0;
  final status = StreamController<InstallStatus>.broadcast();

  @override
  Future<PlayUpdateSnapshot> check() async {
    checks++;
    final err = checkError;
    if (err != null) throw err;
    return snapshot;
  }

  @override
  Future<AppUpdateResult> performImmediate() async {
    immediateCalls++;
    return immediateResult;
  }

  @override
  Future<AppUpdateResult> startFlexible() async {
    flexibleStarts++;
    return AppUpdateResult.success;
  }

  @override
  Future<void> completeFlexible() async => completes++;

  @override
  Stream<InstallStatus> get installStatus {
    listenerSubscriptions++;
    return status.stream;
  }
}

class _MemoryFlag implements ImmediateUpdateFlagStore {
  bool value = false;

  @override
  Future<bool> isSet() async => value;

  @override
  Future<void> set(bool v) async => value = v;
}

class _SilentLog implements AppUpdateLog {
  final events = <String>[];

  @override
  void event(String name, [Map<String, Object?> data = const {}]) =>
      events.add(name);
}

PlayUpdateSnapshot _snap({
  UpdateAvailability availability = UpdateAvailability.updateAvailable,
  bool immediate = true,
  bool flexible = true,
  InstallStatus status = InstallStatus.unknown,
  int? offered = 20,
}) =>
    PlayUpdateSnapshot(
      availability: availability,
      immediateAllowed: immediate,
      flexibleAllowed: flexible,
      installStatus: status,
      availableVersionCode: offered,
    );

void main() {
  late _FakePlay play;
  late _MemoryFlag flag;
  late _SilentLog log;
  late DateTime clock;
  late bool safe;
  late AppUpdateController controller;

  AppUpdateController build({bool supported = true}) {
    final c = AppUpdateController(
      play,
      supported: supported,
      flagStore: flag,
      log: log,
      now: () => clock,
    );
    c.bindSafePoint(() => safe);
    return c;
  }

  setUp(() {
    play = _FakePlay();
    flag = _MemoryFlag();
    log = _SilentLog();
    clock = DateTime(2026, 11, 24, 9);
    safe = true;
    controller = build();
  });

  tearDown(() => controller.dispose());

  group('refresh', () {
    test('does nothing when updates are unsupported (training / non-Android)',
        () async {
      controller.dispose();
      controller = build(supported: false);
      await controller.refresh();
      expect(play.checks, 0);
    });

    test('throttles availability checks to one per window', () async {
      await controller.refresh();
      await controller.refresh();
      expect(play.checks, 1);
      clock = clock.add(const Duration(minutes: 3));
      await controller.refresh();
      expect(play.checks, 2);
    });

    test('subscribes to the install listener exactly once', () async {
      await controller.refresh();
      clock = clock.add(const Duration(minutes: 5));
      await controller.refresh();
      await controller.refresh();
      expect(play.listenerSubscriptions, 1);
    });

    test('surfaces a downloaded flexible update on cold start', () async {
      play.snapshot = _snap(status: InstallStatus.downloaded);
      await controller.refresh();
      expect(controller.restartReady, isTrue);
    });

    test('duplicate downloaded events notify once', () async {
      await controller.refresh();
      var notifications = 0;
      controller.addListener(() => notifications++);
      play.status
        ..add(InstallStatus.downloaded)
        ..add(InstallStatus.downloaded);
      await Future<void>.delayed(Duration.zero);
      expect(controller.restartReady, isTrue);
      expect(notifications, 1);
    });

    test('resumes an interrupted immediate update', () async {
      play.snapshot = _snap(
        availability: UpdateAvailability.developerTriggeredUpdateInProgress,
      );
      await controller.refresh();
      expect(play.immediateCalls, 1);
    });

    test('recovery of an interrupted immediate update is never throttled',
        () async {
      await controller.refresh(); // fills the throttle window
      flag.value = true; // an immediate update was started, then the app died
      play.snapshot = _snap(
        availability: UpdateAvailability.developerTriggeredUpdateInProgress,
      );
      clock = clock.add(const Duration(seconds: 5)); // well inside 2 minutes
      await controller.refresh();
      expect(play.immediateCalls, 1);
    });

    test('clears the in-progress flag once Play reports it finished', () async {
      flag.value = true;
      play.snapshot = _snap(availability: UpdateAvailability.updateNotAvailable);
      await controller.refresh();
      expect(flag.value, isFalse);
      expect(play.immediateCalls, 0);
    });

    test('Play being unavailable is swallowed into a logged event', () async {
      play.checkError = const PlayUpdateUnavailableException(
        code: 'ERROR_API_NOT_AVAILABLE',
      );
      await controller.refresh();
      expect(controller.restartReady, isFalse);
      expect(log.events, contains('check_unavailable'));
    });
  });

  group('resolve (required update)', () {
    const required = AppVersionUpdateRequired('v1.0.9', minVersionCode: 10);

    test('Play can deliver → block', () async {
      expect(await controller.resolve(required),
          RequiredUpdateDecision.blockWithUpdate);
    });

    test('Play offers a build below the minimum → warn', () async {
      play.snapshot = _snap(offered: 9);
      expect(await controller.resolve(required), RequiredUpdateDecision.warn);
    });

    test('Play API unavailable → warn, after grace → stranded + event',
        () async {
      play.checkError =
          const PlayUpdateUnavailableException(code: 'ERROR_API_NOT_AVAILABLE');
      expect(await controller.resolve(required), RequiredUpdateDecision.warn);
      const expired = AppVersionUpdateRequired(
        'v1.0.9',
        minVersionCode: 10,
        graceExpired: true,
      );
      expect(await controller.resolve(expired),
          RequiredUpdateDecision.warnStranded);
      expect(log.events, contains('update_stranded'));
    });

    test('unsupported (training) build never queries Play and never blocks',
        () async {
      controller.dispose();
      controller = build(supported: false);
      expect(await controller.resolve(required), RequiredUpdateDecision.warn);
      expect(play.checks, 0);
    });
  });

  group('starting updates', () {
    test('required: immediate update runs and sets the recovery flag',
        () async {
      final outcome = await controller.startRequiredUpdate();
      expect(outcome, isA<AppUpdateInstalled>());
      expect(play.immediateCalls, 1);
      expect(flag.value, isTrue);
    });

    test('required: a user cancel clears the flag and reports cancelled',
        () async {
      play.immediateResult = AppUpdateResult.userDeniedUpdate;
      final outcome = await controller.startRequiredUpdate();
      expect(outcome, isA<AppUpdateCancelled>());
      expect(flag.value, isFalse);
    });

    test('required: an already-downloaded flexible update is completed, '
        'not re-run as immediate', () async {
      play.snapshot = _snap(status: InstallStatus.downloaded);
      final outcome = await controller.startRequiredUpdate();
      expect(outcome, isA<AppUpdateInstalled>());
      expect(play.completes, 1);
      expect(play.immediateCalls, 0);
    });

    test('required: nothing offered → unavailable', () async {
      play.snapshot =
          _snap(availability: UpdateAvailability.updateNotAvailable);
      expect(await controller.startRequiredUpdate(), isA<AppUpdateUnavailable>());
    });

    test('required: Play API error becomes a typed unavailable outcome',
        () async {
      play.checkError =
          const PlayUpdateUnavailableException(code: 'ERROR_APP_NOT_OWNED');
      final outcome = await controller.startRequiredUpdate();
      expect(outcome, isA<AppUpdateUnavailable>());
      expect((outcome as AppUpdateUnavailable).code, 'ERROR_APP_NOT_OWNED');
    });

    test('optional: flexible when allowed', () async {
      final outcome = await controller.startOptionalUpdate();
      expect(outcome, isA<AppUpdateDownloading>());
      expect(play.flexibleStarts, 1);
      expect(play.immediateCalls, 0);
    });

    test('optional: flexible disallowed → immediate when allowed', () async {
      play.snapshot = _snap(flexible: false);
      await controller.startOptionalUpdate();
      expect(play.flexibleStarts, 0);
      expect(play.immediateCalls, 1);
    });

    test('optional: neither allowed → unavailable (caller decides fallback)',
        () async {
      play.snapshot = _snap(flexible: false, immediate: false);
      expect(await controller.startOptionalUpdate(), isA<AppUpdateUnavailable>());
    });
  });

  group('safe point', () {
    test('restart only when ready and at a safe point', () async {
      play.snapshot = _snap(status: InstallStatus.downloaded);
      await controller.refresh();

      safe = false;
      expect(await controller.completeRestartIfSafe(), isFalse);
      expect(play.completes, 0);

      safe = true;
      expect(await controller.completeRestartIfSafe(), isTrue);
      expect(play.completes, 1);
    });

    test('nothing to restart when no update is downloaded', () async {
      expect(await controller.completeRestartIfSafe(), isFalse);
    });

    test('the required gate defers exactly once away from a safe point', () {
      safe = false;
      expect(controller.deferRequiredOnce(), isTrue);
      expect(controller.deferRequiredOnce(), isFalse);
    });

    test('the required gate never defers at a safe point', () {
      safe = true;
      expect(controller.deferRequiredOnce(), isFalse);
    });

    test('the warning slot is handed out once per session', () {
      expect(controller.takeWarningSlot(), isTrue);
      expect(controller.takeWarningSlot(), isFalse);
    });
  });
}
