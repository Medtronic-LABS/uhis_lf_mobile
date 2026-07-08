import 'package:flutter/foundation.dart';

import '../../core/api/api_repository.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/db/member_dao.dart';
import '../../core/models/assessment_history_item.dart';
import '../../core/models/fhir_observation.dart';
import '../../core/sync/offline_sync_service.dart';
import '../visit/observation_repository.dart';

/// Health assessment data for a member.
class MemberAssessment {
  const MemberAssessment({
    required this.id,
    required this.type,
    required this.date,
    this.visitNumber,
    this.status,
    this.notes,
    this.rawJson = const {},
  });

  final String id;
  final String type; // 'ANC', 'IMCI', 'PNC', 'NCD', etc.
  final DateTime date;
  final int? visitNumber;
  final String? status;
  final String? notes;
  final Map<String, dynamic> rawJson;

  static MemberAssessment? fromJson(Map<String, dynamic> json) {
    // Support both encounterId (new API) and id (legacy)
    final id = json['encounterId']?.toString() ?? json['id']?.toString();
    if (id == null) return null;

    DateTime? date;
    // Support visitDate (new API) and other date fields
    final dateStr = json['visitDate'] ?? json['createdAt'] ?? json['startTime'] ?? json['date'];
    if (dateStr is String) {
      date = DateTime.tryParse(dateStr);
    } else if (dateStr is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateStr);
    }
    date ??= DateTime.now();

    // Support serviceProvided (new API) and assessmentName/type (legacy)
    final type = json['serviceProvided']?.toString() ??
        json['assessmentName']?.toString() ??
        json['type']?.toString() ??
        'Assessment';

    return MemberAssessment(
      id: id,
      type: _normalizeType(type),
      date: date,
      visitNumber: json['visitNumber'] is int ? json['visitNumber'] : null,
      status: json['referralStatus']?.toString() ?? json['status']?.toString(),
      notes: json['referralReason']?.toString() ?? json['clinicalNotes']?.toString(),
      rawJson: json,
    );
  }

  static String _normalizeType(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('ANC') || upper.contains('PREGNANCY')) return 'ANC';
    if (upper.contains('IMCI') || upper.contains('ICCM') || upper.contains('UNDER_FIVE') || upper.contains('UNDER_2')) return 'IMCI';
    if (upper.contains('PNC')) return 'PNC';
    if (upper.contains('NCD')) return 'NCD';
    if (upper.contains('TB')) return 'TB';
    return type;
  }
}

/// Full member health details including assessments.
class MemberHealthDetails {
  const MemberHealthDetails({
    required this.id,
    this.patientId,
    this.name,
    this.gender,
    this.age,
    this.dateOfBirth,
    this.phoneNumber,
    this.nationalId,
    this.householdId,
    this.villageId,
    this.villageName,
    this.isPregnant = false,
    this.isHouseholdHead = false,
    this.maritalStatus,
    this.disability,
    this.shasthyaShebikaId,
    this.guardianId,
    this.guardianFhirId,
    this.motherReferenceId,
    this.latitude,
    this.longitude,
    this.idType,
    this.assessments = const [],
    this.rawJson = const {},
  });

  final String id;
  final String? patientId;
  final String? name;
  final String? gender;
  final int? age;
  final String? dateOfBirth;
  final String? phoneNumber;
  final String? nationalId;
  final String? householdId;
  final String? villageId;
  final String? villageName;
  final bool isPregnant;
  final bool isHouseholdHead;
  final String? maritalStatus;
  final String? disability;
  final String? shasthyaShebikaId;
  final String? guardianId;
  final String? guardianFhirId;
  final String? motherReferenceId;
  final double? latitude;
  final double? longitude;
  final String? idType;
  final List<MemberAssessment> assessments;
  final Map<String, dynamic> rawJson;

  static MemberHealthDetails fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? age;
    final ageVal = json['age'];
    if (ageVal is int) {
      age = ageVal;
    } else if (ageVal is num) {
      age = ageVal.toInt();
    }

    // Calculate age from dateOfBirth if not available
    if (age == null) {
      final dobStr = str('dateOfBirth');
      if (dobStr != null) {
        try {
          final dob = DateTime.parse(dobStr);
          final now = DateTime.now();
          age = now.year - dob.year;
          if (now.month < dob.month ||
              (now.month == dob.month && now.day < dob.day)) {
            age = age - 1;
          }
        } catch (_) {}
      }
    }

    final assessmentsList = <MemberAssessment>[];
    if (json['assessments'] is List) {
      for (final a in json['assessments']) {
        if (a is Map<String, dynamic>) {
          final assessment = MemberAssessment.fromJson(a);
          if (assessment != null) assessmentsList.add(assessment);
        }
      }
    }

    return MemberHealthDetails(
      id: str('id') ?? '',
      patientId: str('patientId'),
      name: str('name') ?? str('firstName'),
      gender: str('gender'),
      age: age,
      dateOfBirth: str('dateOfBirth'),
      phoneNumber: str('phoneNumber'),
      householdId: str('householdId'),
      villageId: str('villageId'),
      isPregnant: json['isPregnant'] == true,
      assessments: assessmentsList,
      rawJson: json,
    );
  }
}

