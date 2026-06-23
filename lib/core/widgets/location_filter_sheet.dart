import 'package:flutter/material.dart';

import '../auth/user_hierarchy_service.dart';
import '../constants/app_strings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Location / SS filter bottom sheet — shared widget
// ─────────────────────────────────────────────────────────────────────────────

/// Filter sheet backed by the full static-data API hierarchy.
///
/// Cascade rules:
///   SS selected    → sub-villages = that SS's nested `subVillages`
///   Village selected (no SS) → sub-villages = top-level list filtered by villageId
///   Neither selected → all top-level sub-villages shown
class LocationFilterSheet extends StatefulWidget {
  const LocationFilterSheet({
    super.key,
    required this.villages,
    required this.allSubVillages,
    required this.ssWorkers,
    required this.selectedVillageId,
    required this.selectedSubVillageId,
    required this.selectedShebikaId,
    required this.onApply,
  });

  final List<({String id, String name})> villages;

  /// Top-level sub-village list from the API (all assigned sub-villages).
  /// Used for village → sub-village cascade when no SS is selected.
  final List<SubVillageRef> allSubVillages;

  final List<SsWorker> ssWorkers;
  final String? selectedVillageId;
  final String? selectedSubVillageId;
  final String? selectedShebikaId;
  final void Function(String? village, String? subVillage, String? shebika) onApply;

  @override
  State<LocationFilterSheet> createState() => _LocationFilterSheetState();
}

class _LocationFilterSheetState extends State<LocationFilterSheet> {
  String? _village;
  String? _subVillage;
  String? _shebika;
  List<({String id, String name})> _subVillages = const [];

  @override
  void initState() {
    super.initState();
    _village = widget.selectedVillageId;
    _subVillage = widget.selectedSubVillageId;
    _shebika = widget.selectedShebikaId;
    _rebuildSubVillages();
  }

  List<({String id, String name})> get _shebikas =>
      widget.ssWorkers.map((ss) => (id: ss.id, name: ss.name)).toList();

  void _rebuildSubVillages() {
    if (_shebika != null) {
      // SS selected: use that SS's assigned sub-villages.
      final ss = widget.ssWorkers.where((s) => s.id == _shebika).firstOrNull;
      _subVillages = ss?.subVillages
              .map((sv) => (id: sv.id, name: sv.name))
              .toList() ??
          const [];
    } else if (_village != null) {
      // Village selected, no SS: filter top-level sub-villages by villageId.
      _subVillages = widget.allSubVillages
          .where((sv) => sv.villageId == _village)
          .map((sv) => (id: sv.id, name: sv.name))
          .toList();
    } else {
      // No filter: show all top-level sub-villages.
      _subVillages = widget.allSubVillages
          .map((sv) => (id: sv.id, name: sv.name))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                HouseholdListStrings.filterTitle,
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _village = null;
                    _subVillage = null;
                    _shebika = null;
                    _rebuildSubVillages();
                  });
                },
                child: Text(HouseholdListStrings.filterClearAll,
                    style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Village (from API top-level villages list)
          LocationFilterDropdown<String?>(
            label: HouseholdListStrings.filterVillage,
            value: _village,
            items: [
              DropdownMenuItem(
                  value: null,
                  child: Text(HouseholdListStrings.filterAllVillages)),
              ...widget.villages.map((v) =>
                  DropdownMenuItem(value: v.id, child: Text(v.name))),
            ],
            onChanged: (v) => setState(() {
              _village = v;
              _subVillage = null;
              _shebika = null;
              _rebuildSubVillages();
            }),
          ),
          const SizedBox(height: 12),

          // SS (from API shasthyaShebikas list)
          if (_shebikas.isNotEmpty) ...[
            LocationFilterDropdown<String?>(
              label: HouseholdListStrings.filterSS,
              value: _shebika,
              items: [
                DropdownMenuItem(
                    value: null,
                    child: Text(HouseholdListStrings.filterAllSS)),
                ..._shebikas.map((ss) =>
                    DropdownMenuItem(value: ss.id, child: Text(ss.name))),
              ],
              onChanged: (ss) => setState(() {
                _shebika = ss;
                _subVillage = null;
                _rebuildSubVillages();
              }),
            ),
            const SizedBox(height: 12),
          ],

          // Sub-village — cascades from SS (or village if no SS selected)
          if (_subVillages.isNotEmpty) ...[
            LocationFilterDropdown<String?>(
              label: HouseholdListStrings.filterSubVillage,
              value: _subVillage,
              items: [
                DropdownMenuItem(
                    value: null,
                    child: Text(HouseholdListStrings.filterAllSubVillages)),
                ..._subVillages.map((sv) =>
                    DropdownMenuItem(value: sv.id, child: Text(sv.name))),
              ],
              onChanged: (sv) => setState(() => _subVillage = sv),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onApply(_village, _subVillage, _shebika);
            },
            child: Text(HouseholdListStrings.filterApply),
          ),
        ],
      ),
    );
  }
}

/// Labeled dropdown used in the location filter sheet.
class LocationFilterDropdown<T> extends StatelessWidget {
  const LocationFilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outline),
            ),
          ),
        ),
      ],
    );
  }
}
