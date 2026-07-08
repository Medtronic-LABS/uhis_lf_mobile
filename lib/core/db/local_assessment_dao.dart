import 'dart:convert';

import 'package:sqflite/sqflite.dart';

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

/// Local assessment entity for offline-first storage.
///
/// Mirrors Android's AssessmentEntity with sync status tracking.
class LocalAssessmentEntity {
  const LocalAssessmentEntity({
    required this.id,
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

    // Mapper already produces the nested structure (bpLog/glucoseLog embedded).
    // Backend AssessmentDetailsDTO expects programme-specific nesting:
    // ANC → {"anc": <AncDTO>}, NCD → {"ncd": <NcdDTO>}, etc.
    final wrappedDetails = _wrapDetailsForType(assessmentType, details);

    // visitNumber — server sequences ANC/PNC visits by this field.
    final visitNum = _extractVisitNumber(assessmentType, details);

    final type = assessmentType.toUpperCase();

    return {
      'referenceId': householdMemberLocalId,
      'assessmentType': type,
      'assessmentDetails': wrappedDetails,
      'villageId': villageId,
      'assessmentDate': createdAt?.toUtc().toIso8601String(),
      'patientStatus': referralStatus ?? 'Recovered',
      'peerSupervisorId': ?peerSupervisorId,
      // Android sends a joined String, not a JSON array.
      'referredReasons': _joinedReferredReasons(referredReasons),
      if (otherDetails != null) 'summary': jsonDecode(otherDetails!),
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
        'visitNumber': ?visitNum,
        if (type == 'ANC' || type == 'PNC' || type == 'PNC_MOTHER' || type == 'PNC_CHILD')
          'pregnancyEpisodeId': ?pregnancyEpisodeId,
        // Android sends customStatus list to track patient state server-side.
        'customStatus': _buildCustomStatus(isReferred, referralStatus),
      },
      if (followUpId != null) 'followUpId': followUpId,
      'updatedAt': updatedAt?.millisecondsSinceEpoch ?? 0,
    };
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

  /// Extracts the sequential ANC/PNC visit number from the stored details map.
  /// Handles both legacy flat format and current nested format.
  static int? _extractVisitNumber(String type, Map<String, dynamic> d) {
    final t = type.toUpperCase();
    String? raw;
    if (t == 'ANC') {
      // Top-level visitNo (current mapper output)
      raw = d['visitNo']?.toString();
      // Flat legacy
      raw ??= d['ancVisitNumber']?.toString();
      // Nested: medicalHistoryPhysicalExamination.ancVisitNumber
      raw ??= (d['medicalHistoryPhysicalExamination'] is Map
          ? (d['medicalHistoryPhysicalExamination'] as Map)['ancVisitNumber']
              ?.toString()
          : null);
      // Double-wrapped legacy
      raw ??= (d['anc'] is Map
          ? (d['anc'] as Map)['ancVisitNumber']?.toString()
          : null);
    } else if (t == 'PNC' || t == 'PNC_MOTHER') {
      raw = d['visitNo']?.toString() ?? d['pncVisitNumber']?.toString();
      raw ??= (d['pncMother'] is Map
          ? ((d['pncMother'] as Map)['visitNo']?.toString() ??
              (d['pncMother'] as Map)['pncVisitNumber']?.toString())
          : null);
    }
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  /// Derives customStatus list from referral state, matching Android's
  /// Assessment.status field sent in offline-sync/create.
  static List<String> _buildCustomStatus(bool isReferred, String? referralStatus) {
    if (isReferred) return ['Referred'];
    final s = referralStatus?.trim();
    if (s == null || s.isEmpty) return ['Recovered'];
    return [s];
  }

  /// Wrap a nested assessment payload under the programme-specific key that
  /// matches the backend's AssessmentDetailsDTO field names.
  ///
  /// The backend deserializes `assessmentDetails` as AssessmentDetailsDTO,
  /// which has typed fields per programme (e.g. `AncDTO anc`, `NcdDTO ncd`).
  /// The mapper already produces the nested sub-object structure; this method
  /// adds the outer programme-key wrapper required by the DTO.
  ///
  /// If `details` already contains the programme key (re-entrant call), it is
  /// returned unchanged to avoid double-wrapping.
  static Map<String, dynamic> _wrapDetailsForType(
    String assessmentType,
    Map<String, dynamic> details,
  ) {
    final key = switch (assessmentType.toUpperCase()) {
      'ANC' => 'anc',
      'NCD' => 'ncd',
      'PNC' || 'PNC_MOTHER' => 'pncMother',
      'PNC_CHILD' || 'PNC_NEONATAL' => 'pncChild',
      'TB' => 'tb',
      'ICCM' || 'IMCI' => 'iccm',
      'EPI' => null,
      _ => null,
    };
    if (key == null || details.containsKey(key)) return details;
    return {key: details};
  }
}

/// DAO for local assessment storage with offline-first sync support.
class LocalAssessmentDao {
  LocalAssessmentDao(this._db);

  final AppDatabase _db;

  static const String tableName = 'local_assessments';

  /// Create the local_assessments table (call during DB migration).
  static Future<void> createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id TEXT PRIMARY KEY,
        household_member_local_id INTEGER NOT NULL,
        member_id TEXT,
        household_id TEXT,
        patient_id TEXT,
        village_id TEXT,
        assessment_type TEXT NOT NULL,
        assessment_details TEXT NOT NULL,
        other_details TEXT,
        is_referred INTEGER DEFAULT 0,
        referral_status TEXT,
        referred_reasons TEXT,
        follow_up_id INTEGER,
        pregnancy_episode_id TEXT,
        latitude REAL DEFAULT 0.0,
        longitude REAL DEFAULT 0.0,
        sync_status TEXT DEFAULT 'pending',
        fhir_id TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_assessments_patient 
      ON $tableName (patient_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_assessments_sync 
      ON $tableName (sync_status)
    ''');
  }

  /// Save a new local assessment.
  Future<void> insert(LocalAssessmentEntity entity) async {
    await _db.db.insert(
      tableName,
      entity.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  /// Get all unsynced assessments.
  Future<List<LocalAssessmentEntity>> getUnsynced() async {
    final rows = await _db.db.query(
      tableName,
      where: 'sync_status = ?',
      whereArgs: [AssessmentSyncStatus.pending.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

  /// Get unsynced count.
  Future<int> getUnsyncedCount() async {
    final result = await _db.db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE sync_status = ?',
      [AssessmentSyncStatus.pending.name],
    );
    return result.first['count'] as int? ?? 0;
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
  /// Queries the most recent NCD or ANC assessment per patient and parses the
  /// assessmentDetails JSON. Returns an empty map if no assessments exist.
  Future<Map<String, ClinicalVitals>> latestClinicalVitalsForMany(
      List<String> patientIds) async {
    if (patientIds.isEmpty) return const {};
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
          flat['glucoseValue'] ??= gLog['glucose'];
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

      // Eclampsia
      final eclampsiaRaw = flat['eclampsia'];
      final hasEclampsia = eclampsiaRaw == true ||
          eclampsiaRaw == 'yes' ||
          eclampsiaRaw == '1';

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

      result[pid] = ClinicalVitals(
        systolicBp: sys,
        diastolicBp: dia,
        hemoglobin: hb,
        fastingGlucoseMmolL: fastingGluMmolL,
        hasDangerSign: hasDanger,
        hasEclampsia: hasEclampsia,
        hasStrokeSign: hasStrokeSign,
        parity: parity,
        hasDiabetes: hasDiabetes,
        assessmentType: type,
      );
    }
    return result;
  }
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