/// Repository for fetching member health details.
///
/// Authoritative data path (Engineering Design Standards: single source of
/// truth + FHIR R4 on the wire):
///   * Past visits / referrals / service status →
///     `POST /offline-service/offline-sync/member-assessment-history`
///     via [OfflineSyncService.fetchAssessmentHistory].
///   * Encounter-level observations (vitals, screening) →
///     `GET /fhir-server/fhir/Observation?encounter=Encounter/{id}` via
///     [ObservationRepository].
/// Legacy spice-service endpoints (`/spice-service/patient/member-assessment
/// -history`, `/spice-service/patientvisit/list`, `/spice-service/medical
/// -review/history`) are not called from here any more — every member
/// assessment goes through the offline-sync contract.
class MemberDetailRepository extends ApiRepository {
  MemberDetailRepository(
    super.api,
    this._authRepo, {
    MemberDao? members,
    OfflineSyncService? offlineSync,
    ObservationRepository? observations,
  })  : _memberDao = members,
        _offlineSync = offlineSync,
        _observations = observations;

  final AuthRepository _authRepo;
  final MemberDao? _memberDao;
  final OfflineSyncService? _offlineSync;
  final ObservationRepository? _observations;

  /// Fetch member details by ID from local SQLite (populated by offline sync).
  Future<MemberHealthDetails?> getMemberById(String memberId) async {
    // ignore: avoid_print
    print('[MemberDetailRepository] getMemberById: $memberId');
    try {
      if (_memberDao != null) {
        HouseholdMemberEntity? entity = await _memberDao.getById(memberId);
        entity ??= await _memberDao.getByPatientId(memberId);
        if (entity != null) {
          // ignore: avoid_print
          print('[MemberDetailRepository] Found in local DB: ${entity.name}');
          return _entityToDetails(entity);
        }
      }
      // ignore: avoid_print
      print('[MemberDetailRepository] Member not found in local DB');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching member: $e');
      return null;
    }
  }

