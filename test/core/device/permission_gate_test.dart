import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:uhis_next/core/device/permission_gate.dart';

/// In-memory stand-in — FlutterSecureStorage needs a platform channel that
/// isn't available in a plain unit test.
class _FakeStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};
  bool throws = false;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throws) throw StateError('keystore unavailable');
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throws) throw StateError('keystore unavailable');
    if (value != null) values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeStorage storage;
  late List<List<Permission>> requested;

  setUp(() {
    storage = _FakeStorage();
    requested = [];
  });

  PermissionGate gate({
    Map<Permission, PermissionStatus>? result,
    bool requesterThrows = false,
    bool settingsOpen = true,
  }) =>
      PermissionGate(
        storage: storage,
        requester: (perms) async {
          requested.add(perms);
          if (requesterThrows) throw StateError('platform channel down');
          return result ??
              {for (final p in perms) p: PermissionStatus.granted};
        },
        openSettings: () async => settingsOpen,
      );

  test('asks for every permission in one batch', () async {
    await gate().requestAll();
    expect(requested.single, kOnboardingPermissions);
  });

  test('notifications are requested last', () async {
    // The least alarming of the four — if an SK fatigue-denies by the final
    // dialog, better it is the one that costs least.
    expect(kOnboardingPermissions.last, Permission.notification);
  });

  test('prompts only once, whatever the answer', () async {
    final g = gate(result: {
      for (final p in kOnboardingPermissions) p: PermissionStatus.denied
    });
    expect(await g.shouldPrompt(), isTrue);
    await g.requestAll();
    expect(await g.shouldPrompt(), isFalse,
        reason: 'a denial must be respected, not re-prompted next launch');
  });

  test('declining at the rationale records asked without prompting', () async {
    final g = gate();
    await g.declineWithoutAsking();

    expect(requested, isEmpty, reason: 'no system dialog should have fired');
    expect(await g.shouldPrompt(), isFalse);
  });

  test('a platform fault still records asked and returns cleanly', () async {
    // Stranding the SK on the onboarding step is worse than missing
    // permissions they can grant later at point of use.
    final g = gate(requesterThrows: true);
    final statuses = await g.requestAll();

    expect(statuses, isEmpty);
    expect(await g.hasAsked(), isTrue);
  });

  test('an unreadable flag suppresses rather than repeats the prompt',
      () async {
    storage.throws = true;
    expect(await gate().shouldPrompt(), isFalse);
  });

  group('permanent denial', () {
    test('is detected so the SK can be sent to settings', () {
      final statuses = {
        Permission.camera: PermissionStatus.granted,
        Permission.microphone: PermissionStatus.permanentlyDenied,
      };
      expect(PermissionGate.anyPermanentlyDenied(statuses), isTrue);
    });

    test('is not reported for an ordinary denial', () {
      // An ordinary denial can still be re-requested later at point of use;
      // only permanent denial needs the settings detour.
      final statuses = {
        Permission.camera: PermissionStatus.granted,
        Permission.microphone: PermissionStatus.denied,
      };
      expect(PermissionGate.anyPermanentlyDenied(statuses), isFalse);
    });

    test('openSettings reports failure instead of throwing', () async {
      expect(await gate(settingsOpen: false).openSettings(), isFalse);
    });
  });
}
