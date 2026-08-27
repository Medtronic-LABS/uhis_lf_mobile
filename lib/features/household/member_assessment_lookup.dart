import '../../core/db/assessment_dao.dart';
import '../../core/db/member_dao.dart';

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
