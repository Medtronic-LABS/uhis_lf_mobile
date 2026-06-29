/// Read-only computed value display — API viewType `InformationLabel`.
///
/// Shows a label on the left and a bold computed value on the right (e.g. BMI
/// calculated from height and weight). [onChanged] is never called; the value
/// is injected as [currentValue] from the assessment view-model.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class InfoLabelField extends StatelessWidget {
  const InfoLabelField({
    super.key,
    required this.labelText,
    this.currentValue,
  });

  final String labelText;
  final String? currentValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              labelText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            currentValue ?? '—',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: currentValue != null ? AppColors.navy : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
