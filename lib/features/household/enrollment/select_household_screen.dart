import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/db/household_dao.dart';
import '../../../core/theme/app_theme.dart';

/// Screen shown when linking a new member to an existing household.
///
/// Mirrors Android's HouseholdSearchActivity + HouseholdListAdapter flow.
/// Loads households from local SQLite, filtered to the SK's village(s).
/// User selects one and taps the sticky "Link & Enrol" CTA which navigates
/// to [LinkMemberScreen] with the chosen household's data.
class SelectHouseholdScreen extends StatefulWidget {
  const SelectHouseholdScreen({super.key});

  @override
  State<SelectHouseholdScreen> createState() => _SelectHouseholdScreenState();
}

class _SelectHouseholdScreenState extends State<SelectHouseholdScreen> {
  final _searchCtrl = TextEditingController();

  List<HouseholdEntity> _households = [];
  List<HouseholdEntity> _filtered = [];
  HouseholdEntity? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHouseholds();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHouseholds() async {
    final dao = context.read<HouseholdDao>();
    final auth = context.read<AuthRepository>();
    final ids = await auth.villageIds();
    final strIds = ids.map((e) => e.toString()).toList();
    final hhs = strIds.isEmpty
        ? await dao.getAll(limit: 200)
        : await dao.getByVillageIds(strIds);
    if (mounted) {
      setState(() {
        _households = hhs;
        _filtered = hhs;
        _loading = false;
      });
    }
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _households
          : _households.where((h) {
              return (h.name?.toLowerCase().contains(q) ?? false) ||
                  (h.householdNo?.toLowerCase().contains(q) ?? false) ||
                  (h.village?.toLowerCase().contains(q) ?? false);
            }).toList();
    });
  }

  void _onProceed() {
    final hh = _selected;
    if (hh == null) return;
    context.push('/household/enrollment/link-member', extra: {
      'householdId': hh.id,
      'householdFhirId': hh.fhirId ?? hh.id,
      'householdName': hh.name ?? '',
      'householdNo': hh.householdNo ?? '',
      'villageId': hh.villageId ?? '',
      'villageName': hh.village ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              SelectHouseholdStrings.title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              SelectHouseholdStrings.subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        toolbarHeight: 72,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ───────────────────────────────────────────────
                Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: SelectHouseholdStrings.searchHint,
                      hintStyle: const TextStyle(
                          fontSize: 14, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.textMuted, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      isDense: true,
                    ),
                  ),
                ),

                // ── Count header ─────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    '${_filtered.length} ${SelectHouseholdStrings.catchmentCount}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),

                // ── Household list ───────────────────────────────────────────
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            SelectHouseholdStrings.emptyState,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, _x) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final hh = _filtered[i];
                            final isSelected = _selected?.id == hh.id;
                            return _HouseholdCard(
                              household: hh,
                              selected: isSelected,
                              onTap: () => setState(() => _selected = hh),
                            );
                          },
                        ),
                ),
              ],
            ),

      // ── Sticky CTA ───────────────────────────────────────────────────────
      bottomNavigationBar: _selected == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _onProceed,
                    child: Text(
                      '${SelectHouseholdStrings.ctaPrefix}'
                      ' → ${_selected!.householdNo ?? _selected!.id}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _HouseholdCard extends StatelessWidget {
  const _HouseholdCard({
    required this.household,
    required this.selected,
    required this.onTap,
  });

  final HouseholdEntity household;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.navy : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // House icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('🏠', style: TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 12),

            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    household.name ?? SelectHouseholdStrings.unknownFamily,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (household.memberCount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${household.memberCount} ${SelectHouseholdStrings.membersLabel}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.navy : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.navy : const Color(0xFFD1D5DB),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    final parts = <String>[];
    if (household.householdNo != null) parts.add(household.householdNo!);
    if (household.village != null) parts.add(household.village!);
    return parts.join(' \u00b7 ');
  }
}