  MemberHealthDetails _entityToDetails(HouseholdMemberEntity m) {
    int? age;
    if (m.dob != null) {
      final dob = DateTime.tryParse(m.dob!);
      if (dob != null) {
        final now = DateTime.now();
        age = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          age = age - 1;
        }
      }
    }
    return MemberHealthDetails(
      id: m.id,
      patientId: m.patientId,
      name: m.name,
      gender: m.gender,
      age: age,
      dateOfBirth: m.dob,
      phoneNumber: m.phone,
      nationalId: m.nationalId,
      householdId: m.householdId,
      villageId: m.villageId,
      villageName: m.villageName,
      isPregnant: m.isPregnant,
      isHouseholdHead: m.isHouseholdHead,
      maritalStatus: m.maritalStatus,
      disability: m.disability,
      shasthyaShebikaId: m.shasthyaShebikaId,
      guardianId: m.guardianId,
      guardianFhirId: m.guardianFhirId,
      motherReferenceId: m.motherReferenceId,
      latitude: m.latitude,
      longitude: m.longitude,
      idType: m.idType,
    );
  }

  /// Fetch assessment history for a member.
  ///
  /// Calls the offline-sync `member-assessment-history` endpoint scoped to
  /// the member's village (when known) and filters the returned history
  /// rows down to the one member via `householdMemberId`. The endpoint is
  /// the only path that returns past visits, referral status, and the
  /// `nextFollowUpDate` consistently — the legacy spice-service routes are
  /// no longer reached from here.
  ///
  /// For local-only / test data with no village context the call returns an
  /// empty list rather than throwing; callers can degrade gracefully.
  Future<List<MemberAssessment>> getMemberAssessments(
    String memberId, {
    String? villageId,
    int? patientAge,
    String? patientGender,
    bool? isPregnant,
  }) async {
    final sync = _offlineSync;
    if (sync == null) {
      debugPrint(
          '[MemberDetailRepository] No OfflineSyncService wired — cannot fetch assessment history');
      return const [];
    }

    // The server sends householdMemberId = the member's FHIR UUID (the `id`
    // field of HouseholdMemberEntity), but the caller passes Patient.id which
    // is preferably the numeric patientId. Resolve all known IDs for this
    // member so the filter can match whichever form the server sends.
    final acceptableIds = <String>{memberId};
    if (_memberDao != null) {
      final entity = await _memberDao.getById(memberId) ??
          await _memberDao.getByPatientId(memberId);
      if (entity != null) {
        if (entity.id.isNotEmpty) acceptableIds.add(entity.id);
        if (entity.fhirId != null && entity.fhirId!.isNotEmpty) {
          acceptableIds.add(entity.fhirId!);
        }
        if (entity.patientId != null && entity.patientId!.isNotEmpty) {
          acceptableIds.add(entity.patientId!);
        }
        // referenceId is the server's internal integer PK — assessment-history
        // rows use this as householdMemberId, so it must be in the match set.
        if (entity.referenceId != null && entity.referenceId!.isNotEmpty) {
          acceptableIds.add(entity.referenceId!);
        }
      }
    }

    final scoped = await _resolveVillageScope(villageId);
    final history = await sync.fetchAssessmentHistory(
      villageIds: scoped,
    );

    debugPrint('[MemberDetailRepository] getMemberAssessments memberId=$memberId acceptableIds=$acceptableIds historyTotal=${history.length}');
    if (history.isNotEmpty) {
      debugPrint('[MemberDetailRepository] sample householdMemberIds=${history.take(5).map((h) => h.householdMemberId).toList()}');
    }
    final assessments = <MemberAssessment>[];
    for (final item in _filterHistoryForMember(history, acceptableIds)) {
      final mapped = _historyToAssessment(item);
      if (mapped != null) assessments.add(mapped);
    }
    debugPrint('[MemberDetailRepository] getMemberAssessments filtered=${assessments.length}');
    assessments.sort((a, b) => b.date.compareTo(a.date));
    return assessments;
  }

  /// Build the village scope for an offline-sync call: prefer the caller's
  /// hint when present, otherwise fall back to the logged-in user's full
  /// assigned set.
  Future<List<int>?> _resolveVillageScope(String? villageId) async {
    if (villageId != null) {
      final id = int.tryParse(villageId);
      if (id != null) return [id];
    }
    final all = await _authRepo.villageIds();
    return all.isEmpty ? null : all;
  }

  /// Pick only the rows that belong to any of the [acceptableIds]. Handles
  /// both plain ID strings and FHIR-reference shapes like `Patient/123`.
  List<AssessmentHistoryItem> _filterHistoryForMember(
    List<AssessmentHistoryItem> rows,
    Set<String> acceptableIds,
  ) {
    // Expand to include the bare segment of any FHIR references in the set.
    final expanded = <String>{...acceptableIds};
    for (final id in acceptableIds) {
      if (id.contains('/')) expanded.add(id.split('/').last);
    }
    return rows.where((row) {
      final hid = row.householdMemberId;
      if (expanded.contains(hid)) return true;
      if (hid.contains('/') && expanded.contains(hid.split('/').last)) {
        return true;
      }
      return false;
    }).toList();
  }

  MemberAssessment? _historyToAssessment(AssessmentHistoryItem item) {
    return MemberAssessment(
      id: item.encounterId,
      type: MemberAssessment._normalizeType(
          item.serviceProvided ?? 'Assessment'),
      date: item.visitDate,
      status: item.referralStatus,
      notes: item.referralReason,
      rawJson: item.rawJson,
    );
  }

  /// Fetch member with their assessments.
  Future<MemberHealthDetails?> getMemberWithAssessments(String memberId) async {
    final member = await getMemberById(memberId);
    if (member == null) return null;

    // Pass the member's villageId and profile to get assessments via villageIds endpoint
    final assessments = await getMemberAssessments(
      memberId,
      villageId: member.villageId,
      patientAge: member.age,
      patientGender: member.gender,
      isPregnant: member.isPregnant,
    );
    
    return MemberHealthDetails(
      id: member.id,
      patientId: member.patientId,
      name: member.name,
      gender: member.gender,
      age: member.age,
      dateOfBirth: member.dateOfBirth,
      phoneNumber: member.phoneNumber,
      householdId: member.householdId,
      villageId: member.villageId,
      isPregnant: member.isPregnant,
      assessments: assessments,
      rawJson: member.rawJson,
    );
  }

  /// Fetch patient details with embedded vitals using the same endpoint as Android.
  /// 
  /// This mirrors Android's approach: calling `/spice-service/patient/patientDetails`
  /// which returns patient data with embedded vitals (avgBloodPressure, glucoseValue, etc.)
  /// and visit counts (pregnancyDetails.ancVisitMedicalReview, etc.).
  /// 
  /// Request body: {patientId, id, assessmentType, type}
  /// Response: PatientListRespModel with vitals and visit counts embedded.
  Future<PatientDetailsWithVitals?> getPatientDetailsWithVitals(
    String patientId, {
    String? assessmentType,
    String? origin,
  }) async {
    debugPrint('[MemberDetailRepository] ========== getPatientDetailsWithVitals START ==========');
    debugPrint('[MemberDetailRepository] patientId=$patientId, assessmentType=$assessmentType, origin=$origin');

    // patientDetails not in approved API set — vitals come from FHIR Observation
    // via assessment-history and offline-sync bundle.
    debugPrint('[MemberDetailRepository] getPatientDetailsWithVitals disabled — not in approved API set');
    return null;
  }

  /// Fetch recent visits for a patient.
  ///
  /// Sourced from the offline-sync `member-assessment-history` endpoint —
  /// the single source of truth for past visits, referral status, and
  /// service-status fields. Legacy spice-service routes
  /// (`patientvisit/list`, `medical-review/history`, FHIR Encounter
  /// fallbacks) are no longer called: every assessment row carries an
  /// `encounterId` we can drill into via [getVisitDetails], so the cascade
  /// is redundant.
  ///
  /// [memberReference] is honoured when the patient is linked to a
  /// `RelatedPerson` (member) record; otherwise we scope by the user's
  /// assigned villages.
  Future<List<PatientVisit>> getRecentVisits(
    String patientId, {
    String? memberReference,
    String? householdId,
    int limit = 5,
  }) async {
    final sync = _offlineSync;
    if (sync == null) {
      debugPrint(
          '[MemberDetailRepository] No OfflineSyncService wired — cannot fetch recent visits');
      return const [];
    }

    final villageScope = await _resolveVillageScope(null);
    final memberId = _memberIdHint(patientId, memberReference);
    final history = await sync.fetchAssessmentHistory(
      villageIds: villageScope,
      memberId: memberId,
    );

    final byEncounterId = <String, PatientVisit>{};
    for (final row in history) {
      if (memberId != null &&
          row.householdMemberId != memberId &&
          !row.householdMemberId.endsWith('/$memberId')) {
        continue;
      }
      byEncounterId[row.encounterId] = PatientVisit.fromAssessmentHistory(row);
    }

    final visits = byEncounterId.values.toList()
      ..sort((a, b) => b.visitDate.compareTo(a.visitDate));
    return visits.take(limit).toList();
  }

  /// Best-effort numeric member id from either [patientId] or [memberReference].
  /// Returns null when the caller has only an opaque FHIR id we cannot match
  /// against the assessment-history rows.
  String? _memberIdHint(String patientId, String? memberReference) {
    if (memberReference != null) {
      final last = memberReference.contains('/')
          ? memberReference.split('/').last
          : memberReference;
      if (last.isNotEmpty) return last;
    }
    if (int.tryParse(patientId) != null) return patientId;
    if (patientId.contains('/')) {
      final last = patientId.split('/').last;
      if (int.tryParse(last) != null) return last;
    }
    return null;
  }

  /// Fetch the FHIR Observation bundle for an encounter.
  ///
  /// This is the new authoritative path for any vitals / screening view —
  /// callers that previously hit `bplog/list`, `glucoselog/list`, or
  /// `medical-review/history` should use this method instead.
  Future<FhirObservationBundle> getEncounterObservations(
      String encounterId) async {
    final obs = _observations;
    if (obs == null) {
      debugPrint(
          '[MemberDetailRepository] No ObservationRepository wired — encounter observations unavailable');
      return const FhirObservationBundle(observations: []);
    }
    return obs.forEncounter(encounterId);
  }

  /// Build a [VisitDetails] from the FHIR Observation bundle for the given
  /// encounter.
  ///
  /// Engineering Design Standards: FHIR R4 on the wire — encounter-level
  /// observations come from `GET /fhir-server/fhir/Observation?encounter=
  /// Encounter/{id}`. The legacy spice-service `medical-review/history` +
  /// type-specific detail endpoints (NCD/ANC/PNC/Mental Health/ICCM/Labour)
  /// are no longer called: vitals, screening, and clinical observations all
  /// live as `Observation` resources keyed by encounter.
  ///
  /// The [type] hint, when supplied, is propagated onto the returned model
  /// so the UI can pick a programme-appropriate render template; otherwise
  /// we leave it null and let the caller decide.
  Future<VisitDetails?> getVisitDetails(
    String encounterId, {
    String? patientReference,
    String? memberReference,
    String? type,
  }) async {
    final bundle = await getEncounterObservations(encounterId);
    if (bundle.observations.isEmpty) {
      debugPrint(
          '[MemberDetailRepository] No observations for encounter $encounterId');
      // Return an empty shell so the UI can still render the visit header
      // (encounter id + caller-supplied programme hint) without surfacing
      // the absence of observations as an error.
      return VisitDetails.fromObservations(
        encounterId: encounterId,
        patientReference: patientReference,
        type: type,
        observations: const [],
      );
    }
    return VisitDetails.fromObservations(
      encounterId: encounterId,
      patientReference: patientReference,
      type: type,
      observations: bundle.observations,
    );
  }
}

