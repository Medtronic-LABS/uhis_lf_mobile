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

    if (activeFormTypes.contains('pncChild') ||
        activeFormTypes.contains('pncNeonatal')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PNC_CHILD',
        details: _toPncChild(data),
      ));
    }

    if (activeFormTypes.contains('pregnancyOutcome')) {
      payloads.add(ProgrammePayload(
        assessmentType: 'PREGNANCY_OUTCOME',
        details: _toPregnancyOutcome(data),
      ));
    }

    return payloads;
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

    final medHx = _compact({
      if (rawSys != null) 'systolic': rawSys.toString(),
      if (rawDia != null) 'diastolic': rawDia.toString(),
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
    final glucoseType = d.getValue('glucoseType') as String?;
    final glucoseValue = asNum(d.getValue('glucoseValue'));
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

    final vaccination = _compact({
      'ttTdCompleted': d.getValue('ttTdCompleted'),
      'folicAcidTotalConsumed': d.getValue('folicAcidTotalConsumed'),
      'folicAcidProvided': d.getValue('folicAcidProvided'),
      'ifaTotalConsumed': d.getValue('ifaTotalConsumed'),
      'ifaProvided': d.getValue('ifaProvided'),
      'calciumTotalConsumed': d.getValue('calciumTotalConsumed'),
      'calciumProvided': d.getValue('calciumProvided'),
    });

    final birthPrep = _compact({
      'facilityIdentifiedForDelivery': d.getValue('facilityIdentifiedForDelivery'),
      'ancVisitsOtherProviders': d.getValue('ancVisitsOtherProviders'),
      'ancFromMedicalDoctor': d.getValue('ancFromMedicalDoctor'),
      'ultrasound': d.getValue('ultrasound'),
    });

    final visitNo = d.getValue('ancVisitNumber') ?? d.getValue('visitNo');
    final bmiCategory = d.getValue('bmiCategory');

    return {
      if (visitNo != null) 'visitNo': visitNo,
      if (bmiCategory != null) 'bmiCategory': bmiCategory,
      if (medHx.isNotEmpty) 'medicalHistoryPhysicalExamination': medHx,
      if (pointOfCare.isNotEmpty) 'pointOfCareInvestigations': pointOfCare,
      'dangerSignsRiskIdentification': dangerSigns,
      if (vaccination.isNotEmpty) 'vaccinationAndSupplements': vaccination,
      if (birthPrep.isNotEmpty) 'ancServicesBirthPreparedness': birthPrep,
    };
  }

  // ── NCD ────────────────────────────────────────────────────────────────────
  // Android NCD payload (from reference + AssessmentViewModel.kt):
  //   ncd.bpLog        = { avgSystolic, avgDiastolic, avgBloodPressure,
  //                        weight, height, bmi, isRegularSmoker, bpLogDetails[] }
  //   ncd.glucoseLog   = { glucose, glucoseType, glucoseUnit, hba1c,
  //                        glucoseDateTime, hba1cDateTime }
  //   ncd.symptomsLog  = { compliance, hasSymptoms, ncdSymptoms[] }
  //
  // weight/height/bmi/isRegularSmoker INSIDE bpLog as numbers.
  // NCD avgSystolic/avgDiastolic are INTEGER on the wire (not strings).

  static Map<String, dynamic> _toNcd(CanonicalVisitData d) {
    double? asNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final sys = asNum(d.getValue('systolic') ?? d.getValue('bloodPressureSystolic'));
    final dia = asNum(d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic'));
    final pulse = asNum(d.getValue('pulse'));

    final bpLog = <String, dynamic>{};
    if (sys != null && dia != null) {
      bpLog['avgSystolic'] = sys.toInt();
      bpLog['avgDiastolic'] = dia.toInt();
      bpLog['avgBloodPressure'] = '${sys.toInt()}/${dia.toInt()}';
      final detail = <String, dynamic>{
        'systolic': sys.toInt(),
        'diastolic': dia.toInt(),
      };
      if (pulse != null) detail['pulse'] = pulse.toInt();
      bpLog['bpLogDetails'] = [detail];
    }
    final weight = asNum(d.getValue('weight'));
    if (weight != null) bpLog['weight'] = weight;
    final height = asNum(d.getValue('height'));
    if (height != null) bpLog['height'] = height;
    final bmi = asNum(d.getValue('bmi'));
    if (bmi != null) bpLog['bmi'] = bmi;
    final isRegularSmoker = d.getValue('isRegularSmoker');
    if (isRegularSmoker != null) bpLog['isRegularSmoker'] = isRegularSmoker;

    final glucoseNum = asNum(d.getValue('glucoseValue'));
    final glucoseLog = <String, dynamic>{};
    if (glucoseNum != null) {
      glucoseLog['glucose'] = glucoseNum;
      final glucoseType = d.getValue('glucoseType');
      if (glucoseType != null) glucoseLog['glucoseType'] = glucoseType;
      glucoseLog['glucoseUnit'] =
          d.getValue('glucoseUnit') as String? ?? 'mmol/L';
      final hba1c = d.getValue('hba1c');
      if (hba1c != null) {
        glucoseLog['hba1c'] = hba1c;
        glucoseLog['hba1cUnit'] = '%';
      }
    }

    final symptomsLog = <String, dynamic>{};
    final compliance = d.getValue('compliance');
    if (compliance != null) symptomsLog['compliance'] = compliance;
    final hasSymptoms = d.getValue('hasSymptoms');
    if (hasSymptoms != null) symptomsLog['hasSymptoms'] = hasSymptoms;
    final ncdSymptoms = d.getValue('ncdSymptoms');
    if (ncdSymptoms != null) symptomsLog['ncdSymptoms'] = ncdSymptoms;

    return {
      if (bpLog.isNotEmpty) 'bpLog': bpLog,
      if (glucoseLog.isNotEmpty) 'glucoseLog': glucoseLog,
      if (symptomsLog.isNotEmpty) 'symptomsLog': symptomsLog,
      if (d.getValue('htnScreening') != null) 'htnScreening': d.getValue('htnScreening'),
      if (d.getValue('generalInformation') != null)
        'generalInformation': d.getValue('generalInformation'),
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

    final glucoseType = d.getValue('glucoseType') as String?;
    final glucoseValue = asNum(d.getValue('glucoseValue'));
    final hasFbs = glucoseType == 'fbs' && glucoseValue != null;
    final hasRbs = glucoseType != null && glucoseType != 'fbs' && glucoseValue != null;

    final maternal = _compact({
      if (rawSys != null) 'systolic': rawSys.toString(),
      if (rawSys != null) 'systolicUnit': 'mmHg',
      if (rawDia != null) 'diastolic': rawDia.toString(),
      if (rawDia != null) 'diastolicUnit': 'mmHg',
      if (rawPulse != null) 'pulse': rawPulse.toString(),
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
      'ifaTabletsProvided': d.getValue('ifaTabletsProvided'),
      'ifaTabletsConsumed': d.getValue('ifaTabletsConsumed'),
      'calciumTabletsProvided': d.getValue('calciumTabletsProvided'),
      'calciumTabletsConsumed': d.getValue('calciumTabletsConsumed'),
      if (glucoseType != null && glucoseValue != null)
        'bloodSugar': glucoseType == 'fbs' ? 'fasting' : 'random',
      if (hasFbs) 'fastingBloodSugar': glucoseValue,
      if (hasFbs) 'fastingBloodSugarUnit': 'mmol/L',
      if (hasRbs) 'randomBloodSugar': glucoseValue,
      if (hasRbs) 'randomBloodSugarUnit': 'mmol/L',
    });

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

  // ── PNC Child ──────────────────────────────────────────────────────────────

  static Map<String, dynamic> _toPncChild(CanonicalVisitData d) {
    return _compact({
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _compact(Map<String, dynamic> src) {
    return Map.fromEntries(
      src.entries.where((e) => e.value != null),
    );
  }
}
