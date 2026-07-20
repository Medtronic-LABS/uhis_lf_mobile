import '../../../core/clinical/referral_evaluator.dart';
import '../../../core/debug/console_log.dart';
import 'canonical_visit_data.dart';

/// A single per-programme assessment payload ready for
/// [AssessmentRepository.saveAssessment].
class ProgrammePayload {
  const ProgrammePayload({
    required this.assessmentType,
    required this.details,
  });

  /// Wire-format assessment type: `'ANC'`, `'NCD'`, `'PNC_MOTHER'`, `'PNC_CHILD'`, etc.
  final String assessmentType;

  /// Nested programme-specific map stored as [LocalAssessmentEntity.assessmentDetails] JSON.
  ///
  /// Matches Android SPICE offline-sync DTO structure exactly:
  ///   ANC        → medicalHistoryPhysicalExamination / pointOfCareInvestigations /
  ///                dangerSignsRiskIdentification / vaccinationAndSupplements /
  ///                ancServicesBirthPreparedness / visitNo / bmiCategory
  ///   NCD        → bpLog (weight/height/bmi inside) / glucoseLog / symptomsLog
  ///   PNC_MOTHER → maternalHealthAssessment / pregnancyHistory / postpartumContraception /
  ///                visitNo / daysSinceDelivery
  ///
  /// [LocalAssessmentEntity.toApiRequest] wraps to `{ "anc": details }` etc.
  final Map<String, dynamic> details;
}

/// Decomposes a [CanonicalVisitData] into per-programme [ProgrammePayload]s.
///
/// Field-ID conventions follow the form JSON configs in assets/forms/.
/// Type coercions mirror what Android SPICE sends on the wire.
abstract final class UnifiedPayloadMapper {
  UnifiedPayloadMapper._();

