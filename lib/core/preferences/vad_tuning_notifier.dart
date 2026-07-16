import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Snapshot of [VadGate]'s tunable parameters — see
/// `lib/features/realtime_asr/vad_gate.dart` for what each one controls.
///
/// Immutable; [VadTuningNotifier] holds the current value and persists
/// changes. [AppConfig.vad*] getters are the factory-default baseline this
/// falls back to when nothing has been saved yet (or a save is corrupt).
@immutable
class VadTuningConfig {
  const VadTuningConfig({
    required this.enterMarginDb,
    required this.sustainMarginDb,
    required this.floorCeilingDbfs,
    required this.floorAlpha,
    required this.bootstrapMs,
    required this.debounceMs,
    required this.hangoverMs,
    required this.preRollMs,
  });

  factory VadTuningConfig.defaults() => VadTuningConfig(
        enterMarginDb: AppConfig.vadEnterMarginDb,
        sustainMarginDb: AppConfig.vadSustainMarginDb,
        floorCeilingDbfs: AppConfig.vadFloorCeilingDbfs,
        floorAlpha: AppConfig.vadFloorAlpha,
        bootstrapMs: AppConfig.vadBootstrapMs,
        debounceMs: AppConfig.vadDebounceMs,
        hangoverMs: AppConfig.vadHangoverMs,
        preRollMs: AppConfig.vadPreRollMs,
      );

  final double enterMarginDb;
  final double sustainMarginDb;
  final double floorCeilingDbfs;
  final double floorAlpha;
  final int bootstrapMs;
  final int debounceMs;
  final int hangoverMs;
  final int preRollMs;

  VadTuningConfig copyWith({
    double? enterMarginDb,
    double? sustainMarginDb,
    double? floorCeilingDbfs,
    double? floorAlpha,
    int? bootstrapMs,
    int? debounceMs,
    int? hangoverMs,
    int? preRollMs,
  }) =>
      VadTuningConfig(
        enterMarginDb: enterMarginDb ?? this.enterMarginDb,
        sustainMarginDb: sustainMarginDb ?? this.sustainMarginDb,
        floorCeilingDbfs: floorCeilingDbfs ?? this.floorCeilingDbfs,
        floorAlpha: floorAlpha ?? this.floorAlpha,
        bootstrapMs: bootstrapMs ?? this.bootstrapMs,
        debounceMs: debounceMs ?? this.debounceMs,
        hangoverMs: hangoverMs ?? this.hangoverMs,
        preRollMs: preRollMs ?? this.preRollMs,
      );

  Map<String, dynamic> toJson() => {
        'enterMarginDb': enterMarginDb,
        'sustainMarginDb': sustainMarginDb,
        'floorCeilingDbfs': floorCeilingDbfs,
        'floorAlpha': floorAlpha,
        'bootstrapMs': bootstrapMs,
        'debounceMs': debounceMs,
        'hangoverMs': hangoverMs,
        'preRollMs': preRollMs,
      };

  /// Parses a persisted JSON map, falling back to [defaults] field-by-field
  /// so a partially-saved or older-shape value never crashes the app.
  factory VadTuningConfig.fromJson(Map<String, dynamic> json) {
    final d = VadTuningConfig.defaults();
    num? asNum(String key) => json[key] as num?;
    return VadTuningConfig(
      enterMarginDb: asNum('enterMarginDb')?.toDouble() ?? d.enterMarginDb,
      sustainMarginDb:
          asNum('sustainMarginDb')?.toDouble() ?? d.sustainMarginDb,
      floorCeilingDbfs:
          asNum('floorCeilingDbfs')?.toDouble() ?? d.floorCeilingDbfs,
      floorAlpha: asNum('floorAlpha')?.toDouble() ?? d.floorAlpha,
      bootstrapMs: asNum('bootstrapMs')?.toInt() ?? d.bootstrapMs,
      debounceMs: asNum('debounceMs')?.toInt() ?? d.debounceMs,
      hangoverMs: asNum('hangoverMs')?.toInt() ?? d.hangoverMs,
      preRollMs: asNum('preRollMs')?.toInt() ?? d.preRollMs,
    );
  }
}

/// Runtime-tunable [VadGate] parameters, persisted on-device.
///
/// Three-tier precedence (lowest to highest, once each tier exists):
/// [AppConfig.vad*] build-time defaults → this notifier's persisted value →
/// (future) a server-fetched remote config. Only the first two tiers are
/// implemented today; a later remote-config layer can populate this
/// notifier's value on fetch without changing [RealtimeAsrController]'s
/// read side at all (TODO(remote-config), see `app_config.dart`).
class VadTuningNotifier extends ChangeNotifier {
  VadTuningNotifier(this._storage);

  final FlutterSecureStorage _storage;
  static const _storageKey = 'vad_tuning_v1';

  VadTuningConfig _config = VadTuningConfig.defaults();
  VadTuningConfig get config => _config;

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      _config = VadTuningConfig.defaults();
    } else {
      try {
        _config = VadTuningConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        // Corrupt/older-shape save — degrade to factory defaults rather than
        // crash the realtime ASR path over a tuning preference.
        _config = VadTuningConfig.defaults();
      }
    }
    notifyListeners();
  }

  Future<void> update(VadTuningConfig config) async {
    _config = config;
    await _storage.write(key: _storageKey, value: jsonEncode(config.toJson()));
    notifyListeners();
  }

  Future<void> resetToDefaults() => update(VadTuningConfig.defaults());
}
