import 'dart:convert';

import 'custom_status_parse.dart';
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
    this.observations,
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
  final Map<String, dynamic>? observations;
  final Map<String, dynamic> rawJson;

  /// This visit with [observations] replaced.
  ///
  /// For the one case where a visit's identity and its measurements come from
  /// different rows: an un-synced local row is the fresher record of the
  /// visit, but only the synced row carries the flat `observations` map.
  AssessmentHistoryItem copyWithObservations(
    Map<String, dynamic>? observations,
  ) =>
      AssessmentHistoryItem(
        householdMemberId: householdMemberId,
        encounterId: encounterId,
        visitDate: visitDate,
        serviceProvided: serviceProvided,
        referralStatus: referralStatus,
        referralReason: referralReason,
        nextFollowUpDate: nextFollowUpDate,
        isLatestVisit: isLatestVisit,
        customStatus: customStatus,
        observations: observations,
        rawJson: rawJson,
      );

  /// One `assessments` table row as a history item.
  ///
  /// The stored `raw_json` is the server payload, which on its own is missing
  /// the ids the row itself carries — so the column values are folded in
  /// before parsing. `??=` throughout: the payload wins where it has a value,
  /// and the columns only fill the gaps.
  ///
  /// [row] is the DB map shape (`id`, `patient_id`, `kind`, `occurred_at`,
  /// `raw_json`) — `AssessmentRow.toDb()` produces it directly.
  ///
  /// Returns null when the row has no id, no payload, or unparseable JSON.
  /// One home for this because two layers need it: the history-cache writer
  /// rebuilding its table, and the assessment repository reading visit
  /// history for a request.
  static AssessmentHistoryItem? fromAssessmentRow(Map<String, Object?> row) {
    final encounterId = row['id'] as String?;
    final raw = row['raw_json'] as String?;
    if (encounterId == null || encounterId.isEmpty || raw == null) return null;
    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on Object {
      return null;
    }
    map['encounterId'] ??= encounterId;
    map['householdMemberId'] ??=
        JsonRead.firstString(map, const ['householdMemberId', 'memberId']) ??
            row['patient_id']?.toString();
    map['serviceProvided'] ??= row['kind']?.toString();
    final visitMs = row['occurred_at'] as int?;
    if (visitMs != null &&
        JsonRead.epochMillis(map, const ['visitDate']) == null) {
      map['visitDate'] = visitMs;
    }
    return fromJson(map);
  }

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

    final customStatus =
        CustomStatusParse.fromAssessmentHistoryJson(json);

    Map<String, dynamic>? observations;
    final obsRaw = json['observations'];
    if (obsRaw is Map) {
      observations = Map<String, dynamic>.from(obsRaw);
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
      observations: observations,
      rawJson: Map<String, dynamic>.from(json),
    );
  }
}
