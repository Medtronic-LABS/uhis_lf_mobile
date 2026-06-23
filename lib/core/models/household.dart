import 'json_read.dart';

/// A household cached for offline use. Maps the spice-service `HouseholdDTO`
/// onto the normalised columns the dashboard + search need, while keeping the
/// full source payload in [rawJson] for future detail screens (no data loss).
class Household {
  const Household({
    required this.id,
    this.householdNo,
    this.name,
    this.village,
    this.villageId,
    this.memberCount,
    this.updatedAt,
    required this.rawJson,
  });

  final String id;
  final String? householdNo;
  final String? name;
  final String? village;
  final String? villageId;
  final int? memberCount;

  /// Server-side last-modified time (epoch millis), used for delta sync ordering.
  final int? updatedAt;
  final String rawJson;

  /// Parses a `HouseholdDTO` JSON map from `/household/list`.
  /// Returns null when the record has no usable primary id (cannot be keyed).
  static Household? fromApiJson(Map json) {
    final id = JsonRead.firstString(json, const ['id', 'referenceId', 'fhirId']);
    if (id == null) return null;
    int? members = JsonRead.firstInt(json, const ['noOfPeople', 'memberCount']);
    if (members == null && json['householdMembers'] is List) {
      members = (json['householdMembers'] as List).length;
    }
    return Household(
      id: id,
      householdNo: JsonRead.firstString(json, const ['householdNo']),
      name: JsonRead.firstString(json, const ['name', 'fullName']),
      village: JsonRead.firstString(json, const ['village']),
      villageId: JsonRead.firstString(json, const ['villageId']),
      memberCount: members,
      updatedAt: JsonRead.epochMillis(json, const ['updatedAt', 'lastUpdated']),
      rawJson: JsonRead.encode(json),
    );
  }

  Map<String, Object?> toDb() => {
        'id': id,
        'household_no': householdNo,
        'name': name,
        'village': village,
        'village_id': villageId,
        'member_count': memberCount,
        'updated_at': updatedAt,
        'raw_json': rawJson,
      };

  static Household fromDb(Map<String, Object?> row) => Household(
        id: row['id'] as String,
        householdNo: row['household_no'] as String?,
        name: row['name'] as String?,
        village: row['village'] as String?,
        villageId: row['village_id'] as String?,
        memberCount: row['member_count'] as int?,
        updatedAt: row['updated_at'] as int?,
        rawJson: row['raw_json'] as String? ?? '{}',
      );
}
