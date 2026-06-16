import '../../core/api/api_repository.dart';
import '../../core/db/follow_up_dao.dart';
import '../../core/db/immunisation_dao.dart';
import '../../core/db/member_dao.dart';

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
/// All reads from local SQLite populated during offline sync.
class HouseholdRepository extends ApiRepository {
  HouseholdRepository(super.api, {
    MemberDao? members,
    FollowUpDao? followUps,
    ImmunisationDao? immunisations,
  })  : _members = members,
        _followUps = followUps,
        _immunisations = immunisations;

  final MemberDao? _members;
  final FollowUpDao? _followUps;
  final ImmunisationDao? _immunisations;

  /// Get care flags for other members in the same household.
  /// Reads entirely from local SQLite — no API calls.
  Future<List<HouseholdMemberFlag>> coFlagsFor(
    String patientId, {
    String? householdId,
  }) async {
    final memberFlags = <HouseholdMemberFlag>[];
    if (householdId == null || householdId.isEmpty) return memberFlags;
    if (_members == null) return memberFlags;

    final members = await _members!.getByHouseholdId(householdId);
    final now = DateTime.now();

    for (final m in members) {
      // Skip the current patient
      if (m.id == patientId || m.patientId == patientId) continue;
      if (!m.isActive) continue;

      final flags = <CareFlag>[];
      final memberPatientId = m.patientId ?? m.id;

      // Check open follow-ups from local DB
      if (_followUps != null) {
        try {
          final fus = await _followUps!.forPatient(memberPatientId);
          for (final fu in fus) {
            if (fu.completedAt != null) continue;
            if (fu.dueAt == null) continue;
            final due = DateTime.fromMillisecondsSinceEpoch(fu.dueAt!);
            if (due.isBefore(now)) {
              flags.add(CareFlag(
                type: CareFlagType.overdueFollowUp,
                label: 'Follow-up overdue',
                dueDate: due,
              ));
              break;
            }
          }
        } catch (_) {}
      }

      // Check overdue immunisations for children under 5
      final dob = m.dob != null ? DateTime.tryParse(m.dob!) : null;
      final ageYears = dob != null ? now.year - dob.year : null;
      if (ageYears != null && ageYears < 5 && _immunisations != null) {
        try {
          final immMap = await _immunisations!.forMany([memberPatientId]);
          final imms = immMap[memberPatientId] ?? [];
          for (final imm in imms) {
            if (imm.givenAt == null) {
              flags.add(CareFlag(
                type: CareFlagType.overdueImmunisation,
                label: 'Immunisation due',
              ));
              break;
            }
          }
        } catch (_) {}
      }

      if (flags.isNotEmpty) {
        memberFlags.add(HouseholdMemberFlag(
          memberId: m.id,
          name: m.name ?? 'Unknown',
          relationship: m.relation,
          age: ageYears,
          gender: m.gender,
          flags: flags,
        ));
      }
    }

    return memberFlags;
  }
}
