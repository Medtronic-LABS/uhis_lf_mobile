import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
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

    final relation = str('relation')?.toLowerCase();
    final isHead = relation == 'head' ||
        relation == 'self' ||
        relation == 'household head' ||
        json['isHouseholdHead'] == true;

    final isPregnant = json['isPregnant'] == true;

    return HouseholdMemberData(
      id: str('id'),
      patientId: str('patientId'),
      name: str('name') ?? str('firstName'),
      relation: str('relation'),
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

  @override
  void initState() {
    super.initState();
    _household = widget.household;
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
      // First try local database (synced patients)
      final patientDao = context.read<PatientDao>();
      // ignore: avoid_print
      print('[HouseholdDetail] Trying local DB for household $householdId');
      
      final localPatients = await patientDao.getByHouseholdId(householdId);
      // ignore: avoid_print
      print('[HouseholdDetail] Found ${localPatients.length} patients in local DB');
      
      if (localPatients.isNotEmpty && mounted) {
        // Convert local patients to member data format
        final members = localPatients.map((p) {
          final rawJson = p['raw_json'];
          if (rawJson is String && rawJson.isNotEmpty && rawJson.startsWith('{')) {
            try {
              final decoded = jsonDecode(rawJson);
              if (decoded is Map<String, dynamic>) {
                return HouseholdMemberData.fromJson(decoded);
              }
            } catch (_) {}
          }
          return HouseholdMemberData.fromJson(p);
        }).toList();
        
        setState(() {
          _household = HouseholdDetailData(
            id: _household.id,
            name: _household.name,
            householdNo: _household.householdNo,
            village: _household.village,
            subVillage: _household.subVillage,
            memberCount: members.length,
            latitude: _household.latitude,
            longitude: _household.longitude,
            members: members,
          );
          _loadingMembers = false;
        });
        return;
      }

      // Fall back to API
      final repo = context.read<DashboardRepository>();
      // ignore: avoid_print
      print('[HouseholdDetail] Falling back to API for household $householdId');
      
      final householdData = await repo.getHouseholdById(householdId);
      
      if (householdData != null && mounted) {
        final updated = HouseholdDetailData.fromJson(householdData);
        // ignore: avoid_print
        print('[HouseholdDetail] Got ${updated.members.length} members from API');
        
        setState(() {
          _household = updated;
          _loadingMembers = false;
        });
      } else if (mounted) {
        // ignore: avoid_print
        print('[HouseholdDetail] No data returned for household $householdId');
        setState(() {
          _loadError = 'No members found';
          _loadingMembers = false;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('[HouseholdDetail] Error fetching household: $e');
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loadingMembers = false;
        });
      }
    }
  }

  HouseholdDetailData get household => _household;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final head = household.head;

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
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: scheme.tertiaryContainer,
                        child: Icon(
                          Icons.home_work_outlined,
                          size: 28,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              household.name ??
                                  HouseholdDetailStrings.unnamedHousehold,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurface,
                              ),
                            ),
                            if (household.householdNo != null)
                              Text(
                                household.householdNo!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.people_alt_outlined,
                    label: HouseholdDetailStrings.members,
                    value: '${household.memberCount ?? 0}',
                    color: scheme.primary,
                  ),
                  if (household.village != null || household.subVillage != null)
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: HouseholdDetailStrings.location,
                      value: [household.subVillage, household.village]
                          .where((s) => s != null && s.isNotEmpty)
                          .join(', '),
                      color: scheme.secondary,
                    ),
                  if (household.latitude != null && household.longitude != null)
                    _InfoRow(
                      icon: Icons.my_location_outlined,
                      label: HouseholdDetailStrings.coordinates,
                      value:
                          '${household.latitude!.toStringAsFixed(4)}, ${household.longitude!.toStringAsFixed(4)}',
                      color: scheme.tertiary,
                    ),
                ],
              ),
            ),

            // Household Head section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                HouseholdDetailStrings.householdHead,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingMembers)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Loading…',
                        style: TextStyle(color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              )
            else if (head != null)
              _MemberCard(
                member: head,
                isHead: true,
                onTap: () => _showMemberDetail(context, head),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      color: scheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        HouseholdDetailStrings.noHeadInfo,
                        style: TextStyle(color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

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
                final nonHeadMembers = cappedMembers.where((m) => !m.isHead).toList();
                
                return [
                  ...nonHeadMembers.map((m) => _MemberCard(
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
    this.isHead = false,
    this.onTap,
  });

  final HouseholdMemberData member;
  final bool isHead;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isHead
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      isHead ? scheme.primary : scheme.secondaryContainer,
                  child: Icon(
                    isHead ? Icons.star : Icons.person_outline,
                    color:
                        isHead ? scheme.onPrimary : scheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              member.name ?? HouseholdDetailStrings.unnamed,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isHead ? scheme.onPrimaryContainer : scheme.onSurface,
                              ),
                            ),
                          ),
                          if (isHead)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                HouseholdDetailStrings.head,
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (member.relation != null && !isHead)
                            Text(
                              member.relation!,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          if (member.age != null) ...[
                            if (member.relation != null && !isHead)
                              Text(
                                ' • ',
                                style: TextStyle(
                                  color: scheme.outline,
                                  fontSize: 12,
                                ),
                              ),
                            Text(
                              '${member.age} yrs',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (member.gender != null) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: scheme.outline,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              member.gender!,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.outline,
                ),
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
