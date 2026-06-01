import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';

/// Type of follow-up.
enum FollowUpType {
  screening,
  medicalReview,
  assessment,
  lost,
  other,
}

/// A follow-up task for a patient.
class FollowUp {
  const FollowUp({
    required this.id,
    required this.patientId,
    required this.type,
    required this.dueDate,
    this.completedAt,
    this.attempts = 0,
    this.isLost = false,
    this.reason,
    this.programme,
    this.rawJson = const {},
  });

  final String id;
  final String patientId;
  final FollowUpType type;
  final DateTime dueDate;
  final DateTime? completedAt;
  final int attempts;
  final bool isLost;
  final String? reason;
  final String? programme;
  final Map<String, dynamic> rawJson;

  bool get isOpen => completedAt == null && !isLost;
  bool get isOverdue => isOpen && dueDate.isBefore(DateTime.now());

  static FollowUp? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final patientId = json['patientId']?.toString() ?? 
                      json['memberId']?.toString();
    if (id == null || patientId == null) return null;

    // Parse due date
    DateTime? dueDate;
    final dueDateVal = json['nextFollowUpDate'] ?? 
                       json['dueDate'] ?? 
                       json['scheduledDate'];
    if (dueDateVal is String) {
      dueDate = DateTime.tryParse(dueDateVal);
    } else if (dueDateVal is int) {
      dueDate = DateTime.fromMillisecondsSinceEpoch(dueDateVal);
    }
    dueDate ??= DateTime.now();

    // Parse completed date
    DateTime? completedAt;
    final completedVal = json['completedAt'] ?? json['completedDate'];
    if (completedVal is String) {
      completedAt = DateTime.tryParse(completedVal);
    } else if (completedVal is int) {
      completedAt = DateTime.fromMillisecondsSinceEpoch(completedVal);
    }

    // Parse type
    final typeStr = json['type']?.toString()?.toLowerCase() ?? 
                    json['followUpType']?.toString()?.toLowerCase() ?? '';
    FollowUpType type;
    if (typeStr.contains('screening')) {
      type = FollowUpType.screening;
    } else if (typeStr.contains('medical') || typeStr.contains('review')) {
      type = FollowUpType.medicalReview;
    } else if (typeStr.contains('assessment')) {
      type = FollowUpType.assessment;
    } else if (typeStr.contains('lost')) {
      type = FollowUpType.lost;
    } else {
      type = FollowUpType.other;
    }

    return FollowUp(
      id: id,
      patientId: patientId,
      type: type,
      dueDate: dueDate,
      completedAt: completedAt,
      attempts: json['attempts'] is int ? json['attempts'] : 0,
      isLost: json['isLostToFollowUp'] == true || json['isLost'] == true,
      reason: json['reason']?.toString() ?? json['referralReason']?.toString(),
      programme: json['programme']?.toString() ?? json['programType']?.toString(),
      rawJson: json,
    );
  }
}

/// Repository for fetching follow-up data.
class FollowUpRepository extends ApiRepository {
  FollowUpRepository(super.api);

  /// Get open follow-ups for a patient.
  Future<List<FollowUp>> openForPatient(String patientId) async {
    final followUps = <FollowUp>[];

    try {
      final body = await postOk(
        Endpoints.followUpList,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
          'isCompleted': false,
        },
        action: 'Open follow-ups',
      );

      final list = extractList(body);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final fu = FollowUp.fromJson(item);
          if (fu != null && fu.isOpen) {
            followUps.add(fu);
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[FollowUpRepository] Failed to fetch follow-ups: $e');
    }

    // Sort by due date ascending (most urgent first)
    followUps.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return followUps;
  }

  /// Get all follow-ups for a patient (open and closed).
  Future<List<FollowUp>> allForPatient(String patientId) async {
    final followUps = <FollowUp>[];

    try {
      final body = await postOk(
        Endpoints.followUpList,
        data: {
          'patientId': patientId,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'All follow-ups',
      );

      final list = extractList(body);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final fu = FollowUp.fromJson(item);
          if (fu != null) followUps.add(fu);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[FollowUpRepository] Failed to fetch follow-ups: $e');
    }

    // Sort by due date descending (most recent first)
    followUps.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return followUps;
  }

  /// Get overdue follow-ups for a patient.
  Future<List<FollowUp>> overdueForPatient(String patientId) async {
    final all = await openForPatient(patientId);
    return all.where((fu) => fu.isOverdue).toList();
  }

  /// Get lost-to-follow-up patients in a village.
  Future<List<FollowUp>> lostInVillage(List<int> villageIds) async {
    final followUps = <FollowUp>[];

    try {
      final body = await postOk(
        Endpoints.followUpOfflineLost,
        data: {
          'villageIds': villageIds,
          'tenantId': api.tenantIdAsNum,
        },
        action: 'Lost to follow-up',
      );

      final list = extractList(body);
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final fu = FollowUp.fromJson(item);
          if (fu != null) followUps.add(fu);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[FollowUpRepository] Failed to fetch lost follow-ups: $e');
    }

    return followUps;
  }
}