/// Detailed visit information.
///
/// Authoritative data path: the FHIR Observation bundle returned by
/// `GET /fhir-server/fhir/Observation?encounter=Encounter/{id}` —
/// see [VisitDetails.fromObservations]. The legacy spice-service medical-
/// review shape ([reviewDetails], [history], [typeSpecificDetails]) is kept
/// for the JSON-decoding compatibility of older test fixtures only; live
/// code populates [observations] instead.
class VisitDetails {
  const VisitDetails({
    this.id,
    this.patientReference,
    this.dateOfReview,
    this.type,
    this.reviewDetails,
    this.history,
    this.typeSpecificDetails,
    this.observations = const [],
    this.rawJson = const {},
  });

  /// Build a VisitDetails from an Observation bundle keyed by encounter.
  /// `dateOfReview` defaults to the earliest observation's
  /// `effectiveDateTime` so the visit-detail header has a date to render
  /// even when the upstream history row is not in scope.
  factory VisitDetails.fromObservations({
    required String encounterId,
    String? patientReference,
    String? type,
    required List<FhirObservation> observations,
  }) {
    DateTime? earliest;
    for (final o in observations) {
      final eff = o.effectiveDateTime;
      if (eff == null) continue;
      if (earliest == null || eff.isBefore(earliest)) earliest = eff;
    }
    return VisitDetails(
      id: encounterId,
      patientReference: patientReference,
      dateOfReview: earliest?.toIso8601String(),
      type: type,
      observations: List<FhirObservation>.unmodifiable(observations),
    );
  }

