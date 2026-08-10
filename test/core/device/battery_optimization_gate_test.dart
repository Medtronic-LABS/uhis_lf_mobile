import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/device/battery_optimization_gate.dart';
import 'package:uhis_next/core/device/battery_optimization_service.dart';

class _FakeService implements BatteryOptimizationService {
  _FakeService({
    this.exempt = false,
    this.hasOem = false,
    this.oemOpens = true,
    this.batteryOpens = true,
    this.throwOnExempt = false,
  });

  bool exempt;
  bool hasOem;
  bool oemOpens;
  bool batteryOpens;
  bool throwOnExempt;

  int oemCalls = 0;
  int batteryCalls = 0;

  @override
  Future<bool> isExempt() async {
    if (throwOnExempt) throw StateError('channel down');
    return exempt;
  }

  @override
  Future<String> manufacturer() async => 'xiaomi';

  @override
  Future<bool> hasOemAutoStartScreen() async => hasOem;

  @override
  Future<bool> openOemAutoStartSettings() async {
    oemCalls++;
    return oemOpens;
  }

  @override
  Future<bool> openBatterySettings() async {
    batteryCalls++;
    return batteryOpens;
  }
}

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeService service;
  late _FakeStorage storage;
  late BatteryOptimizationGate gate;

  setUp(() {
    service = _FakeService();
    storage = _FakeStorage();
    gate = BatteryOptimizationGate(service: service, storage: storage);
  });

  group('shouldPrompt', () {
    test('prompts when not exempt and never asked', () async {
      service.exempt = false;
      expect(await gate.shouldPrompt(), isTrue);
    });

    test('does not prompt when already exempt', () async {
      service.exempt = true;
      expect(await gate.shouldPrompt(), isFalse);
    });

    test('never asks twice — declining is permanent', () async {
      service.exempt = false;
      expect(await gate.shouldPrompt(), isTrue);
      await gate.markAsked();
      expect(await gate.shouldPrompt(), isFalse);
    });

    test('a platform that cannot answer is not a reason to nag', () async {
      service.throwOnExempt = true;
      expect(await gate.shouldPrompt(), isFalse);
    });

    test('an unreadable flag suppresses rather than repeats the prompt',
        () async {
      // A storage fault must not turn into a prompt on every single launch.
      storage.throws = true;
      expect(await gate.shouldPrompt(), isFalse);
    });
  });

  group('openBestSettingsScreen', () {
    test('prefers the OEM autostart screen when the device has one', () async {
      service.hasOem = true;
      expect(await gate.openBestSettingsScreen(), isTrue);
      expect(service.oemCalls, 1);
      expect(service.batteryCalls, 0,
          reason: 'the vendor list is what actually kills background work');
    });

    test('falls back to system battery settings when there is no OEM screen',
        () async {
      service.hasOem = false;
      expect(await gate.openBestSettingsScreen(), isTrue);
      expect(service.oemCalls, 0);
      expect(service.batteryCalls, 1);
    });

    test('falls back when the OEM screen exists but will not open', () async {
      // Vendor ComponentNames drift between ROM versions; resolving is not a
      // guarantee that launching succeeds.
      service.hasOem = true;
      service.oemOpens = false;
      expect(await gate.openBestSettingsScreen(), isTrue);
      expect(service.oemCalls, 1);
      expect(service.batteryCalls, 1);
    });

    test('reports failure when nothing can be opened', () async {
      service.hasOem = false;
      service.batteryOpens = false;
      expect(await gate.openBestSettingsScreen(), isFalse);
    });
  });
}
