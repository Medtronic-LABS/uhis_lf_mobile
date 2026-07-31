import '../../../core/clinical/referral_evaluator.dart';
import '../../../core/debug/console_log.dart';
import '../models/anc_assessment.dart';
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
  ///                ancServicesBirthPreparedness / visitNo / ancVisitDate /
  ///                summary (highRiskPregnantWoman, gapsInAnc) —
  ///                wrapped under {anc: …} by LocalAssessmentEntity.toApiRequest
  ///   NCD        → biometric / bpLog / glucoseLog / symptomsLog /
  ///                generalInformation / eyeCare
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

    // On a combined delivery visit, mother/child PNC only after live birth.
    // Abortion / maternal death end the pregnancy episode without a PNC
    // assessment (Android: Pregnancy Outcome is a separate menu; Leapfrog
    // seeds PNC form types for delivery visits but must not fan them out
    // unless the outcome is liveBirth).
    final isDeliveryVisit = activeFormTypes.contains('pregnancyOutcome');
    final includePnc = _shouldIncludePncWithPregnancyOutcome(data, activeFormTypes);

    if (includePnc && activeFormTypes.contains('pncMother')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PNC_MOTHER',
        // visitNo is assigned in UnifiedFormNotifier from
        // patient_pregnancy_snapshot.pnc_visit_no (+1). Fallback 1 only when
        // that path missed (e.g. unit tests without a snapshot dao write).
        details: _toPncMother(data, defaultVisitNo: isDeliveryVisit ? 1 : null),
      ));
    }

    // Childhood Visit: Spice wire type ChildHood_Visit, details under pncChild.
    // Child Health card resolves imci → pncChild. Delivery seeds pncChild for
    // UI only and must not emit a childhood assessment (Android outcome submit
    // saves PREGNANCYOUTCOME + baby member; childhood is a later visit).
    if (!isDeliveryVisit && activeFormTypes.contains('pncChild')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'CHILDHOOD_VISIT',
        details: _toChildhoodVisit(data),
      ));
    }

    // PNC_NEONATE: Android wire type "PNC_NEONATE", wrapped under "pncNeonatal".
    // Separate from childhood visit — neonate findings against the baby.
    if (!isDeliveryVisit && activeFormTypes.contains('pncNeonatal')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PNC_NEONATE',
        details: _toPncNeonatal(data),
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

  /// PNC rides a delivery visit only when the pregnancy outcome is a live birth.
  /// Standalone PNC visits (no pregnancyOutcome form type) are unchanged.
  static bool _shouldIncludePncWithPregnancyOutcome(
    CanonicalVisitData data,
    Set<String> activeFormTypes,
  ) {
    if (!activeFormTypes.contains('pregnancyOutcome')) return true;
    return data.getValue('deliveryOutcomeType')?.toString() == 'liveBirth';
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
    });

    // ANC point-of-care:
    //   glucoseType == 'fbs'/'fasting' → bloodSugarFasting + bloodSugar: 'fasting'
    //   glucoseType == 'rbs'/'ppbs'/'random' → bloodSugarRandom + bloodSugar: 'random'
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
    final isFastingType = _isFastingGlucoseType(glucoseType);
    final hasFbs = isFastingType && glucoseValue != null;
    final hasRbs = glucoseType != null && !isFastingType && glucoseValue != null;
    final pointOfCare = _compact({
      'urinaryAlbumin': d.getValue('urinaryAlbumin'),
      'urinaryBilirubin': d.getValue('urinaryBilirubin'),
      'urinarySugar': d.getValue('urinarySugar'),
      'hemoglobin': d.getValue('hemoglobin'),
      if (d.getValue('hemoglobin') != null) 'hemoglobinUnit': 'g/dL',
      if (glucoseType != null && glucoseValue != null)
        'bloodSugar': isFastingType ? 'fasting' : 'random',
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

    // Spice evaluateAndAddAncSummaryData — summary.highRiskPregnantWoman is a
    // { URGENT: [...], NON_URGENT: [...] } map computed client-side, not a form field.
    double? tempF = asNum(d.getValue('temperature'));
    double? tempC = tempF == null ? null : (tempF - 32) * 5 / 9;
    final pulseRaw = d.getValue('pulse');
    final pulseBpm = pulseRaw is int
        ? pulseRaw
        : (pulseRaw is num
            ? pulseRaw.toInt()
            : (pulseRaw is String ? int.tryParse(pulseRaw) : null));
    final referral = AncReferralEvaluator.evaluate(
      AncAssessment(
        medicalHistoryPhysicalExamination: MedicalHistoryPhysicalExamination(
          bloodPressureSystolic: asNum(rawSys)?.toInt(),
          bloodPressureDiastolic: asNum(rawDia)?.toInt(),
          fundalHeight: fundalHeight,
          oedema: (d.getValue('oedema') ?? d.getValue('edema')) as String?,
          weight: weight,
          height: height,
        ),
        pointOfCareInvestigations: PointOfCareInvestigations(
          hemoglobin: asNum(d.getValue('hemoglobin')),
          urinaryAlbumin: d.getValue('urinaryAlbumin') as String?,
          urinaryBilirubin: d.getValue('urinaryBilirubin') as String?,
          urinarySugar: d.getValue('urinarySugar') as String?,
          bloodSugarFasting: hasFbs ? glucoseValue : null,
          bloodSugarRandom: hasRbs ? glucoseValue : null,
        ),
        dangerSignsRiskIdentification: DangerSignsRiskIdentification(
          dangerSignsExperienced12:
              (d.getValue('dangerSignsExperienced12') as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
          dangerSignsExperienced13To27:
              (d.getValue('dangerSignsExperienced13To27') as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
          dangerSignsExperienced28To40:
              (d.getValue('dangerSignsExperienced28To40') as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
        ),
        gestationalWeeks: gestationalWeeks?.toInt(),
      ),
      temperatureCelsius: tempC,
      pulseBpm: pulseBpm,
    );

    final highRisk = <String, dynamic>{};
    if (referral.emergencyConditions.isNotEmpty) {
      highRisk['URGENT'] = referral.emergencyConditions;
    }
    if (referral.nonEmergencyConditions.isNotEmpty) {
      highRisk['NON_URGENT'] = referral.nonEmergencyConditions;
    }

    final summary = <String, dynamic>{
      if (highRisk.isNotEmpty) 'highRiskPregnantWoman': highRisk,
      if (gapsResult.hasGaps) 'gapsInAnc': gapsResult.gaps,
    };

    return {
      if (visitNo != null) 'visitNo': visitNo,
      // Spice AssessmentRMNCHFragment.evaluateAndAddAncSummaryData stamps this.
      'ancVisitDate': DateTime.now().toUtc().toIso8601String(),
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
  // Android wire type is "PWPROFILE" (menu id uppercased) and the details are
  // grouped by the form card's `family`, so _wrapDetailsForType nests this map
  // as { "pwProfile": { "pregnancyDetailsAndHistory": {…} } }.
  //
  // Field IDs are the ones in Android's pregnancy_woman_profile.json:
  // lmp / gravida / parity / livingChildren / ageOfLastChild / pregnancyTest.
  // Counts go out as Doubles (numeric EditText), the DatePicker stores LMP as
  // "yyyy-MM-dd'T'HH:mm:ss+00:00", and ageOfLastChild is an AgeOrDob field that
  // always stores a date of birth rather than the age the SK typed.
  static Map<String, dynamic> _toPwProfile(CanonicalVisitData d) {
    return _compact({
      'lmp': _asDateWire(d.getValue('lmp')),
      'gravida': _asDoubleWire(d.getValue('gravida')),
      'parity': _asDoubleWire(d.getValue('parity')),
      'livingChildren': _asDoubleWire(d.getValue('livingChildren')),
      'ageOfLastChild': _asDobWire(d.getValue('ageOfLastChild')),
      'pregnancyTest': d.getValue('pregnancyTest'),
    });
  }

  // ── NCD ────────────────────────────────────────────────────────────────────
  // Android NCD payload (from reference + AssessmentViewModel.kt):
  //   ncd.bpLog        = { diagnosedBP, diagnosedBPMedication, avgSystolic,
  //                        avgDiastolic, avgBloodPressure, weight, height, bmi,
  //                        isRegularSmoker, cvdRisk, bpLogDetails[] }
  //   ncd.glucoseLog   = { diagnosedGlucose, diagnosedGlucoseMedication,
  //                        glucose, glucoseValue, glucoseType, glucoseUnit,
  //                        hba1c, glucoseDateTime, hba1cDateTime }
  //   ncd.symptomsLog  = { compliance:"Yes"/"No", hasSymptoms:"Yes"/"No",
  //                        ncdSymptoms[], newWorseningSymptoms,
  //                        ncdSymptomsMedication }
  //   ncd.biometric    = { height, weight, bmi }
  //
  // weight/height/bmi/isRegularSmoker INSIDE bpLog as numbers.
  // NCD avgSystolic/avgDiastolic are INTEGER on the wire (not strings).
  // compliance and hasSymptoms are "Yes"/"No" STRINGS (not booleans).
  //
  // Multiple BP readings: form may supply bp_reading_1..3 as JSON list under
  // 'bpReadings', or flat systolic_1/diastolic_1 etc. When present, the
  // bpLogDetails array carries all readings and averages are computed here.

  /// Average systolic/diastolic from canonical NCD BP fields.
  ///
  /// Mirrors the reading aggregation used by [_toNcd] so referral logic and
  /// the wire payload share one source of truth.
  static ({int? systolic, int? diastolic}) ncdAvgBp(CanonicalVisitData d) {
    final details = _ncdBpDetails(d);
    if (details.isEmpty) return (systolic: null, diastolic: null);
    final avgSys = (details.map((r) => r['systolic'] as int).reduce((a, b) => a + b) /
            details.length)
        .round();
    final avgDia = (details.map((r) => r['diastolic'] as int).reduce((a, b) => a + b) /
            details.length)
        .round();
    return (systolic: avgSys, diastolic: avgDia);
  }

  static List<Map<String, dynamic>> _ncdBpDetails(CanonicalVisitData d) {
    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final bpDetails = <Map<String, dynamic>>[];
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
      return bpDetails;
    }

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
    if (bpDetails.isEmpty) {
      final s =
          asNum(d.getValue('systolic') ?? d.getValue('bloodPressureSystolic'));
      final di = asNum(
          d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic'));
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
    return bpDetails;
  }

  /// Local ISO-8601 with numeric offset, e.g. `2026-07-30T23:45:45+05:30`.
  /// Matches Spice `DateUtils.getTodayDateDDMMYYYY` / glucose stamp format.
  static String _localIsoWithOffset(DateTime dt) {
    final local = dt.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final oh = abs.inHours.toString().padLeft(2, '0');
    final om = (abs.inMinutes % 60).toString().padLeft(2, '0');
    String p(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${p(local.month)}-${p(local.day)}'
        'T${p(local.hour)}:${p(local.minute)}:${p(local.second)}'
        '$sign$oh:$om';
  }

  static Map<String, dynamic> _toNcd(CanonicalVisitData d) {
    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // Normalize boolean-like values to Android "Yes"/"No" string convention.
    String? yesNo(dynamic v) {
      if (v == null) return null;
      if (v == true || v == 'true' || v == 'yes' || v == 'Yes' || v == 1) {
        return 'Yes';
      }
      if (v == false || v == 'false' || v == 'no' || v == 'No' || v == 0) {
        return 'No';
      }
      final s = v.toString().toLowerCase();
      if (s == 'yes') return 'Yes';
      if (s == 'no') return 'No';
      return v.toString();
    }

    bool? toBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      final s = v.toString().toLowerCase();
      if (s == 'true' || s == 'yes' || s == '1') return true;
      if (s == 'false' || s == 'no' || s == '0') return false;
      return null;
    }

    // ── BP log (readings + diagnosis; biometrics live under ncd.biometric) ──
    final bpLog = <String, dynamic>{};
    final bpDetails = _ncdBpDetails(d);
    if (bpDetails.isNotEmpty) {
      final avg = ncdAvgBp(d);
      bpLog['avgSystolic'] = avg.systolic;
      bpLog['avgDiastolic'] = avg.diastolic;
      bpLog['avgBloodPressure'] = '${avg.systolic}/${avg.diastolic}';
      bpLog['bpLogDetails'] = bpDetails;
    }

    // Diagnosis / smoker may appear without BP readings on a follow-up visit.
    final isRegularSmoker = d.getValue('isRegularSmoker');
    if (isRegularSmoker != null) {
      bpLog['isRegularSmoker'] = toBool(isRegularSmoker);
    }
    final diagBp =
        yesNo(d.getValue('diagnosedBP') ?? d.getValue('isBeforeHtnDiagnosis'));
    if (diagBp != null) bpLog['diagnosedBP'] = diagBp;
    final diagBpMed = yesNo(d.getValue('diagnosedBPMedication') ??
        d.getValue('medicationFrequencyBp'));
    if (diagBpMed != null) bpLog['diagnosedBPMedication'] = diagBpMed;
    // CVD risk intentionally omitted for now (Spice calculator not ported).

    // ── Glucose log ──────────────────────────────────────────────────────────
    final glucoseNum = asNum(d.getValue('glucoseValue') ??
        d.getValue('glucose') ??
        d.getValue('fastingBloodSugar') ??
        d.getValue('randomBloodSugar') ??
        d.getValue('ancBloodGlucose'));
    final glucoseLog = <String, dynamic>{};
    if (glucoseNum != null) {
      // Spice BD wire uses `glucose` only (not glucoseValue / bgTakenOn).
      glucoseLog['glucose'] = glucoseNum;
      final glucoseType = d.getValue('glucoseType') ??
          switch (d.getValue('bloodSugar')) {
            'fasting' => 'fbs',
            'random' => 'rbs',
            final other => other,
          };
      if (glucoseType != null) glucoseLog['glucoseType'] = glucoseType;
      glucoseLog['glucoseUnit'] =
          d.getValue('glucoseUnit') as String? ?? 'mmol/L';
      final stamped = d.getValue('glucoseDateTime') as String? ??
          _localIsoWithOffset(DateTime.now());
      glucoseLog['glucoseDateTime'] = stamped;
      glucoseLog['hba1cDateTime'] =
          d.getValue('hba1cDateTime') as String? ?? stamped;
      final hba1c = asNum(d.getValue('hba1c'));
      if (hba1c != null) {
        glucoseLog['hba1c'] = hba1c;
        glucoseLog['hba1cUnit'] = d.getValue('hba1cUnit') as String? ?? '%';
      }
    }
    final diagGlucose = yesNo(
        d.getValue('diagnosedGlucose') ?? d.getValue('isBeforeDiabetesDiagnosis'));
    if (diagGlucose != null) glucoseLog['diagnosedGlucose'] = diagGlucose;
    final diagGlucoseMed = yesNo(d.getValue('diagnosedGlucoseMedication') ??
        d.getValue('medicationFrequencyBg'));
    if (diagGlucoseMed != null) {
      glucoseLog['diagnosedGlucoseMedication'] = diagGlucoseMed;
    }

    // ── Symptoms log ─────────────────────────────────────────────────────────
    final symptomsLog = <String, dynamic>{};
    final complianceStr = yesNo(d.getValue('compliance'));
    if (complianceStr != null) symptomsLog['compliance'] = complianceStr;
    final hasSymptomsStr = yesNo(d.getValue('hasSymptoms'));
    if (hasSymptomsStr != null) symptomsLog['hasSymptoms'] = hasSymptomsStr;
    final ncdSymptoms = d.getValue('ncdSymptoms');
    if (ncdSymptoms != null) symptomsLog['ncdSymptoms'] = ncdSymptoms;
    final newWorseningSymptoms = d.getValue('newWorseningSymptoms');
    if (newWorseningSymptoms != null) {
      symptomsLog['newWorseningSymptoms'] = newWorseningSymptoms;
    }
    final ncdSymptomsMedication =
        yesNo(d.getValue('ncdSymptomsMedication')) ?? complianceStr;
    if (ncdSymptomsMedication != null) {
      symptomsLog['ncdSymptomsMedication'] = ncdSymptomsMedication;
    }

    // ── Biometric (Spice ncd.biometric — not duplicated under bpLog) ─────────
    final biometric = <String, dynamic>{};
    final height = asNum(d.getValue('height'));
    final weight = asNum(d.getValue('weight'));
    final bmi = asNum(d.getValue('bmi'));
    if (height != null) biometric['height'] = height;
    if (weight != null) biometric['weight'] = weight;
    if (bmi != null) biometric['bmi'] = bmi;

    // Empty card groups always present on Spice BD ncd.json layouts.
    final generalInformation =
        d.getValue('generalInformation') as Map<String, dynamic>? ??
            const <String, dynamic>{};
    final eyeCare =
        d.getValue('eyeCare') as Map<String, dynamic>? ?? _eyeCareCard(d);

    return {
      if (symptomsLog.isNotEmpty) 'symptomsLog': symptomsLog,
      if (biometric.isNotEmpty) 'biometric': biometric,
      if (bpLog.isNotEmpty) 'bpLog': bpLog,
      if (glucoseLog.isNotEmpty) 'glucoseLog': glucoseLog,
      'generalInformation': generalInformation,
      'eyeCare': eyeCare,
      if (d.getValue('htnScreening') != null)
        'htnScreening': d.getValue('htnScreening'),
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

  static Map<String, dynamic> _toPncMother(
    CanonicalVisitData d, {
    int? defaultVisitNo,
  }) {
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
    final isFastingType = _isFastingGlucoseType(glucoseType);
    final hasFbs = isFastingType && glucoseValue != null;
    final hasRbs = glucoseType != null && !isFastingType && glucoseValue != null;

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
        'bloodSugar': isFastingType ? 'fasting' : 'random',
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
      'visitNo': d.getValue('pncVisitNumber') ??
          d.getValue('visitNo') ??
          defaultVisitNo,
      'daysSinceDelivery': d.getValue('daysSinceDelivery'),
    });
  }

  // ── Childhood Visit (CHILDHOOD_VISIT → ChildHood_Visit) ───────────────────
  // Field ids match Spice rmnch_childhood_visit.json / pncChild family.
  // DAO wraps under {"pncChild": {...}, "cbs": {}}.

  static Map<String, dynamic> _toChildhoodVisit(CanonicalVisitData d) {
    return _compact({
      // Spice AssessmentRMNCHFragment stamps pncChild.visitNo before save;
      // OfflineSyncRepository reads it back into encounter.visitNumber.
      // UnifiedFormNotifier assigns childVisitNumber; 1 only when that path
      // missed (e.g. unit tests calling decompose directly).
      'visitNo': d.getValue('childVisitNumber') ?? d.getValue('visitNo') ?? 1,
      'congenitalDefect': d.getValue('congenitalDefect'),
      'weight': _asDoubleWire(d.getValue('weight')),
      'childFeedLast24Hrs': d.getValue('childFeedLast24Hrs'),
      'otherChildFeed': d.getValue('otherChildFeed'),
      'hrsBreastFed': _asDoubleWire(d.getValue('hrsBreastFed')),
      'monthAdditionalFeedGiven': d.getValue('monthAdditionalFeedGiven'),
      'childBreastFeeding': d.getValue('childBreastFeeding'),
      'additionalFood24Hrs': d.getValue('additionalFood24Hrs'),
      'receivedVaccine': d.getValue('receivedVaccine'),
      'dewormingMedicine': d.getValue('dewormingMedicine'),
      'anyIllness': d.getValue('anyIllness'),
      'childIllnessType': d.getValue('childIllnessType'),
      'childReferral': d.getValue('childReferral'),
      'childReferralFacilityType': d.getValue('childReferralFacilityType'),
    });
  }

  // ── PNC Neonate (PNC_NEONATE wire type) ───────────────────────────────────
  // Android wraps under "pncNeonatal" key; _wrapDetailsForType handles that.
  // visitNo is extracted by _extractVisitNumber in local_assessment_dao.dart.

  static Map<String, dynamic> _toPncNeonatal(CanonicalVisitData d) {
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
  // Android wire structure (FormResultComposer groups by form card `family`):
  //   pregnancyOutcome → {
  //     ancServicesBirthPreparedness: { ancVisitsOtherProviders },
  //     pregnancyOutcome:  { pregnancyOutcomeType },
  //     maternalDeath?:    { timeOfDeath, gestationMonthAtDeath, causeOfDeath },
  //     abortion?:         { gestationMonthAtAbortion, typeOfAbortion },
  //     deliveryOutcomes?: { liveBirthNumbers, stillbirthNumbers, … },
  //     newbornDetails?:   [{ isBabyAlive, sex, causeOfNeonatalDeath? }]
  //   }
  // Field-ID renames (Flutter form id → Android wire key):
  //   deliveryOutcomeType → pregnancyOutcomeType
  //   babyAlive           → isBabyAlive ("Yes"/"No")
  //   babySex             → sex
  //   neonatalDeathCause  → causeOfNeonatalDeath
  // _wrapDetailsForType wraps this map under "pregnancyOutcome" automatically.

  static Map<String, dynamic> _toPregnancyOutcome(CanonicalVisitData d) {
    // Android FormResultComposer nests pregnancyOutcomeType under the
    // "pregnancyOutcome" card family (same name as the menu wrapper).
    final pregnancyOutcome = _compact({
      'pregnancyOutcomeType': d.getValue('deliveryOutcomeType'),
    });

    final ancServices = _compact({
      'ancVisitsOtherProviders':
          _asDoubleWire(d.getValue('ancVisitsOtherProviders')),
    });

    final maternalDeath = _compact({
      'timeOfDeath': d.getValue('timeOfDeath'),
      'gestationMonthAtDeath':
          _asDoubleWire(d.getValue('gestationMonthAtDeath')),
      'causeOfDeath': d.getValue('causeOfDeath'),
    });

    final abortion = _compact({
      'gestationMonthAtAbortion':
          _asDoubleWire(d.getValue('gestationMonthAtAbortion')),
      'typeOfAbortion': d.getValue('typeOfAbortion'),
    });

    final deliveryOutcomes = _compact({
      'deliveryOutcome': d.getValue('deliveryOutcome'),
      'liveBirthNumbers': _asDoubleWire(d.getValue('liveBirthNumbers')),
      'stillbirthNumbers': _asDoubleWire(d.getValue('stillbirthNumbers')),
      'placeOfDelivery': d.getValue('placeOfDelivery'),
      'dateOfDelivery': _asDateWire(d.getValue('dateOfDelivery')),
      'modeOfDelivery': d.getValue('modeOfDelivery'),
      'birthAttendant': d.getValue('birthAttendant'),
      'anyComplicationsDuringDelivery':
          d.getValue('anyComplicationsDuringDelivery'),
      'complicationsDuringDelivery': d.getValue('complicationsDuringDelivery'),
    });

    // Spice builds N baby cards from liveBirthNumbers into newbornDetails[].
    final newborns = _newbornDetailsWire(d);

    return _compact(<String, dynamic>{
      if (ancServices.isNotEmpty) 'ancServicesBirthPreparedness': ancServices,
      if (pregnancyOutcome.isNotEmpty) 'pregnancyOutcome': pregnancyOutcome,
      if (maternalDeath.isNotEmpty) 'maternalDeath': maternalDeath,
      if (abortion.isNotEmpty) 'abortion': abortion,
      if (deliveryOutcomes.isNotEmpty) 'deliveryOutcomes': deliveryOutcomes,
      if (newborns != null && newborns.isNotEmpty) 'newbornDetails': newborns,
    });
  }

  /// Prefer the dynamic `newbornDetails` list; fall back to legacy flat
  /// babyAlive / babySex / neonatalDeathCause fields.
  static List<Map<String, dynamic>>? _newbornDetailsWire(CanonicalVisitData d) {
    final raw = d.getValue('newbornDetails');
    if (raw is List && raw.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final entry = _compact({
          'isBabyAlive': _asYesNoWire(e['isBabyAlive']),
          'sex': e['sex'],
          'causeOfNeonatalDeath': e['causeOfNeonatalDeath'],
        });
        if (entry.isNotEmpty) out.add(entry);
      }
      return out.isEmpty ? null : out;
    }
    final legacy = _compact({
      'isBabyAlive': _asYesNoWire(d.getValue('babyAlive')),
      'sex': d.getValue('babySex'),
      'causeOfNeonatalDeath': d.getValue('neonatalDeathCause'),
    });
    return legacy.isEmpty ? null : [legacy];
  }

  // ── Eye Care ───────────────────────────────────────────────────────────────
  // Android wire type: "eye_care". FormResultComposer groups the answers by
  // their card family and addToMenuGroup wraps the result under the menu id, so
  // the details are { eyeCare: {...}, generalInformation: {...} } — the outer
  // "eye_care" key is added by LocalAssessmentEntity._wrapDetailsForType.
  //
  // `generalInformation` holds camp_type, which Spice only reveals for FO/PO
  // users (AssessmentViewModel.revealBdCampFields). It has no Flutter
  // equivalent yet, but createGroup() emits the empty card either way.

  static Map<String, dynamic> _toEyeCare(CanonicalVisitData d) {
    return {
      'eyeCare': _eyeCareCard(d),
      'generalInformation': const <String, dynamic>{},
    };
  }

  /// The `eyeCare` card body, shared by the standalone `eye_care` assessment
  /// and the eyeCare family Spice's NCD form carries (ncd.json familyOrder 5).
  static Map<String, dynamic> _eyeCareCard(CanonicalVisitData d) {
    // Android AssessmentViewModel.getAssessmentDetails rewrites the single
    // selection into a one-element list and drops the singular key.
    final outcome = d.getValue('eyeTestOutcome')?.toString();
    return _compact({
      if (outcome != null && outcome.isNotEmpty) 'eyeTestOutcomes': [outcome],
      'glassPower': d.getValue('glassPower'),
      'haveTheGlassesBeenSold': d.getValue('haveTheGlassesBeenSold'),
      'typeOfGlass': d.getValue('typeOfGlass'),
      'typeOfFrame': d.getValue('typeOfFrame'),
      'firstTimeUser': d.getValue('firstTimeUser'),
      'referPlace': d.getValue('referPlace'),
    });
  }

  // ── Cataract ───────────────────────────────────────────────────────────────
  // Android FormResultComposer groups card families under menu key "cataract",
  // then AssessmentViewModel renames eyeDisease → eyeTestOutcomes and, when
  // NCD vitals were captured, nests bpLog / glucoseLog under sibling "ncd".

  static Map<String, dynamic> _toCataract(CanonicalVisitData d) {
    final ncd = _cataractNcdCard(d);
    return {
      'generalInformation': _cataractGeneralInformation(d),
      'cataract': _cataractCard(d),
      if (ncd != null) 'ncd': ncd,
      if (_referralInformationCard(d) case final referral?)
        'referralInformation': referral,
    };
  }

  static Map<String, dynamic> _cataractGeneralInformation(CanonicalVisitData d) {
    final camp = d.getValue('camp_date');
    if (camp == null || camp.toString().isEmpty) {
      return const <String, dynamic>{};
    }
    return {'camp_date': camp};
  }

  /// Inner `cataract` card body. Spice rewrites the multi-select `eyeDisease`
  /// into `eyeTestOutcomes` before sync; we emit the transformed key directly.
  static Map<String, dynamic> _cataractCard(CanonicalVisitData d) {
    return _compact({
      'eyeTestOutcomes': _asStringList(d.getValue('eyeDisease')),
      'glassPower': d.getValue('glassPower'),
      'haveTheGlassesBeenSold': d.getValue('haveTheGlassesBeenSold'),
      'typeOfGlass': d.getValue('typeOfGlass'),
      'typeOfFrame': d.getValue('typeOfFrame'),
      'firstTimeUser': d.getValue('firstTimeUser'),
      'referPlace': d.getValue('referPlace'),
      'historyOfOtherDiseases':
          _asStringList(d.getValue('historyOfOtherDiseases')),
      'patientReferredForOperation':
          d.getValue('patientReferredForOperation'),
      'operationName': _asStringList(d.getValue('operationName')),
      'reason': _asStringList(d.getValue('reason')),
      'pseudophakiaPostCataractSurgery':
          d.getValue('pseudophakiaPostCataractSurgery'),
      'ncdServiceProvided': d.getValue('ncdServiceProvided'),
    });
  }

  /// Spice nests vitals under `cataract.ncd` when NCD service was provided.
  /// Height/weight/bmi live inside `bpLog` (not a separate biometric card).
  /// `isBeforeHtnDiagnosis` / `isBeforeDiabetesDiagnosis` are booleans.
  static Map<String, dynamic>? _cataractNcdCard(CanonicalVisitData d) {
    if (d.getValue('ncdServiceProvided')?.toString().toLowerCase() != 'yes') {
      return null;
    }

    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    bool? toBool(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      final s = v.toString().trim().toLowerCase();
      if (s == 'yes' || s == 'true' || s == '1') return true;
      if (s == 'no' || s == 'false' || s == '0') return false;
      return null;
    }

    final bpLog = <String, dynamic>{};
    final bpDetails = _ncdBpDetails(d);
    if (bpDetails.isNotEmpty) {
      final avg = ncdAvgBp(d);
      bpLog['avgSystolic'] = avg.systolic;
      bpLog['avgDiastolic'] = avg.diastolic;
      bpLog['avgBloodPressure'] = '${avg.systolic}/${avg.diastolic}';
      bpLog['bpLogDetails'] = bpDetails;
    }
    final height = asNum(d.getValue('height'));
    final weight = asNum(d.getValue('weight'));
    final bmi = asNum(d.getValue('bmi'));
    if (height != null) bpLog['height'] = height;
    if (weight != null) bpLog['weight'] = weight;
    if (bmi != null) bpLog['bmi'] = bmi;
    final htn = toBool(d.getValue('isBeforeHtnDiagnosis'));
    if (htn != null) bpLog['isBeforeHtnDiagnosis'] = htn;
    final smoker = toBool(d.getValue('isRegularSmoker'));
    if (smoker != null) bpLog['isRegularSmoker'] = smoker;
    final medBp = d.getValue('medicationFrequencyBp');
    if (medBp != null) bpLog['medicationFrequencyBp'] = medBp;

    final glucoseLog = <String, dynamic>{};
    final glucoseNum = asNum(d.getValue('glucoseValue') ?? d.getValue('glucose'));
    if (glucoseNum != null) {
      glucoseLog['glucose'] = glucoseNum;
      final glucoseType = d.getValue('glucoseType');
      if (glucoseType != null) glucoseLog['glucoseType'] = glucoseType;
      glucoseLog['glucoseUnit'] =
          d.getValue('glucoseUnit') as String? ?? 'mmol/L';
      glucoseLog['glucoseDateTime'] =
          d.getValue('glucoseDateTime') as String? ??
              _localIsoWithOffset(DateTime.now());
    }
    final dm = toBool(d.getValue('isBeforeDiabetesDiagnosis'));
    if (dm != null) glucoseLog['isBeforeDiabetesDiagnosis'] = dm;
    final medBg = d.getValue('medicationFrequencyBg');
    if (medBg != null) glucoseLog['medicationFrequencyBg'] = medBg;

    final ncd = <String, dynamic>{
      if (bpLog.isNotEmpty) 'bpLog': bpLog,
      if (glucoseLog.isNotEmpty) 'glucoseLog': glucoseLog,
      if (d.getValue('referralFacilityType') != null)
        'referralFacilityType': d.getValue('referralFacilityType'),
    };
    return ncd.isEmpty ? null : ncd;
  }

  static Map<String, dynamic>? _referralInformationCard(CanonicalVisitData d) {
    final who = d.getValue('whoReferredThisPerson');
    if (who == null || who.toString().isEmpty) return null;
    return {'whoReferredThisPerson': who};
  }

  // ── Family Planning ────────────────────────────────────────────────────────
  // Android wire type: "FAMILY_PLANNING", wrapped under "familyPlanning" by
  // _wrapDetailsForType. Android collects these four fields in the
  // "clientProfileAssessment" form section, then AssessmentViewModel lifts the
  // section contents up one level before sync, so the section name never
  // reaches the wire:
  //   familyPlanning = { numberOfLivingChildren, ageOfLastChild,
  //                      desireForChildrenInFuture, familyPlanningMethods }
  //
  // numberOfLivingChildren is a STRING on the wire, and familyPlanningMethods
  // is an ARRAY even though the form renders a single-select Spinner — Android
  // AssessmentFamilyPlanningFragment.onFormSubmit wraps the picked option in a
  // list for backward compatibility with older stored data.
  //
  // ageOfLastChild is an AgeOrDob field on Android, which always stores a date
  // of birth ("2025-01-01T00:00:00+00:00") — never the age the SK typed.

  static Map<String, dynamic> _toFamilyPlanning(CanonicalVisitData d) {
    return _compact({
      'numberOfLivingChildren':
          d.getValue('numberOfLivingChildren')?.toString(),
      'ageOfLastChild': _asDobWire(d.getValue('ageOfLastChild')),
      'desireForChildrenInFuture': d.getValue('desireForChildrenInFuture') ??
          d.getValue('desireForChildren'),
      'familyPlanningMethods':
          _asStringList(d.getValue('familyPlanningMethods')),
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

  /// NCD/Cataract capture the glucose type as `fbs`/`rbs` (BloodGlucoseEntry),
  /// ANC/PNC as `fasting`/`random` (the `bloodSugar` selector). Both vocabularies
  /// reach the mappers through the same fan-out read.
  static bool _isFastingGlucoseType(String? glucoseType) =>
      glucoseType == 'fbs' || glucoseType == 'fasting';

  static Map<String, dynamic> _compact(Map<String, dynamic> src) {
    return Map.fromEntries(
      src.entries.where((e) => e.value != null),
    );
  }

  /// Converts an age in years into the date-of-birth string Android's AgeOrDob
  /// widget stores, matching DateUtils.calculateDOBFromAge: 1 January of
  /// (current year − age), at midnight UTC. Values that are already a date
  /// pass through untouched.
  static String? _asDobWire(Object? value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final years = num.tryParse(raw);
    if (years == null) return raw;
    return '${DateTime.now().year - years.round()}-01-01T00:00:00+00:00';
  }

  /// Formats a picked calendar date the way Android's DatePicker stores it:
  /// midnight, "yyyy-MM-dd'T'HH:mm:ss+00:00". Accepts ISO strings and epoch
  /// milliseconds; anything unparseable is dropped.
  static String? _asDateWire(Object? value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final date = DateTime.tryParse(raw) ??
        (int.tryParse(raw) != null
            ? DateTime.fromMillisecondsSinceEpoch(int.parse(raw))
            : null);
    if (date == null) return null;
    final m = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-${day}T00:00:00+00:00';
  }

  /// Numeric form answers reach the wire as Doubles on Android, whatever the
  /// widget stored locally ("3", 3, 3.0 → 3.0).
  static double? _asDoubleWire(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  /// Normalises yes/no answers to the capitalised form Android stores for
  /// pregnancy-outcome baby alive (`"Yes"` / `"No"`).
  static String? _asYesNoWire(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim().toLowerCase();
    if (s == 'yes' || s == 'true' || s == '1') return 'Yes';
    if (s == 'no' || s == 'false' || s == '0') return 'No';
    final raw = value.toString().trim();
    return raw.isEmpty ? null : raw;
  }

  /// Coerces a single-select answer into the list shape Android sends.
  /// Returns null for absent/blank values so [_compact] drops the key.
  static List<String>? _asStringList(Object? value) {
    if (value == null) return null;
    if (value is List) {
      final items = value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      return items.isEmpty ? null : items;
    }
    final single = value.toString().trim();
    return single.isEmpty ? null : [single];
  }
}