  final String? id;
  final String? patientReference;
  final String? dateOfReview;
  final String? type;
  final ReviewDetails? reviewDetails;
  final List<Map<String, dynamic>>? history;

  /// Legacy spice-service "type-specific details" map. Only ever populated
  /// by [fromJson] for backwards-compatible deserialisation; live fetches
  /// populate [observations] instead.
  final Map<String, dynamic>? typeSpecificDetails;

  /// FHIR Observation resources captured during this encounter — vitals,
  /// screening responses, programme observations. Authoritative for the
  /// visit-detail view.
  final List<FhirObservation> observations;
  final Map<String, dynamic> rawJson;

  /// Get the visit type - either from top level or from first history item
  String? get visitType {
    if (type != null && type!.isNotEmpty) return type;
    if (history != null && history!.isNotEmpty) {
      final firstHistory = history![0];
      final historyType = firstHistory['type']?.toString();
      if (historyType != null && historyType.isNotEmpty) return historyType;
    }
    return null;
  }

  /// Get the medicalReview sub-object from type-specific details
  Map<String, dynamic>? get _medicalReview {
    if (typeSpecificDetails == null) return null;
    final mr = typeSpecificDetails!['medicalReview'];
    if (mr is Map<String, dynamic>) return mr;
    // If no nested medicalReview, use typeSpecificDetails directly
    return typeSpecificDetails;
  }

  /// Get complaints from type-specific details
  List<String> get complaints {
    final mr = _medicalReview;
    if (mr == null) return [];
    final c = mr['complaints'];
    if (c is List) return c.whereType<String>().toList();
    return [];
  }

  /// Get physical exams from type-specific details
  List<String> get physicalExams {
    final mr = _medicalReview;
    if (mr == null) return [];
    final p = mr['physicalExams'];
    if (p is List) return p.whereType<String>().toList();
    return [];
  }

  /// Get clinical notes from type-specific details
  String? get clinicalNote {
    final mr = _medicalReview;
    if (mr == null) return null;
    // Check for 'notes' array or 'clinicalNote' string
    final notes = mr['notes'];
    if (notes is List && notes.isNotEmpty) {
      return notes.whereType<String>().join('\n');
    }
    return mr['clinicalNote']?.toString();
  }

  /// Get comorbidities from type-specific details
  List<String> get comorbidities {
    final mr = _medicalReview;
    if (mr == null) return [];
    final c = mr['comorbidities'];
    if (c is List) return c.whereType<String>().toList();
    return [];
  }

  /// Get complications from type-specific details
  List<String> get complications {
    final mr = _medicalReview;
    if (mr == null) return [];
    final c = mr['complications'];
    if (c is List) return c.whereType<String>().toList();
    return [];
  }

