import 'dart:convert';

import 'json_read.dart';
import 'risk.dart';

/// A patient cached for offline use. Maps the spice-service `PatientDetailsDTO`
/// (`/patient/offline/list`) onto normalised columns; the rich clinical fields
/// are preserved verbatim in [rawJson] for the patient-intelligence view.
///
/// Schema v2 adds the AI-Worklist risk + scheduling fields. Programme
/// membership lives in the separate `patient_programmes` table — joined in by
/// [WorklistRepository] — not on this row.
class Patient {
  const Patient({
    required this.id,
    this.patientId,
    this.name,
    this.gender,
    this.dob,
    this.phone,
    this.nationalId,
    this.householdId,
    this.villageId,
    this.villageName,
    this.isActive,
    this.updatedAt,
    required this.rawJson,
    this.age,
    this.riskScore,
    this.riskBand,
    this.riskModifier,
    this.riskReasons = const <String>[],
    this.riskHintLevel,
    this.riskHintColor,
    this.redFlag,
    this.lastVisitAt,
    this.nextDueAt,
    this.missedVisitCount,
  });

  final String id;
  final String? patientId;
  final String? name;
  final String? gender;
  final String? dob;
  final String? phone;
  final String? nationalId;
  final String? householdId;
  final String? villageId;
  final String? villageName;
  final bool? isActive;
  final int? updatedAt;
  final String rawJson;

  // ── Risk / scheduling (worklist) ──────────────────────────────────────────
  final int? age;

  /// Numeric sort rank — `sortRankFor(band, modifier)`. SQL ORDER BY DESC on
  /// this column yields the spec sequence 1a → 1b → 1 → … → 4. Column name
  /// retained from the legacy 0–100 composite-score model to keep migrations
  /// minimal; semantics changed in schema v14.
  final int? riskScore;
  final Band? riskBand;
  final Modifier? riskModifier;
  final List<String> riskReasons;
  final String? riskHintLevel;
  final String? riskHintColor;
  final bool? redFlag;
  final int? lastVisitAt;
  final int? nextDueAt;
  final int? missedVisitCount;

  static Patient? fromApiJson(Map json) {
    final id = JsonRead.firstString(json, const ['id', 'patientId', 'fhirUrl']);
    if (id == null) return null;
    return Patient(
      id: id,
      patientId: JsonRead.firstString(json, const ['patientId']),
      name: JsonRead.composeName(json),
      gender: JsonRead.firstString(json, const ['gender', 'sex']),
      dob: JsonRead.dateIso(json, const ['birthDate', 'dateOfBirth', 'dob']),
      phone: JsonRead.firstString(
          json, const ['phoneNumber', 'mobile', 'contactNumber']),
      nationalId: JsonRead.firstString(
          json, const ['nationalId', 'idCode', 'nid', 'identityValue']),
      householdId:
          JsonRead.firstString(json, const ['houseHoldId', 'householdId']),
      villageId: JsonRead.firstString(json, const ['villageId']),
      villageName: JsonRead.firstString(
          json, const ['subVillage', 'subVillageName', 'sub_village_name']),
      isActive: JsonRead.firstBool(json, const ['isActive', 'active']),
      updatedAt: JsonRead.epochMillis(json, const ['updatedAt', 'lastUpdated']),
      rawJson: JsonRead.encode(json),
      age: JsonRead.firstInt(json, const ['age']),
      riskHintLevel: JsonRead.firstString(json, const ['riskLevel']),
      riskHintColor: JsonRead.firstString(json, const ['riskColorCode']),
      redFlag: JsonRead.firstBool(json, const ['redRiskPatient', 'isRedRisk']),
    );
  }

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'name': name,
        'gender': gender,
        'dob': dob,
        'phone': phone,
        'national_id': nationalId,
        'household_id': householdId,
        'village_id': villageId,
        'village_name': villageName,
        'is_active': isActive == null ? null : (isActive! ? 1 : 0),
        'updated_at': updatedAt,
        'raw_json': rawJson,
        'age': age,
        'risk_score': riskScore,
        'risk_band': riskBand?.wireTag,
        'risk_modifier': riskModifier?.wireTag,
        'risk_reasons':
            riskReasons.isEmpty ? null : jsonEncode(riskReasons),
        'risk_hint_level': riskHintLevel,
        'risk_hint_color': riskHintColor,
        'red_flag': redFlag == null ? null : (redFlag! ? 1 : 0),
        'last_visit_at': lastVisitAt,
        'next_due_at': nextDueAt,
        'missed_visit_count': missedVisitCount,
      };

  static Patient fromDb(Map<String, Object?> row) => Patient(
        id: row['id'] as String,
        patientId: row['patient_id'] as String?,
        name: row['name'] as String?,
        gender: row['gender'] as String?,
        dob: row['dob'] as String?,
        phone: row['phone'] as String?,
        nationalId: row['national_id'] as String?,
        householdId: row['household_id'] as String?,
        villageId: row['village_id'] as String?,
        villageName: row['village_name'] as String?,
        isActive: row['is_active'] == null ? null : (row['is_active'] == 1),
        updatedAt: row['updated_at'] as int?,
        rawJson: row['raw_json'] as String? ?? '{}',
        age: row['age'] as int?,
        riskScore: row['risk_score'] as int?,
        riskBand: row['risk_band'] == null
            ? null
            : Band.fromWireTag(row['risk_band'] as String?),
        riskModifier: row['risk_modifier'] == null
            ? null
            : Modifier.fromWireTag(row['risk_modifier'] as String?),
        riskReasons: _decodeReasons(row['risk_reasons'] as String?),
        riskHintLevel: row['risk_hint_level'] as String?,
        riskHintColor: row['risk_hint_color'] as String?,
        redFlag: row['red_flag'] == null ? null : (row['red_flag'] == 1),
        lastVisitAt: row['last_visit_at'] as int?,
        nextDueAt: row['next_due_at'] as int?,
        missedVisitCount: row['missed_visit_count'] as int?,
      );

  static List<String> _decodeReasons(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on FormatException {
      // Stored value is malformed; treat as empty rather than crashing the UI.
    }
    return const <String>[];
  }
}
