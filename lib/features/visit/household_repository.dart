import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';

/// A household member with flags indicating care needs.
class HouseholdMemberFlag {
  const HouseholdMemberFlag({
    required this.memberId,
    required this.name,
    this.relationship,
    this.age,
    this.gender,
    required this.flags,
  });

  final String memberId;
  final String name;
  final String? relationship;
  final int? age;
  final String? gender;
  final List<CareFlag> flags;

  bool get hasFlags => flags.isNotEmpty;
}

/// Type of care flag for a household member.
enum CareFlagType {
  overdueFollowUp,
  overdueImmunisation,
  activeEnrolment,
  referralPending,
  highRisk,
}

/// A care flag indicating a member needs attention.
class CareFlag {
  const CareFlag({
    required this.type,
    required this.label,
    this.dueDate,
    this.programme,
  });

  final CareFlagType type;
  final String label;
  final DateTime? dueDate;
  final String? programme;

  String get displayLabel {
    if (dueDate != null) {
      final days = dueDate!.difference(DateTime.now()).inDays;
      if (days < 0) {
        return '$label (${-days} days overdue)';
      } else if (days == 0) {
        return '$label (today)';
      } else {
        return '$label (in $days days)';
      }
    }
    return label;
  }
}

/// Repository for household-level data including co-flags.
class HouseholdRepository extends ApiRepository {
  HouseholdRepository(super.api);

  /// Get care flags for other members in the same household.
  /// 
  /// This is used on the Visit Landing screen to show "Also in this household"
  /// section with relevant flags for follow-ups, immunisations, etc.
  Future<List<HouseholdMemberFlag>> coFlagsFor(
    String patientId, {
    String? householdId,
  }) async {
    final memberFlags = <HouseholdMemberFlag>[];

    if (householdId == null || householdId.isEmpty) {
      return memberFlags;
    }

    try {
      // 1. Get household members
      final householdBody = await getOk(
        Endpoints.householdById(householdId),
        action: 'Household details',
      );

      final entity = householdBody['entity'] as Map<String, dynamic>?;
      if (entity == null) return memberFlags;

      final members = entity['householdMembers'] as List<dynamic>? ?? [];

      // 2. Get follow-ups for each member (excluding current patient)
      for (final member in members) {
        if (member is! Map<String, dynamic>) continue;

        final memberId = member['id']?.toString();
        final memberPatientId = member['patientId']?.toString();
        
        // Skip the current patient
        if (memberId == patientId || memberPatientId == patientId) continue;

        final name = member['name']?.toString() ?? 
                     member['firstName']?.toString() ?? 
                     'Unknown';
        final relationship = member['relationship']?.toString();
        final gender = member['gender']?.toString();
        
        int? age;
        final ageVal = member['age'];
        if (ageVal is int) {
          age = ageVal;
        } else if (ageVal is num) {
          age = ageVal.toInt();
        }

        final flags = <CareFlag>[];

        // Check for open follow-ups
        try {
          if (memberPatientId != null) {
            final fuBody = await postOk(
              Endpoints.followUpList,
              data: {
                'patientId': memberPatientId,
                'tenantId': api.tenantIdAsNum,
                'isCompleted': false,
              },
              action: 'Member follow-ups',
            );
            final fuList = extractList(fuBody);
            for (final fu in fuList) {
              if (fu is Map<String, dynamic>) {
                DateTime? dueDate;
                final dueDateVal = fu['nextFollowUpDate'] ?? fu['dueDate'];
                if (dueDateVal is String) {
                  dueDate = DateTime.tryParse(dueDateVal);
                } else if (dueDateVal is int) {
                  dueDate = DateTime.fromMillisecondsSinceEpoch(dueDateVal);
                }
                
                final isOverdue = dueDate?.isBefore(DateTime.now()) ?? false;
                if (isOverdue) {
                  flags.add(CareFlag(
                    type: CareFlagType.overdueFollowUp,
                    label: 'Follow-up overdue',
                    dueDate: dueDate,
                    programme: fu['programme']?.toString(),
                  ));
                }
              }
            }
          }
        } catch (_) {}

        // Check for overdue immunisations (for children)
        if (age != null && age < 5) {
          try {
            final immunBody = await postOk(
              Endpoints.immunisationList,
              data: {
                'patientId': memberPatientId ?? memberId,
                'tenantId': api.tenantIdAsNum,
              },
              action: 'Member immunisations',
            );
            final immunList = extractList(immunBody);
            for (final immun in immunList) {
              if (immun is Map<String, dynamic>) {
                final givenAt = immun['givenAt'] ?? immun['administeredDate'];
                if (givenAt == null) {
                  DateTime? dueDate;
                  final dueDateVal = immun['dueAt'] ?? immun['dueDate'];
                  if (dueDateVal is String) {
                    dueDate = DateTime.tryParse(dueDateVal);
                  } else if (dueDateVal is int) {
                    dueDate = DateTime.fromMillisecondsSinceEpoch(dueDateVal);
                  }
                  
                  final isOverdue = dueDate?.isBefore(DateTime.now()) ?? false;
                  if (isOverdue) {
                    final vaccine = immun['vaccineName']?.toString() ?? 
                                   immun['vaccineCode']?.toString() ?? 
                                   'Immunisation';
                    flags.add(CareFlag(
                      type: CareFlagType.overdueImmunisation,
                      label: '$vaccine overdue',
                      dueDate: dueDate,
                    ));
                    break; // Only show first overdue immunisation
                  }
                }
              }
            }
          } catch (_) {}
        }

        // Only add member if they have flags
        if (flags.isNotEmpty) {
          memberFlags.add(HouseholdMemberFlag(
            memberId: memberId ?? '',
            name: name,
            relationship: relationship,
            age: age,
            gender: gender,
            flags: flags,
          ));
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[HouseholdRepository] Failed to fetch co-flags: $e');
    }

    return memberFlags;
  }
}
