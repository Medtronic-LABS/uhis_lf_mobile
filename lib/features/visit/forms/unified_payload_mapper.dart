import 'canonical_visit_data.dart';

/// A single per-programme assessment payload ready for
/// [AssessmentRepository.saveAssessment].
class ProgrammePayload {
  const ProgrammePayload({
    required this.assessmentType,
    required this.details,
  });

  /// Wire-format assessment type: `'ANC'`, `'NCD'`, `'PNC'`, `'PNC_CHILD'`, etc.
  final String assessmentType;

  /// Nested programme-specific map stored as [LocalAssessmentEntity.assessmentDetails] JSON.
  ///
  /// Matches Android's form-group structure exactly:
  ///   ANC  → medicalHistoryPhysicalExamination / pointOfCareInvestigations /
  ///           dangerSignsRiskIdentification / vaccinationAndSupplements /
  ///           ancServicesBirthPreparedness
  ///   NCD  → bpLog (with weight/height/bmi inside) / glucoseLog / symptomsLog
  ///   PNC  → maternalHealthAssessment / pregnancyHistory / postpartumContraception
  ///
  /// [LocalAssessmentEntity.toApiRequest] wraps to `{ "anc": details }` etc.
  /// bpLog/glucoseLog are embedded here — no injection needed at sync time.
  final Map<String, dynamic> details;
}

