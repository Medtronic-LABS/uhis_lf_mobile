import 'dart:convert';

import 'package:sqflite/sqflite.dart';

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
  /// [provenance] — ProvanceDto with `organizationId`, `spiceUserId`, `userId`,
  /// `modifiedDate` from the logged-in user session (matches Android ProvanceDto).
  /// [peerSupervisorId] — numeric user ID used as `peerSupervisorId`.
  Map<String, dynamic> toApiRequest({
    required ProvanceDto? provenance,
    int? peerSupervisorId,
  }) {
    final details =
        jsonDecode(assessmentDetails) as Map<String, dynamic>;

    _injectVitalLogs(details);

    final wrappedDetails = _wrapDetailsForType(assessmentType, details);

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
        if (type == 'ANC' || type == 'PNC') 'pregnancyEpisodeId': ?pregnancyEpisodeId,
        'customStatus': _buildCustomStatus(isReferred, referralStatus),
      },
      if (followUpId != null) 'followUpId': followUpId,
      'updatedAt': updatedAt?.millisecondsSinceEpoch ?? 0,
    };
  }

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

  static int? _extractVisitNumber(String type, Map<String, dynamic> d) {
    final t = type.toUpperCase();
    String? raw;
    if (t == 'ANC') {
      raw = d['ancVisitNumber']?.toString() ??
          (d['anc'] is Map
              ? (d['anc'] as Map)['ancVisitNumber']?.toString()
              : null);
    } else if (t == 'PNC') {
      raw = d['pncVisitNumber']?.toString() ??
          (d['pncMother'] is Map
              ? (d['pncMother'] as Map)['pncVisitNumber']?.toString()
              : null);
    }
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  static List<String> _buildCustomStatus(bool isReferred, String? referralStatus) {
    if (isReferred) return ['Referred'];
    final s = referralStatus?.trim();
    if (s == null || s.isEmpty) return ['Recovered'];
    return [s];
  }

  static void _injectVitalLogs(Map<String, dynamic> d) {
    double? asDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    if (!d.containsKey('bpLog')) {
      final sys = asDouble(d['systolic'] ?? d['systolicBp'] ?? d['bloodPressureSystolic']);
      final dia = asDouble(d['diastolic'] ?? d['diastolicBp'] ?? d['bloodPressureDiastolic']);
      if (sys != null && dia != null) {
        d['bpLog'] = {
          'avgSystolic': sys.toInt(),
          'avgDiastolic': dia.toInt(),
          'avgBloodPressure': '${sys.toInt()}/${dia.toInt()}',
          'bpLogDetails': [
            {'systolic': sys.toInt(), 'diastolic': dia.toInt()}
          ],
        };
      }
    }

    if (!d.containsKey('glucoseLog')) {
      final glucose = asDouble(
          d['glucoseValue'] ?? d['glucose'] ?? d['bloodGlucose'] ?? d['fbs'] ?? d['rbs']);
      if (glucose != null) {
        final type = d['glucoseType'] as String? ??
            (d.containsKey('fbs') ? 'fbs' : d.containsKey('rbs') ? 'rbs' : 'rbs');
        final unit = d['glucoseUnit'] as String? ?? 'mg/dL';
        d['glucoseLog'] = {
          'glucose': glucose,
          'glucoseValue': glucose,
          'glucoseType': type,
          'glucoseUnit': unit,
        };
      }
    }
  }

  static Map<String, dynamic> _wrapDetailsForType(
    String assessmentType,
    Map<String, dynamic> flat,
  ) {
    final key = switch (assessmentType.toUpperCase()) {
      'ANC' => 'anc',
      'NCD' => 'ncd',
      'PNC' => 'pncMother',
      'TB' => 'tb',
      'ICCM' || 'IMCI' => 'iccm',
      'EPI' => null,
      _ => null,
    };
    if (key == null || flat.containsKey(key)) return flat;
    return {key: flat};
  }
}

class LocalAssessmentDao {
  LocalAssessmentDao(this._db);

  final AppDatabase _db;

  static const String tableName = 'local_assessments';

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

  Future<void> insert(LocalAssessmentEntity entity) async {
    await _db.db.insert(
      tableName,
      entity.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(LocalAssessmentEntity entity) async {
    await _db.db.update(
      tableName,
      entity.toDb(),
      where: 'id = ?',
      whereArgs: [entity.id],
    );
  }

  Future<List<LocalAssessmentEntity>> getUnsynced() async {
    final rows = await _db.db.query(
      tableName,
      where: 'sync_status = ?',
      whereArgs: [AssessmentSyncStatus.pending.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

  Future<int> getUnsyncedCount() async {
    final result = await _db.db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE sync_status = ?',
      [AssessmentSyncStatus.pending.name],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<LocalAssessmentEntity>> getByPatientId(String patientId) async {
    final rows = await _db.db.query(
      tableName,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LocalAssessmentEntity.fromDb).toList();
  }

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

  Future<void> delete(String id) async {
    await _db.db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

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
}
