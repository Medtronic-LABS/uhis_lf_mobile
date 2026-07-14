import 'dart:convert';

import '../models/risk.dart';

/// Builds [ClinicalVitals] from a synced assessment-history row.
///
/// Assessment history stores clinical values under `observations` (and
/// sometimes `assessmentDetails`) — e.g. `{hemoglobin: 7, weight: 45}` —
/// which never lands in `local_assessments`. The worklist risk engine needs
/// those values to assign ANC/NCD bands, so this parser is the bridge.
class ClinicalVitalsFromHistory {
  const ClinicalVitalsFromHistory._();

  /// Parse one assessment-history / AssessmentRow raw JSON blob.
  /// Returns null when no recognisable clinical field is present.
  static ClinicalVitals? fromRawJson(String rawJson, {String? assessmentType}) {
    Map<String, dynamic> raw;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      raw = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    return fromMap(raw, assessmentType: assessmentType);
  }

  static ClinicalVitals? fromMap(
    Map<String, dynamic> raw, {
    String? assessmentType,
  }) {
    final flat = <String, dynamic>{};

    for (final key in const ['observations', 'assessmentDetails']) {
      final nested = raw[key];
      if (nested is Map) {
        flat.addAll(Map<String, dynamic>.from(nested));
      }
    }
    // Top-level fallbacks (some payloads inline vitals).
    for (final e in raw.entries) {
      flat.putIfAbsent(e.key, () => e.value);
    }

    int? parseInt(String key) {
      final v = flat[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    double? parseDouble(String key) {
      final v = flat[key];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim());
      return null;
    }

    // BP — slash string or discrete fields.
    int? sys = parseInt('systolic') ??
        parseInt('systolicBp') ??
        parseInt('avgSystolic') ??
        parseInt('bloodPressureSystolic');
    int? dia = parseInt('diastolic') ??
        parseInt('diastolicBp') ??
        parseInt('avgDiastolic') ??
        parseInt('bloodPressureDiastolic');
    final bpStr = flat['bp'];
    if (bpStr is String && bpStr.contains('/')) {
      final parts = bpStr.split('/');
      if (parts.length == 2) {
        sys ??= double.tryParse(parts[0].trim())?.toInt();
        dia ??= double.tryParse(parts[1].trim())?.toInt();
      }
    }

    final hb = parseDouble('hemoglobin') ?? parseDouble('hb');

    double? fastingGlu;
    final glucose = parseDouble('glucoseValue') ??
        parseDouble('bg') ??
        parseDouble('glucose') ??
        parseDouble('bloodGlucose') ??
        parseDouble('fastingGlucose');
    final glucoseType = (flat['glucoseType'] as String?)?.toLowerCase();
    if (glucose != null &&
        (glucoseType == null ||
            glucoseType == 'fasting' ||
            glucoseType.contains('fast'))) {
      fastingGlu = glucose;
    }

    // Primigravida: parity == 0, or gravida == 1 (PW profile).
    int? parity = parseInt('parity');
    final gravida = parseInt('gravida');
    if (parity == null && gravida != null) {
      parity = gravida <= 1 ? 0 : gravida - 1;
    }

    final ga = parseInt('gestationalWeeks') ??
        parseInt('gestationalAgeWeeks') ??
        parseInt('gaWeeks');

    final hasAbnormalUrine = flat['urineProtein'] == 'Present' ||
        flat['urineProtein'] == true ||
        (flat['urineProtein'] is String &&
            (flat['urineProtein'] as String).toLowerCase() == 'positive') ||
        flat['urinaryAlbumin'] != null ||
        flat['urinarySugar'] == 'Present';

    final diabetesRaw = flat['diabetes'] ?? flat['hasDiabetes'];
    final hasDiabetes = diabetesRaw == true ||
        diabetesRaw == 'yes' ||
        (fastingGlu != null && fastingGlu >= 7.0);

    // Only explicit danger-sign tags — do not treat HIGH_RISK_PW as Band 1
    // (that flag often accompanies moderate findings that belong in Band 2).
    final custom = raw['customStatus'];
    var hasDanger = false;
    if (custom is List) {
      for (final c in custom) {
        final tag = c.toString().toUpperCase();
        if (tag.contains('DANGER_SIGN') || tag == 'DANGER_SIGNS') {
          hasDanger = true;
          break;
        }
      }
    }

    final type = (assessmentType ??
            raw['serviceProvided'] as String? ??
            raw['assessmentType'] as String? ??
            '')
        .toUpperCase();

    final hasAny = sys != null ||
        dia != null ||
        hb != null ||
        fastingGlu != null ||
        parity != null ||
        ga != null ||
        hasAbnormalUrine ||
        hasDiabetes ||
        hasDanger;
    if (!hasAny) return null;

    final hasSob = flat['chestTightnessOrSob'] == true ||
        flat['chestTightnessOrSob'] == 'yes';
    final hasSobWithHighBp = hasSob && sys != null && sys >= 140;
    final hasStroke = flat['oneSidedWeakness'] == true ||
        flat['oneSidedWeakness'] == 'yes';

    return ClinicalVitals(
      systolicBp: sys,
      diastolicBp: dia,
      hemoglobin: hb,
      fastingGlucoseMmolL: fastingGlu,
      hasDangerSign: hasDanger,
      hasStrokeSign: hasStroke,
      hasAbnormalUrine: hasAbnormalUrine,
      hasSobWithHighBp: hasSobWithHighBp,
      gestationalAgeWeeks: ga,
      parity: parity,
      hasDiabetes: hasDiabetes,
      assessmentType: type.isEmpty ? null : type,
    );
  }

  /// Prefer non-null fields from [primary], fill gaps from [fallback].
  static ClinicalVitals? merge(ClinicalVitals? primary, ClinicalVitals? fallback) {
    if (primary == null) return fallback;
    if (fallback == null) return primary;
    return ClinicalVitals(
      systolicBp: primary.systolicBp ?? fallback.systolicBp,
      diastolicBp: primary.diastolicBp ?? fallback.diastolicBp,
      hemoglobin: primary.hemoglobin ?? fallback.hemoglobin,
      fastingGlucoseMmolL:
          primary.fastingGlucoseMmolL ?? fallback.fastingGlucoseMmolL,
      hasDangerSign: primary.hasDangerSign || fallback.hasDangerSign,
      hasEclampsia: primary.hasEclampsia || fallback.hasEclampsia,
      hasStrokeSign: primary.hasStrokeSign || fallback.hasStrokeSign,
      hasAbnormalUrine: primary.hasAbnormalUrine || fallback.hasAbnormalUrine,
      hasSobWithHighBp: primary.hasSobWithHighBp || fallback.hasSobWithHighBp,
      gestationalAgeWeeks:
          primary.gestationalAgeWeeks ?? fallback.gestationalAgeWeeks,
      parity: primary.parity ?? fallback.parity,
      hasDiabetes: primary.hasDiabetes || fallback.hasDiabetes,
      assessmentType: primary.assessmentType ?? fallback.assessmentType,
    );
  }
}
