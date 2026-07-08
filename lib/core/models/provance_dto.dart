/// Provenance DTO matching Android's ProvanceDto.
/// Contains organizationId, userId, spiceUserId, modifiedDate for sync operations.
class ProvanceDto {
  final String? userId;
  final String? organizationId;
  final int? spiceUserId;
  final String modifiedDate;

  /// Private constructor for internal use.
  ProvanceDto._({
    required this.userId,
    required this.organizationId,
    required this.spiceUserId,
    required this.modifiedDate,
  });

  /// Factory constructor from a map (used during provenance construction).
  factory ProvanceDto.fromMap(Map<String, dynamic> map) {
    return ProvanceDto._(
      userId: map['userId'] as String?,
      organizationId: map['organizationId'] as String?,
      spiceUserId: map['spiceUserId'] as int?,
      modifiedDate: map['modifiedDate'] as String? ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Convert to JSON for API requests.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'organizationId': organizationId,
    'spiceUserId': spiceUserId,
    'modifiedDate': modifiedDate,
  };

  @override
  String toString() => 'ProvanceDto(userId=$userId, organizationId=$organizationId, spiceUserId=$spiceUserId, modifiedDate=$modifiedDate)';
}
