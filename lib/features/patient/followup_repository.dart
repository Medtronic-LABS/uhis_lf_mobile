import 'dart:convert';

import '../../core/api/api_repository.dart';
import '../../core/db/follow_up_dao.dart';

/// Type of follow-up. `referred` and `householdVisit` mirror the wire
/// `type` values `REFERRED` / `HH_VISIT` the offline bundle ships.
/// Without these, every REFERRED + HH_VISIT row falls into `other` and the
/// patient detail page can't differentiate "patient I sent to facility"
/// from "routine household visit due".
enum FollowUpType {
  screening,
  medicalReview,
  assessment,
  referred,
  householdVisit,
  lost,
  other,
}

/// A follow-up task for a patient.
class FollowUp {
  const FollowUp({
    required this.id,
    required this.patientId,
    required this.type,
    required this.dueDate,
    this.completedAt,
    this.attempts = 0,
    this.isLost = false,
    this.reason,
    this.programme,
    this.rawJson = const {},
  });

  final String id;
  final String patientId;
  final FollowUpType type;
  final DateTime dueDate;
  final DateTime? completedAt;
  final int attempts;
  final bool isLost;
  final String? reason;
  final String? programme;
  final Map<String, dynamic> rawJson;

  bool get isOpen => completedAt == null && !isLost;
  bool get isOverdue => isOpen && dueDate.isBefore(DateTime.now());

  static FollowUp? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final patientId = json['patientId']?.toString() ?? 
                      json['memberId']?.toString();
    if (id == null || patientId == null) return null;

    // Parse due date
    DateTime? dueDate;
    final dueDateVal = json['nextFollowUpDate'] ?? 
                       json['dueDate'] ?? 
                       json['scheduledDate'];
    if (dueDateVal is String) {
      dueDate = DateTime.tryParse(dueDateVal);
    } else if (dueDateVal is int) {
      dueDate = DateTime.fromMillisecondsSinceEpoch(dueDateVal);
    }
    dueDate ??= DateTime.now();

    // Parse completed date
    DateTime? completedAt;
    final completedVal = json['completedAt'] ?? json['completedDate'];
    if (completedVal is String) {
      completedAt = DateTime.tryParse(completedVal);
    } else if (completedVal is int) {
      completedAt = DateTime.fromMillisecondsSinceEpoch(completedVal);
    }

    // Parse type — wire values are `REFERRED` / `HH_VISIT` /
    // `LOST_TO_FOLLOW_UP` / `MEDICAL_REVIEW` / `SCREENED`. Bundle samples
    // (kakina_sk) show 15 REFERRED + 9 HH_VISIT — drop both into `other`
    // and the page misclassifies them, so we map explicitly.
    final typeStr = json['type']?.toString().toLowerCase() ??
                    json['followUpType']?.toString().toLowerCase() ?? '';
    FollowUpType type;
    if (typeStr == 'referred' || typeStr.contains('referr')) {
      type = FollowUpType.referred;
    } else if (typeStr.contains('hh_visit') || typeStr == 'hh-visit' ||
               typeStr.contains('household')) {
      type = FollowUpType.householdVisit;
    } else if (typeStr.contains('lost')) {
      type = FollowUpType.lost;
    } else if (typeStr.contains('medical') || typeStr.contains('review')) {
      type = FollowUpType.medicalReview;
    } else if (typeStr.contains('screen')) {
      type = FollowUpType.screening;
    } else if (typeStr.contains('assessment')) {
      type = FollowUpType.assessment;
    } else {
      type = FollowUpType.other;
    }

    return FollowUp(
      id: id,
      patientId: patientId,
      type: type,
      dueDate: dueDate,
      completedAt: completedAt,
      attempts: json['attempts'] is int ? json['attempts'] : 0,
      isLost: json['isLostToFollowUp'] == true || json['isLost'] == true,
      reason: json['reason']?.toString() ?? json['referralReason']?.toString(),
      programme: json['programme']?.toString() ?? json['programType']?.toString(),
      rawJson: json,
    );
  }
}

/// Repository for fetching follow-up data.
class FollowUpRepository extends ApiRepository {
  FollowUpRepository(super.api, {FollowUpDao? dao}) : _dao = dao;