/// Decomposes a [CanonicalVisitData] into per-programme [ProgrammePayload]s.
///
/// Output structure matches Android AssessmentDefinedParams group keys so the
/// backend offline-service deserializes correctly into its DTO hierarchy.
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
        assessmentType: 'PNC',
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
  // BP lives in medicalHistoryPhysicalExamination.systolic/diastolic — NOT in bpLog.

  static Map<String, dynamic> _toAnc(CanonicalVisitData d) {
    final medHx = _compact({
      'systolic': d.getValue('systolic') ?? d.getValue('bloodPressureSystolic'),
      'diastolic': d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic'),
      'weight': d.getValue('weight'),
      'height': d.getValue('height'),
      'hemoglobin': d.getValue('hemoglobin'),
      'gestationalAge': d.getValue('gestationalAge'),
      'fundalHeight': d.getValue('fundalHeight'),
      'fetalHeartRate': d.getValue('fetalHeartRate'),
      'fetalMovement': d.getValue('fetalMovement'),
      'presentation': d.getValue('presentation'),
      'oedema': d.getValue('oedema'),
      'pallor': d.getValue('pallor'),
      'parity': d.getValue('parity'),
      'ancVisitNumber': d.getValue('ancVisitNumber'),
    });

    final pointOfCare = _compact({
      'urinaryAlbumin': d.getValue('urinaryAlbumin'),
      'urinaryBilirubin': d.getValue('urinaryBilirubin'),
      'urinarySugar': d.getValue('urinarySugar'),
      'bloodSugarFasting': d.getValue('bloodSugarFasting'),
      'bloodSugarRandom': d.getValue('bloodSugarRandom'),
      'glucoseType': d.getValue('glucoseType'),
      'glucoseValue': d.getValue('glucoseValue'),
    });

    // dangerSigns lists are always present (empty = no danger signs reported)
    final dangerSigns = <String, dynamic>{
      'dangerSignsExperienced12':
          d.getValue('dangerSignsExperienced12') ?? <String>[],
      'dangerSignsExperienced13To27':
          d.getValue('dangerSignsExperienced13To27') ?? <String>[],
      'dangerSignsExperienced28To40':
          d.getValue('dangerSignsExperienced28To40') ?? <String>[],
    };
    final eclampsia = d.getValue('eclampsia');
    if (eclampsia != null) dangerSigns['eclampsia'] = eclampsia;

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
      'facilityIdentifiedForDelivery':
          d.getValue('facilityIdentifiedForDelivery'),
      'ancVisitsOtherProviders': d.getValue('ancVisitsOtherProviders'),
      'ancFromMedicalDoctor': d.getValue('ancFromMedicalDoctor'),
      'ultrasound': d.getValue('ultrasound'),
    });

    return {
      if (medHx.isNotEmpty) 'medicalHistoryPhysicalExamination': medHx,
      if (pointOfCare.isNotEmpty) 'pointOfCareInvestigations': pointOfCare,
      'dangerSignsRiskIdentification': dangerSigns,
      if (vaccination.isNotEmpty) 'vaccinationAndSupplements': vaccination,
      if (birthPrep.isNotEmpty) 'ancServicesBirthPreparedness': birthPrep,
    };
  }

  // ── NCD ────────────────────────────────────────────────────────────────────
  // Android NCD payload structure (from reference payload + AssessmentViewModel):
  //   ncd.bpLog   = { avgSystolic, avgDiastolic, avgBloodPressure,
  //                   weight, height, bmi, isRegularSmoker, bpLogDetails[] }
  //   ncd.glucoseLog = { glucose, glucoseType, glucoseUnit, hba1c }
  //   ncd.symptomsLog = { compliance, hasSymptoms, ncdSymptoms[] }
  //
  // weight/height/bmi/isRegularSmoker are INSIDE bpLog, not at top level.

  static Map<String, dynamic> _toNcd(CanonicalVisitData d) {
    double? asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final sys = asDouble(d.getValue('systolic') ?? d.getValue('bloodPressureSystolic'));
    final dia = asDouble(d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic'));

    final bpLog = <String, dynamic>{};
    if (sys != null && dia != null) {
      bpLog['avgSystolic'] = sys.toInt();
      bpLog['avgDiastolic'] = dia.toInt();
      bpLog['avgBloodPressure'] = '${sys.toInt()}/${dia.toInt()}';
      bpLog['bpLogDetails'] = [
        {'systolic': sys.toInt(), 'diastolic': dia.toInt()}
      ];
    }
    final weight = d.getValue('weight');
    if (weight != null) bpLog['weight'] = weight;
    final height = d.getValue('height');
    if (height != null) bpLog['height'] = height;
    final bmi = d.getValue('bmi');
    if (bmi != null) bpLog['bmi'] = bmi;
    final isRegularSmoker = d.getValue('isRegularSmoker');
    if (isRegularSmoker != null) bpLog['isRegularSmoker'] = isRegularSmoker;

    final glucoseNum = asDouble(d.getValue('glucoseValue'));
    final glucoseLog = <String, dynamic>{};
    if (glucoseNum != null) {
      glucoseLog['glucose'] = glucoseNum;
      final glucoseType = d.getValue('glucoseType');
      if (glucoseType != null) glucoseLog['glucoseType'] = glucoseType;
      glucoseLog['glucoseUnit'] =
          d.getValue('glucoseUnit') as String? ?? 'mmol/L';
      final hba1c = d.getValue('hba1c');
      if (hba1c != null) glucoseLog['hba1c'] = hba1c;
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
      if (d.getValue('temperature') != null) 'temperature': d.getValue('temperature'),
      if (d.getValue('htnScreening') != null) 'htnScreening': d.getValue('htnScreening'),
    };
  }

  // ── PNC Mother ─────────────────────────────────────────────────────────────
  // Android PNC Mother payload (from reference payload + RMNCH.kt constants):
  //   pncMother.maternalHealthAssessment = { systolic, diastolic, weight,
  //                                          hemoglobin, urinaryAlbumin, ... }
  //   pncMother.pregnancyHistory         = { parity, gravida, livingChildren }
  //   pncMother.postpartumContraception  = { familyPlanningMethods }
  //   pncMother.visitNo                  = <int>
  //   pncMother.daysSinceDelivery        = <int>

  static Map<String, dynamic> _toPncMother(CanonicalVisitData d) {
    final maternal = _compact({
      'systolic': d.getValue('systolic') ?? d.getValue('bloodPressureSystolic'),
      'diastolic': d.getValue('diastolic') ?? d.getValue('bloodPressureDiastolic'),
      'weight': d.getValue('weight'),
      'hemoglobin': d.getValue('hemoglobin'),
      'urinaryAlbumin': d.getValue('urinaryAlbumin'),
      'urinaryBilirubin': d.getValue('urinaryBilirubin'),
      'temperature': d.getValue('temperature'),
      'pulse': d.getValue('pulse'),
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
