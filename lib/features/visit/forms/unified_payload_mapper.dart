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

  /// FLAT map stored as [LocalAssessmentEntity.assessmentDetails] JSON.
  ///
  /// Must be FLAT (no programme key wrapper, no bpLog/glucoseLog sub-objects).
  /// [LocalAssessmentEntity.toApiRequest] handles:
  ///   1. `_wrapDetailsForType` → wraps to `{ "anc": flat }` before POST.
  ///   2. `_injectVitalLogs`    → builds bpLog/glucoseLog from flat fields.
  final Map<String, dynamic> details;
}

/// Decomposes a [CanonicalVisitData] into per-programme [ProgrammePayload]s.
///
/// Field names must match exactly what [LocalAssessmentEntity._injectVitalLogs]
/// and [LocalAssessmentDao.latestClinicalVitalsForMany] read.
abstract final class UnifiedPayloadMapper {
  UnifiedPayloadMapper._();

  /// Decomposes canonical field values into one payload per active formType.
  ///
  /// [activeFormTypes] uses layout_manifests.json keys:
  /// `'anc'`, `'pncMother'`, `'pncChild'`, `'pncNeonatal'`, `'ncd'`,
  /// `'pregnancyOutcome'`, `'pwProfile'`, etc.
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
  // Field names match [LocalAssessmentEntity._injectVitalLogs] aliases and
  // [LocalAssessmentDao.latestClinicalVitalsForMany] read keys.

  static Map<String, dynamic> _toAnc(CanonicalVisitData d) {
    return _compact({
      'bloodPressureSystolic': d.getValue('bloodPressureSystolic'),
      'bloodPressureDiastolic': d.getValue('bloodPressureDiastolic'),
      'weight': d.getValue('weight'),
      'height': d.getValue('height'),
      'bmi': d.getValue('bmi'),
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
      // Urine tests
      'urinaryAlbumin': d.getValue('urinaryAlbumin'),
      'urinaryBilirubin': d.getValue('urinaryBilirubin'),
      'urinarySugar': d.getValue('urinarySugar'),
      // Blood tests
      'bloodSugarFasting': d.getValue('bloodSugarFasting'),
      'bloodSugarRandom': d.getValue('bloodSugarRandom'),
      'glucoseType': d.getValue('glucoseType'),
      'glucoseValue': d.getValue('glucoseValue'),
      // Vaccination & supplements
      'ttTdCompleted': d.getValue('ttTdCompleted'),
      'folicAcidTotalConsumed': d.getValue('folicAcidTotalConsumed'),
      'folicAcidProvided': d.getValue('folicAcidProvided'),
      'ifaTotalConsumed': d.getValue('ifaTotalConsumed'),
      'ifaProvided': d.getValue('ifaProvided'),
      'calciumTotalConsumed': d.getValue('calciumTotalConsumed'),
      'calciumProvided': d.getValue('calciumProvided'),
      // Danger signs — always included (empty list = no danger signs)
      'dangerSignsExperienced12':
          d.getValue('dangerSignsExperienced12') ?? <String>[],
      'dangerSignsExperienced13To27':
          d.getValue('dangerSignsExperienced13To27') ?? <String>[],
      'dangerSignsExperienced28To40':
          d.getValue('dangerSignsExperienced28To40') ?? <String>[],
      'eclampsia': d.getValue('eclampsia'),
      // Birth preparedness
      'facilityIdentifiedForDelivery':
          d.getValue('facilityIdentifiedForDelivery'),
      'ancVisitsOtherProviders': d.getValue('ancVisitsOtherProviders'),
      'ancFromMedicalDoctor': d.getValue('ancFromMedicalDoctor'),
      'ultrasound': d.getValue('ultrasound'),
    });
  }

  // ── NCD ────────────────────────────────────────────────────────────────────
  // Shares weight/height/BP from canonical — no re-entry when ANC also active.
  // _injectVitalLogs builds bpLog from bloodPressureSystolic/Diastolic.
  // _injectVitalLogs builds glucoseLog from glucoseValue/glucoseType.

  static Map<String, dynamic> _toNcd(CanonicalVisitData d) {
    return _compact({
      'bloodPressureSystolic': d.getValue('bloodPressureSystolic'),
      'bloodPressureDiastolic': d.getValue('bloodPressureDiastolic'),
      'weight': d.getValue('weight'),
      'height': d.getValue('height'),
      'bmi': d.getValue('bmi'),
      'temperature': d.getValue('temperature'),
      'glucoseValue': d.getValue('glucoseValue'),
      'glucoseType': d.getValue('glucoseType'),
      'hba1c': d.getValue('hba1c'),
      'isRegularSmoker': d.getValue('isRegularSmoker'),
      // HTN screening — stored as a nested map; backend reads htnScreening.*
      'htnScreening': d.getValue('htnScreening'),
    });
  }

  // ── PNC Mother ─────────────────────────────────────────────────────────────

  static Map<String, dynamic> _toPncMother(CanonicalVisitData d) {
    return _compact({
      'bloodPressureSystolic': d.getValue('bloodPressureSystolic'),
      'bloodPressureDiastolic': d.getValue('bloodPressureDiastolic'),
      'weight': d.getValue('weight'),
      'height': d.getValue('height'),
      'pncVisitNumber': d.getValue('pncVisitNumber'),
      'deliveryType': d.getValue('deliveryType'),
      'deliveryAt': d.getValue('deliveryAt'),
      'deliveryStatus': d.getValue('deliveryStatus'),
      'deliveryDate': d.getValue('deliveryDate'),
      'motherAlive': d.getValue('motherAlive'),
      // Supplements
      'folicAcidTotalConsumed': d.getValue('folicAcidTotalConsumed'),
      'ifaTotalConsumed': d.getValue('ifaTotalConsumed'),
      'calciumTotalConsumed': d.getValue('calciumTotalConsumed'),
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

  /// Removes null entries; always-present list fields are kept as-is.
  static Map<String, dynamic> _compact(Map<String, dynamic> src) {
    return Map.fromEntries(
      src.entries.where((e) => e.value != null),
    );
  }
}