  /// Get prescriptions from type-specific details
  List<Map<String, dynamic>> get prescriptions {
    final mr = _medicalReview;
    if (mr == null) return [];
    final p = mr['prescriptions'];
    if (p is List) return p.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  /// Get investigations from type-specific details
  List<String> get investigations {
    final mr = _medicalReview;
    if (mr == null) return [];
    final i = mr['investigations'];
    if (i is List) return i.whereType<String>().toList();
    return [];
  }

  /// Check if type-specific details have been loaded
  bool get hasTypeSpecificDetails {
    if (typeSpecificDetails == null || typeSpecificDetails!.isEmpty) return false;
    // Check if there's actual content in medicalReview
    final mr = _medicalReview;
    if (mr == null) return false;
    return mr.values.any((v) => v is List && v.isNotEmpty);
  }

  static VisitDetails? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // Parse reviewDetails
    ReviewDetails? reviewDetails;
    if (json['reviewDetails'] is Map<String, dynamic>) {
      reviewDetails = ReviewDetails.fromJson(json['reviewDetails']);
    }

    // Parse history list
    List<Map<String, dynamic>>? history;
    if (json['history'] is List) {
      history = (json['history'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    // Try to get type from history if not at top level
    String? resolvedType = str('type');
    if ((resolvedType == null || resolvedType.isEmpty) && 
        history != null && history.isNotEmpty) {
      resolvedType = history[0]['type']?.toString();
    }

    return VisitDetails(
      id: str('id'),
      patientReference: str('patientReference'),
      dateOfReview: str('dateOfReview'),
      type: resolvedType,
      reviewDetails: reviewDetails,
      history: history,
      rawJson: json,
    );
  }
}

/// Review details from medical-review/history endpoint.
/// Mirrors Android's ReviewDetails model.
class ReviewDetails {
  const ReviewDetails({
    this.id,
    this.visitNumber,
    this.patientReference,
    this.patientStatus,
    this.diagnosis,
    this.presentingComplaints,
    this.presentingComplaintsNotes,
    this.systemicExaminations,
    this.systemicExaminationsNotes,
    this.obstetricExaminations,
    this.obstetricExaminationsNotes,
    this.clinicalNotes,
    this.isMotherAlive,
    this.breastCondition,
    this.breastConditionNotes,
    this.involutionsOfTheUterus,
    this.involutionsOfTheUterusNotes,
    this.neonateOutcome,
    this.stateOfBaby,
    this.birthWeight,
    this.signs,
    this.labourDTO,
    this.rawJson = const {},
  });

  final String? id;
  final int? visitNumber;
  final String? patientReference;
  final String? patientStatus;
  final List<DiagnosisInfo>? diagnosis;
  final List<String>? presentingComplaints;
  final String? presentingComplaintsNotes;
  final List<String>? systemicExaminations;
  final String? systemicExaminationsNotes;
  final List<String>? obstetricExaminations;
  final String? obstetricExaminationsNotes;
  final String? clinicalNotes;
  final bool? isMotherAlive;
  final String? breastCondition;
  final String? breastConditionNotes;
  final String? involutionsOfTheUterus;
  final String? involutionsOfTheUterusNotes;
  final String? neonateOutcome;
  final String? stateOfBaby;
  final String? birthWeight;
  final List<String>? signs;
  final LabourDetails? labourDTO;
  final Map<String, dynamic> rawJson;

  static ReviewDetails? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? intVal(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    List<String>? strList(dynamic v) {
      if (v == null) return null;
      if (v is List) {
        return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
      return null;
    }

    // Parse diagnosis list
    List<DiagnosisInfo>? diagnosis;
    if (json['diagnosis'] is List) {
      diagnosis = (json['diagnosis'] as List)
          .whereType<Map<String, dynamic>>()
          .map((d) => DiagnosisInfo.fromJson(d))
          .whereType<DiagnosisInfo>()
          .toList();
    }

    // Parse labour details
    LabourDetails? labourDTO;
    if (json['labourDTO'] is Map<String, dynamic>) {
      labourDTO = LabourDetails.fromJson(json['labourDTO']);
    }

    return ReviewDetails(
      id: str('id'),
      visitNumber: intVal(json['visitNumber']),
      patientReference: str('patientReference'),
      patientStatus: str('patientStatus'),
      diagnosis: diagnosis,
      presentingComplaints: strList(json['presentingComplaints']),
      presentingComplaintsNotes: str('presentingComplaintsNotes'),
      systemicExaminations: strList(json['systemicExaminations']) ?? strList(json['systemicExamination']),
      systemicExaminationsNotes: str('systemicExaminationsNotes') ?? str('systemicExaminationNotes'),
      obstetricExaminations: strList(json['obstetricExaminations']),
      obstetricExaminationsNotes: str('obstetricExaminationsNotes') ?? str('obstetricExaminationNotes'),
      clinicalNotes: str('clinicalNotes'),
      isMotherAlive: json['isMotherAlive'] as bool?,
      breastCondition: str('breastCondition'),
      breastConditionNotes: str('breastConditionNotes'),
      involutionsOfTheUterus: str('involutionsOfTheUterus'),
      involutionsOfTheUterusNotes: str('involutionsOfTheUterusNotes'),
      neonateOutcome: str('neonateOutcome'),
      stateOfBaby: str('stateOfBaby'),
      birthWeight: str('birthWeight'),
      signs: strList(json['signs']),
      labourDTO: labourDTO,
      rawJson: json,
    );
  }
}

/// Diagnosis information from review details.
class DiagnosisInfo {
  const DiagnosisInfo({
    this.diseaseCategoryId,
    this.diseaseConditionId,
    this.diseaseCategory,
    this.diseaseCondition,
    this.notes,
    this.type,
  });

  final int? diseaseCategoryId;
  final int? diseaseConditionId;
  final String? diseaseCategory;
  final String? diseaseCondition;
  final String? notes;
  final String? type;

  static DiagnosisInfo? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? intVal(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    return DiagnosisInfo(
      diseaseCategoryId: intVal(json['diseaseCategoryId']),
      diseaseConditionId: intVal(json['diseaseConditionId']),
      diseaseCategory: str('diseaseCategory'),
      diseaseCondition: str('diseaseCondition'),
      notes: str('notes'),
      type: str('type'),
    );
  }

  @override
  String toString() => diseaseCondition ?? diseaseCategory ?? 'Unknown';
}

/// Labour/delivery details.
class LabourDetails {
  const LabourDetails({
    this.dateAndTimeOfDelivery,
    this.dateAndTimeOfLabourOnset,
    this.deliveryType,
    this.deliveryBy,
    this.deliveryAt,
    this.deliveryStatus,
  });

  final String? dateAndTimeOfDelivery;
  final String? dateAndTimeOfLabourOnset;
  final String? deliveryType;
  final String? deliveryBy;
  final String? deliveryAt;
  final String? deliveryStatus;

  static LabourDetails? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return LabourDetails(
      dateAndTimeOfDelivery: str('dateAndTimeOfDelivery'),
      dateAndTimeOfLabourOnset: str('dateAndTimeOfLabourOnset'),
      deliveryType: str('deliveryType'),
      deliveryBy: str('deliveryBy'),
      deliveryAt: str('deliveryAt'),
      deliveryStatus: str('deliveryStatus'),
    );
  }
}

/// Patient visit data from /spice-service/patientvisit/list.
class PatientVisit {
  const PatientVisit({
    required this.id,
    required this.visitDate,
    this.visitNumber,
    this.encounterType,
    this.serviceProvided,
    this.status,
    this.providerName,
    this.notes,
    this.rawJson = const {},
  });

  final String id;
  final DateTime visitDate;
  final int? visitNumber;
  final String? encounterType;
  final String? serviceProvided;
  final String? status;
  final String? providerName;
  final String? notes;
  final Map<String, dynamic> rawJson;

  /// Build a [PatientVisit] from an offline-sync assessment-history row.
  /// This is the authoritative path: the offline-sync endpoint guarantees
  /// `encounterId` + `visitDate` for every past visit, which is all the
  /// Service-History timeline needs to render.
  static PatientVisit fromAssessmentHistory(AssessmentHistoryItem item) {
    return PatientVisit(
      id: item.encounterId,
      visitDate: item.visitDate,
      encounterType: item.serviceProvided,
      serviceProvided: item.serviceProvided,
      status: item.referralStatus,
      notes: item.referralReason,
      rawJson: item.rawJson,
    );
  }

  static PatientVisit? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ??
        json['visitId']?.toString() ??
        json['encounterReference']?.toString();
    if (id == null) return null;

    DateTime? date;
    final dateVal = json['visitDate'] ??
        json['createdAt'] ??
        json['startTime'] ??
        json['date'];
    if (dateVal is String) {
      date = DateTime.tryParse(dateVal);
    } else if (dateVal is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateVal);
    }
    date ??= DateTime.now();

    return PatientVisit(
      id: id,
      visitDate: date,
      visitNumber: json['visitNumber'] is int ? json['visitNumber'] : null,
      encounterType: json['encounterType']?.toString(),
      serviceProvided: json['serviceProvided']?.toString(),
      status: json['status']?.toString(),
      providerName: json['providerName']?.toString() ??
          json['createdByName']?.toString(),
      notes: json['clinicalNotes']?.toString() ?? json['notes']?.toString(),
      rawJson: json,
    );
  }

  static PatientVisit? fromMedicalReview(Map<String, dynamic> json) {
    final id = json['encounterId']?.toString() ??
        json['id']?.toString() ??
        json['encounterReference']?.toString();
    if (id == null) return null;

    DateTime? date;
    final dateVal = json['reviewDate'] ??
        json['visitDate'] ??
        json['createdAt'] ??
        json['date'];
    if (dateVal is String) {
      date = DateTime.tryParse(dateVal);
    } else if (dateVal is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateVal);
    }
    date ??= DateTime.now();

    return PatientVisit(
      id: id,
      visitDate: date,
      visitNumber: json['visitNumber'] is int ? json['visitNumber'] : null,
      encounterType: 'Medical Review',
      serviceProvided: json['reviewType']?.toString() ??
          json['serviceProvided']?.toString(),
      status: json['status']?.toString(),
      providerName: json['reviewerName']?.toString() ??
          json['createdByName']?.toString(),
      notes: json['summary']?.toString() ?? json['clinicalNotes']?.toString(),
      rawJson: json,
    );
  }

