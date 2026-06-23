import 'json_read.dart';

/// One row of the offline-sync member-assessment-history endpoint
/// (`POST /offline-service/offline-sync/member-assessment-history`).
///
/// Mirrors the backend DTO at
/// `uhis-platform/offline-service/.../dto/AssessmentHistoryItemDTO.java`.
/// The DTO is the single source of truth for the Service-History timeline —
/// no other endpoint should be reached for past visits, referrals, or
/// service-status display.
class AssessmentHistoryItem {
  const AssessmentHistoryItem({
    required this.householdMemberId,
    required this.encounterId,
    required this.visitDate,
    this.serviceProvided,
    this.referralStatus,
    this.referralReason,
    this.nextFollowUpDate,
    this.isLatestVisit = false,
    this.customStatus = const [],
    this.rawJson = const {},
  });

  /// FHIR ID of the household member the visit belongs to.
  final String householdMemberId;

  /// FHIR `Encounter` id — used as the key for the encounter-detail FHIR
  /// fetch (`Observation?encounter=Encounter/{id}`).
  final String encounterId;

  final DateTime visitDate;
  final String? serviceProvided;
  final String? referralStatus;
  final String? referralReason;
  final DateTime? nextFollowUpDate;
  final bool isLatestVisit;
  final List<String> customStatus;
  final Map<String, dynamic> rawJson;

  /// Returns null for rows missing the two id keys we need to render or drill
  /// into the visit (`householdMemberId` + `encounterId`). Skipping silently
  /// keeps the timeline rendering even when one item is malformed.
  static AssessmentHistoryItem? fromJson(Map<String, dynamic> json) {
    final memberId =
        JsonRead.firstString(json, const ['householdMemberId', 'memberId']);
    final encounterId =
        JsonRead.firstString(json, const ['encounterId', 'encounterFhirId']);
    if (memberId == null || encounterId == null) return null;

    final visitMillis = JsonRead.epochMillis(json, const ['visitDate']);
    final visitDate = visitMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(visitMillis)
        : null;
    if (visitDate == null) return null;

    DateTime? followUp;
    final followUpMillis =
        JsonRead.epochMillis(json, const ['nextFollowUpDate']);
    if (followUpMillis != null) {
      followUp = DateTime.fromMillisecondsSinceEpoch(followUpMillis);
    }

    final statusRaw = json['customStatus'];
    final customStatus = <String>[];
    if (statusRaw is List) {
      for (final s in statusRaw) {
        if (s == null) continue;
        final str = s.toString().trim();
        if (str.isNotEmpty) customStatus.add(str);
      }
    }

    return AssessmentHistoryItem(
      householdMemberId: memberId,
      encounterId: encounterId,
      visitDate: visitDate,
      serviceProvided: JsonRead.firstString(json, const ['serviceProvided']),
      referralStatus: JsonRead.firstString(json, const ['referralStatus']),
      referralReason: JsonRead.firstString(json, const ['referralReason']),
      nextFollowUpDate: followUp,
      isLatestVisit:
          JsonRead.firstBool(json, const ['isLatestVisit', 'latestVisit']) ??
              false,
      customStatus: customStatus,
      rawJson: Map<String, dynamic>.from(json),
    );
  }
}
