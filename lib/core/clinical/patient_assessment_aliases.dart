import '../db/patient_dao.dart';

/// Every patient id assessments may be stored under on this device.
///
/// Care History reads with the route id (`members.patient_id`, FHIR suffix,
/// local PK, …) while [PatientContextBuilder] remaps to `patients.id`.
/// Revisit locks must query all aliases or today's ANC row is missed and
/// yesterday's visit is treated as "last ANC".
Future<List<String>> patientAssessmentAliasIds(
  PatientDao patientDao, {
  required String patientId,
  String? memberId,
}) async {
  final ids = <String>{};

  void add(String? raw) {
    if (raw == null) return;
    final t = raw.trim();
    if (t.isEmpty) return;
    ids.add(t);
    if (t.contains('/')) {
      final stripped = t.substring(t.lastIndexOf('/') + 1).trim();
      if (stripped.isNotEmpty) ids.add(stripped);
    }
  }

  add(patientId);
  add(memberId);

  Future<void> mergePatient(String id) async {
    if (id.trim().isEmpty) return;
    try {
      final patient = await patientDao.byAnyId(id);
      if (patient == null) return;
      add(patient.id);
      add(patient.patientId);
    } catch (_) {}
  }

  await mergePatient(patientId);
  if (memberId != null &&
      memberId.trim().isNotEmpty &&
      memberId.trim() != patientId.trim()) {
    await mergePatient(memberId);
  }

  return ids.toList(growable: false);
}
