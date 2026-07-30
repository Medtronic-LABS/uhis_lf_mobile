import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/debug/console_log.dart';
import '../../core/models/referral.dart';

/// Referral API service.
///
/// [fetchReferrals] calls POST /spice-service/patient/referral-tickets to
/// retrieve live referral ticket status — including nurse medical review
/// outcome (patientStatus: "Controlled" | "Uncontrolled") set by
/// NurseMedicalReviewActivity in Spice Android.
///
/// Mutating endpoints (create/update/escalate) remain disabled — those
/// actions go through the offline-sync bundle.
class ReferralApiService extends ApiRepository {
  ReferralApiService(super.api);

  /// Fetch referral tickets for [patientId] from the spice-service.
  ///
  /// Called on patient context screen load so the SK sees the latest
  /// nurse-review outcome without waiting for the next full sync.
  ///
  /// Returns empty list on any error — caller degrades to SQLite snapshot.
  ///
  /// DEBUG: logs full request body and response status via [ConsoleLog].
  Future<List<Map<String, dynamic>>> fetchReferrals({
    required String patientId,
    String? memberId,
    String? ticketId,
    String? type,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId,
      if (memberId != null) 'memberId': memberId,
      if (ticketId != null) 'ticketId': ticketId,
      if (type != null) 'type': type,
    };

    // DEBUG: log full request before POST so payload can be diffed against
    // the Spice Android reference without a proxy.
    ConsoleLog.banner('[PayloadDebug] referral-ticket-fetch: ${body.toString()}');

    try {
      final response = await postOk(
        Endpoints.referralTicketDetails,
        data: body,
        action: 'fetchReferralTickets',
      );

      ConsoleLog.step(
        '[PayloadDebug] referral-ticket-fetch → response type: ${response.runtimeType}',
      );

      final list = extractList(response);
      final tickets = list.whereType<Map<String, dynamic>>().toList(growable: false);

      // DEBUG: log count and first ticket for quick field inspection.
      ConsoleLog.step(
        '[ReferralApiService] fetchReferrals patientId=$patientId → ${tickets.length} ticket(s)',
      );
      if (tickets.isNotEmpty) {
        ConsoleLog.step('[ReferralApiService] first ticket: ${tickets.first}');
      }

      return tickets;
    } on ApiException catch (e) {
      ConsoleLog.warn('[ReferralApiService] fetchReferrals ApiException: $e');
      return const [];
    } catch (e) {
      ConsoleLog.warn('[ReferralApiService] fetchReferrals unexpected error: $e');
      return const [];
    }
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
    ConsoleLog.step('[ReferralApiService] createReferral disabled');
    return null;
  }

  Future<bool> updateReferralStatus({
    required String referralId,
    required String memberId,
    required ReferralStatus status,
    String? reason,
    String? actor,
  }) async {
    ConsoleLog.step('[ReferralApiService] updateReferralStatus disabled');
    return false;
  }

  Future<bool> escalateReferral({
    required String referralId,
    required String memberId,
    required int currentLevel,
    String? reason,
  }) async {
    ConsoleLog.step('[ReferralApiService] escalateReferral disabled');
    return false;
  }

  Future<bool> addReferralNote({
    required String referralId,
    required String memberId,
    required String note,
    String? actor,
  }) async {
    ConsoleLog.step('[ReferralApiService] addReferralNote disabled');
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
    ConsoleLog.step('[ReferralApiService] createFollowUp disabled');
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
