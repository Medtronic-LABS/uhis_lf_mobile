import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/auth/user_hierarchy_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../dashboard/dashboard_repository.dart';

/// Full details of a household member for display.
class HouseholdMemberData {
  HouseholdMemberData({
    this.id,
    this.patientId,
    this.name,
    this.relation,
    this.age,
    this.gender,
    this.phoneNumber,
    this.dateOfBirth,
    this.isHead = false,
    this.isPregnant = false,
    this.householdId,
    this.villageId,
    this.recentService,
    this.recentServiceAt,
  });

  final String? id;
  final String? patientId;
  final String? name;
  final String? relation;
  final int? age;
  final String? gender;
  final String? phoneNumber;
  final String? dateOfBirth;
  final bool isHead;
  final bool isPregnant;
  final String? householdId;
  final String? villageId;
  final String? recentService;
  final DateTime? recentServiceAt;

  static HouseholdMemberData fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? age;
    final ageVal = json['age'];
    if (ageVal is int) {
      age = ageVal;
    } else if (ageVal is num) {
      age = ageVal.toInt();
    } else if (ageVal is String) {
      age = int.tryParse(ageVal);
    }

    // Calculate age from dateOfBirth if not directly available
    if (age == null) {
      final dobStr = str('dateOfBirth');
      if (dobStr != null) {
        try {
          final dob = DateTime.parse(dobStr);
          final now = DateTime.now();
          age = now.year - dob.year;
          if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
            age = age - 1;
          }
        } catch (_) {}
      }
    }

    // Parse householdHeadRelationship (API field name) or relation
    final relation = str('householdHeadRelationship') ?? str('relation');
    final relationLower = relation?.toLowerCase();
    final isHead = relationLower == 'head' ||
        relationLower == 'self' ||
        relationLower == 'household head' ||
        relationLower == 'householdhead' ||
        json['isHouseholdHead'] == true;

    final isPregnant = json['isPregnant'] == true;

    return HouseholdMemberData(
      id: str('id'),
      patientId: str('patientId'),
      name: str('name') ?? str('firstName'),
      relation: relation,
      age: age,
      gender: str('gender'),
      phoneNumber: str('phoneNumber') ?? str('phone'),
      dateOfBirth: str('dateOfBirth'),
      isHead: isHead,
      isPregnant: isPregnant,
      householdId: str('householdId'),
      villageId: str('villageId'),
    );
  }

  HouseholdMemberData withService({
    required String? recentService,
    required DateTime? recentServiceAt,
  }) =>
      HouseholdMemberData(
        id: id,
        patientId: patientId,
        name: name,
        relation: relation,
        age: age,
        gender: gender,
        phoneNumber: phoneNumber,
        dateOfBirth: dateOfBirth,
        isHead: isHead,
        isPregnant: isPregnant,
        householdId: householdId,
        villageId: villageId,
        recentService: recentService,
        recentServiceAt: recentServiceAt,
      );

  /// Creates from local SQLite HouseholdMemberEntity.
  static HouseholdMemberData fromEntity(HouseholdMemberEntity e) {
    int? age;
    if (e.dob != null && e.dob!.isNotEmpty) {
      try {
        final dob = DateTime.parse(e.dob!);
        final now = DateTime.now();
        age = now.year - dob.year;
        if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
          age = age - 1;
        }
      } catch (_) {}
    }
    return HouseholdMemberData(
      id: e.id,
      patientId: e.patientId,
      name: e.name,
      relation: e.relation,
      age: age,
      gender: e.gender,
      phoneNumber: e.phone,
      dateOfBirth: e.dob,
      isHead: e.isHouseholdHead,
      isPregnant: e.isPregnant,
      householdId: e.householdId,
      villageId: e.villageId,
    );
  }
}

/// Full household data for the detail screen.
class HouseholdDetailData {
  HouseholdDetailData({
    this.id,
    this.name,
    this.householdNo,
    this.village,
    this.subVillage,
    this.memberCount,
    this.latitude,
    this.longitude,
    this.members = const [],
    this.ssName,
    this.lastVisitAt,
  });

  final String? id;
  final String? name;
  final String? householdNo;
  final String? village;
  final String? subVillage;
  final int? memberCount;
  final double? latitude;
  final double? longitude;
  final List<HouseholdMemberData> members;
  final String? ssName;
  final DateTime? lastVisitAt;

  HouseholdMemberData? get head => members.where((m) => m.isHead).firstOrNull;

