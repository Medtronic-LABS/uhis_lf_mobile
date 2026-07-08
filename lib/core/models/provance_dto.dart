/// Provenance DTO matching Android's ProvanceDto.
/// Contains organizationId, userId, spiceUserId, modifiedDate, and spiceRole for sync operations.
class ProvanceDto {
  final String? userId;
  final String? organizationId;
  final int? spiceUserId;
  final String modifiedDate;
  // Required by the fhir-mapper to upsert a Practitioner resource for the SK
  // in the same transaction bundle, preventing HAPI-1094 reference failures.
  final String? spiceRole;

  /// Private constructor for internal use.
  ProvanceDto._({
    required this.userId,
    required this.organizationId,
    required this.spiceUserId,
    required this.modifiedDate,
    this.spiceRole,
  });

  /// Factory constructor from a map (used during provenance construction).
  factory ProvanceDto.fromMap(Map<String, dynamic> map) {
    return ProvanceDto._(
      userId: map['userId'] as String?,
      organizationId: map['organizationId'] as String?,
      spiceUserId: map['spiceUserId'] as int?,
      modifiedDate: map['modifiedDate'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      spiceRole: map['spiceRole'] as String?,
    );
  }

  /// Convert to JSON for API requests.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'userId': userId,
      'organizationId': organizationId,
      'spiceUserId': spiceUserId,
      'modifiedDate': modifiedDate,
    };
    if (spiceRole != null) json['spiceRole'] = spiceRole;
    return json;
  }

  @override
  String toString() =>
      'ProvanceDto(userId=$userId, organizationId=$organizationId, spiceUserId=$spiceUserId, spiceRole=$spiceRole, modifiedDate=$modifiedDate)';
}
