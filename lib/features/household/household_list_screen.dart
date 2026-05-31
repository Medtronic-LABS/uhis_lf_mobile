import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../dashboard/dashboard_repository.dart';
import 'household_detail_screen.dart';

/// View mode for the list screen.
enum HouseholdListMode {
  /// Show households with member counts.
  households,

  /// Show a flat list of all members across households.
  members,
}

class HouseholdListScreen extends StatefulWidget {
  const HouseholdListScreen({super.key, required this.mode});

  final HouseholdListMode mode;

  @override
  State<HouseholdListScreen> createState() => _HouseholdListScreenState();
}

class _HouseholdListScreenState extends State<HouseholdListScreen> {
  late Future<List<_HouseholdItem>> _future;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadData() {
    final repo = context.read<DashboardRepository>();
    _future = _fetchHouseholds(repo);
  }

  Future<List<_HouseholdItem>> _fetchHouseholds(DashboardRepository repo) async {
    // Fetch households with embedded member data
    final rawList = await repo.getHouseholdsWithMembers();
    return rawList.map((raw) => _HouseholdItem.fromJson(raw)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isMembers = widget.mode == HouseholdListMode.members;
    final title = isMembers
        ? HouseholdListStrings.allMembers
        : HouseholdListStrings.allHouseholds;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_loadData),
          ),
        ],
      ),
      body: FutureBuilder<List<_HouseholdItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(HouseholdListStrings.loadError),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => setState(_loadData),
                    child: const Text(CommonStrings.retry),
                  ),
                ],
              ),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMembers ? Icons.people_outline : Icons.home_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isMembers
                        ? HouseholdListStrings.noMembers
                        : HouseholdListStrings.noHouseholds,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          if (isMembers) {
            return _buildMembersList(context, items);
          } else {
            return _buildHouseholdsList(context, items);
          }
        },
      ),
    );
  }

  Widget _buildHouseholdsList(BuildContext context, List<_HouseholdItem> items) {
    final scheme = Theme.of(context).colorScheme;
    final totalMembers = items.fold<int>(0, (sum, h) => sum + (h.memberCount ?? 0));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Expanded(
                child: _SummaryChip(
                  icon: Icons.home_work_outlined,
                  label: HouseholdListStrings.householdsCount(items.length),
                  color: scheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryChip(
                  icon: Icons.people_alt_outlined,
                  label: HouseholdListStrings.membersCount(totalMembers),
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final item = items[index];
              return _HouseholdTile(
                item: item,
                onTap: () => _navigateToDetail(context, item),
              );
            },
          ),
        ),
      ],
    );
  }

  void _navigateToDetail(BuildContext context, _HouseholdItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HouseholdDetailScreen(household: item.toDetailData()),
      ),
    );
  }

  void _navigateToMemberDetail(BuildContext context, _MemberInfo member) {
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
        'householdId': member.householdId,
        'householdName': member.householdName,
        'patientId': member.patientId,
      },
    );
  }

  Widget _buildMembersList(BuildContext context, List<_HouseholdItem> items) {
    final scheme = Theme.of(context).colorScheme;
    // Flatten all members from all households
    final members = <_MemberInfo>[];
    for (final household in items) {
      for (final member in household.members) {
        members.add(_MemberInfo.fromMember(member, household));
      }
    }

    // Calculate total from noOfPeople if we don't have individual members
    final totalFromCount = items.fold<int>(0, (sum, h) => sum + (h.memberCount ?? 0));

    // If we have no individual members but have a count, show households with counts
    if (members.isEmpty && totalFromCount > 0) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryChip(
                    icon: Icons.people_alt_outlined,
                    label: HouseholdListStrings.totalMembersCount(totalFromCount),
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryChip(
                    icon: Icons.home_work_outlined,
                    label: HouseholdListStrings.acrossHouseholds(items.length),
                    color: scheme.tertiary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final item = items[index];
                return _HouseholdWithMemberCountTile(
                  item: item,
                  onTap: () => _navigateToDetail(context, item),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Flexible(
                child: _SummaryChip(
                  icon: Icons.people_alt_outlined,
                  label: HouseholdListStrings.totalMembersCount(members.length),
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: _SummaryChip(
                  icon: Icons.home_work_outlined,
                  label: HouseholdListStrings.acrossHouseholds(items.length),
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: members.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final member = members[index];
              return _MemberTile(
                member: member,
                onTap: () => _navigateToMemberDetail(context, member),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  const _HouseholdTile({required this.item, this.onTap});

  final _HouseholdItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.tertiaryContainer,
        child: Icon(Icons.home_outlined, color: scheme.onTertiaryContainer),
      ),
      title: Text(
        item.name ?? HouseholdListStrings.unnamedHousehold,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(
        item.householdNo ?? '',
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, size: 16, color: scheme.onPrimaryContainer),
                const SizedBox(width: 4),
                Text(
                  '${item.memberCount ?? 0}',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: scheme.outline),
        ],
      ),
    );
  }
}

/// Tile for displaying households with member counts in the "All Members" view
/// when individual member data is not available from the API.
class _HouseholdWithMemberCountTile extends StatelessWidget {
  const _HouseholdWithMemberCountTile({required this.item, this.onTap});

  final _HouseholdItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = item.memberCount ?? 0;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          '$count',
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        item.name ?? HouseholdListStrings.unnamedHousehold,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      subtitle: Text(
        HouseholdListStrings.membersCount(count),
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, this.onTap});

  final _MemberInfo member;
  final VoidCallback? onTap;

  IconData _genderIcon() {
    final g = member.gender?.toLowerCase();
    if (g == 'male' || g == 'm') return Icons.male;
    if (g == 'female' || g == 'f') return Icons.female;
    return Icons.person_outline;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    // Build metadata parts: Age · Gender · House #
    final metaParts = <String>[];
    if (member.age != null) {
      metaParts.add('Age ${member.age}');
    }
    if (member.gender != null) {
      metaParts.add(member.gender!);
    }
    if (member.householdNo != null) {
      metaParts.add('House #${member.householdNo}');
    } else if (member.householdName != null) {
      metaParts.add(member.householdName!);
    }
    final metaLine = metaParts.join(' · ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: member.isPregnant
            ? scheme.tertiaryContainer
            : scheme.primaryContainer,
        child: member.isPregnant
            ? const Text('🤰', style: TextStyle(fontSize: 20))
            : Icon(_genderIcon(), color: scheme.onPrimaryContainer),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.name ?? HouseholdListStrings.unnamedMember,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.isPregnant)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Pregnant',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member.relation != null)
            Text(
              member.relation!,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (metaLine.isNotEmpty)
            Text(
              metaLine,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.outline),
      isThreeLine: member.relation != null,
    );
  }
}

class _HouseholdItem {
  _HouseholdItem({
    this.id,
    this.name,
    this.householdNo,
    this.village,
    this.subVillage,
    this.memberCount,
    this.latitude,
    this.longitude,
    this.members = const [],
    this.rawJson,
  });

  final String? id;
  final String? name;
  final String? householdNo;
  final String? village;
  final String? subVillage;
  final int? memberCount;
  final double? latitude;
  final double? longitude;
  final List<_HouseholdMember> members;
  final Map<String, dynamic>? rawJson;

  /// Convert to HouseholdDetailData for the detail screen.
  HouseholdDetailData toDetailData() {
    return HouseholdDetailData.fromJson(rawJson ?? {});
  }

  static _HouseholdItem fromJson(Map json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? members;
    final members1 = json['noOfPeople'];
    if (members1 is int) {
      members = members1;
    } else if (members1 is num) {
      members = members1.toInt();
    } else if (members1 is String) {
      members = int.tryParse(members1);
    }

    double? lat, lng;
    final latVal = json['latitude'];
    final lngVal = json['longitude'];
    if (latVal is double) lat = latVal;
    else if (latVal is num) lat = latVal.toDouble();
    if (lngVal is double) lng = lngVal;
    else if (lngVal is num) lng = lngVal.toDouble();

    final memberList = <_HouseholdMember>[];
    if (json['householdMembers'] is List) {
      for (final m in json['householdMembers']) {
        if (m is Map) {
          memberList.add(_HouseholdMember.fromJson(m));
        }
      }
      members ??= memberList.length;
    }

    return _HouseholdItem(
      id: str('id'),
      name: str('name'),
      householdNo: str('householdNo'),
      village: str('village'),
      subVillage: str('subVillage'),
      memberCount: members,
      latitude: lat,
      longitude: lng,
      members: memberList,
      rawJson: json is Map<String, dynamic> ? json : Map<String, dynamic>.from(json),
    );
  }
}

class _HouseholdMember {
  _HouseholdMember({
    this.id,
    this.patientId,
    this.name,
    this.relation,
    this.gender,
    this.dateOfBirth,
    this.phoneNumber,
    this.isHouseholdHead,
    this.isPregnant,
    this.householdId,
    this.villageId,
  });

  final String? id;
  final String? patientId;
  final String? name;
  final String? relation;
  final String? gender;
  final String? dateOfBirth;
  final String? phoneNumber;
  final bool? isHouseholdHead;
  final bool? isPregnant;
  final String? householdId;
  final String? villageId;

  static _HouseholdMember fromJson(Map json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return _HouseholdMember(
      id: str('id'),
      patientId: str('patientId'),
      name: str('name') ?? str('firstName'),
      relation: str('relation'),
      gender: str('gender'),
      dateOfBirth: str('dateOfBirth'),
      phoneNumber: str('phoneNumber'),
      isHouseholdHead: json['isHouseholdHead'] == true,
      isPregnant: json['isPregnant'] == true,
      householdId: str('householdId'),
      villageId: str('villageId'),
    );
  }
}

class _MemberInfo {
  _MemberInfo({
    this.id,
    this.patientId,
    this.name,
    this.relation,
    this.gender,
    this.age,
    this.dateOfBirth,
    this.phoneNumber,
    this.isPregnant = false,
    this.householdId,
    this.householdName,
    this.householdNo,
  });

  final String? id;
  final String? patientId;
  final String? name;
  final String? relation;
  final String? gender;
  final int? age;
  final String? dateOfBirth;
  final String? phoneNumber;
  final bool isPregnant;
  final String? householdId;
  final String? householdName;
  final String? householdNo;

  /// Calculate age from date of birth if not directly provided.
  static int? _calculateAge(String? dateOfBirth) {
    if (dateOfBirth == null) return null;
    try {
      final dob = DateTime.parse(dateOfBirth);
      final now = DateTime.now();
      var age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  /// Create from _HouseholdMember and household context.
  factory _MemberInfo.fromMember(_HouseholdMember member, _HouseholdItem household) {
    return _MemberInfo(
      id: member.id,
      patientId: member.patientId,
      name: member.name,
      relation: member.relation,
      gender: member.gender,
      age: _calculateAge(member.dateOfBirth),
      dateOfBirth: member.dateOfBirth,
      phoneNumber: member.phoneNumber,
      isPregnant: member.isPregnant ?? false,
      householdId: member.householdId ?? household.id,
      householdName: household.name,
      householdNo: household.householdNo,
    );
  }
}