  static HouseholdDetailData fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? memberCount;
    final countVal = json['noOfPeople'];
    if (countVal is int) {
      memberCount = countVal;
    } else if (countVal is num) {
      memberCount = countVal.toInt();
    } else if (countVal is String) {
      memberCount = int.tryParse(countVal);
    }

    double? lat, lng;
    final latVal = json['latitude'];
    final lngVal = json['longitude'];
    if (latVal is double) lat = latVal;
    else if (latVal is num) lat = latVal.toDouble();
    if (lngVal is double) lng = lngVal;
    else if (lngVal is num) lng = lngVal.toDouble();

    final memberList = <HouseholdMemberData>[];
    if (json['householdMembers'] is List) {
      for (final m in json['householdMembers']) {
        if (m is Map<String, dynamic>) {
          memberList.add(HouseholdMemberData.fromJson(m));
        } else if (m is Map) {
          memberList.add(
              HouseholdMemberData.fromJson(Map<String, dynamic>.from(m)));
        }
      }
    }

    return HouseholdDetailData(
      id: str('id'),
      name: str('name'),
      householdNo: str('householdNo'),
      village: str('village'),
      subVillage: str('subVillage'),
      memberCount: memberCount ?? memberList.length,
      latitude: lat,
      longitude: lng,
      members: memberList,
    );
  }
}

class HouseholdDetailScreen extends StatefulWidget {
  const HouseholdDetailScreen({
    super.key,
    required this.household,
  });

  final HouseholdDetailData household;

  @override
  State<HouseholdDetailScreen> createState() => _HouseholdDetailScreenState();
}

class _HouseholdDetailScreenState extends State<HouseholdDetailScreen> {
  late HouseholdDetailData _household;
  bool _loadingMembers = false;
  String? _loadError;

