import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (isRequired)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '*',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.statusCritical,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(
              options.length,
              (index) {
                final option = options[index];
                final isSelected = selectedValue == option;

                return Padding(
                  padding: EdgeInsets.only(
                    right: index < options.length - 1 ? 8 : 0,
                  ),
                  child: Material(
                    child: InkWell(
                      onTap: () => onChanged(option),
                      borderRadius: BorderRadius.circular(AppRadius.button),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.navy
                              : AppColors.border,
                          borderRadius:
                              BorderRadius.circular(AppRadius.button),
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? AppColors.textOnNavy
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