  /// Parse a FHIR Encounter resource into a PatientVisit.
  /// FHIR Encounter structure: https://www.hl7.org/fhir/encounter.html
  static PatientVisit? fromFhirEncounter(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    if (id == null) return null;

    // Parse period.start for the visit date
    DateTime? date;
    final period = json['period'] as Map<String, dynamic>?;
    if (period != null) {
      final startStr = period['start']?.toString();
      if (startStr != null) {
        date = DateTime.tryParse(startStr);
      }
    }
    // Fallback to meta.lastUpdated
    if (date == null) {
      final meta = json['meta'] as Map<String, dynamic>?;
      final lastUpdated = meta?['lastUpdated']?.toString();
      if (lastUpdated != null) {
        date = DateTime.tryParse(lastUpdated);
      }
    }
    date ??= DateTime.now();

    // Extract encounter type from type[0].coding[0].display or text
    String? encounterType;
    final types = json['type'] as List?;
    if (types != null && types.isNotEmpty) {
      final firstType = types[0] as Map<String, dynamic>?;
      if (firstType != null) {
        encounterType = firstType['text']?.toString();
        if (encounterType == null) {
          final codings = firstType['coding'] as List?;
          if (codings != null && codings.isNotEmpty) {
            final coding = codings[0] as Map<String, dynamic>?;
            encounterType = coding?['display']?.toString() ?? coding?['code']?.toString();
          }
        }
      }
    }

    // Extract service type from serviceType.coding[0].display
    String? serviceProvided;
    final serviceType = json['serviceType'] as Map<String, dynamic>?;
    if (serviceType != null) {
      serviceProvided = serviceType['text']?.toString();
      if (serviceProvided == null) {
        final codings = serviceType['coding'] as List?;
        if (codings != null && codings.isNotEmpty) {
          final coding = codings[0] as Map<String, dynamic>?;
          serviceProvided = coding?['display']?.toString() ?? coding?['code']?.toString();
        }
      }
    }

    // Extract status
    final status = json['status']?.toString();

    return PatientVisit(
      id: id,
      visitDate: date,
      encounterType: encounterType ?? 'Encounter',
      serviceProvided: serviceProvided,
      status: status,
      rawJson: json,
    );
  }
}

