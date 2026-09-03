import '../../core/db/assessment_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';

/// Keys under which synced assessment history may be stored for a member.
///
/// Sync writes assessment rows keyed by the member's local PK (`members.id`);
/// older rows or fallbacks may use FHIR id or `patient_id`.
List<String> memberAssessmentLookupKeys({
  String? id,
  String? fhirId,
  String? patientId,
  String? referenceId,
}) {
  final keys = <String>{};
  void add(String? v) {
    final s = v?.trim();
    if (s != null && s.isNotEmpty) keys.add(s);
  }

  add(id);
  add(fhirId);
  add(patientId);
  add(referenceId);
  return keys.toList();
}

List<String> memberAssessmentLookupKeysFromEntity(HouseholdMemberEntity m) =>
    memberAssessmentLookupKeys(
      id: m.id,
      fhirId: m.fhirId,
      patientId: m.patientId,
      referenceId: m.referenceId,
    );

/// Strips FHIR-style prefixes from a route or reference id.
String stripPatientRouteId(String patientId) {
  if (!patientId.contains('/')) return patientId;
  return patientId.substring(patientId.lastIndexOf('/') + 1);
}

/// Every SQLite key that may hold synced assessment rows for [routePatientId].
///
/// Assessment history is persisted under the local member PK (`members.id` /
/// `patients.id`). Screens often route with the server `patients.patient_id`
/// (e.g. `646733`) while `members.patient_id` still holds the local key — bridge
/// through [PatientDao.byAnyId] before querying [AssessmentDao].
Future<Set<String>> assessmentLookupKeysForRoute({
  required String routePatientId,
  required MemberDao memberDao,
  required PatientDao patientDao,
  Map<String, dynamic>? navigationExtra,
}) async {
  final stripped = stripPatientRouteId(routePatientId.trim());
  final keys = <String>{};
  if (stripped.isNotEmpty) keys.add(stripped);

  final patient = await patientDao.byAnyId(stripped);
  if (patient != null) {
    keys.add(patient.id);
    final serverId = patient.patientId?.trim();
    if (serverId != null && serverId.isNotEmpty) keys.add(serverId);
  }

  try {
    final entity = await memberDao.getById(stripped) ??
        await memberDao.getByPatientId(stripped);
    if (entity != null) {
      keys.addAll(memberAssessmentLookupKeysFromEntity(entity));
    }
  } on Object {
    // Non-fatal — caller still has route + patients-table aliases above.
  }

  if (navigationExtra != null) {
    for (final field in const ['id', 'patientId']) {
      final v = navigationExtra[field]?.toString().trim();
      if (v != null && v.isNotEmpty) keys.add(v);
    }
  }

  return keys;
}

/// Canonical patient key for joined side tables (programmes, follow-ups).
String? memberSideTableKey(HouseholdMemberEntity m) {
  if (m.id.trim().isNotEmpty) return m.id;
  final fhir = m.fhirId?.trim();
  if (fhir != null && fhir.isNotEmpty) return fhir;
  final pid = m.patientId?.trim();
  if (pid != null && pid.isNotEmpty) return pid;
  return null;
}

AssessmentRow? latestSyncedAssessmentForKeys(
  List<String> keys,
  Map<String, List<AssessmentRow>> byKey,
) {
  AssessmentRow? latest;
  for (final key in keys) {
    for (final row in byKey[key] ?? const <AssessmentRow>[]) {
      if (latest == null) {
        latest = row;
        continue;
      }
      final candidateAt = row.occurredAt ?? 0;
      final latestAt = latest.occurredAt ?? 0;
      if (candidateAt > latestAt) latest = row;
    }
  }
  return latest;
}

/// Picks the newest service kind between synced history and local assessments.
String? resolveRecentServiceKind({
  required List<String> lookupKeys,
  required Map<String, List<AssessmentRow>> syncedByKey,
  required Map<String, ({String type, int at})> localLatestByPatientId,
}) {
  final synced = latestSyncedAssessmentForKeys(lookupKeys, syncedByKey);
  ({String type, int at})? local;
  for (final key in lookupKeys) {
    final candidate = localLatestByPatientId[key];
    if (candidate == null) continue;
    if (local == null || candidate.at > local.at) local = candidate;
  }

  final syncedAt = synced?.occurredAt ?? 0;
  final localAt = local?.at ?? 0;
  if (localAt > syncedAt) return local!.type;
  return synced?.kind;
}
