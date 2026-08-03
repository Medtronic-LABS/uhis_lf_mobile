import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../debug/console_log.dart';
import '../models/risk.dart';
import '../models/provance_dto.dart';
import 'app_database.dart';

/// Sync status for local assessments, matching Android's OfflineSyncStatus.
enum AssessmentSyncStatus {
  pending,
  inProgress,
  success,
  failed,
  networkError,
}

/// Split of the unsynced queue into assessments that can be pushed now and
/// those whose member or household is not registered server-side yet.
class PushableAssessments {
  const PushableAssessments({required this.ready, required this.blocked});

  /// Encounter identity resolved — safe to send.
  final List<LocalAssessmentEntity> ready;

  /// Held back until the member / household syncs; left untouched in the queue.
  final List<LocalAssessmentEntity> blocked;
}

/// Local assessment entity for offline-first storage.
///
/// Mirrors Android's AssessmentEntity with sync status tracking.
class LocalAssessmentEntity {
  const LocalAssessmentEntity({
    required this.id,
    this.referenceId,
    required this.householdMemberLocalId,
    this.memberId,
    this.householdId,
    this.patientId,
    this.villageId,
    required this.assessmentType,
    required this.assessmentDetails,
    this.otherDetails,
    this.isReferred = false,
    this.referralStatus,
    this.referredReasons,
    this.customStatus,
    this.followUpId,
    this.pregnancyEpisodeId,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.syncStatus = AssessmentSyncStatus.pending,
    this.fhirId,
    this.createdAt,
    this.updatedAt,
  });

  /// Local unique ID (UUID).
  final String id;

  /// Monotonic numeric id sent as the wire `referenceId`, matching Android's
  /// `AssessmentEntity.id` (Long). Assigned by [LocalAssessmentDao.insert];
  /// null only for rows written before schema v38 backfilled them.
  final int? referenceId;

  /// Local household member ID (referenceId).
  final int householdMemberLocalId;

  /// Server member ID (FHIR).
  final String? memberId;

  /// Household ID.
  final String? householdId;

  /// Patient ID (FHIR).
  final String? patientId;

  /// Village ID.
  final String? villageId;

  /// Assessment type: NCD, TB, ANC, ICCM, etc.
  final String assessmentType;

  /// JSON-encoded assessment details.
  final String assessmentDetails;

  /// JSON-encoded other details (follow-up date, referral site, etc.)
  final String? otherDetails;

  /// Whether patient was referred.
  final bool isReferred;

  /// Referral status: Referred, OnTreatment, Recovered.
  final String? referralStatus;

  /// List of referral reasons (JSON array).
  final String? referredReasons;

  /// Programme status computed at submit time (JSON array), matching Android's
  /// AssessmentStatusGenerator output — e.g. `["HIGH_RISK_PW"]`. Sent as
  /// `encounter.customStatus`; null falls back to the referral-derived status.
  final String? customStatus;

  /// Follow-up ID if this is a follow-up assessment.
  final int? followUpId;

  /// Pregnancy episode UUID — generated once per ANC/PNC episode, matching
  /// Android's pregnancyEpisodeId in PregnancyDetails. Required by the server
  /// to link sequential ANC/PNC assessments to the same pregnancy.
  final String? pregnancyEpisodeId;

  /// GPS coordinates.
  final double latitude;
  final double longitude;

  /// Sync status for offline-first.
  final AssessmentSyncStatus syncStatus;

  /// Server-assigned FHIR ID after sync.
  final String? fhirId;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  Map<String, Object?> toDb() => {
        'id': id,
        'reference_id': referenceId,
        'household_member_local_id': householdMemberLocalId,
        'member_id': memberId,
        'household_id': householdId,
        'patient_id': patientId,
        'village_id': villageId,
        'assessment_type': assessmentType,
        'assessment_details': assessmentDetails,
        'other_details': otherDetails,
        'is_referred': isReferred ? 1 : 0,
        'referral_status': referralStatus,
        'referred_reasons': referredReasons,
        'custom_status': customStatus,
        'follow_up_id': followUpId,
        'pregnancy_episode_id': pregnancyEpisodeId,
        'latitude': latitude,
        'longitude': longitude,
        'sync_status': syncStatus.name,
        'fhir_id': fhirId,
        'created_at': createdAt?.millisecondsSinceEpoch,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };

