import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/models/referral.dart';

/// API service for referral-related backend operations.
/// Handles communication with spice-service and fhir-mapper-service endpoints.
class ReferralApiService extends ApiRepository {
  ReferralApiService(super.api);

  /// Fetch referral tickets for a patient from the server.
  /// Returns list of referral data from fhir-mapper-service.
  Future<List<Map<String, dynamic>>> fetchReferrals({
    required String patientId,
    int? limit,
    int? offset,
  }) async {
    try {
      final body = await postOk(
        Endpoints.fhirReferralTicketList,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
          if (limit != null) 'limit': limit,
          if (offset != null) 'offset': offset,
        },
        action: 'Fetch referrals',
      );
      return List<Map<String, dynamic>>.from(extractList(body));
    } catch (e) {
      debugPrint('[ReferralApiService] fetchReferrals error: $e');
      return [];
    }
  }

  /// Create a new referral ticket via fhir-mapper-service.
  Future<String?> createReferral({
    required String patientId,
    required String memberId,
    required String referredReason,
    required String referredTo,
    String? referredBy,
    SlaTier? slaTier,
    String? notes,
  }) async {
    try {
      final body = await postOk(
        Endpoints.fhirReferralTicketCreate,
        data: {
          'patientId': patientId,
          'memberId': memberId,
          'referredReason': referredReason,
          'referredTo': referredTo,
          'referredBy': referredBy ?? 'SK',
          'tenantId': api.tenantIdAsNum,
          if (slaTier != null) 'slaTier': slaTier.wireTag,
          if (notes != null) 'notes': notes,
        },
        action: 'Create referral',
      );
      if (body is Map) {
        return body['id']?.toString() ?? body['referralId']?.toString();
      }
      return null;
    } catch (e) {
      debugPrint('[ReferralApiService] createReferral error: $e');
      rethrow;
    }
  }

  /// Update a referral ticket status via fhir-mapper-service.
  Future<bool> updateReferralStatus({
    required String referralId,
    required String memberId,
    required ReferralStatus status,
    String? reason,
    String? actor,
  }) async {
    try {
      await postOk(
        Endpoints.fhirReferralTicketUpdate,
        data: {
          'referralId': referralId,
          'memberId': memberId,
          'patientStatus': _statusToWireTag(status),
          'tenantId': api.tenantIdAsNum,
          if (reason != null) 'reason': reason,
          if (actor != null) 'updatedBy': actor,
        },
        action: 'Update referral status',
      );
      return true;
    } catch (e) {
      debugPrint('[ReferralApiService] updateReferralStatus error: $e');
      return false;
    }
  }

  /// Escalate a referral to the next level.
  Future<bool> escalateReferral({
    required String referralId,
    required String memberId,
    required int currentLevel,
    String? reason,
  }) async {
    try {
      // Map escalation level to supervisor endpoint
      final nextLevel = currentLevel + 1;
      await postOk(
        Endpoints.fhirReferralTicketUpdate,
        data: {
          'referralId': referralId,
          'memberId': memberId,
          'escalationLevel': nextLevel,
          'escalationReason': reason ?? 'SLA breach - escalated by SK',
          'tenantId': api.tenantIdAsNum,
        },
        action: 'Escalate referral',
      );
      return true;
    } catch (e) {
      debugPrint('[ReferralApiService] escalateReferral error: $e');
      return false;
    }
  }

  /// Add a note/comment to a referral.
  Future<bool> addReferralNote({
    required String referralId,
    required String memberId,
    required String note,
    String? actor,
  }) async {
    try {
      await postOk(
        Endpoints.fhirReferralTicketUpdate,
        data: {
          'referralId': referralId,
          'memberId': memberId,
          'notes': note,
          'tenantId': api.tenantIdAsNum,
          if (actor != null) 'updatedBy': actor,
        },
        action: 'Add referral note',
      );
      return true;
    } catch (e) {
      debugPrint('[ReferralApiService] addReferralNote error: $e');
      return false;
    }
  }

  /// Fetch prescription/treatment details for a patient.
  Future<List<Map<String, dynamic>>> fetchPrescriptions({
    required String patientId,
  }) async {
    try {
      final body = await postOk(
        Endpoints.prescriptionPrescribedDetails,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'Fetch prescriptions',
      );
      final list = extractList(body);
      return List<Map<String, dynamic>>.from(list);
    } catch (e) {
      debugPrint('[ReferralApiService] fetchPrescriptions error: $e');
      return [];
    }
  }

  /// Fetch facility details by ID.
  Future<Map<String, dynamic>?> fetchFacility(int facilityId) async {
    try {
      final body = await getOk(
        '/admin-service/facility/$facilityId',
        action: 'Fetch facility',
      );
      if (body is Map<String, dynamic>) return body;
      if (body is Map && body['entity'] is Map) {
        return Map<String, dynamic>.from(body['entity'] as Map);
      }
      return null;
    } catch (e) {
      debugPrint('[ReferralApiService] fetchFacility error: $e');
      return null;
    }
  }

  /// Bulk fetch multiple referrals by IDs.
  Future<List<Map<String, dynamic>>> fetchReferralsByIds({
    required List<String> referralIds,
  }) async {
    try {
      final body = await postOk(
        Endpoints.fhirReferralTicketList,
        data: {
          'referralIds': referralIds,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'Fetch referrals by IDs',
      );
      return List<Map<String, dynamic>>.from(extractList(body));
    } catch (e) {
      debugPrint('[ReferralApiService] fetchReferralsByIds error: $e');
      return [];
    }
  }

  /// Create a follow-up for a referral.
  Future<bool> createFollowUp({
    required String patientId,
    required String referralId,
    required DateTime dueAt,
    String? type,
    String? notes,
  }) async {
    try {
      // Use the follow-up endpoint to schedule
      await postOk(
        '/spice-service/follow-up/create',
        data: {
          'patientId': patientId,
          'referralId': referralId,
          'dueAt': dueAt.millisecondsSinceEpoch,
          'type': type ?? 'referral_follow_up',
          'tenantId': api.tenantIdAsNum,
          if (notes != null) 'notes': notes,
        },
        action: 'Create follow-up',
      );
      return true;
    } catch (e) {
      debugPrint('[ReferralApiService] createFollowUp error: $e');
      return false;
    }
  }

  /// Map device-side status to server wire tag.
  String _statusToWireTag(ReferralStatus status) {
    switch (status) {
      case ReferralStatus.created:
        return 'Referred';
      case ReferralStatus.treatmentStarted:
      case ReferralStatus.arrived:
      case ReferralStatus.inTransit:
      case ReferralStatus.acknowledged:
        return 'OnTreatment';
      case ReferralStatus.closedRecovered:
        return 'Recovered';
      case ReferralStatus.closedDeceased:
        return 'Died';
      default:
        return status.wireTag;
    }
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
