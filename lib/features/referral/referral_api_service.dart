import 'package:flutter/foundation.dart';

import '../../core/api/api_repository.dart';
import '../../core/models/referral.dart';

/// Referral API service — all mutating endpoints removed from approved API set.
/// Referral status is read-only, sourced from followUps[].referralStatus in
/// the fetch-synced-data bundle. Creation/update will be re-added once
/// offline-sync/create gains a referrals[] field.
class ReferralApiService extends ApiRepository {
  ReferralApiService(super.api);

  /// Referral data comes from the offline sync bundle (followUps[].referralStatus).
  /// No network call — returns empty list.
  Future<List<Map<String, dynamic>>> fetchReferrals({
    required String patientId,
    int? limit,
    int? offset,
  }) async {
    debugPrint('[ReferralApiService] disabled — not in approved API set');
    return const [];
  }

  Future<String?> createReferral({
    required String patientId,
    required String memberId,
    required String referredReason,
    required String referredTo,
    String? referredBy,
    SlaTier? slaTier,
    String? notes,
  }) async {
    debugPrint('[ReferralApiService] createReferral disabled');
    return null;
  }

  Future<bool> updateReferralStatus({
    required String referralId,
    required String memberId,
    required ReferralStatus status,
    String? reason,
    String? actor,
  }) async {
    debugPrint('[ReferralApiService] updateReferralStatus disabled');
    return false;
  }

  Future<bool> escalateReferral({
    required String referralId,
    required String memberId,
    required int currentLevel,
    String? reason,
  }) async {
    debugPrint('[ReferralApiService] escalateReferral disabled');
    return false;
  }

  Future<bool> addReferralNote({
    required String referralId,
    required String memberId,
    required String note,
    String? actor,
  }) async {
    debugPrint('[ReferralApiService] addReferralNote disabled');
    return false;
  }

  Future<List<Map<String, dynamic>>> fetchPrescriptions({
    required String patientId,
  }) async =>
      const [];

  Future<Map<String, dynamic>?> fetchFacility(int facilityId) async => null;

  Future<List<Map<String, dynamic>>> fetchReferralsByIds({
    required List<String> referralIds,
  }) async =>
      const [];

  Future<bool> createFollowUp({
    required String patientId,
    required String referralId,
    required DateTime dueAt,
    String? type,
    String? notes,
  }) async {
    debugPrint('[ReferralApiService] createFollowUp disabled');
    return false;
  }
}

/// Model for prescription/treatment details.
class Prescription {
  const Prescription({
    required this.id,
    this.medicationName,
    this.dosage,
    this.frequency,
    this.duration,
    this.prescribedAt,
    this.prescribedBy,
    this.instructions,
    this.isActive = true,
  });

  final String id;
  final String? medicationName;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final DateTime? prescribedAt;
  final String? prescribedBy;
  final String? instructions;
  final bool isActive;

  factory Prescription.fromJson(Map<String, dynamic> json) {
    return Prescription(
      id: (json['id'] ?? json['prescriptionId'] ?? '').toString(),
      medicationName: json['medicationName'] as String? ??
          json['medication'] as String? ??
          json['drugName'] as String?,
      dosage: json['dosage'] as String? ?? json['dose'] as String?,
      frequency: json['frequency'] as String? ??
          json['dosageFrequency'] as String?,
      duration: json['duration'] as String? ??
          json['prescribedDays']?.toString(),
      prescribedAt: _parseDate(json['prescribedAt'] ?? json['prescribedDate']),
      prescribedBy: json['prescribedBy'] as String? ??
          json['prescriberName'] as String?,
      instructions: json['instructions'] as String? ??
          json['remarks'] as String?,
      isActive: json['isActive'] as bool? ?? json['active'] as bool? ?? true,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// Model for facility information.
class Facility {
  const Facility({
    required this.id,
    this.name,
    this.phone,
    this.address,
    this.latitude,
    this.longitude,
    this.type,
  });

  final int id;
  final String? name;
  final String? phone;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? type;

  factory Facility.fromJson(Map<String, dynamic> json) {
    return Facility(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? json['facilityName'] as String?,
      phone: json['phone'] as String? ??
          json['phoneNumber'] as String? ??
          json['contactNumber'] as String?,
      address: json['address'] as String? ?? json['location'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ??
          (json['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ??
          (json['lng'] as num?)?.toDouble() ??
          (json['lon'] as num?)?.toDouble(),
      type: json['type'] as String? ?? json['facilityType'] as String?,
    );
  }
}

/// Model for referral note/comment.
class ReferralNote {
  const ReferralNote({
    required this.id,
    required this.referralId,
    required this.content,
    required this.createdAt,
    this.author,
    this.type,
  });

  final String id;
  final String referralId;
  final String content;
  final DateTime createdAt;
  final String? author;
  final String? type;

  factory ReferralNote.fromJson(Map<String, dynamic> json) {
    return ReferralNote(
      id: (json['id'] ?? '').toString(),
      referralId: (json['referralId'] ?? '').toString(),
      content: json['content'] as String? ??
          json['note'] as String? ??
          json['text'] as String? ??
          '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      author: json['author'] as String? ?? json['createdBy'] as String?,
      type: json['type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'referralId': referralId,
        'content': content,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (author != null) 'author': author,
        if (type != null) 'type': type,
      };
}
