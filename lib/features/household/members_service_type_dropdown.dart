import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import 'service_static_filter.dart';

/// UHIS-style service cohort picker above the village filter row.
class MembersServiceTypeDropdown extends StatelessWidget {
  const MembersServiceTypeDropdown({
    super.key,
    required this.filters,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final List<ServiceStaticFilter> filters;
  final ServiceStaticFilter selected;
  final Map<ServiceStaticFilter, int> counts;
  final ValueChanged<ServiceStaticFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ServiceStaticFilter>(
              isExpanded: true,
              value: selected,
              icon: const Icon(Icons.expand_more, color: AppColors.navy),
              style: const TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              items: [
                for (final f in filters)
                  DropdownMenuItem(
                    value: f,
                    child: Text(
                      ServiceMemberFilterStrings.dropdownLabel(
                        f.label,
                        counts[f] ?? 0,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onSelected(v);
              },
            ),
          ),
        ),
      ),
    );
  }
}