  factory LocalAssessmentEntity.fromDb(Map<String, Object?> row) {
    return LocalAssessmentEntity(
      id: row['id'] as String,
      referenceId: row['reference_id'] as int?,
      householdMemberLocalId: row['household_member_local_id'] as int,
      memberId: row['member_id'] as String?,
      householdId: row['household_id'] as String?,
      patientId: row['patient_id'] as String?,
      villageId: row['village_id'] as String?,
      assessmentType: row['assessment_type'] as String,
      assessmentDetails: row['assessment_details'] as String,
      otherDetails: row['other_details'] as String?,
      isReferred: (row['is_referred'] as int?) == 1,
      referralStatus: row['referral_status'] as String?,
      referredReasons: row['referred_reasons'] as String?,
      customStatus: row['custom_status'] as String?,
      followUpId: row['follow_up_id'] as int?,
      pregnancyEpisodeId: row['pregnancy_episode_id'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (row['longitude'] as num?)?.toDouble() ?? 0.0,
      syncStatus: AssessmentSyncStatus.values.firstWhere(
        (e) => e.name == (row['sync_status'] as String?),
        orElse: () => AssessmentSyncStatus.pending,
      ),
      fhirId: row['fhir_id'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int)
          : null,
      updatedAt: row['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int)
          : null,
    );
  }

  LocalAssessmentEntity copyWith({
    String? id,
    int? referenceId,
    int? householdMemberLocalId,
    String? memberId,
    String? householdId,
    String? patientId,
    String? villageId,
    String? assessmentType,
    String? assessmentDetails,
    String? otherDetails,
    bool? isReferred,
    String? referralStatus,
    String? referredReasons,
    String? customStatus,
    int? followUpId,
    String? pregnancyEpisodeId,
    double? latitude,
    double? longitude,
    AssessmentSyncStatus? syncStatus,
    String? fhirId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      LocalAssessmentEntity(
        id: id ?? this.id,
        referenceId: referenceId ?? this.referenceId,
        householdMemberLocalId:
            householdMemberLocalId ?? this.householdMemberLocalId,
        memberId: memberId ?? this.memberId,
        householdId: householdId ?? this.householdId,
        patientId: patientId ?? this.patientId,
        villageId: villageId ?? this.villageId,
        assessmentType: assessmentType ?? this.assessmentType,
        assessmentDetails: assessmentDetails ?? this.assessmentDetails,
        otherDetails: otherDetails ?? this.otherDetails,
        isReferred: isReferred ?? this.isReferred,
        referralStatus: referralStatus ?? this.referralStatus,
        referredReasons: referredReasons ?? this.referredReasons,
        customStatus: customStatus ?? this.customStatus,
        followUpId: followUpId ?? this.followUpId,
        pregnancyEpisodeId: pregnancyEpisodeId ?? this.pregnancyEpisodeId,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        syncStatus: syncStatus ?? this.syncStatus,
        fhirId: fhirId ?? this.fhirId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Convert to API request format matching Android's Assessment model.
  ///
  /// [provenance] — map with `organizationId`, `spiceUserId`, `userId`,
  /// `modifiedDate` from the logged-in user session.
  /// [peerSupervisorId] — numeric user ID used as `peerSupervisorId`.
  /// Convert to API request format matching Android's Assessment model.
  ///
  /// [provenance] — ProvanceDto with `organizationId`, `spiceUserId`, `userId`,
  /// `modifiedDate` from the logged-in user session (matches Android ProvanceDto).
  /// [peerSupervisorId] — numeric user ID used as `peerSupervisorId`.
  Map<String, dynamic> toApiRequest({
    required ProvanceDto? provenance,
    int? peerSupervisorId,
  }) {
    final details =
        jsonDecode(assessmentDetails) as Map<String, dynamic>;

    // Mapper produces a flat structure; _wrapDetailsForType adds the programme key
    // required by AssessmentDetailsDTO (e.g. NCD → {"ncd": ...}, ANC → {"anc": ...}).
    final wrappedDetails = _wrapDetailsForType(assessmentType, details);

    // visitNumber — server sequences ANC/PNC/RMNCH visits by this field.
    final visitNum = _extractVisitNumber(assessmentType, details);

    // Android wire type may differ from Flutter's stored type — e.g. "PNC_CHILD"
    // is stored in Flutter but Android sends "PNC_NEONATE" on the wire (GAP 6 fix).
    final wireType = _wireType(assessmentType);

    // Pregnancy types that carry a pregnancyEpisodeId in the encounter, matching
    // Android OfflineSyncRepository.getPregnancyEpisodeId() which includes:
    // pwProfile, pregnancyOutcome, anc, PNC_MOTHER, ChildHood_Visit.
    const pregnancyTypes = {
      'ANC', 'PWPROFILE', 'PW_PROFILE', 'PREGNANCY_OUTCOME', 'PREGNANCYOUTCOME',
      'PNC_MOTHER', 'PNC', 'PNC_CHILD', 'PNC_NEONATE', 'PNC_NEONATAL',
      'CHILDHOOD_VISIT', 'CHILD_MENU',
    };
    final isPregnancyType = pregnancyTypes.contains(assessmentType.toUpperCase());

    final request = <String, dynamic>{
      // Android sends the assessment row's own numeric PK. Ours is a UUID, so
      // schema v38 carries a parallel numeric reference_id; pre-v38 rows that
      // were never backfilled fall back to the member id as before.
      'referenceId': referenceId ?? householdMemberLocalId,
      'assessmentType': wireType,
      'assessmentDetails': wrappedDetails,
      // Android's Assessment.villageId is non-null (String), resolved from the
      // household sub-village with a '0' fallback. A null here fails the whole
      // entity server-side.
      'villageId': villageId?.isNotEmpty == true ? villageId : '0',
      'assessmentDate': createdAt?.toUtc().toIso8601String(),
      'patientStatus': referralStatus ?? 'Recovered',
      // Android Assessment DTO has no top-level assessmentStatus — only
      // encounter.customStatus. Omitting keeps the wire shape Android-shaped.
      'peerSupervisorId': ?peerSupervisorId,
      // Android sends a joined String, not a JSON array.
      'referredReasons': _joinedReferredReasons(referredReasons),
      // otherDetails may stash Flutter-only keys (e.g. encounterId) — strip
      // before emitting the Spice top-level `summary`.
      if (_wireSummary(otherDetails) case final summary?) 'summary': summary,
      'encounter': {
        'householdId': householdId,
        'memberId': memberId,
        'referred': isReferred,
        'patientId': patientId,
        'provenance': provenance?.toJson(),
        'latitude': latitude,
        'longitude': longitude,
        'startTime': createdAt?.toUtc().toIso8601String(),
        'endTime': updatedAt?.toUtc().toIso8601String(),
        // All RMNCH types (ANC, PNC_MOTHER, PNC_NEONATE, ChildHood_Visit) carry visitNumber.
        'visitNumber': ?visitNum,
        if (isPregnancyType) 'pregnancyEpisodeId': ?pregnancyEpisodeId,
        // Android sends customStatus list to track patient state server-side.
        // Omitted entirely when the programme has no status to report — Android
        // sends `entity.status`, which is null for workflows
        // AssessmentStatusGenerator does not evaluate (e.g. ChildHood_Visit).
        if (_buildCustomStatus(
              isReferred,
              referralStatus,
              assessmentType,
              wrappedDetails,
              customStatus,
            )
            case final status? when status.isNotEmpty)
          'customStatus': status,
      },
      if (followUpId != null) 'followUpId': followUpId,
      'updatedAt': updatedAt?.millisecondsSinceEpoch ?? 0,
    };

    ConsoleLog.banner('[PayloadDebug] assessment-payload ($wireType)\n${request.toString()}');
    return request;
  }

  /// Decodes [otherDetails] into the wire `summary`, dropping internal keys
  /// that must not leave the device (notably `encounterId`).
  static Map<String, dynamic>? _wireSummary(String? otherDetails) {
    if (otherDetails == null || otherDetails.isEmpty) return null;
    try {
      final decoded = jsonDecode(otherDetails);
      if (decoded is! Map) return null;
      final summary = Map<String, dynamic>.from(decoded);
      summary.remove('encounterId');
      // Leftover from a brief hold-flag experiment — never send to server.
      summary.remove('awaitingSummary');
      return summary.isEmpty ? null : summary;
    } catch (_) {
      return null;
    }
  }

  /// Joins a JSON-encoded `List<String>` into the ", "-delimited string format
  /// that Android's offline-sync/create sends for `referredReasons`.
  static String? _joinedReferredReasons(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is List) {
        final joined = decoded.whereType<String>().join(', ');
        return joined.isEmpty ? null : joined;
      }
      if (decoded is String) return decoded.isEmpty ? null : decoded;
    } catch (_) {}
    return encoded;
  }

  /// Maps Flutter's stored assessment type to the Android wire-format type string.
  ///
  /// Android uses different strings than Flutter's internal constants:
  ///   Flutter "PNC_CHILD" → Android "PNC_NEONATE"
  ///   Flutter "CHILDHOOD_VISIT" → Android "ChildHood_Visit"
  ///   Flutter "ICCM" / "IMCI" → Android "iccm"
  ///   Flutter "EYE_CARE" → Android "eye_care"
  ///   Flutter "FP" → Android "FAMILY_PLANNING"
  static String _wireType(String assessmentType) {
    return switch (assessmentType.toUpperCase()) {
      'PNC_CHILD' || 'PNC_NEONATE' || 'PNC_NEONATAL' => 'PNC_NEONATE',
      'CHILDHOOD_VISIT' || 'CHILD_MENU' => 'ChildHood_Visit',
      // Android stores the menu id uppercased (AssessmentRepository.saveAssessment)
      // and syncs that stored value, so "pwProfile" goes out as "PWPROFILE".
      'PWPROFILE' || 'PW_PROFILE' => 'PWPROFILE',
      // Android stores the menu id uppercased (AssessmentRepository.saveAssessment)
      // and syncs that stored value, so "pregnancyOutcome" goes out as
      // "PREGNANCYOUTCOME".
      'PREGNANCY_OUTCOME' || 'PREGNANCYOUTCOME' => 'PREGNANCYOUTCOME',
      'ICCM' || 'IMCI' => 'iccm',
      'EYE_CARE' => 'eye_care',
      // Android stores the FP menu id uppercased and sends the stored value, so
      // the wire type is "FAMILY_PLANNING" (not the lowercase menu id).
      'FAMILY_PLANNING' || 'FP' => 'FAMILY_PLANNING',
      // CATARACT, NCD, ANC, TB, EPI, PNC_MOTHER, PNC — pass through as-is
      String t => t,
    };
  }

  /// Extracts the sequential visit number from the stored details map.
  /// Android extracts visitNumber for all RMNCH types (ANC, PNC_MOTHER,
  /// PNC_NEONATE, ChildHood_Visit); all other types return null.
  static int? _extractVisitNumber(String type, Map<String, dynamic> d) {
    final t = type.toUpperCase();
    String? raw;
    if (t == 'ANC') {
      // Prefer Spice nested anc.visitNo (wire / already-wrapped rows); fall
      // back to the flat mapper output stored in assessment_details.
      if (d['anc'] is Map) {
        final anc = d['anc'] as Map;
        raw = anc['visitNo']?.toString() ?? anc['ancVisitNumber']?.toString();
      }
      raw ??= d['visitNo']?.toString();
      raw ??= d['ancVisitNumber']?.toString();
      raw ??= (d['medicalHistoryPhysicalExamination'] is Map
          ? (d['medicalHistoryPhysicalExamination'] as Map)['ancVisitNumber']
              ?.toString()
          : null);
    } else if (t == 'PNC' || t == 'PNC_MOTHER') {
      raw = d['visitNo']?.toString() ?? d['pncVisitNumber']?.toString();
      raw ??= (d['pncMother'] is Map
          ? ((d['pncMother'] as Map)['visitNo']?.toString() ??
              (d['pncMother'] as Map)['pncVisitNumber']?.toString())
          : null);
    } else if (t == 'PNC_CHILD' || t == 'PNC_NEONATE' || t == 'PNC_NEONATAL') {
      // Neonate PNC visit number.
      raw = d['visitNo']?.toString() ??
          d['pncNeonateVisitNumber']?.toString() ??
          d['pncVisitNumber']?.toString();
    } else if (t == 'CHILDHOOD_VISIT' || t == 'CHILD_MENU') {
      // Childhood / IMCI visit number.
      raw = d['visitNo']?.toString() ?? d['childVisitNumber']?.toString();
    }
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  /// Derives customStatus list from referral state, matching Android's
  /// Assessment.status field sent in offline-sync/create.
  ///
  /// A [storedStatus] written at submit time (Android AssessmentStatusGenerator
  /// equivalent, e.g. `["HIGH_RISK_PW"]`) wins: Android reports the programme
  /// status regardless of referral, and the referral itself already travels in
  /// `patientStatus` and `encounter.referred`.
  ///
  /// Family Planning reports a programme status instead of the generic
  /// Recovered marker, matching Android AssessmentStatusGenerator.
  ///
  /// Returns null when the programme reports no status at all — Android's
  /// generator has no `pncChild` branch, so a childhood visit syncs with
  /// `customStatus` absent rather than a synthesised "Recovered".
  static List<String>? _buildCustomStatus(
    bool isReferred,
    String? referralStatus,
    String assessmentType,
    Map<String, dynamic> details,
    String? storedStatus,
  ) {
    final decoded = _decodeStatusList(storedStatus);
    if (decoded.isNotEmpty) return decoded;
    final t = assessmentType.toUpperCase();
    if (t == 'CHILDHOOD_VISIT' || t == 'CHILD_MENU') return null;
    if (isReferred) return ['Referred'];
    if (t == 'FAMILY_PLANNING' || t == 'FP') {
      return [_familyPlanningStatus(details)];
    }
    final s = referralStatus?.trim();
    if (s == null || s.isEmpty) return ['Recovered'];
    return [s];
  }

  static List<String> _decodeStatusList(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is List) {
        return decoded
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {/* not JSON — ignore and fall back */}
    return const [];
  }

  /// Android AssessmentStatusGenerator treats an empty method list or the
  /// explicit "none" option as not being on a modern method.
  /// Accepts both the wrapped and legacy flat detail shapes.
  static String _familyPlanningStatus(Map<String, dynamic> details) {
    final wrapped = details['familyPlanning'];
    final methods = (wrapped is Map ? wrapped['familyPlanningMethods'] : null) ??
        details['familyPlanningMethods'];
    final first = methods is List
        ? (methods.isEmpty ? '' : methods.first?.toString() ?? '')
        : methods?.toString() ?? '';
    final value = first.trim().toLowerCase();
    if (value.isEmpty || value == 'none') return 'NOT_USING_MODERN_FP';
    return 'USING_MODERN_FP';
  }

  /// Wrap an assessment payload under the programme-specific key required by
  /// AssessmentDetailsDTO, matching Android OfflineSyncRepository.getAssessmentDetails().
  ///
  ///   ANC         → {"anc": {...}} (FormResultComposer.addToMenuGroup)
  ///   PWPROFILE   → {"pwProfile": {"pregnancyDetailsAndHistory": {...}}}
  ///   PNC_NEONATE → {"pncNeonatal": {...}, "cbs": {}} (CBS sibling required by Android)
  ///   CHILDHOOD_VISIT → {"pncChild": {...}} — no "cbs" sibling: Android's
  ///                     OfflineSyncRepository only moves a "cbs" key into
  ///                     pncChild.cbs when one is already present, and nothing
  ///                     in the childhood-visit form ever populates it, so real
  ///                     production traffic for this type never sends "cbs" at all.
  ///   FAMILY_PLANNING → {"familyPlanning": {...}} (Android AssessmentViewModel
  ///                     rewrites the stored form map to this key before sync)
  ///   EYE_CARE    → {"eye_care": {"eyeCare": {...}, "generalInformation": {...}}}
  ///   CATARACT    → {"cataract": {"generalInformation": {}, "cataract": {...}, ...}}
  ///   TB / EPI → flat (Android pass-through)
  ///
  /// If `details` already contains the programme key (re-entrant call), it is
  /// returned unchanged to avoid double-wrapping.
  static Map<String, dynamic> _wrapDetailsForType(
    String assessmentType,
    Map<String, dynamic> details,
  ) {
    final t = assessmentType.toUpperCase();

    // PNC_NEONATE and CHILDHOOD_VISIT require a "cbs" sibling alongside the
    // programme wrapper — Android OfflineSyncRepository.getAssessmentDetails()
    // always inserts an empty/populated CBS map for both types.
    if (t == 'PNC_CHILD' || t == 'PNC_NEONATE' || t == 'PNC_NEONATAL') {
      if (details.containsKey('pncNeonatal')) return details;
      return {'pncNeonatal': details, 'cbs': <String, dynamic>{}};
    }
    if (t == 'CHILDHOOD_VISIT' || t == 'CHILD_MENU') {
      if (details.containsKey('pncChild')) return details;
      return {'pncChild': details};
    }

    // PW registration: Android groups answers by the form card's `family`, so
    // the single "pregnancyDetailsAndHistory" card becomes an inner object.
    if (t == 'PWPROFILE' || t == 'PW_PROFILE') {
      if (details.containsKey('pwProfile')) return details;
      final grouped = details.containsKey('pregnancyDetailsAndHistory')
          ? details
          : {'pregnancyDetailsAndHistory': details};
      return {'pwProfile': grouped};
    }

    // Pregnancy outcome: Android FormResultComposer.addToMenuGroup wraps all
    // card families under menu key "pregnancyOutcome". The mapper also nests
    // pregnancyOutcomeType under an *inner* card named "pregnancyOutcome", so
    // a plain containsKey check would skip the outer wrap incorrectly.
    if (t == 'PREGNANCY_OUTCOME' || t == 'PREGNANCYOUTCOME') {
      if (_isPregnancyOutcomeMenuWrapped(details)) return details;
      return {'pregnancyOutcome': details};
    }

    // Cataract: FormResultComposer wraps under menu key "cataract", and the
    // Eye Problems card family is also named "cataract" — same double-key
    // pattern as pregnancy outcome.
    if (t == 'CATARACT') {
      if (_isCataractMenuWrapped(details)) return details;
      return {'cataract': details};
    }

    final key = switch (t) {
      // ANC: FormResultComposer.addToMenuGroup wraps under lowercase "anc".
      // The old "GAP 6b" comment misread a commented CBS inject — Android still
      // nests the family groups under assessmentDetails.anc.
      'ANC' => 'anc',
      'NCD' => 'ncd',
      'PNC' || 'PNC_MOTHER' => 'pncMother',
      // ICCM is the only non-NCD/PNC type that gets wrapped (Android explicit handling).
      'ICCM' || 'IMCI' => 'iccm',
      'FAMILY_PLANNING' || 'FP' => 'familyPlanning',
      // Eye care: FormResultComposer.addToMenuGroup(menuType = "eye_care")
      // nests the eyeCare / generalInformation card families under the menu id.
      'EYE_CARE' => 'eye_care',
      // All others — TB, EPI — are flat pass-through
      'CHILD_IMMUNIZATION' => 'childImmunization',
      // All others — TB, EPI, EYE_CARE, CATARACT — are flat pass-through
      // (Android OfflineSyncRepository default branch).
      _ => null,
    };
    if (key == null || details.containsKey(key)) return details;
    return {key: details};
  }

  /// True when [details] is already the Spice outer menu wrap
  /// `{ cataract: { generalInformation / cataract card / … } }`, not the
  /// mapper's card bag that merely contains an inner `cataract` family.
  static bool _isCataractMenuWrapped(Map<String, dynamic> details) {
    if (details.length != 1) return false;
    final inner = details['cataract'];
    if (inner is! Map) return false;
    return inner.containsKey('generalInformation') ||
        inner.containsKey('referralInformation') ||
        inner.containsKey('ncd') ||
        inner['cataract'] is Map;
  }

  /// True when [details] is already the Spice outer menu wrap
  /// `{ pregnancyOutcome: { cardFamilies... } }`, not the mapper's flat card bag
  /// that merely contains an inner `pregnancyOutcome` type card.
  static bool _isPregnancyOutcomeMenuWrapped(Map<String, dynamic> details) {
    if (details.length != 1) return false;
    final inner = details['pregnancyOutcome'];
    if (inner is! Map) return false;
    return inner.containsKey('abortion') ||
        inner.containsKey('maternalDeath') ||
        inner.containsKey('deliveryOutcomes') ||
        inner.containsKey('ancServicesBirthPreparedness') ||
        inner.containsKey('newbornDetails') ||
        inner.containsKey('counsellingAdverseEvent') ||
        inner['pregnancyOutcome'] is Map;
  }
}

/// DAO for local assessment storage with offline-first sync support.
class LocalAssessmentDao {
  LocalAssessmentDao(this._db);

  final AppDatabase _db;

  static const String tableName = 'local_assessments';

  /// Save a new local assessment, assigning the numeric [
  /// LocalAssessmentEntity.referenceId] the server correlates sync status by.
  ///
  /// Ids are handed out as `MAX + 1` rather than reusing `rowid`, so a deleted
  /// row can never hand its number to a later assessment and collide with a
  /// mapping the server already holds.
  Future<int> insert(LocalAssessmentEntity entity) async {
    return _db.db.transaction((txn) async {
      var reference = entity.referenceId;
      if (reference == null) {
        final row = await txn
            .rawQuery('SELECT MAX(reference_id) AS next FROM $tableName');
        reference = ((row.first['next'] as int?) ?? 0) + 1;
      }
      await txn.insert(
        tableName,
        entity.copyWith(referenceId: reference).toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return reference;
    });
  }

  /// Update an existing assessment.
  Future<void> update(LocalAssessmentEntity entity) async {
    await _db.db.update(
      tableName,
      entity.toDb(),
      where: 'id = ?',
      whereArgs: [entity.id],
    );
  }

  /// Pending / retryable assessments whose `otherDetails.encounterId` matches
  /// [encounterId] (visit id). Used by Step 3 to stamp Spice `summary` fields.
  Future<List<LocalAssessmentEntity>> forEncounter(String encounterId) async {
    if (encounterId.isEmpty) return const [];
    final rows = await getUnsynced(includeFailed: true);
    final matched = <LocalAssessmentEntity>[];
    for (final e in rows) {
      final raw = e.otherDetails;
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['encounterId'] == encounterId) {
          matched.add(e);
        }
      } catch (_) {}
    }
    return matched;
  }

  /// Merge [patch] into each matching assessment's `otherDetails` JSON.
  /// Returns how many rows were updated.
  Future<int> mergeOtherDetailsForEncounter({
    required String encounterId,
    required Map<String, dynamic> Function(LocalAssessmentEntity row) patchFor,
  }) async {
    final rows = await forEncounter(encounterId);
    if (rows.isEmpty) return 0;
    final now = DateTime.now();
    var updated = 0;
    for (final row in rows) {
      final existing = <String, dynamic>{};
      final raw = row.otherDetails;
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            existing.addAll(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      }
      existing.addAll(patchFor(row));
      // Preserve encounterId even if patch omitted it.
      existing['encounterId'] = existing['encounterId'] ?? encounterId;
      // Drop any leftover hold flag from earlier builds.
      existing.remove('awaitingSummary');
      await update(row.copyWith(
        otherDetails: jsonEncode(existing),
        updatedAt: now,
      ));
      updated++;
    }
    return updated;
  }

  /// Get all assessments eligible for upload.
  ///
  /// Always includes [AssessmentSyncStatus.pending] and
  /// [AssessmentSyncStatus.networkError] (matching Android's
  /// `getUnSyncedAssessmentByHHMId`). When [includeFailed] is true (Manual /
  /// Initial sync), also includes [AssessmentSyncStatus.failed] so the SK can
  /// retry a prior server rejection.
  Future<List<LocalAssessmentEntity>> getUnsynced({
    bool includeFailed = false,
  }) async {
    final statuses = <String>[
      AssessmentSyncStatus.pending.name,
      AssessmentSyncStatus.networkError.name,
      if (includeFailed) AssessmentSyncStatus.failed.name,
    ];
    final placeholders = List.filled(statuses.length, '?').join(',');
    final rows = await _db.db.query(
      tableName,
      where: 'sync_status IN ($placeholders)',
      whereArgs: statuses,
      orderBy: 'created_at ASC',
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

  /// Assessments eligible for upload, with their encounter identity resolved
  /// from the live member / household rows.
  ///
  /// Android's `AssessmentDAO.getUnSyncedAssessments` joins HouseholdMember and
  /// Household at sync time (`hhm.fhir_id as memberId, hh.fhir_id as
  /// householdId`) rather than trusting whatever was stamped on the row when
  /// the form was saved, and skips any assessment whose member (or household)
  /// has not been registered server-side yet. Doing the same here keeps the
  /// wire payload correct no matter which screen started the visit, and stops
  /// us burning retries on an assessment the FHIR mapper cannot resolve.
  Future<PushableAssessments> getUnsyncedForPush({
    bool includeFailed = false,
  }) async {
    final statuses = <String>[
      AssessmentSyncStatus.pending.name,
      AssessmentSyncStatus.networkError.name,
      if (includeFailed) AssessmentSyncStatus.failed.name,
    ];
    final placeholders = List.filled(statuses.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      'SELECT a.*, '
      'm.fhir_id AS j_member_fhir, m.patient_id AS j_patient_id, '
      'm.household_id AS j_member_household, '
      'm.sub_village_id AS j_member_sub_village, '
      'm.village_id AS j_member_village, '
      'h.fhir_id AS j_household_fhir, '
      'h.sub_village_id AS j_household_sub_village, '
      'h.village_id AS j_household_village '
      'FROM $tableName a '
      'LEFT JOIN ${AppDatabase.tableMembers} m '
      '  ON m.id = a.household_member_local_id '
      'LEFT JOIN ${AppDatabase.tableHouseholds} h ON h.id = m.household_id '
      'WHERE a.sync_status IN ($placeholders) '
      'ORDER BY a.created_at ASC',
      statuses,
    );

    // household_member_local_id can be 0 when the visit was started from a
    // screen that never resolved it — recover those by patient id before
    // deciding an assessment is unpushable.
    final orphanPatientIds = rows
        .where((r) => r['j_member_fhir'] == null)
        .map((r) => r['patient_id'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    var rescue = const <String, Map<String, Object?>>{};
    if (orphanPatientIds.isNotEmpty) {
      final ph = List.filled(orphanPatientIds.length, '?').join(',');
      final found = await _db.db.rawQuery(
        'SELECT m.patient_id, m.fhir_id, m.household_id, m.sub_village_id, '
        '  m.village_id, h.fhir_id AS household_fhir, '
        '  h.sub_village_id AS household_sub_village, '
        '  h.village_id AS household_village '
        'FROM ${AppDatabase.tableMembers} m '
        'LEFT JOIN ${AppDatabase.tableHouseholds} h ON h.id = m.household_id '
        'WHERE m.patient_id IN ($ph)',
        orphanPatientIds,
      );
      rescue = {
        for (final r in found) r['patient_id'] as String: r,
      };
    }

    final ready = <LocalAssessmentEntity>[];
    final blocked = <LocalAssessmentEntity>[];
    for (final row in rows) {
      final entity = LocalAssessmentEntity.fromDb(row);
      final fallback = rescue[row['patient_id']];

      String? pick(String joined, String rescued) =>
          (row[joined] as String?)?.isNotEmpty == true
              ? row[joined] as String
              : (fallback?[rescued] as String?);

      final memberFhir = pick('j_member_fhir', 'fhir_id');
      final householdFhir = pick('j_household_fhir', 'household_fhir');
      final householdLocal = row['j_member_household'] ??
          fallback?['household_id'];

      // Android: `hhm.fhir_id IS NOT NULL AND (hh.id IS NULL OR hh.fhir_id IS
      // NOT NULL)` — hold the assessment until its member (and household, when
      // it has one) exists server-side.
      if (memberFhir == null ||
          (householdLocal != null && householdFhir == null)) {
        blocked.add(entity);
        continue;
      }

      final village = [
        entity.villageId,
        pick('j_household_sub_village', 'household_sub_village'),
        pick('j_member_sub_village', 'sub_village_id'),
        pick('j_household_village', 'household_village'),
        pick('j_member_village', 'village_id'),
      ].firstWhere(
        (v) => v != null && v.isNotEmpty,
        orElse: () => '0',
      );

      ready.add(
        entity.copyWith(
          memberId: memberFhir,
          householdId: householdFhir,
          patientId: entity.patientId?.isNotEmpty == true
              ? entity.patientId
              : pick('j_patient_id', 'patient_id'),
          villageId: village,
        ),
      );
    }
    return PushableAssessments(ready: ready, blocked: blocked);
  }

  /// Count of assessments pending upload (pending + networkError).
  Future<int> getUnsyncedCount() async {
    final result = await _db.db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE sync_status IN (?, ?)',
      [
        AssessmentSyncStatus.pending.name,
        AssessmentSyncStatus.networkError.name,
      ],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Reclaim rows left as [AssessmentSyncStatus.inProgress] after a killed /
  /// crashed sync — but only when older than [olderThan], so an in-flight
  /// Android-parity status poll (create → InProgress → poll status) is not
  /// reset mid-flight into a duplicate re-push.
  Future<int> resetStuckInProgress({
    Duration olderThan = const Duration(minutes: 15),
  }) async {
    final cutoff =
        DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    return _db.db.rawUpdate(
      'UPDATE $tableName SET sync_status = ?, updated_at = ? '
      'WHERE sync_status = ? AND updated_at < ?',
      [
        AssessmentSyncStatus.pending.name,
        DateTime.now().millisecondsSinceEpoch,
        AssessmentSyncStatus.inProgress.name,
        cutoff,
      ],
    );
  }

  /// Open referred assessments (still `Referred` / `OnTreatment` or flagged
  /// `is_referred` without a closed status). Used to backfill the CCE
  /// `referrals` table for locally-created visits.
  Future<List<LocalAssessmentEntity>> getOpenReferred({int limit = 500}) async {
    final rows = await _db.db.query(
      tableName,
      where: 'is_referred = 1 AND (referral_status IS NULL OR referral_status '
          "NOT IN ('Recovered', 'Died', 'closedRecovered', 'closedDeceased'))",
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

  /// Get assessments by patient ID.
  Future<List<LocalAssessmentEntity>> getByPatientId(String patientId) async {
    final rows = await _db.db.query(
      tableName,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

  /// Get assessments by member ID string (server household-member ID).
  /// Fallback for rows stored before FHIR patient ID was reliably set.
  Future<List<LocalAssessmentEntity>> getByMemberId(String memberId) async {
    final rows = await _db.db.query(
      tableName,
      where: 'member_id = ?',
      whereArgs: [memberId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

  /// Get assessment by local ID.
  Future<LocalAssessmentEntity?> getById(String id) async {
    final rows = await _db.db.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LocalAssessmentEntity.fromDb(rows.first);
  }

  /// Update sync status for multiple assessments.
  Future<void> updateSyncStatus(
    List<String> ids,
    AssessmentSyncStatus status,
  ) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.db.rawUpdate(
      'UPDATE $tableName SET sync_status = ?, updated_at = ? WHERE id IN ($placeholders)',
      [status.name, DateTime.now().millisecondsSinceEpoch, ...ids],
    );
  }

  /// Update sync status for the rows carrying [referenceIds], the numeric keys
  /// `offline-sync/status` reports per entity.
  Future<void> updateSyncStatusByReferenceIds(
    List<int> referenceIds,
    AssessmentSyncStatus status,
  ) async {
    if (referenceIds.isEmpty) return;
    final placeholders = List.filled(referenceIds.length, '?').join(',');
    await _db.db.rawUpdate(
      'UPDATE $tableName SET sync_status = ?, updated_at = ? '
      'WHERE reference_id IN ($placeholders)',
      [status.name, DateTime.now().millisecondsSinceEpoch, ...referenceIds],
    );
  }

  /// Stamp the server FHIR id onto the row carrying [referenceId].
  Future<void> applyFhirIdByReferenceId(int referenceId, String fhirId) async {
    await _db.db.update(
      tableName,
      {
        'fhir_id': fhirId,
        'sync_status': AssessmentSyncStatus.success.name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'reference_id = ?',
      whereArgs: [referenceId],
    );
  }

  /// Update FHIR ID after successful sync.
  Future<void> updateFhirId(String localId, String fhirId) async {
    await _db.db.update(
      tableName,
      {
        'fhir_id': fhirId,
        'sync_status': AssessmentSyncStatus.success.name,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Delete assessment by ID.
  Future<void> delete(String id) async {
    await _db.db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Returns true when an ANC assessment already exists today for [patientId].
  /// Used to block duplicate same-day ANC visits.
  Future<bool> hasAncAssessmentTodayForPatient(String patientId) async {
    final todayStart = DateTime.now()
        .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
    final result = await _db.db.rawQuery(
      "SELECT COUNT(*) as count FROM $tableName "
      "WHERE patient_id = ? "
      "AND assessment_type IN ('ANC', 'anc') "
      "AND created_at >= ?",
      [patientId, todayStart.millisecondsSinceEpoch],
    );
    return (result.first['count'] as int) > 0;
  }

  /// Get all assessments for a household member.
  Future<List<LocalAssessmentEntity>> getByHouseholdMemberId(
      int memberId) async {
    final rows = await _db.db.query(
      tableName,
      where: 'household_member_local_id = ?',
      whereArgs: [memberId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

  /// Returns the most recent extracted vitals per patient.
  /// Returns the most recent draft `created_at` (epoch ms) per patient.
  /// Used by the worklist scorer to suppress the overdue signal when a draft
  /// was saved offline more recently than the last synced follow-up date.
  Future<Map<String, int>> latestDraftCreatedAtForMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const {};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    final rows = await _db.db.rawQuery(
      '''
      SELECT patient_id, MAX(created_at) AS latest_at
      FROM $tableName
      WHERE patient_id IN ($placeholders)
        AND patient_id IS NOT NULL
      GROUP BY patient_id
      ''',
      patientIds,
    );
    final out = <String, int>{};
    for (final r in rows) {
      final pid = r['patient_id'] as String?;
      final at = r['latest_at'];
      if (pid != null && at != null) {
        out[pid] = (at is int) ? at : int.tryParse(at.toString()) ?? 0;
      }
    }
    return out;
  }

  /// Queries the most recent NCD or ANC assessment per patient and parses the
  /// assessmentDetails JSON. Merges the form-level eclampsia flag with the
  /// 3-visit trend rule (PRD §2.8.1 Band 2). Returns an empty map if no
  /// assessments exist.
  Future<Map<String, ClinicalVitals>> latestClinicalVitalsForMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const {};

    // Detect the pre-eclampsia pattern: BP + weight + urine rising across
    // 3 visits (PRD §2.8.1 Band 2). Run before the single-vitals query so
    // the flag is ready when we build ClinicalVitals below.
    final trendSnapshots = await _ancTrendSnapshotsForMany(patientIds);
    final eclampsiaTrendPids = <String>{
      for (final entry in trendSnapshots.entries)
        if (_hasEclampsiaTrend(entry.value)) entry.key,
    };

    final placeholders = List.filled(patientIds.length, '?').join(',');
    // Get the most recent NCD or ANC assessment per patient
    final rows = await _db.db.rawQuery(
      '''
    SELECT la.*
    FROM $tableName la
    INNER JOIN (
      SELECT patient_id, MAX(created_at) AS max_at
      FROM $tableName
      WHERE patient_id IN ($placeholders)
        AND assessment_type IN ('NCD', 'ANC', 'ncd', 'anc')
        AND patient_id IS NOT NULL
      GROUP BY patient_id
    ) latest ON la.patient_id = latest.patient_id AND la.created_at = latest.max_at
    ''',
      patientIds,
    );

    final result = <String, ClinicalVitals>{};
    for (final row in rows) {
      final pid = row['patient_id'] as String?;
      if (pid == null) continue;
      final type = (row['assessment_type'] as String?)?.toUpperCase() ?? '';
      final detailsJson = row['assessment_details'] as String?;
      if (detailsJson == null) continue;
      Map<String, dynamic> map;
      try {
        map = jsonDecode(detailsJson) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      // Unwrap nested programme sub-objects into a flat vitals map so
      // extraction logic below works regardless of storage format.
      // ANC: medicalHistoryPhysicalExamination + pointOfCareInvestigations + dangerSignsRiskIdentification
      // NCD: bpLog (avgSystolic/avgDiastolic) + glucoseLog (glucose/glucoseType)
      final flat = <String, dynamic>{...map};
      if (type == 'ANC') {
        for (final sub in [
          'medicalHistoryPhysicalExamination',
          'pointOfCareInvestigations',
          'dangerSignsRiskIdentification',
        ]) {
          if (map[sub] is Map) {
            flat.addAll((map[sub] as Map).cast<String, dynamic>());
          }
        }
      } else if (type == 'NCD') {
        final bpLog = map['bpLog'];
        if (bpLog is Map) {
          flat['bloodPressureSystolic'] ??= bpLog['avgSystolic'];
          flat['bloodPressureDiastolic'] ??= bpLog['avgDiastolic'];
        }
        final gLog = map['glucoseLog'];
        if (gLog is Map) {
          // Spice BD wire uses `glucose`; accept legacy `glucoseValue` too.
          flat['glucoseValue'] ??= gLog['glucose'] ?? gLog['glucoseValue'];
          flat['glucoseType'] ??= gLog['glucoseType'];
        }
      } else if (type == 'PNC_MOTHER' || type == 'PNC') {
        final mha = map['maternalHealthAssessment'];
        if (mha is Map) {
          flat.addAll(mha.cast<String, dynamic>());
        }
      }

      int? parseInt(String key) {
        final v = flat[key];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      }

      double? parseDouble(String key) {
        final v = flat[key];
        if (v is double) return v;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }

      // BP — handles both flat and nested (unwrapped above)
      int? sys = parseInt('systolic') ??
          parseInt('bloodPressureSystolic') ??
          parseInt('avgSystolic');
      if (sys == null) {
        final log = flat['bpLogDetails'];
        if (log is List && log.isNotEmpty) {
          final first = log.first;
          if (first is Map) {
            sys = first['systolic'] is num
                ? (first['systolic'] as num).toInt()
                : null;
          }
        }
      }
      final dia = parseInt('diastolic') ??
          parseInt('bloodPressureDiastolic') ??
          parseInt('avgDiastolic');

      // Hb
      final hb = parseDouble('hemoglobin');

      // Glucose: forms capture mmol/L per spec §2.8 (ANC §4.2.3, NCD §5.2.1).
      // Store fasting only; random readings cannot be compared against the
      // band thresholds reliably.
      double? fastingGluMmolL;
      final glucoseRaw = parseDouble('glucoseValue');
      final glucoseType = (flat['glucoseType'] as String?)?.toLowerCase();
      if (glucoseRaw != null) {
        if (glucoseType == 'fasting' || glucoseType == null) {
          fastingGluMmolL = glucoseRaw;
        }
      }

      // Danger signs — dangerSignsExperienced* are List<String> or bool
      bool hasDanger = false;
      for (final key in const [
        'dangerSignsExperienced12',
        'dangerSignsExperienced13To27',
        'dangerSignsExperienced28To40',
      ]) {
        final v = flat[key];
        if (v == true || (v is List && v.isNotEmpty) || v == 'true') {
          hasDanger = true;
          break;
        }
      }

      // Eclampsia — form-level flag OR 3-visit trend detected above.
      final eclampsiaRaw = flat['eclampsia'];
      final hasEclampsia = eclampsiaRaw == true ||
          eclampsiaRaw == 'yes' ||
          eclampsiaRaw == '1' ||
          eclampsiaTrendPids.contains(pid);

      // Parity — in ANC nested under medicalHistoryPhysicalExamination (unwrapped above)
      final parity = parseInt('parity');

      // Diabetes (check for explicit diabetes field or fasting glucose ≥ 7.0
      // mmol/L per spec §2.8.2 DM diagnostic cutoff).
      final diabetesRaw = flat['diabetes'] ?? flat['hasDiabetes'];
      final hasDiabetes = diabetesRaw == true ||
          diabetesRaw == 'yes' ||
          (fastingGluMmolL != null && fastingGluMmolL >= 7.0);

      // Spec §5.2.2 HTN screening + §2.8.2 stroke-sign Band 1 short-circuit.
      bool readBoolFlag(String key) {
        dynamic v = flat[key];
        if (v == null && flat['htnScreening'] is Map) {
          v = (flat['htnScreening'] as Map)[key];
        }
        return v == true || v == 'true' || v == 'yes' || v == 1;
      }

      final hasStrokeSign = readBoolFlag('oneSidedWeakness');

      // Gestational age (ANC) — stored as 'gestationalWeeks' in the ANC form.
      final gestationalAgeWeeks = parseInt('gestationalWeeks');

      // Abnormal urine (ANC) — urineProtein / urinaryAlbumin / urinarySugar are
      // inside pointOfCareInvestigations, already unwrapped into flat above.
      final hasAbnormalUrine = flat['urineProtein'] == 'Present' ||
          flat['urinaryAlbumin'] != null ||
          flat['urinarySugar'] == 'Present';

      // NCD Band 1: shortness of breath (chestTightnessOrSob from htnScreening)
      // together with an elevated BP reading.
      final hasSob = readBoolFlag('chestTightnessOrSob');
      final hasSobWithHighBp = hasSob && sys != null && sys >= 140;

      result[pid] = ClinicalVitals(
        systolicBp: sys,
        diastolicBp: dia,
        hemoglobin: hb,
        fastingGlucoseMmolL: fastingGluMmolL,
        hasDangerSign: hasDanger,
        hasEclampsia: hasEclampsia,
        hasStrokeSign: hasStrokeSign,
        hasAbnormalUrine: hasAbnormalUrine,
        hasSobWithHighBp: hasSobWithHighBp,
        gestationalAgeWeeks: gestationalAgeWeeks,
        parity: parity,
        hasDiabetes: hasDiabetes,
        assessmentType: type,
      );
    }
    return result;
  }

  /// Fetches the last 3 ANC assessments per patient and parses them into
  /// [_AncTrendSnapshot] records (oldest-first within each list).
  /// Used by [latestClinicalVitalsForMany] to detect the pre-eclampsia
  /// trend pattern (PRD §2.8.1 Band 2 rule).
  Future<Map<String, List<_AncTrendSnapshot>>> _ancTrendSnapshotsForMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const {};
    final placeholders = List.filled(patientIds.length, '?').join(',');
    // Fetch newest-first so we can stop after 3 per patient cheaply in Dart.
    final rows = await _db.db.rawQuery(
      '''
      SELECT patient_id, assessment_details, created_at
      FROM $tableName
      WHERE assessment_type IN ('ANC', 'anc')
        AND patient_id IN ($placeholders)
        AND patient_id IS NOT NULL
      ORDER BY patient_id ASC, created_at DESC
      ''',
      patientIds,
    );

    final byPid = <String, List<_AncTrendSnapshot>>{};
    for (final row in rows) {
      final pid = row['patient_id'] as String?;
      if (pid == null) continue;
      final list = byPid.putIfAbsent(pid, () => []);
      if (list.length >= 3) continue; // already collected 3 newest

      final detailsJson = row['assessment_details'] as String?;
      if (detailsJson == null) continue;
      Map<String, dynamic> map;
      try {
        map = jsonDecode(detailsJson) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      // Mirror the ANC flattening done in latestClinicalVitalsForMany.
      final flat = <String, dynamic>{...map};
      for (final sub in const [
        'medicalHistoryPhysicalExamination',
        'pointOfCareInvestigations',
        'dangerSignsRiskIdentification',
      ]) {
        if (map[sub] is Map) {
          flat.addAll((map[sub] as Map).cast<String, dynamic>());
        }
      }

      int? parseInt(String key) {
        final v = flat[key];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      }

      double? parseDouble(String key) {
        final v = flat[key];
        if (v is double) return v;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }

      list.add(_AncTrendSnapshot(
        systolicBp: parseInt('systolic') ?? parseInt('bloodPressureSystolic'),
        weightKg: parseDouble('weight') ?? parseDouble('bodyWeight'),
        urineProteinPositive: flat['urineProtein'] == 'Present' ||
            flat['urinaryAlbumin'] != null ||
            flat['urinarySugar'] == 'Present',
      ));
    }

    // Rows arrived newest-first; reverse each list so index 0 is the oldest.
    return byPid.map((pid, list) => MapEntry(pid, list.reversed.toList()));
  }

  /// Returns `true` when the last 3 ANC visits show the pre-eclampsia trend
  /// pattern (PRD §2.8.1 Band 2): systolic BP non-decreasing with an overall
  /// rise, weight non-decreasing with an overall rise (where readings exist),
  /// and urine protein positive at the most recent visit.
  ///
  /// Conservative: a missing systolic at any of the three visits returns
  /// `false` — incomplete data never falsely promotes to Band 2.
  static bool _hasEclampsiaTrend(List<_AncTrendSnapshot> snapshots) {
    if (snapshots.length < 3) return false;
    final s1 = snapshots[0]; // oldest
    final s2 = snapshots[1];
    final s3 = snapshots[2]; // newest

    // All three systolic readings must be present.
    final sys1 = s1.systolicBp;
    final sys2 = s2.systolicBp;
    final sys3 = s3.systolicBp;
    if (sys1 == null || sys2 == null || sys3 == null) return false;

    // Non-decreasing at each step AND overall strictly increasing.
    if (sys1 > sys2 || sys2 > sys3 || sys1 >= sys3) return false;

    // Weight: where readings exist, must be non-decreasing with overall rise.
    final w1 = s1.weightKg;
    final w3 = s3.weightKg;
    if (w1 != null && w3 != null) {
      if (w1 >= w3) return false;
      final w2 = s2.weightKg;
      if (w2 != null && (w1 > w2 || w2 > w3)) return false;
    }

    // Latest visit must show urine protein.
    return s3.urineProteinPositive;
  }
}

/// Minimal vitals snapshot for the eclampsia trend computation.
/// File-private — only [LocalAssessmentDao._ancTrendSnapshotsForMany] uses it.
class _AncTrendSnapshot {
  const _AncTrendSnapshot({
    required this.systolicBp,
    required this.weightKg,
    required this.urineProteinPositive,
  });

  final int? systolicBp;
  final double? weightKg;
  final bool urineProteinPositive;
}

// ── Assessment draft DAO (Phase 2) ────────────────────────────────────────────

/// A single in-progress assessment draft, persisted across section saves so
/// the SK can close the app and resume without losing work.
///
/// The row is keyed by [encounterId] (one draft per encounter), which lets the
/// submission orchestrator fan out per-programme legs after all sections are
/// complete.
class AssessmentDraftRow {
  const AssessmentDraftRow({
    required this.encounterId,
    required this.patientId,
    this.memberId,
    required this.activatedProgrammes,
    this.skippedPathways,
    required this.fieldValues,
    required this.sectionStatus,
    this.fieldSources,
    this.createdAt,
    this.updatedAt,
  });

  /// PRIMARY KEY — matches the encounter UUID created by [AssessmentRepository].
  final String encounterId;

  /// FHIR patient ID.
  final String patientId;

  /// FHIR member ID (nullable for household head or pre-registration).
  final String? memberId;

  /// JSON array of activated programme wire-tags (e.g. `["IMCI","TB"]`).
  final String activatedProgrammes;

  /// JSON array of skipped pathway wire-tags (nullable).
  final String? skippedPathways;

  /// JSON map of fieldId → value (e.g. `{"temperature":37.5,"hasCough":true}`).
  final String fieldValues;

  /// JSON map of sectionId → status (`'done'` or `'pending'`).
  final String sectionStatus;

  /// JSON `{"sources": {fieldId: FieldSource.name}, "segments": {fieldId: quote}}`
  /// tracking which draft values were AI-filled (nullable — absent on rows
  /// written before the AI-provenance migration).
  final String? fieldSources;

  /// Unix epoch ms — set on first insert.
  final int? createdAt;

  /// Unix epoch ms — updated on every save.
  final int? updatedAt;

  Map<String, Object?> toDb() => {
        'encounter_id': encounterId,
        'patient_id': patientId,
        'member_id': memberId,
        'activated_programmes': activatedProgrammes,
        'skipped_pathways': skippedPathways,
        'field_values': fieldValues,
        'section_status': sectionStatus,
        'field_sources': fieldSources,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory AssessmentDraftRow.fromDb(Map<String, Object?> row) =>
      AssessmentDraftRow(
        encounterId: row['encounter_id'] as String,
        patientId: row['patient_id'] as String,
        memberId: row['member_id'] as String?,
        activatedProgrammes: row['activated_programmes'] as String,
        skippedPathways: row['skipped_pathways'] as String?,
        fieldValues: row['field_values'] as String,
        sectionStatus: row['section_status'] as String,
        fieldSources: row['field_sources'] as String?,
        createdAt: row['created_at'] as int?,
        updatedAt: row['updated_at'] as int?,
      );

  AssessmentDraftRow copyWith({
    String? encounterId,
    String? patientId,
    String? memberId,
    String? activatedProgrammes,
    String? skippedPathways,
    String? fieldValues,
    String? sectionStatus,
    String? fieldSources,
    int? createdAt,
    int? updatedAt,
  }) =>
      AssessmentDraftRow(
        encounterId: encounterId ?? this.encounterId,
        patientId: patientId ?? this.patientId,
        memberId: memberId ?? this.memberId,
        activatedProgrammes: activatedProgrammes ?? this.activatedProgrammes,
        skippedPathways: skippedPathways ?? this.skippedPathways,
        fieldValues: fieldValues ?? this.fieldValues,
        sectionStatus: sectionStatus ?? this.sectionStatus,
        fieldSources: fieldSources ?? this.fieldSources,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// DAO for in-progress assessment drafts.
///
/// Supports resume-on-relaunch: the screen queries [getAllPending] on startup
/// and offers the SK a "Resume visit?" dialog if a draft is found.
class AssessmentDraftDao {
  AssessmentDraftDao(this._db);

  final AppDatabase _db;

  static const String tableName = 'assessment_draft';

  /// Upsert a draft (insert or replace on primary-key conflict).
  Future<void> saveDraft(AssessmentDraftRow draft) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = draft.toDb();
    // Preserve created_at on updates.
    if (data['created_at'] == null) {
      data['created_at'] = now;
    }
    data['updated_at'] = now;
    await _db.db.insert(
      tableName,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Return the draft for [encounterId], or null if none exists.
  Future<AssessmentDraftRow?> getDraft(String encounterId) async {
    final rows = await _db.db.query(
      tableName,
      where: 'encounter_id = ?',
      whereArgs: [encounterId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AssessmentDraftRow.fromDb(rows.first);
  }

  /// Return the most recently updated draft for [patientId], or null.
  Future<AssessmentDraftRow?> getLatestDraftForPatient(
      String patientId) async {
    final rows = await _db.db.query(
      tableName,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AssessmentDraftRow.fromDb(rows.first);
  }

  /// Delete the draft for [encounterId] (called after successful submission).
  Future<void> deleteDraft(String encounterId) async {
    await _db.db.delete(
      tableName,
      where: 'encounter_id = ?',
      whereArgs: [encounterId],
    );
  }

  /// Return all drafts (used by the resume-on-relaunch check).
  Future<List<AssessmentDraftRow>> getAllPending() async {
    final rows = await _db.db.query(
      tableName,
      orderBy: 'updated_at DESC',
    );
    return rows.map(AssessmentDraftRow.fromDb).toList();
  }

  /// Create the [assessment_draft] table (called during DB schema creation /
  /// migration).
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        encounter_id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        member_id TEXT,
        activated_programmes TEXT NOT NULL,
        skipped_pathways TEXT,
        field_values TEXT NOT NULL,
        section_status TEXT NOT NULL,
        field_sources TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_draft_patient ON $tableName(patient_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_draft_updated ON $tableName(updated_at DESC)');
  }
}