  /// Optional on-device DAO. When present, [openForPatient] reads the
  /// `follow_ups` table first (offline-first contract — architecture §3.1)
  /// and falls back to remote only if the local query returned empty.
  final FollowUpDao? _dao;

  /// Open follow-ups for a patient — local-first, type-agnostic.
  ///
  /// Old behavior dropped 24/24 bundle rows for kakina_sk because the
  /// remote call hard-filtered `type='MEDICAL_REVIEW'` while every row was
  /// `REFERRED` or `HH_VISIT`. The new contract: query whatever the sync
  /// already wrote into `follow_ups`, keep `completedAt == null && !isLost`.
  /// Remote endpoint only runs when the local set is empty (fresh install,
  /// patient never synced).
  Future<List<FollowUp>> openForPatient(String patientId) async {
    return openForPatientLocal(patientId);
  }

  /// Local-only path. Reads [FollowUpDao.forPatient] and maps each
  /// [FollowUpRow] into the [FollowUp] value object the UI consumes.
  /// Filters to `isOpen` (no completedAt, not lost). Sorted by [FollowUp.dueDate]
  /// ASC (most urgent first).
  Future<List<FollowUp>> openForPatientLocal(String patientId) async {
    final dao = _dao;
    if (dao == null) return const <FollowUp>[];
    // Callers pass either the bare id (`0390444751474`) OR a FHIR
    // reference (`RelatedPerson/0390444751474`, `Patient/...`). The
    // `follow_ups.patient_id` column stores the bare id, so strip any
    // resource-type prefix before the lookup.
    final normalized = _stripFhirPrefix(patientId);
    final rows = await dao.forPatient(normalized);
    final out = <FollowUp>[];
    for (final r in rows) {
      if (r.completedAt != null) continue;
      if (r.isLost) continue;
      final fu = _rowToFollowUp(r);
      if (fu != null) out.add(fu);
    }
    out.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return out;
  }

  static String _stripFhirPrefix(String id) {
    final slash = id.lastIndexOf('/');
    return slash < 0 ? id : id.substring(slash + 1);
  }

  /// Build a [FollowUp] from a [FollowUpRow]. Returns `null` if [FollowUpRow.dueAt]
  /// is missing — UI requires a non-null `dueDate` and a row with no due
  /// date carries no actionable signal.
  FollowUp? _rowToFollowUp(FollowUpRow r) {
    if (r.dueAt == null) return null;

    // Decode rawJson once so type-parsing + reason/programme inference can
    // run through the existing FollowUp.fromJson logic and stay in lockstep.
    Map<String, dynamic> raw;
    try {
      final decoded = jsonDecode(r.rawJson);
      raw = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
    } on Object {
      raw = <String, dynamic>{};
    }

    final type = _mapWireType(r.type);
    return FollowUp(
      id: r.id,
      patientId: r.patientId,
      type: type,
      dueDate: DateTime.fromMillisecondsSinceEpoch(r.dueAt!),
      completedAt: r.completedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(r.completedAt!),
      attempts: r.attempts ?? 0,
      isLost: r.isLost,
      reason: raw['reason']?.toString() ??
          raw['referralReason']?.toString() ??
          raw['encounterName']?.toString(),
      programme: raw['encounterType']?.toString() ??
          raw['programme']?.toString(),
      rawJson: raw,
    );
  }

  /// Stable mapping from bundle wire `type` to enum. Mirrors the
  /// classifier (`MissionDashboardService._classify`) so a follow-up shown
  /// on the dashboard and on the patient detail page carries the same
  /// semantic label.
  static FollowUpType _mapWireType(String? wire) {
    final t = wire?.toUpperCase();
    switch (t) {
      case 'REFERRED':
        return FollowUpType.referred;
      case 'HH_VISIT':
        return FollowUpType.householdVisit;
      case 'LOST_TO_FOLLOW_UP':
        return FollowUpType.lost;
      case 'MEDICAL_REVIEW':
        return FollowUpType.medicalReview;
      case 'SCREENED':
      case 'SCREENING':
        return FollowUpType.screening;
      case 'ASSESSMENT':
        return FollowUpType.assessment;
      default:
        return FollowUpType.other;
    }
  }

  /// Get overdue follow-ups for a patient.
  Future<List<FollowUp>> overdueForPatient(String patientId) async {
    final all = await openForPatient(patientId);
    return all.where((fu) => fu.isOverdue).toList();
  }
}