/// Patient details with embedded vitals data.
/// Mirrors Android's `PatientListRespModel` from `/spice-service/patient/patientDetails`.
class PatientDetailsWithVitals {
  const PatientDetailsWithVitals({
    this.id,
    this.patientId,
    this.memberId,
    this.name,
    this.gender,
    this.age,
    this.dateOfBirth,
    this.phoneNumber,
    this.householdId,
    this.villageId,
    this.encounterId,
    // Vitals - embedded in response
    this.avgBloodPressure,
    this.glucoseValue,
    this.glucoseUnit,
    this.height,
    this.weight,
    this.bmi,
    // Visit counts from pregnancyDetails
    this.ancVisitMedicalReview,
    this.pncVisitMedicalReview,
    this.ancVisitAssessment,
    this.pncVisitAssessment,
    this.isPregnant = false,
    this.pregnancyDetails = const {},
    this.rawJson = const {},
  });

  final String? id;
  final String? patientId;
  final String? memberId;
  final String? name;
  final String? gender;
  final int? age;
  final String? dateOfBirth;
  final String? phoneNumber;
  final String? householdId;
  final String? villageId;
  final String? encounterId;
  
  // Recent vitals (like Android's PatientListRespModel)
  final String? avgBloodPressure;
  final String? glucoseValue;
  final String? glucoseUnit;
  final double? height;
  final double? weight;
  final double? bmi;
  
  // Visit counts (from pregnancyDetails)
  final int? ancVisitMedicalReview;
  final int? pncVisitMedicalReview;
  final int? ancVisitAssessment;
  final int? pncVisitAssessment;
  final bool isPregnant;
  final Map<String, dynamic> pregnancyDetails;
  final Map<String, dynamic> rawJson;

  /// Total visits count (ANC + PNC assessments and medical reviews).
  int get totalVisitCount {
    return (ancVisitMedicalReview ?? 0) +
        (pncVisitMedicalReview ?? 0) +
        (ancVisitAssessment ?? 0).toInt() +
        (pncVisitAssessment ?? 0).toInt();
  }

  /// Check if we have any vitals data.
  bool get hasVitals =>
      avgBloodPressure != null ||
      glucoseValue != null ||
      height != null ||
      weight != null;

  /// Parse from API response (matches Android's PatientListRespModel).
  static PatientDetailsWithVitals? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    double? dbl(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int? intVal(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    // Parse pregnancyDetails sub-object
    final pregnancyDetails = json['pregnancyDetails'] as Map<String, dynamic>? ?? {};

    return PatientDetailsWithVitals(
      id: str('id') ?? str('fhirUrl'),
      patientId: str('patientId'),
      memberId: str('memberId'),
      name: str('name') ?? str('firstName'),
      gender: str('gender'),
      age: intVal(json['age']),
      dateOfBirth: str('dateOfBirth') ?? str('birthDate'),
      phoneNumber: str('phoneNumber'),
      householdId: str('houseHoldId') ?? str('householdId'),
      villageId: str('villageId'),
      encounterId: str('encounterId'),
      // Vitals from response
      avgBloodPressure: str('avgBloodPressure'),
      glucoseValue: str('glucoseValue'),
      glucoseUnit: str('glucoseUnit'),
      height: dbl(json['height']),
      weight: dbl(json['weight']),
      bmi: dbl(json['bmi']),
      // Visit counts from pregnancyDetails
      ancVisitMedicalReview: intVal(pregnancyDetails['ancVisitMedicalReview']),
      pncVisitMedicalReview: intVal(pregnancyDetails['pncVisitMedicalReview']),
      ancVisitAssessment: intVal(pregnancyDetails['ancVisitAssessment']),
      pncVisitAssessment: intVal(pregnancyDetails['pncVisitAssessment']),
      isPregnant: json['isPregnant'] == true,
      pregnancyDetails: pregnancyDetails,
      rawJson: json,
    );
  }
}
