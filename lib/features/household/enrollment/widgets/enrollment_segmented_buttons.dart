import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Pill-style segmented button group for enrollment forms.
///
/// Selected pill: navy background (#24356F) + white text.
/// Unselected pill: white background + #E5E7EB border + #6B7280 text.
/// Each pill has 10px border-radius. The wrapping row has 12px border-radius.
class EnrollmentSegmentedButtons extends StatelessWidget {
  const EnrollmentSegmentedButtons({
    required this.label,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.isRequired = false,
    super.key,
  });

  final String label;
  final List<String> options;
  final String? selectedValue;
  final ValueChanged<String> onChanged;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            if (isRequired)
              const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Text(
                  '*',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.statusCritical,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            border: Border.all(color: AppColors.border, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                options.length,
                (index) {
                  final option = options[index];
                  final isSelected = selectedValue == option;

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index < options.length - 1 ? 4 : 0,
                    ),
                    child: GestureDetector(
                      onTap: () => onChanged(option),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.navy
                              : AppColors.cardSurface,
                          border: isSelected
                              ? null
                              : Border.all(
                                  color: AppColors.border,
                                  width: 1,
                                ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