  /// Derives household name from head's name (same logic as household_list_screen).
  /// Returns: "HeadName's Household" or "Household #ID" or existing name.
  String? _deriveHouseholdName({
    required String? existingName,
    required List<HouseholdMemberData> members,
    required String householdId,
  }) {
    // If we already have a valid name, keep it
    if (existingName != null && existingName.isNotEmpty) {
      return existingName;
    }
    
    // Find household head
    final head = members.firstWhere(
      (m) => m.isHead,
      orElse: () => members.isNotEmpty ? members.first : HouseholdMemberData(),
    );
    
    // Use head's name to derive household name
    if (head.name != null && head.name!.isNotEmpty) {
      return "${head.name}'s Household";
    }
    
    // Fallback to "Household #ID"
    if (householdId.isNotEmpty) {
      return 'Household #$householdId';
    }
    
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Derive household name from head if not available
    final derivedName = _deriveHouseholdName(
      existingName: widget.household.name,
      members: widget.household.members,
      householdId: widget.household.id ?? '',
    );
    _household = HouseholdDetailData(
      id: widget.household.id,
      name: derivedName,
      householdNo: widget.household.householdNo,
      village: widget.household.village,
      subVillage: widget.household.subVillage,
      memberCount: widget.household.memberCount,
      latitude: widget.household.latitude,
      longitude: widget.household.longitude,
      members: widget.household.members,
    );
    // Auto-fetch members if not provided (defer to avoid setState in initState)
    if (_household.members.isEmpty && _household.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchMembers();
      });
    }
  }

  Future<void> _fetchMembers() async {
    if (_loadingMembers) return;
    setState(() {
      _loadingMembers = true;
      _loadError = null;
    });

    final householdId = _household.id;
    if (householdId == null) {
      setState(() {
        _loadError = 'Household ID not available';
        _loadingMembers = false;
      });
      return;
    }

    try {
      final memberDao = context.read<MemberDao>();
      final assessmentDao = context.read<AssessmentDao>();
      final patientDao = context.read<PatientDao>();
      final hierarchy = context.read<UserHierarchyService>();
      await hierarchy.prefetch();

      final localMembers = await memberDao.getByHouseholdId(householdId);

      if (localMembers.isNotEmpty && mounted) {
        final base = localMembers.map(HouseholdMemberData.fromEntity).toList();
        final enriched = await _enrichMembers(base, assessmentDao, patientDao);
        final ssName = _resolveSsName(
            localMembers.first.shasthyaShebikaId, hierarchy);
        final lastVisitAt = _householdLastVisit(enriched);
        final derivedName = _deriveHouseholdName(
          existingName: _household.name,
          members: enriched,
          householdId: householdId,
        );
        if (!mounted) return;
        setState(() {
          _household = HouseholdDetailData(
            id: _household.id,
            name: derivedName,
            householdNo: _household.householdNo,
            village: _household.village,
            subVillage: _household.subVillage,
            memberCount: enriched.length,
            latitude: _household.latitude,
            longitude: _household.longitude,
            members: enriched,
            ssName: ssName,
            lastVisitAt: lastVisitAt,
          );
          _loadingMembers = false;
        });
        return;
      }

      // Fall back to API only if local cache is empty
      final repo = context.read<DashboardRepository>();
      final householdData = await repo.getHouseholdById(householdId);

      if (householdData != null && mounted) {
        final updated = HouseholdDetailData.fromJson(householdData);
        final enriched =
            await _enrichMembers(updated.members, assessmentDao, patientDao);
        final ssName = enriched.isNotEmpty
            ? _resolveSsName(
                localMembers.firstOrNull?.shasthyaShebikaId, hierarchy)
            : null;
        final lastVisitAt = _householdLastVisit(enriched);
        final derivedName = _deriveHouseholdName(
          existingName: updated.name,
          members: enriched,
          householdId: householdId,
        );
        if (!mounted) return;
        setState(() {
          _household = HouseholdDetailData(
            id: updated.id,
            name: derivedName,
            householdNo: updated.householdNo,
            village: updated.village,
            subVillage: updated.subVillage,
            memberCount: updated.memberCount,
            latitude: updated.latitude,
            longitude: updated.longitude,
            members: enriched,
            ssName: ssName,
            lastVisitAt: lastVisitAt,
          );
          _loadingMembers = false;
        });
      } else if (mounted) {
        setState(() {
          _loadError = 'No members found';
          _loadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loadingMembers = false;
        });
      }
    }
  }

  /// Enriches members with most-recent assessment kind + date from local DB.
  Future<List<HouseholdMemberData>> _enrichMembers(
    List<HouseholdMemberData> members,
    AssessmentDao assessmentDao,
    PatientDao patientDao,
  ) async {
    final patientIds =
        members.map((m) => m.patientId).whereType<String>().toList();
    if (patientIds.isEmpty) return members;

    final assessments = await assessmentDao.forMany(patientIds);
    final lastVisits = await patientDao.lastVisitAtForPatients(patientIds);

    return members.map((m) {
      final pid = m.patientId;
      if (pid == null) return m;
      final latestAssessment = assessments[pid]?.first;
      final lastVisitMs = lastVisits[pid];
      final serviceAt = latestAssessment?.occurredAt != null
          ? DateTime.fromMillisecondsSinceEpoch(latestAssessment!.occurredAt!)
          : (lastVisitMs != null
              ? DateTime.fromMillisecondsSinceEpoch(lastVisitMs)
              : null);
      return m.withService(
        recentService: latestAssessment?.kind,
        recentServiceAt: serviceAt,
      );
    }).toList();
  }

  String? _resolveSsName(String? shebikaId, UserHierarchyService hierarchy) {
    if (shebikaId == null) return null;
    return hierarchy.ssWorkers
        ?.where((ss) => ss.id == shebikaId)
        .firstOrNull
        ?.name;
  }

  DateTime? _householdLastVisit(List<HouseholdMemberData> members) {
    DateTime? latest;
    for (final m in members) {
      final d = m.recentServiceAt;
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest;
  }

  HouseholdDetailData get household => _household;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(household.name ?? HouseholdDetailStrings.unnamedHousehold),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Household info card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.tag_outlined,
                    label: HouseholdDetailStrings.householdNumber,
                    value: household.householdNo ??
                        HouseholdDetailStrings.notAvailable,
                    color: scheme.primary,
                  ),
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: HouseholdDetailStrings.village,
                    value: household.village ??
                        HouseholdDetailStrings.notAvailable,
                    color: scheme.secondary,
                  ),
                  _InfoRow(
                    icon: Icons.person_pin_outlined,
                    label: HouseholdDetailStrings.ssName,
                    value: household.ssName ??
                        HouseholdDetailStrings.noSsAssigned,
                    color: scheme.tertiary,
                  ),
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: HouseholdDetailStrings.lastVisitDate,
                    value: household.lastVisitAt != null
                        ? DateFormat('d MMM yyyy').format(household.lastVisitAt!)
                        : HouseholdDetailStrings.neverVisited,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Members section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    HouseholdDetailStrings.householdMembers,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${household.memberCount ?? household.members.length}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            if (_loadingMembers)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      'Loading members…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                  ],
                ),
              )
            else if (_loadError != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.error.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: scheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load members',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _fetchMembers,
                      child: const Text(CommonStrings.retry),
                    ),
                  ],
                ),
              )
            else if (household.members.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 48,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      household.memberCount != null && household.memberCount! > 0
                          ? HouseholdDetailStrings.memberDataNotLoaded(
                              household.memberCount!)
                          : HouseholdDetailStrings.noMembers,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                    if (household.id != null) ...[
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _fetchMembers,
                        child: const Text('Load members'),
                      ),
                    ],
                  ],
                ),
              )
            else
              ...() {
                // Use all members but cap to memberCount if available to avoid data inconsistencies
                final allMembers = household.members.toList();
                final actualMemberCount = household.memberCount ?? allMembers.length;
                final cappedMembers = allMembers.length > actualMemberCount 
                    ? allMembers.take(actualMemberCount).toList() 
                    : allMembers;
                return [
                  ...cappedMembers.map((m) => _MemberCard(
                    member: m,
                    onTap: () => _showMemberDetail(context, m),
                  )),
                ];
              }(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showMemberDetail(BuildContext context, HouseholdMemberData member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MemberDetailSheet(
        member: member,
        household: household,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    this.onTap,
  });

  final HouseholdMemberData member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Age · Gender summary line
    final ageParts = <String>[
      if (member.age != null) '${member.age} yrs',
      if (member.gender != null) member.gender!,
    ];

    final serviceDate = member.recentServiceAt != null
        ? DateFormat('d MMM yyyy').format(member.recentServiceAt!)
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    color: scheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name ?? HouseholdDetailStrings.unnamed,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (ageParts.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          ageParts.join(' · '),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (member.recentService != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${HouseholdDetailStrings.recentService}: ${member.recentService!}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (serviceDate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${HouseholdDetailStrings.recentServiceDate}: $serviceDate',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (member.patientId != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${HouseholdDetailStrings.patientId}: ${member.patientId!}',
                          style: TextStyle(
                            color: scheme.outline,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberDetailSheet extends StatelessWidget {
  const _MemberDetailSheet({
    required this.member,
    required this.household,
  });

  final HouseholdMemberData member;
  final HouseholdDetailData household;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Member header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: member.isHead
                      ? scheme.primaryContainer
                      : scheme.secondaryContainer,
                  child: Icon(
                    member.isHead ? Icons.star : Icons.person,
                    size: 32,
                    color: member.isHead
                        ? scheme.onPrimaryContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name ?? HouseholdDetailStrings.unnamed,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (member.isHead)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            HouseholdDetailStrings.householdHead,
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (member.relation != null)
                        Text(
                          member.relation!,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Member details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  HouseholdDetailStrings.personalInfo,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: HouseholdDetailStrings.age,
                  value: member.age != null
                      ? '${member.age} years'
                      : HouseholdDetailStrings.notAvailable,
                ),
                _DetailRow(
                  label: HouseholdDetailStrings.gender,
                  value: member.gender ?? HouseholdDetailStrings.notAvailable,
                ),
                _DetailRow(
                  label: HouseholdDetailStrings.phone,
                  value:
                      member.phoneNumber ?? HouseholdDetailStrings.notAvailable,
                ),
                if (member.patientId != null)
                  _DetailRow(
                    label: HouseholdDetailStrings.patientId,
                    value: member.patientId!,
                  ),
                if (member.isPregnant)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pregnant_woman, size: 18, color: scheme.onTertiaryContainer),
                          const SizedBox(width: 6),
                          Text(
                            HouseholdDetailStrings.pregnant,
                            style: TextStyle(
                              color: scheme.onTertiaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(),

          // Household info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  HouseholdDetailStrings.householdInfo,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: HouseholdDetailStrings.householdName,
                  value: household.name ??
                      HouseholdDetailStrings.unnamedHousehold,
                ),
                if (household.householdNo != null)
                  _DetailRow(
                    label: HouseholdDetailStrings.householdNumber,
                    value: household.householdNo!,
                  ),
                _DetailRow(
                  label: HouseholdDetailStrings.totalMembers,
                  value: '${household.memberCount ?? household.members.length}',
                ),
              ],
            ),
          ),

          // View Health Details button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // Navigate to patient detail with member data
                context.push(
                  '/patient/${member.id}',
                  extra: {
                    'id': member.id,
                    'name': member.name,
                    'gender': member.gender,
                    'age': member.age,
                    'dateOfBirth': member.dateOfBirth,
                    'phoneNumber': member.phoneNumber,
                    'isPregnant': member.isPregnant,
                    'householdId': member.householdId ?? household.id,
                    'householdName': household.name,
                    'patientId': member.patientId,
                  },
                );
              },
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text(HouseholdDetailStrings.viewHealthDetails),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
