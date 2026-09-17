import 'dart:convert';

import 'assessment_thresholds.dart';

/// Normalises glucose-type wire values to the NCD display vocabulary
/// (`FBS` / `RBS` / `PPBS`).
///
/// ANC/PNC forms use `fasting` / `random`; NCD forms use `fbs` / `rbs`.
String? normalizeGlucoseTypeLabel(String? raw) {
  if (raw == null) return null;
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return null;
  return switch (t) {
    'fasting' || 'fbs' => 'FBS',
    'random' || 'rbs' => 'RBS',
    'postprandial' || 'ppbs' => 'PPBS',
    _ => raw.trim().toUpperCase(),
  };
}

bool isFastingGlucoseType(String? raw) =>
    normalizeGlucoseTypeLabel(raw) == 'FBS';

/// True when [bgMmol] meets the programme-specific elevated threshold.
bool isGlucoseElevated(
  double bgMmol,
  String? bgType, {
  required bool anc,
}) {
  if (bgMmol <= 0) return false;
  final label = normalizeGlucoseTypeLabel(bgType);
  if (anc) {
    return label == 'FBS'
        ? bgMmol >= ancFbsDiabetesMmol
        : bgMmol >= ancRbsDiabetesMmol;
  }
  return label == 'FBS'
      ? bgMmol >= ncdControlledFbsMax
      : bgMmol >= ncdControlledRbsMax;
}

/// Unpacks the `{kind, raw}` envelope written by [AssessmentDao].
Map<String, dynamic> unpackAssessmentRaw(Map<String, dynamic> rawJson) {
  final r = rawJson['raw'];
  if (r is String) {
    try {
      final decoded = jsonDecode(r);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  if (r is Map) return Map<String, dynamic>.from(r);
  return rawJson;
}

String? _rawStr(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is List) {
    return v
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .join(', ');
  }
  return v.toString();
}

void _flattenMapInto(Map<String, dynamic> out, Map<dynamic, dynamic> sub) {
  for (final e in sub.entries) {
    out.putIfAbsent(e.key.toString(), () => e.value);
  }
}

/// Normalises assessment raw JSON so clinical fields are readable as
/// `bp`, `bg`, and `bgType` regardless of programme wire shape.
Map<String, dynamic> normalizeAssessmentRaw(Map<String, dynamic> rawJson) {
  final raw = unpackAssessmentRaw(rawJson);
  final out = Map<String, dynamic>.from(raw);

  for (final subKey in const ['observations', 'assessmentDetails']) {
    final sub = raw[subKey];
    if (sub is Map) _flattenMapInto(out, sub);
  }

  for (final subKey in const ['familyPlanning', 'family_planning']) {
    final sub = out[subKey];
    if (sub is Map) _flattenMapInto(out, sub);
  }

  for (var depth = 0; depth < 2; depth++) {
    var lifted = false;
    for (final subKey in const [
      'pwProfile',
      'pregnancyDetailsAndHistory',
      'pregnancyDetails',
      'pregnancyProfile',
      'obstetricHistory',
    ]) {
      final sub = out[subKey];
      if (sub is! Map) continue;
      _flattenMapInto(out, sub);
      lifted = true;
    }
    if (!lifted) break;
  }

  // ANC / PNC / RMNCH nested programme groups (mirrors LocalAssessmentDao).
  for (final subKey in const [
    'medicalHistoryPhysicalExamination',
    'pointOfCareInvestigations',
    'dangerSignsRiskIdentification',
    'maternalHealthAssessment',
    'anc',
    'pncMother',
    'pnc',
  ]) {
    final sub = out[subKey];
    if (sub is Map) _flattenMapInto(out, sub);
  }

  final bpLog = out['bpLog'] ?? raw['bpLog'];
  if (bpLog is Map) {
    out.putIfAbsent('avgSystolic', () => bpLog['avgSystolic']);
    out.putIfAbsent('avgDiastolic', () => bpLog['avgDiastolic']);
  }
  final gLog = out['glucoseLog'] ?? raw['glucoseLog'];
  if (gLog is Map) {
    out.putIfAbsent('glucoseValue', () => gLog['glucose'] ?? gLog['glucoseValue']);
    out.putIfAbsent('glucoseType', () => gLog['glucoseType']);
  }

  if (_rawStr(out['bp']) == null) {
    int? sys;
    int? dia;
    for (final k in const ['systolic', 'bloodPressureSystolic', 'avgSystolic']) {
      final v = out[k];
      if (v is num) {
        sys = v.toInt();
        break;
      }
      if (v is String) {
        sys = int.tryParse(v);
        if (sys != null) break;
      }
    }
    if (sys == null) {
      final log = out['bpLogDetails'];
      if (log is List && log.isNotEmpty && log.first is Map) {
        final first = log.first as Map;
        final s = first['systolic'];
        sys = s is num ? s.toInt() : (s is String ? int.tryParse(s) : null);
        final d = first['diastolic'];
        dia = d is num ? d.toInt() : (d is String ? int.tryParse(d) : null);
      }
    }
    if (dia == null) {
      for (final k in const ['diastolic', 'bloodPressureDiastolic', 'avgDiastolic']) {
        final v = out[k];
        if (v is num) {
          dia = v.toInt();
          break;
        }
        if (v is String) {
          dia = int.tryParse(v);
          if (dia != null) break;
        }
      }
    }
    if (sys != null && dia != null) out['bp'] = '$sys/$dia';
  }

  if (_rawStr(out['bg']) == null) {
    final bloodSugarKind =
        (out['bloodSugar'] as String?)?.trim().toLowerCase();
    final fastingVal = out['bloodSugarFasting'] ?? out['fastingBloodSugar'];
    final randomVal = out['bloodSugarRandom'] ?? out['randomBloodSugar'];

    dynamic glu;
    String? inferredType;

    if (fastingVal != null &&
        (bloodSugarKind == null ||
            bloodSugarKind == 'fasting' ||
            isFastingGlucoseType(out['glucoseType']?.toString()))) {
      glu = fastingVal;
      inferredType = 'fasting';
    } else if (randomVal != null &&
        (bloodSugarKind == null || bloodSugarKind == 'random')) {
      glu = randomVal;
      inferredType = 'random';
    } else {
      glu = out['glucoseValue'] ??
          out['glucose'] ??
          out['bloodGlucose'] ??
          out['ancBloodGlucose'];
      inferredType = out['glucoseType']?.toString() ?? bloodSugarKind;
    }

    if (glu != null) {
      out['bg'] = glu.toString();
      out.putIfAbsent('glucoseType', () => inferredType);
    }
  }

  final resolvedType = normalizeGlucoseTypeLabel(
    out['bgType']?.toString() ??
        out['glucoseType']?.toString() ??
        out['bloodSugar']?.toString(),
  );
  if (resolvedType != null) {
    out['bgType'] = resolvedType;
  }

  return out;
}
