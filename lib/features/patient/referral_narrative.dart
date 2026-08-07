import 'dart:convert';

import '../../core/constants/app_strings.dart';

/// Parses referral-reason wire values into clean tokens.
///
/// Accepts:
/// - JSON array string: `["bloodPressure", "symptoms"]`
/// - Comma / semicolon list: `bloodPressure, bloodGlucose`
/// - Already-decoded [List]
///
/// Strips brackets/quotes so timeline copy never shows raw JSON.
List<String> parseReferralReasonTokens(Object? reasons) {
  if (reasons == null) return const [];

  if (reasons is List) {
    return reasons
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  final trimmed = reasons.toString().trim();
  if (trimmed.isEmpty) return const [];

  if (trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) return parseReferralReasonTokens(decoded);
    } catch (_) {
      // Fall through to delimiter split after stripping brackets.
    }
  }

  return trimmed
      .replaceAll(RegExp(r'^\[|\]$'), '')
      .split(RegExp(r'[,;]'))
      .map((r) => r.trim().replaceAll(RegExp(r'''^["']+|["']+$'''), ''))
      .where((r) => r.isNotEmpty)
      .toList(growable: false);
}

/// Short human-readable label for a single referral reason token.
String shortReasonLabel(String reason) {
  final k = reason.toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ').trim();
  final compact = k.replaceAll(' ', '');
  if (compact.contains('bloodglucose') ||
      (compact.contains('glucose') && !compact.contains('bloodpressure'))) {
    return ReferralStrings.shortReasonBloodGlucoseElevated;
  }
  if (compact.contains('pulse')) return ReferralStrings.shortReasonAbnormalPulse;
  if (compact.contains('bloodpressure') ||
      k == 'bp' ||
      compact.contains('hypertension')) {
    return ReferralStrings.shortReasonHighBp;
  }
  if (compact.contains('hemoglobin') ||
      compact.contains('anaemia') ||
      compact.contains('anemia') ||
      (k.startsWith('hb') && k.length <= 4)) {
    return ReferralStrings.shortReasonLowHbAnemia;
  }
  if (compact.contains('dangersign') || k == 'danger') return ReferralStrings.shortReasonDangerSign;
  if (compact.contains('temperature') || compact.contains('fever')) {
    return ReferralStrings.shortReasonElevatedTemp;
  }
  if (compact.contains('weight') && !compact.contains('birth')) {
    return ReferralStrings.shortReasonLowWeight;
  }
  if (compact.contains('medication') || compact.contains('adherence')) {
    return ReferralStrings.shortReasonLowAdherence;
  }
  if (compact.contains('familyplanning') ||
      compact.contains('contraception') ||
      k == 'fp') {
    return ReferralStrings.shortReasonNoFpMethod;
  }
  if (compact.contains('supplement') ||
      compact.contains('vitamin') ||
      compact.contains('ifa') ||
      compact.contains('calcium')) {
    return ReferralStrings.shortReasonSupplementGap;
  }
  if (compact.contains('overdue') || compact.contains('missedvisit')) {
    return ReferralStrings.shortReasonVisitOverdue;
  }
  if (compact.contains('symptom')) return ReferralStrings.shortReasonClinicalSymptoms;
  final t = reason.trim();
  if (t.isEmpty) return '';
  // camelCase / snake_case → spaced words for unknown codes
  final spaced = t
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .trim();
  return spaced[0].toUpperCase() + spaced.substring(1);
}

int _sys(String bp) {
  final parts = bp.split('/');
  if (parts.isEmpty) return 0;
  return int.tryParse(parts[0].trim()) ?? 0;
}

int _dia(String bp) {
  final parts = bp.split('/');
  if (parts.length < 2) return 0;
  return int.tryParse(parts[1].trim()) ?? 0;
}