  static List<ProgrammePayload> decompose(
    CanonicalVisitData data,
    Set<String> activeFormTypes,
  ) {
    final payloads = <ProgrammePayload>[];

    if (activeFormTypes.contains('pwProfile')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PWPROFILE',
        details: _toPwProfile(data),
      ));
    }

    if (activeFormTypes.contains('anc')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'ANC',
        details: _toAnc(data),
      ));
    }

    if (activeFormTypes.contains('ncd')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'NCD',
        details: _toNcd(data),
      ));
    }

    if (activeFormTypes.contains('pncMother')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PNC_MOTHER',
        details: _toPncMother(data),
      ));
    }

    // PNC_NEONATE: Android wire type is "PNC_NEONATE" (not "PNC_CHILD") wrapped
    // under "pncNeonatal" key. GAP 6 fix.
    if (activeFormTypes.contains('pncChild') ||
        activeFormTypes.contains('pncNeonatal')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PNC_NEONATE',
        details: _toPncChild(data),
      ));
    }

    if (activeFormTypes.contains('pregnancyOutcome')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PREGNANCY_OUTCOME',
        details: _toPregnancyOutcome(data),
      ));
    }

    // GAP 10: programmes that have form sections but previously had no mapper.
    if (activeFormTypes.contains('eyeCare') ||
        activeFormTypes.contains('eye_care')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'EYE_CARE',
        details: _toEyeCare(data),
      ));
    }

    if (activeFormTypes.contains('cataract')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'CATARACT',
        details: _toCataract(data),
      ));
    }

    if (activeFormTypes.contains('familyPlanning') ||
        activeFormTypes.contains('family_planning')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'FAMILY_PLANNING',
        details: _toFamilyPlanning(data),
      ));
    }

    // GAP 11b: IMCI sick-child visit (in pilot scope; form to be added separately).
    if (activeFormTypes.contains('iccm') ||
        activeFormTypes.contains('imci')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'ICCM',
        details: _toIccm(data),
      ));
    }

    if (activeFormTypes.contains('tb')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'TB',
        details: _toTb(data),
      ));
    }

    // TODO: add EPI form + mapper when EPI is added to kPilotProgrammes (GAP 12).
    // TODO: add HIV form + mapper when HIV is in scope (GAP 12).
    // TODO: add NUTRITION form + mapper when NUTRITION is in scope (GAP 12).

    _debugLogMergedCommons(data);
    _debugLogPayloads(payloads);
    ConsoleLog.banner('[PayloadDebug] programme-payload — decompose → ${payloads.length} payloads: ${payloads.map((p) => p.assessmentType).join(', ')}');

    return payloads;
  }

  static void _debugLogMergedCommons(CanonicalVisitData d) {
    ConsoleLog.step('[PayloadDebug] programme-payload — merged common fields: '
        'systolic=${d.getValue('systolic')} diastolic=${d.getValue('diastolic')} '
        'weight=${d.getValue('weight')} '
        'glucoseType=${d.getValue('glucoseType') ?? d.getValue('bloodSugar')} '
        'glucoseValue=${d.getValue('glucoseValue') ?? d.getValue('glucose')}');
  }

  static void _debugLogPayloads(List<ProgrammePayload> payloads) {
    for (final p in payloads) {
      final summary = p.details.entries
          .where((e) => e.value != null)
          .map((e) {
            final v = e.value;
            if (v is Map) return '${e.key}:{${v.keys.join(',')}}';
            if (v is List) return '${e.key}:[${v.length}]';
            return '${e.key}=${e.value}';
          })
          .join(' · ');
      ConsoleLog.step('[PayloadDebug] programme-payload   ${p.assessmentType}: $summary');
    }
  }

  // ── ANC ────────────────────────────────────────────────────────────────────
  // Android group constants (AssessmentDefinedParams.kt):
  //   GROUP_MEDICAL_HISTORY_PHYSICAL_EXAMINATION = "medicalHistoryPhysicalExamination"
  //   GROUP_POINT_OF_CARE_INVESTIGATIONS         = "pointOfCareInvestigations"
  //   GROUP_DANGER_SIGNS_RISK_IDENTIFICATION     = "dangerSignsRiskIdentification"
  //   GROUP_VACCINATION_AND_SUPPLEMENTS          = "vaccinationAndSupplements"
  //   GROUP_ANC_SERVICES_BIRTH_PREPAREDNESS      = "ancServicesBirthPreparedness"
  //
  // ANC systolic/diastolic are STRINGS on the wire (Android reference: "139", "88").
  // temperature/pulse/weight/height are numbers.
  // BP lives in medicalHistoryPhysicalExamination — NOT in a separate bpLog.

  static Map<String, dynamic> _toAnc(CanonicalVisitData d) {
    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // BP: pass through as strings (Android sends "139"/"88").
    final rawSys = d.getValue('systolic') ?? d.getValue('bloodPressureSystolic');
    final rawDia = d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic');

    // Numeric vitals.
    final weight = asNum(d.getValue('weight'));
    final height = asNum(d.getValue('height'));
    final bmi = asNum(d.getValue('bmi'));
    final temperature = asNum(d.getValue('temperature'));
    final pulse = d.getValue('pulse');
    final fundalHeight = asNum(d.getValue('fundalHeight'));

    // Android sends systolic/diastolic as integer strings ("139", "88").
    // If the value came in as a double (e.g. 80.0), truncate to int first so
    // Java's Integer deserializer doesn't reject "80.0".
    String? bpStr(dynamic v) {
      if (v == null) return null;
      final n = asNum(v);
      if (n != null) return n.toInt().toString();
      return v.toString();
    }

    final medHx = _compact({
      if (rawSys != null) 'systolic': bpStr(rawSys),
      if (rawDia != null) 'diastolic': bpStr(rawDia),
      if (rawSys != null) 'systolicUnit': 'mmHg',
      if (rawDia != null) 'diastolicUnit': 'mmHg',
      if (weight != null) 'weight': weight,
      if (weight != null) 'weightUnit': 'kg',
      if (height != null) 'height': height,
      if (height != null) 'heightUnit': 'cm',
      if (bmi != null) 'bmi': bmi,
      if (temperature != null) 'temperature': temperature,
      if (temperature != null) 'temperatureUnit': '°F',
      if (pulse != null) 'pulse': pulse,
      if (pulse != null) 'pulseUnit': 'bpm',
      if (fundalHeight != null) 'fundalHeight': fundalHeight,
      if (fundalHeight != null) 'fundalHeightUnit': 'cm',
      'hemoglobin': d.getValue('hemoglobin'),
      'fetalHeartRate': d.getValue('fetalHeartRate'),
      'fetalMovement': d.getValue('fetalMovement'),
      'presentation': d.getValue('presentation'),
      // Backend DTO uses "edema" spelling.
      'edema': d.getValue('oedema') ?? d.getValue('edema'),
      'pallor': d.getValue('pallor'),
      'parity': d.getValue('parity'),
      'gestationalAge': d.getValue('gestationalAge'),
      'pregnantWomanExistingIllness': d.getValue('pregnantWomanExistingIllness'),
      'pregnantWomanOnTreatment': d.getValue('pregnantWomanOnTreatment'),
      'previousPregnancyComplications': d.getValue('previousPregnancyComplications') ?? <String>[],
      'highRiskPregnantWoman': d.getValue('highRiskPregnantWoman'),
    });

    // ANC point-of-care:
    //   glucoseType == 'fbs'         → bloodSugarFasting + bloodSugar: 'fasting'
    //   glucoseType == 'rbs'/'ppbs'  → bloodSugarRandom  + bloodSugar: 'random'
    //   hemoglobin already in medHx; hemoglobinUnit added here for POC DTO shape.
    //
    // Fan-out: union reads so the single captured glucose value populates ANC,
    // PNC, and NCD payloads regardless of which field ID survived dedup.
    final glucoseType = (d.getValue('glucoseType') ??
        d.getValue('bloodSugar')) as String?;
    final glucoseValue = asNum(d.getValue('glucoseValue') ??
        d.getValue('glucose') ??
        d.getValue('ancBloodGlucose') ??
        d.getValue('fastingBloodSugar') ??
        d.getValue('randomBloodSugar'));
    final hasFbs = glucoseType == 'fbs' && glucoseValue != null;
    final hasRbs = glucoseType != null && glucoseType != 'fbs' && glucoseValue != null;
    final pointOfCare = _compact({
      'urinaryAlbumin': d.getValue('urinaryAlbumin'),
      'urinaryBilirubin': d.getValue('urinaryBilirubin'),
      'urinarySugar': d.getValue('urinarySugar'),
      'hemoglobin': d.getValue('hemoglobin'),
      if (d.getValue('hemoglobin') != null) 'hemoglobinUnit': 'g/dL',
      if (glucoseType != null && glucoseValue != null) 'bloodSugar': glucoseType == 'fbs' ? 'fasting' : 'random',
      if (hasFbs) 'bloodSugarFasting': glucoseValue,
      if (hasFbs) 'bloodSugarFastingUnit': d.getValue('glucoseUnit') as String? ?? 'mmol/L',
      if (hasRbs) 'bloodSugarRandom': glucoseValue,
      if (hasRbs) 'bloodSugarRandomUnit': d.getValue('glucoseUnit') as String? ?? 'mmol/L',
      // Direct fields when collected without glucoseType routing.
      if (!hasFbs && glucoseValue == null) 'bloodSugarFasting': d.getValue('bloodSugarFasting'),
      if (!hasRbs && glucoseValue == null) 'bloodSugarRandom': d.getValue('bloodSugarRandom'),
    });

    // dangerSigns: always include collected trimester lists.
    final dangerSigns = <String, dynamic>{};
    final ds12 = d.getValue('dangerSignsExperienced12');
    if (ds12 != null) dangerSigns['dangerSignsExperienced12'] = ds12;
    final ds13 = d.getValue('dangerSignsExperienced13To27');
    if (ds13 != null) dangerSigns['dangerSignsExperienced13To27'] = ds13;
    final ds28 = d.getValue('dangerSignsExperienced28To40');
    if (ds28 != null) dangerSigns['dangerSignsExperienced28To40'] = ds28;
    final eclampsia = d.getValue('eclampsia');
    if (eclampsia != null) dangerSigns['eclampsia'] = eclampsia;
    // Always send at least the first-trimester key so backend danger-sign check has a target.
    dangerSigns.putIfAbsent('dangerSignsExperienced12', () => <String>[]);

    // Fan-out: whichever IFA/Calcium field survived the semantic dedup feeds
    // every relevant programme payload via union reads.
    final ifaConsumed = d.getValue('ifaTotalConsumed') ??
        d.getValue('ifaTabletsConsumed') ??
        d.getValue('ifaTablets');
    final ifaProvided =
        d.getValue('ifaProvided') ?? d.getValue('ifaTabletsProvided');
    final calciumConsumed = d.getValue('calciumTotalConsumed') ??
        d.getValue('calciumTabletsConsumed') ??
        d.getValue('calciumTablets');
    final calciumProvided =
        d.getValue('calciumProvided') ?? d.getValue('calciumTabletsProvided');

    final vaccination = _compact({
      'ttTdCompleted': d.getValue('ttTdCompleted'),
      'folicAcidTotalConsumed': d.getValue('folicAcidTotalConsumed') ??
          d.getValue('folicAcidTablets'),
      'folicAcidProvided': d.getValue('folicAcidProvided'),
      'ifaTotalConsumed': ifaConsumed,
      'ifaProvided': ifaProvided,
      'calciumTotalConsumed': calciumConsumed,
      'calciumProvided': calciumProvided,
    });

    final birthPrep = _compact({
      'facilityIdentifiedForDelivery': d.getValue('facilityIdentifiedForDelivery'),
      'ancVisitsOtherProviders': d.getValue('ancVisitsOtherProviders'),
      'ancFromMedicalDoctor': d.getValue('ancFromMedicalDoctor'),
      'ultrasound': d.getValue('ultrasound'),
    });

    final visitNo = d.getValue('ancVisitNumber') ?? d.getValue('visitNo');
    final bmiCategory = d.getValue('bmiCategory');

    // Compute ANC care gaps (mirrors Android ANCAssessmentEvaluator.evaluateGapsInANC).
    int? toInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final gestationalWeeks = asNum(
      d.getValue('gestationalAge') ?? d.getValue('gestationalWeeks'),
    );
    final gapsResult = AncReferralEvaluator.evaluateGaps(
      gestationalAgeWeeks: gestationalWeeks,
      ttTdCompleted: d.getValue('ttTdCompleted') as String?,
      ultrasound: d.getValue('ultrasound') as String?,
      ancFromMedicalDoctor: d.getValue('ancFromMedicalDoctor') as String?,
      facilityIdentifiedForDelivery:
          d.getValue('facilityIdentifiedForDelivery') as String?,
      ifaTotalConsumed: toInt(ifaConsumed),
      calciumTotalConsumed: toInt(calciumConsumed),
      ancVisitCount: toInt(visitNo),
    );

    final summary = <String, dynamic>{};
    if (gapsResult.hasGaps) summary['gapsInAnc'] = gapsResult.gaps;

    return {
      if (visitNo != null) 'visitNo': visitNo,
      if (bmiCategory != null) 'bmiCategory': bmiCategory,
      if (medHx.isNotEmpty) 'medicalHistoryPhysicalExamination': medHx,
      if (pointOfCare.isNotEmpty) 'pointOfCareInvestigations': pointOfCare,
      'dangerSignsRiskIdentification': dangerSigns,
      if (vaccination.isNotEmpty) 'vaccinationAndSupplements': vaccination,
      if (birthPrep.isNotEmpty) 'ancServicesBirthPreparedness': birthPrep,
      if (summary.isNotEmpty) 'summary': summary,
    };
  }

  // ── PWPROFILE ──────────────────────────────────────────────────────────────
  // PW registration assessment — captures LMP, gravida, parity, living
  // children, and obstetric history collected in pregnancyDetailsAndHistory.
  // Sent as a separate assessment alongside ANC when both are selected.
  static Map<String, dynamic> _toPwProfile(CanonicalVisitData d) {
    final lmpStr = d.getValue('lmp') as String?;
    // Server stores and returns LMP as epoch milliseconds.
    final lmpMs = lmpStr != null
        ? DateTime.tryParse(lmpStr)?.millisecondsSinceEpoch
        : null;
    return _compact({
      if (lmpMs != null) 'lmpDate': lmpMs,
      'gravida': d.getValue('gravida'),
      'parity': d.getValue('parity'),
      'livingChildren': d.getValue('livingChildren'),
      'ageOfLastChild': d.getValue('ageOfLastChild'),
      'pregnancyTest': d.getValue('pregnancyTest'),
    });
  }

  // ── NCD ────────────────────────────────────────────────────────────────────
  // Android NCD payload (from reference + AssessmentViewModel.kt):
  //   ncd.bpLog        = { diagnosedBP, diagnosedBPMedication, avgSystolic,
  //                        avgDiastolic, avgBloodPressure, weight, height, bmi,
  //                        isRegularSmoker, cvdRisk, bpLogDetails[] }
  //   ncd.glucoseLog   = { diagnosedGlucose, diagnosedGlucoseMedication,
  //                        glucose, glucoseType, glucoseUnit, hba1c,
  //                        glucoseDateTime, hba1cDateTime }
  //   ncd.symptomsLog  = { compliance:"Yes"/"No", hasSymptoms:"Yes"/"No",
  //                        ncdSymptoms[], newWorseningSymptoms,
  //                        ncdSymptomsMedication }
  //
  // weight/height/bmi/isRegularSmoker INSIDE bpLog as numbers.
  // NCD avgSystolic/avgDiastolic are INTEGER on the wire (not strings).
  // compliance and hasSymptoms are "Yes"/"No" STRINGS (not booleans).
  //
  // Multiple BP readings: form may supply bp_reading_1..3 as JSON list under
  // 'bpReadings', or flat systolic_1/diastolic_1 etc. When present, the
  // bpLogDetails array carries all readings and averages are computed here.

  static Map<String, dynamic> _toNcd(CanonicalVisitData d) {
    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // Normalize boolean-like values to Android "Yes"/"No" string convention.
    String? yesNo(dynamic v) {
      if (v == null) return null;
      if (v == true || v == 'true' || v == 'yes' || v == 'Yes' || v == 1) return 'Yes';
      if (v == false || v == 'false' || v == 'no' || v == 'No' || v == 0) return 'No';
      // Already a string — normalize casing
      final s = v.toString().toLowerCase();
      if (s == 'yes') return 'Yes';
      if (s == 'no') return 'No';
      return v.toString();
    }

    // Coerce to Dart bool for fields where the DTO expects Boolean (not string).
    bool? toBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      final s = v.toString().toLowerCase();
      if (s == 'true' || s == 'yes' || s == '1') return true;
      if (s == 'false' || s == 'no' || s == '0') return false;
      return null;
    }

    // ── BP readings ──────────────────────────────────────────────────────────
    // Support up to 3 indexed readings (systolic_1/diastolic_1 … _3) or a
    // single flat systolic/diastolic. Averages and bpLogDetails are derived
    // from whichever readings are present.
    final bpLog = <String, dynamic>{};
    final bpDetails = <Map<String, dynamic>>[];

    // Priority: bpLogDetails (stored by the _BpReadingField widget in the
    // unified form — field ID matches field_library.json), then bpReadings
    // (legacy AI Scribe pre-fill), then indexed/flat fields.
    final bpReadingsRaw =
        d.getValue('bpLogDetails') ?? d.getValue('bpReadings');
    if (bpReadingsRaw is List && bpReadingsRaw.isNotEmpty) {
      for (final r in bpReadingsRaw) {
        if (r is! Map) continue;
        final s = asNum(r['systolic']);
        final di = asNum(r['diastolic']);
        if (s != null && di != null) {
          final detail = <String, dynamic>{
            'systolic': s.toInt(),
            'diastolic': di.toInt(),
          };
          final p = asNum(r['pulse']);
          if (p != null) detail['pulse'] = p.toInt();
          bpDetails.add(detail);
        }
      }
    } else {
      // Fall back to indexed flat fields, then to plain systolic/diastolic.
      for (var i = 1; i <= 3; i++) {
        final s = asNum(d.getValue('systolic_$i'));
        final di = asNum(d.getValue('diastolic_$i'));
        if (s != null && di != null) {
          final detail = <String, dynamic>{
            'systolic': s.toInt(),
            'diastolic': di.toInt(),
          };
          final p = asNum(d.getValue('pulse_$i'));
          if (p != null) detail['pulse'] = p.toInt();
          bpDetails.add(detail);
        }
      }
      // Fallback: single reading from plain fields.
      if (bpDetails.isEmpty) {
        final s = asNum(d.getValue('systolic') ?? d.getValue('bloodPressureSystolic'));
        final di = asNum(d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic'));
        if (s != null && di != null) {
          final detail = <String, dynamic>{
            'systolic': s.toInt(),
            'diastolic': di.toInt(),
          };
          final pulse = asNum(d.getValue('pulse'));
          if (pulse != null) detail['pulse'] = pulse.toInt();
          bpDetails.add(detail);
        }
      }
    }

    if (bpDetails.isNotEmpty) {
      final avgSys = (bpDetails.map((r) => r['systolic'] as int).reduce((a, b) => a + b) / bpDetails.length).round();
      final avgDia = (bpDetails.map((r) => r['diastolic'] as int).reduce((a, b) => a + b) / bpDetails.length).round();
      bpLog['avgSystolic'] = avgSys;
      bpLog['avgDiastolic'] = avgDia;
      bpLog['avgBloodPressure'] = '$avgSys/$avgDia';
      bpLog['bpLogDetails'] = bpDetails;
      // Android CommonUtils stamps bpTakenOn on every NCD BP log (UTC ISO-8601).
      bpLog['bpTakenOn'] = DateTime.now().toUtc().toIso8601String();
      // Biometric data inside bpLog (Android stores weight/height/bmi here).
      final weight = asNum(d.getValue('weight'));
      if (weight != null) bpLog['weight'] = weight;
      final height = asNum(d.getValue('height'));
      if (height != null) bpLog['height'] = height;
      final bmi = asNum(d.getValue('bmi'));
      if (bmi != null) bpLog['bmi'] = bmi;
      final bmiCategory = d.getValue('bmiCategory');
      if (bmiCategory != null) bpLog['bmiCategory'] = bmiCategory;
      final isRegularSmoker = d.getValue('isRegularSmoker');
      if (isRegularSmoker != null) {
        // Spice-service BpLogDTO field is Boolean — coerce "Yes"/"yes"/true → true.
        bpLog['isRegularSmoker'] = toBool(isRegularSmoker);
      }
      // Prior diagnosis fields: Flutter form uses isBeforeHtnDiagnosis / medicationFrequencyBp
      // (both store "Yes"/"No" strings); Android wire names are diagnosedBP / diagnosedBPMedication.
      final diagBp =
          d.getValue('diagnosedBP') ?? d.getValue('isBeforeHtnDiagnosis');
      if (diagBp != null) bpLog['diagnosedBP'] = diagBp;
      final diagBpMed =
          d.getValue('diagnosedBPMedication') ?? d.getValue('medicationFrequencyBp');
      if (diagBpMed != null) bpLog['diagnosedBPMedication'] = diagBpMed;
      final cvdRisk = d.getValue('cvdRisk');
      if (cvdRisk != null) bpLog['cvdRisk'] = cvdRisk;
    }

    // ── Glucose log ──────────────────────────────────────────────────────────
    // Fan-out: union reads so whichever glucose field survived the semantic
    // dedup (NCD: glucoseType/glucoseValue vs PNC: bloodSugar/fastingBloodSugar)
    // populates the NCD payload.
    final glucoseNum = asNum(d.getValue('glucoseValue') ??
        d.getValue('glucose') ??
        d.getValue('fastingBloodSugar') ??
        d.getValue('randomBloodSugar') ??
        d.getValue('ancBloodGlucose'));
    final glucoseLog = <String, dynamic>{};
    if (glucoseNum != null) {
      // Spice-service BpLogDTO / FHIR mapper both read `glucoseValue`, not `glucose`.
      glucoseLog['glucoseValue'] = glucoseNum;
      final glucoseType =
          d.getValue('glucoseType') ?? d.getValue('bloodSugar');
      if (glucoseType != null) glucoseLog['glucoseType'] = glucoseType;
      glucoseLog['glucoseUnit'] =
          d.getValue('glucoseUnit') as String? ?? 'mmol/L';
      glucoseLog['bgTakenOn'] = DateTime.now().toUtc().toIso8601String();
      final hba1c = asNum(d.getValue('hba1c'));
      if (hba1c != null) {
        glucoseLog['hba1c'] = hba1c;
        glucoseLog['hba1cUnit'] = d.getValue('hba1cUnit') as String? ?? '%';
      }
      final glucoseDateTime = d.getValue('glucoseDateTime');
      if (glucoseDateTime != null) glucoseLog['glucoseDateTime'] = glucoseDateTime;
      final hba1cDateTime = d.getValue('hba1cDateTime');
      if (hba1cDateTime != null) glucoseLog['hba1cDateTime'] = hba1cDateTime;
      // Prior diagnosis: Flutter form uses isBeforeDiabetesDiagnosis / medicationFrequencyBg;
      // Android wire names are diagnosedGlucose / diagnosedGlucoseMedication.
      final diagGlucose =
          d.getValue('diagnosedGlucose') ?? d.getValue('isBeforeDiabetesDiagnosis');
      if (diagGlucose != null) glucoseLog['diagnosedGlucose'] = diagGlucose;
      final diagGlucoseMed =
          d.getValue('diagnosedGlucoseMedication') ?? d.getValue('medicationFrequencyBg');
      if (diagGlucoseMed != null) glucoseLog['diagnosedGlucoseMedication'] = diagGlucoseMed;
    }

    // ── Symptoms log ─────────────────────────────────────────────────────────
    // Android always sends compliance and hasSymptoms as "Yes"/"No" strings.
    final symptomsLog = <String, dynamic>{};
    final complianceRaw = d.getValue('compliance');
    final complianceStr = yesNo(complianceRaw);
    if (complianceStr != null) symptomsLog['compliance'] = complianceStr;
    final hasSymptomsRaw = d.getValue('hasSymptoms');
    final hasSymptomsStr = yesNo(hasSymptomsRaw);
    if (hasSymptomsStr != null) symptomsLog['hasSymptoms'] = hasSymptomsStr;
    final ncdSymptoms = d.getValue('ncdSymptoms');
    if (ncdSymptoms != null) symptomsLog['ncdSymptoms'] = ncdSymptoms;
    final newWorseningSymptoms = d.getValue('newWorseningSymptoms');
    if (newWorseningSymptoms != null) symptomsLog['newWorseningSymptoms'] = newWorseningSymptoms;
    final ncdSymptomsMedication = d.getValue('ncdSymptomsMedication');
    if (ncdSymptomsMedication != null) symptomsLog['ncdSymptomsMedication'] = ncdSymptomsMedication;

    return {
      if (bpLog.isNotEmpty) 'bpLog': bpLog,
      if (glucoseLog.isNotEmpty) 'glucoseLog': glucoseLog,
      if (symptomsLog.isNotEmpty) 'symptomsLog': symptomsLog,
      if (d.getValue('htnScreening') != null) 'htnScreening': d.getValue('htnScreening'),
      if (d.getValue('generalInformation') != null)
        'generalInformation': d.getValue('generalInformation'),
      if (d.getValue('referralFacilityType') != null)
        'referralFacilityType': d.getValue('referralFacilityType'),
    };
  }

  // ── PNC Mother ─────────────────────────────────────────────────────────────
  // Android PNC Mother (from reference payload + RMNCH.kt):
  //   pncMother.maternalHealthAssessment = { systolic(str), diastolic(str),
  //     pulse(str), weight, hemoglobin, urinaryAlbumin, urinaryBilirubin,
  //     temperature, edema, postpartumDangerSigns, bloodSugar, fastingBloodSugar,
  //     fastingBloodSugarUnit, htnPatient, dmPatient, gdmPatient, eclampsia,
  //     onTreatmentHtnEclampsia, onTreatmentDmGdm, vitaminAConsumed,
  //     ifaTabletsProvided, ifaTabletsConsumed, calciumTabletsProvided,
  //     calciumTabletsConsumed, weightUnit, diastolicUnit, systolicUnit,
  //     pulseUnit, temperatureUnit, hemoglobinUnit, fastingBloodSugarUnit,
  //     randomBloodSugarUnit }
  //   pncMother.pregnancyHistory = { parity, gravida, livingChildren }
  //   pncMother.postpartumContraception = { familyPlanningMethods }
  //   pncMother.visitNo, pncMother.daysSinceDelivery
  //
  // systolic/diastolic/pulse are STRINGS on the wire (matching Android reference).

  static Map<String, dynamic> _toPncMother(CanonicalVisitData d) {
    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final rawSys = d.getValue('systolic') ?? d.getValue('bloodPressureSystolic');
    final rawDia = d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic');
    final rawPulse = d.getValue('pulse');
    final weight = asNum(d.getValue('weight'));
    final temperature = asNum(d.getValue('temperature'));

    // Android sends BP/pulse as integer strings; truncate doubles before stringify.
    String? bpStr(dynamic v) {
      if (v == null) return null;
      final n = asNum(v);
      if (n != null) return n.toInt().toString();
      return v.toString();
    }

    // Fan-out: union reads so the single captured glucose / IFA / Calcium
    // value populates the PNC payload regardless of which field ID survived
    // the semantic dedup (ANC fields vs PNC fields).
    final glucoseType = (d.getValue('glucoseType') ??
        d.getValue('bloodSugar')) as String?;
    final glucoseValue = asNum(d.getValue('glucoseValue') ??
        d.getValue('glucose') ??
        d.getValue('ancBloodGlucose') ??
        d.getValue('fastingBloodSugar') ??
        d.getValue('randomBloodSugar'));
    final hasFbs = glucoseType == 'fbs' && glucoseValue != null;
    final hasRbs = glucoseType != null && glucoseType != 'fbs' && glucoseValue != null;

    final ifaTabletsConsumed = d.getValue('ifaTabletsConsumed') ??
        d.getValue('ifaTotalConsumed') ??
        d.getValue('ifaTablets');
    final ifaTabletsProvided =
        d.getValue('ifaTabletsProvided') ?? d.getValue('ifaProvided');
    final calciumTabletsConsumed = d.getValue('calciumTabletsConsumed') ??
        d.getValue('calciumTotalConsumed') ??
        d.getValue('calciumTablets');
    final calciumTabletsProvided =
        d.getValue('calciumTabletsProvided') ?? d.getValue('calciumProvided');

    final maternal = _compact({
      if (rawSys != null) 'systolic': bpStr(rawSys),
      if (rawSys != null) 'systolicUnit': 'mmHg',
      if (rawDia != null) 'diastolic': bpStr(rawDia),
      if (rawDia != null) 'diastolicUnit': 'mmHg',
      if (rawPulse != null) 'pulse': bpStr(rawPulse),
      if (rawPulse != null) 'pulseUnit': 'per minute',
      if (weight != null) 'weight': weight,
      if (weight != null) 'weightUnit': 'kg',
      if (temperature != null) 'temperature': temperature,
      if (temperature != null) 'temperatureUnit': '°F',
      'hemoglobin': d.getValue('hemoglobin'),
      if (d.getValue('hemoglobin') != null) 'hemoglobinUnit': 'g/dL',
      'urinaryAlbumin': d.getValue('urinaryAlbumin'),
      'urinaryBilirubin': d.getValue('urinaryBilirubin'),
      'edema': d.getValue('oedema') ?? d.getValue('edema'),
      'postpartumDangerSigns': d.getValue('postpartumDangerSigns'),
      'htnPatient': d.getValue('htnPatient'),
      'dmPatient': d.getValue('dmPatient'),
      'gdmPatient': d.getValue('gdmPatient'),
      'eclampsia': d.getValue('eclampsia'),
      'onTreatmentHtnEclampsia': d.getValue('onTreatmentHtnEclampsia'),
      'onTreatmentDmGdm': d.getValue('onTreatmentDmGdm'),
      'vitaminAConsumed': d.getValue('vitaminAConsumed'),
      'ifaTabletsProvided': ifaTabletsProvided,
      'ifaTabletsConsumed': ifaTabletsConsumed,
      'calciumTabletsProvided': calciumTabletsProvided,
      'calciumTabletsConsumed': calciumTabletsConsumed,
      if (glucoseType != null && glucoseValue != null)
        'bloodSugar': glucoseType == 'fbs' ? 'fasting' : 'random',
      if (hasFbs) 'fastingBloodSugar': glucoseValue,
      if (hasFbs) 'fastingBloodSugarUnit': 'mmol/L',
      if (hasRbs) 'randomBloodSugar': glucoseValue,
      if (hasRbs) 'randomBloodSugarUnit': 'mmol/L',
    });
    if (hasFbs || hasRbs) maternal['bgTakenOn'] = DateTime.now().toUtc().toIso8601String();
    for (final sign in const [
      'heavyBleeding', 'foulSmellDischarge', 'severeAbdominalPain',
      'difficultyBreathing', 'convulsions', 'unconsciousness',
    ]) {
      final v = d.getValue(sign);
      if (v != null) maternal[sign] = v;
    }

    final pregnancy = _compact({
      'parity': d.getValue('parity'),
      'gravida': d.getValue('gravida'),
      'livingChildren': d.getValue('livingChildren'),
    });

    final contraception = _compact({
      'familyPlanningMethods': d.getValue('familyPlanningMethods'),
    });

    return _compact({
      if (maternal.isNotEmpty) 'maternalHealthAssessment': maternal,
      if (pregnancy.isNotEmpty) 'pregnancyHistory': pregnancy,
      if (contraception.isNotEmpty) 'postpartumContraception': contraception,
      'visitNo': d.getValue('pncVisitNumber') ?? d.getValue('visitNo'),
      'daysSinceDelivery': d.getValue('daysSinceDelivery'),
    });
  }

  // ── PNC Neonate (PNC_NEONATE wire type) ───────────────────────────────────
  // Android wraps under "pncNeonatal" key; _wrapDetailsForType handles that.
  // visitNo is extracted by _extractVisitNumber in local_assessment_dao.dart.

  static Map<String, dynamic> _toPncChild(CanonicalVisitData d) {
    return _compact({
      'visitNo': d.getValue('pncNeonateVisitNumber') ?? d.getValue('visitNo'),
      'isChildAlive': d.getValue('isChildAlive'),
      'childWeight': d.getValue('childWeight'),
      'childHeight': d.getValue('childHeight'),
      'childAge': d.getValue('childAge'),
      'neonateOutcome': d.getValue('neonateOutcome'),
      'stateOfBaby': d.getValue('stateOfBaby'),
      'breastfeeding': d.getValue('breastfeeding'),
    });
  }

  // ── Pregnancy Outcome ──────────────────────────────────────────────────────

  static Map<String, dynamic> _toPregnancyOutcome(CanonicalVisitData d) {
    return _compact({
      'deliveryType': d.getValue('deliveryType'),
      'deliveryAt': d.getValue('deliveryAt'),
      'deliveryDate': d.getValue('deliveryDate'),
      'deliveryStatus': d.getValue('deliveryStatus'),
      'motherAlive': d.getValue('motherAlive'),
      'neonateOutcome': d.getValue('neonateOutcome'),
      'stateOfBaby': d.getValue('stateOfBaby'),
    });
  }

  // ── Eye Care ───────────────────────────────────────────────────────────────
  // Android wire type: "eye_care", flat pass-through (no wrapper key).
  // Form section: "eyeCare" in layout_manifests.json.

  static Map<String, dynamic> _toEyeCare(CanonicalVisitData d) {
    return _compact({
      'visualAcuityRight': d.getValue('visualAcuityRight'),
      'visualAcuityLeft': d.getValue('visualAcuityLeft'),
      'eyeCondition': d.getValue('eyeCondition'),
      'eyeDisease': d.getValue('eyeDisease'),
      'referredForEyeCare': d.getValue('referredForEyeCare'),
      'eyeCareRecommendations': d.getValue('eyeCareRecommendations'),
      // Generic pass-through for any additional eye care fields in the form.
      'eyeCareAssessment': d.getValue('eyeCareAssessment'),
    });
  }

  // ── Cataract ───────────────────────────────────────────────────────────────
  // Android wire type: "cataract", flat pass-through.
  // Form sections: "cataract" + "bpLog" + "glucoseLog" + "referralInformation".

  static Map<String, dynamic> _toCataract(CanonicalVisitData d) {
    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return _compact({
      // Cataract-specific.
      'cataractType': d.getValue('cataractType'),
      'cataractGrade': d.getValue('cataractGrade'),
      'visualAcuityRight': d.getValue('visualAcuityRight'),
      'visualAcuityLeft': d.getValue('visualAcuityLeft'),
      'referredForCataractSurgery': d.getValue('referredForCataractSurgery'),
      'cataractReferralFacility': d.getValue('cataractReferralFacility'),
      // Biometrics (cataract form includes BP and glucose).
      'systolic': asNum(d.getValue('systolic') ?? d.getValue('bloodPressureSystolic'))?.toInt().toString(),
      'diastolic': asNum(d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic'))?.toInt().toString(),
      'weight': asNum(d.getValue('weight')),
      'height': asNum(d.getValue('height')),
      'bmi': asNum(d.getValue('bmi')),
      'glucoseValue': asNum(d.getValue('glucoseValue') ?? d.getValue('glucose')),
      'glucoseType': d.getValue('glucoseType'),
    });
  }

  // ── Family Planning ────────────────────────────────────────────────────────
  // Android wire type: "family_planning", flat pass-through.
  // Form section: "clientProfileAssessment".

  static Map<String, dynamic> _toFamilyPlanning(CanonicalVisitData d) {
    return _compact({
      'familyPlanningMethods': d.getValue('familyPlanningMethods'),
      'desireForChildren': d.getValue('desireForChildren') ?? d.getValue('desireForChildrenInFuture'),
      'numberOfLivingChildren': d.getValue('numberOfLivingChildren'),
      'lastDeliveryDate': d.getValue('lastDeliveryDate'),
      'breastfeeding': d.getValue('breastfeeding'),
      'counsellingProvided': d.getValue('counsellingProvided'),
      'sideEffects': d.getValue('sideEffects'),
      'clientAssessment': d.getValue('clientAssessment'),
    });
  }

  // ── ICCM / Sick-Child Visit ────────────────────────────────────────────────
  // Android wire type: "iccm", wrapped under "iccm" key (the only non-NCD/PNC
  // programme with explicit wrapping in OfflineSyncRepository.getAssessmentDetails).
  // GAP 11b: IMCI form sections to be added to layout_manifests.json separately.

  static Map<String, dynamic> _toIccm(CanonicalVisitData d) {
    return _compact({
      // Chief complaint / presenting symptoms.
      'chiefComplaint': d.getValue('chiefComplaint'),
      'presentingSymptoms': d.getValue('presentingSymptoms') ?? d.getValue('symptoms'),
      // Danger signs (IMCI critical fields).
      'convulsions': d.getValue('convulsions'),
      'unconscious': d.getValue('unconscious'),
      'unableToFeedOrDrink': d.getValue('unableToFeedOrDrink'),
      'stridor': d.getValue('stridor'),
      'chestIndrawing': d.getValue('chestIndrawing'),
      'vomitingEverything': d.getValue('vomitingEverything'),
      // Classification.
      'iccmClassification': d.getValue('iccmClassification') ?? d.getValue('illnessClassification'),
      'severity': d.getValue('severity'),
      // Vitals.
      'temperature': d.getValue('temperature'),
      'respiratoryRate': d.getValue('respiratoryRate'),
      'muac': d.getValue('muac'),
      // Treatment.
      'treatmentPrescribed': d.getValue('treatmentPrescribed') ?? d.getValue('treatment'),
      'referralRequired': d.getValue('referralRequired'),
      'referralFacility': d.getValue('referralFacility'),
      // CBS follow-up fields are added by Android's updateCbsForRMNCH when CBS
      // form data is present; Flutter has no CBS form section yet — omit for now.
    });
  }

  // ── TB Screening ───────────────────────────────────────────────────────────
  // Android wire type: "TB", wrapped under "tb" key by toApiRequest().
  // Form sections: "tbScreening" + "contactTracing".

  static Map<String, dynamic> _toTb(CanonicalVisitData d) {
    return _compact({
      // WHO 4-symptom screen
      'hasCough': d.getValue('hasCough'),
      'hasCoughLastedLonger': d.getValue('hasCoughLastedLonger'),
      'hasNightSweats': d.getValue('hasNightSweats'),
      'hasFever': d.getValue('hasTbFever') ?? d.getValue('hasFever'),
      'hasWeightLoss': d.getValue('hasWeightLoss'),
      // Android wire key is "dateOfOnset"; form field ID is "tbDateOfOnset".
      'dateOfOnset': d.getValue('tbDateOfOnset') ?? d.getValue('dateOfOnset'),
      // Contact tracing
      'relationshipToIC': d.getValue('tbRelationshipToIC'),
      'sleepLocation': d.getValue('tbSleepLocation'),
      'hasPreviouslyTreatedForTB': d.getValue('hasPreviouslyTreatedForTB'),
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _compact(Map<String, dynamic> src) {
    return Map.fromEntries(
      src.entries.where((e) => e.value != null),
    );
  }
}
