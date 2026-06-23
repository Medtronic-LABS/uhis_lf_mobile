import 'json_read.dart';

/// A household member cached for offline use. Maps the spice-service
/// `HouseholdMemberDTO` (`/household/member/list`) onto normalised columns,
/// keeping the source payload in [rawJson].
class Member {
  const Member({
    required this.id,
    this.householdId,
    this.name,
    this.gender,
    this.dob,
    this.phone,
    this.nationalId,
    this.patientId,
    this.villageId,
    this.isActive,
    this.updatedAt,
    required this.rawJson,
  });

  final String id;
  final String? householdId;
  final String? name;
  final String? gender;

  /// Date of birth, ISO-8601 string.
  final String? dob;
  final String? phone;
  final String? nationalId;

  /// Linked patient id when the member is enrolled as a patient.
  final String? patientId;
  final String? villageId;
  final bool? isActive;
  final int? updatedAt;
  final String rawJson;

  static Member? fromApiJson(Map json) {
    final id = JsonRead.firstString(json, const ['id', 'memberId', 'fhirId']);
    if (id == null) return null;
    return Member(
      id: id,
      householdId:
          JsonRead.firstString(json, const ['householdId', 'houseHoldId']),
      name: JsonRead.composeName(json),
      gender: JsonRead.firstString(json, const ['gender', 'sex']),
      dob: JsonRead.dateIso(json, const ['dateOfBirth', 'birthDate', 'dob']),
      phone: JsonRead.firstString(
          json, const ['phoneNumber', 'mobile', 'contactNumber']),
      nationalId: JsonRead.firstString(
          json, const ['nationalId', 'idCode', 'nid', 'identityValue']),
      patientId: JsonRead.firstString(json, const ['patientId']),
      villageId: JsonRead.firstString(json, const ['villageId']),
      isActive: JsonRead.firstBool(json, const ['isActive', 'active']),
      updatedAt: JsonRead.epochMillis(json, const ['updatedAt', 'lastUpdated']),
      rawJson: JsonRead.encode(json),
    );
  }

  Map<String, Object?> toDb() => {
        'id': id,
        'household_id': householdId,
        'name': name,
        'gender': gender,
        'dob': dob,
        'phone': phone,
        'national_id': nationalId,
        'patient_id': patientId,
        'village_id': villageId,
        'is_active': isActive == null ? null : (isActive! ? 1 : 0),
        'updated_at': updatedAt,
        'raw_json': rawJson,
      };

  static Member fromDb(Map<String, Object?> row) => Member(
        id: row['id'] as String,
        householdId: row['household_id'] as String?,
        name: row['name'] as String?,
        gender: row['gender'] as String?,
        dob: row['dob'] as String?,
        phone: row['phone'] as String?,
        nationalId: row['national_id'] as String?,
        patientId: row['patient_id'] as String?,
        villageId: row['village_id'] as String?,
        isActive: row['is_active'] == null ? null : (row['is_active'] == 1),
        updatedAt: row['updated_at'] as int?,
        rawJson: row['raw_json'] as String? ?? '{}',
      );
}