/// Builds CARE HISTORY referral subtitle from reason tokens + vitals in [raw].
String buildReferralNarrative(Object? reasons, Map<String, dynamic> raw) {
  final tokens = parseReferralReasonTokens(reasons)
      .map((r) => r.toLowerCase().replaceAll(RegExp(r'[\s_]+'), ''))
      .where((r) => r.isNotEmpty)
      .toSet();
  final reasonLower = tokens.join(' ');

  bool hasReason(List<String> keys) =>
      keys.any((k) => reasonLower.contains(k.replaceAll(' ', '')));

  final findings = <String>[];
  final handled = <String>{};

  final dSign =
      (raw['dangerSigns']?.toString() ?? raw['dangerSign']?.toString() ?? '')
          .trim();
  final dSignPresent = dSign.isNotEmpty &&
      !const ['none', 'no', 'false', ''].contains(dSign.toLowerCase());
  if (hasReason(['danger']) || dSignPresent) {
    findings.add(dSignPresent
        ? ReferralStrings.dangerSignReported(dSign)
        : ReferralStrings.dangerSignReportedGeneric);
    handled.addAll(['danger']);
  }

  final bp = raw['bp']?.toString() ?? '';
  final sys = _sys(bp);
  final dia = _dia(bp);
  final bpHigh = sys >= 140 || dia >= 90;
  if (hasReason(['bp', 'bloodpressure', 'hypertension']) || bpHigh) {
    if (bp.isNotEmpty && sys > 0) {
      if (sys >= 160 || dia >= 110) {
        findings.add(ReferralStrings.bpDangerouslyElevated(bp));
      } else {
        findings.add(ReferralStrings.bpAboveNormal(bp));
      }
    } else {
      findings.add(ReferralStrings.bpAboveNormalGeneric);
    }
    handled.addAll(['bp', 'bloodpressure', 'hypertension']);
  }

  final bg = double.tryParse(raw['bg']?.toString() ?? '') ?? 0;
  final bgType = raw['bgType']?.toString() ?? 'RBS';
  final bgThreshold = bgType == 'FBS' ? 7.0 : 11.1;
  final bgHigh = bg > 0 && bg < 50 && bg >= bgThreshold;
  if (hasReason(['glucose', 'bloodsugar', 'bloodglucose']) || bgHigh) {
    if (bg > 0 && bg < 50) {
      findings.add(ReferralStrings.bloodSugarElevated('$bg', bgType));
    } else {
      findings.add(ReferralStrings.bloodSugarElevatedGeneric);
    }
    handled.addAll(['glucose', 'bloodsugar', 'bloodglucose']);
  }

  final hb = double.tryParse(raw['hemoglobin']?.toString() ?? '') ?? 0;
  final hbPlausible = hb > 0 && hb <= 20;
  final hbLow = hbPlausible && hb < 8;
  if (hasReason(['hemoglobin', 'anemia', 'anaemia']) || hbLow) {
    if (hbPlausible) {
      findings.add(hb < 7
          ? ReferralStrings.severeAnemiaWithValue('$hb')
          : ReferralStrings.anemiaWithValue('$hb'));
    } else {
      findings.add(ReferralStrings.severeAnemiaGeneric);
    }
    handled.addAll(['hemoglobin', 'anemia', 'anaemia']);
  }

  final pulse = int.tryParse(
          raw['pulse']?.toString() ?? raw['heartRate']?.toString() ?? '') ??
      0;
  final pulseAbnormal = pulse > 0 && (pulse > 90 || pulse < 60);
  if (hasReason(['pulse']) || pulseAbnormal) {
    if (pulse > 0) {
      findings.add(pulse > 90
          ? ReferralStrings.pulseAboveNormal('$pulse')
          : ReferralStrings.pulseBelowNormal('$pulse'));
    } else {
      findings.add(ReferralStrings.pulseAbnormalGeneric);
    }
    handled.add('pulse');
  }

  final rawTemp = double.tryParse(raw['temperature']?.toString() ?? '') ?? 0;
  final tempC = rawTemp >= 50 ? (rawTemp - 32) * 5 / 9 : rawTemp;
  final tempHigh = tempC > 0 && tempC >= 38.9;
  if (hasReason(['temperature', 'fever']) || tempHigh) {
    if (tempC > 0) {
      findings.add(ReferralStrings.temperatureElevated(tempC.toStringAsFixed(1)));
    } else {
      findings.add(ReferralStrings.elevatedTemperatureGeneric);
    }
    handled.addAll(['temperature', 'fever']);
  }

  final wt = double.tryParse(raw['weight']?.toString() ?? '') ?? 0;
  final wtPlausible = wt >= 20 && wt <= 200;
  final wtLow = wtPlausible && wt < 45;
  if (hasReason(['weight']) || wtLow) {
    if (wtPlausible) {
      findings.add(ReferralStrings.lowWeightWithValue('$wt'));
    } else {
      findings.add(ReferralStrings.lowWeightGeneric);
    }
    handled.add('weight');
  }

  if (hasReason(['medication', 'adherence'])) {
    findings.add(ReferralStrings.medicationAdherenceLow);
    handled.addAll(['medication', 'adherence']);
  }

  if (hasReason(['familyplanning', 'contraception', 'fp'])) {
    findings.add(ReferralStrings.noContraceptionMethod);
    handled.addAll(['familyplanning', 'contraception', 'fp']);
  }

  if (hasReason(['supplement', 'vitamin', 'ifa', 'calcium'])) {
    findings.add(ReferralStrings.supplementGapNarrative);
    handled.addAll(['supplement', 'vitamin', 'ifa', 'calcium']);
  }

  if (hasReason(['overdue', 'missedvisit'])) {
    findings.add(ReferralStrings.visitOverdueNarrative);
    handled.addAll(['overdue', 'missedvisit']);
  }

  if (hasReason(['symptom'])) {
    findings.add(ReferralStrings.clinicalSymptomsPresent);
    handled.addAll(['symptom', 'symptoms']);
  }

  for (final token in tokens) {
    if (token.length <= 2) continue;
    if (handled.any((h) => token.contains(h) || h.contains(token))) continue;
    final label = shortReasonLabel(token);
    if (label.isNotEmpty) findings.add(ReferralStrings.labelWithPeriod(label));
  }

  return findings.isEmpty
      ? ReferralStrings.referredForClinicalReviewFallback
      : findings.join(' ');
}
