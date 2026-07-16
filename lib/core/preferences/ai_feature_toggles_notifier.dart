import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-step on/off switches for the visit flow's AI-service-backed widgets.
///
/// All default `true` so existing behavior is unchanged until an SK
/// explicitly opts out of a surface — e.g. to save mobile data in an area
/// with poor/expensive connectivity.
@immutable
class AiFeatureToggles {
  const AiFeatureToggles({
    required this.step1SummaryEnabled,
    required this.step1AsrEnabled,
    required this.step2AsrEnabled,
    required this.step3SummaryEnabled,
    required this.step3ReferralAlertEnabled,
    required this.step3WhatsAppEnabled,
  });

  factory AiFeatureToggles.defaults() => const AiFeatureToggles(
        step1SummaryEnabled: true,
        step1AsrEnabled: true,
        step2AsrEnabled: true,
        step3SummaryEnabled: true,
        step3ReferralAlertEnabled: true,
        step3WhatsAppEnabled: true,
      );

  /// Step 1 — "Before You Knock" visit briefing cards.
  final bool step1SummaryEnabled;

  /// Step 1 — AI Scribe voice capture that pre-ticks symptom cards.
  final bool step1AsrEnabled;

  /// Step 2 — AI Scribe voice capture that fills the assessment form.
  final bool step2AsrEnabled;

  /// Step 3 — NABA-generated visit summary and recommendations.
  final bool step3SummaryEnabled;

  /// Step 3 — danger-sign / referral alert card.
  final bool step3ReferralAlertEnabled;

  /// Step 3 — WhatsApp draft message card.
  final bool step3WhatsAppEnabled;

  AiFeatureToggles copyWith({
    bool? step1SummaryEnabled,
    bool? step1AsrEnabled,
    bool? step2AsrEnabled,
    bool? step3SummaryEnabled,
    bool? step3ReferralAlertEnabled,
    bool? step3WhatsAppEnabled,
  }) =>
      AiFeatureToggles(
        step1SummaryEnabled: step1SummaryEnabled ?? this.step1SummaryEnabled,
        step1AsrEnabled: step1AsrEnabled ?? this.step1AsrEnabled,
        step2AsrEnabled: step2AsrEnabled ?? this.step2AsrEnabled,
        step3SummaryEnabled: step3SummaryEnabled ?? this.step3SummaryEnabled,
        step3ReferralAlertEnabled:
            step3ReferralAlertEnabled ?? this.step3ReferralAlertEnabled,
        step3WhatsAppEnabled: step3WhatsAppEnabled ?? this.step3WhatsAppEnabled,
      );

  Map<String, dynamic> toJson() => {
        'step1SummaryEnabled': step1SummaryEnabled,
        'step1AsrEnabled': step1AsrEnabled,
        'step2AsrEnabled': step2AsrEnabled,
        'step3SummaryEnabled': step3SummaryEnabled,
        'step3ReferralAlertEnabled': step3ReferralAlertEnabled,
        'step3WhatsAppEnabled': step3WhatsAppEnabled,
      };

  /// Parses a persisted JSON map, falling back to [defaults] field-by-field
  /// so a partially-saved or older-shape value never crashes the app.
  factory AiFeatureToggles.fromJson(Map<String, dynamic> json) {
    final d = AiFeatureToggles.defaults();
    bool? asBool(String key) => json[key] as bool?;
    return AiFeatureToggles(
      step1SummaryEnabled:
          asBool('step1SummaryEnabled') ?? d.step1SummaryEnabled,
      step1AsrEnabled: asBool('step1AsrEnabled') ?? d.step1AsrEnabled,
      step2AsrEnabled: asBool('step2AsrEnabled') ?? d.step2AsrEnabled,
      step3SummaryEnabled:
          asBool('step3SummaryEnabled') ?? d.step3SummaryEnabled,
      step3ReferralAlertEnabled: asBool('step3ReferralAlertEnabled') ??
          d.step3ReferralAlertEnabled,
      step3WhatsAppEnabled:
          asBool('step3WhatsAppEnabled') ?? d.step3WhatsAppEnabled,
    );
  }
}

/// Runtime on/off switches for the visit flow's AI widgets, persisted
/// on-device (Settings → AI Settings), field-tunable without a rebuild.
///
/// Mirrors [VadTuningNotifier]'s shape and the same three-tier precedence
/// doctrine: no build-time flag exists for most of these surfaces today
/// (Step 1 briefing, Step 3 NABA outputs), so this notifier's persisted
/// value is the only override tier until a future server-driven config API
/// is added above it. `AppConfig.scribeEnabled` remains the build-time
/// ceiling for the two ASR toggles specifically — see its call sites.
class AiFeatureTogglesNotifier extends ChangeNotifier {
  AiFeatureTogglesNotifier(this._storage);

  final FlutterSecureStorage _storage;
  static const _storageKey = 'ai_feature_toggles_v1';

  AiFeatureToggles _toggles = AiFeatureToggles.defaults();
  AiFeatureToggles get toggles => _toggles;

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      _toggles = AiFeatureToggles.defaults();
    } else {
      try {
        _toggles = AiFeatureToggles.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        // Corrupt/older-shape save — degrade to factory defaults (all AI
        // widgets on) rather than crash the visit flow over a preference.
        _toggles = AiFeatureToggles.defaults();
      }
    }
    notifyListeners();
  }

  Future<void> update(AiFeatureToggles toggles) async {
    _toggles = toggles;
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(toggles.toJson()),
    );
    notifyListeners();
  }

  Future<void> resetToDefaults() => update(AiFeatureToggles.defaults());
}
