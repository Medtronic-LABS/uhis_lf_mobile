import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

/// A styled dropdown matching the enrollment form aesthetic.
///
/// Renders a label (with optional red asterisk for [isRequired]) above a
/// white rounded container with a [DropdownButtonFormField] that uses the
/// same visual language as [EnrollmentInputField].
class EnrollmentDropdown extends StatelessWidget {
  const EnrollmentDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint,
    this.isRequired = false,
    this.errorText,
    this.optionLabel,
  });

  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Placeholder shown when nothing is selected. Falls back to
  /// [EnrollmentStrings.dropdownDefaultHint] when omitted — kept nullable
  /// because a default parameter value cannot call a translation lookup.
  final String? hint;
  final bool isRequired;
  final String? errorText;

  /// Optional display label for an option id (e.g. Bangla for occupation).
  /// Wire / selected value stays the [options] entry.
  final String Function(String option)? optionLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedHint = hint ?? EnrollmentStrings.dropdownDefaultHint;
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
          padding: const EdgeInsets.only(left: AppSpacing.xxxl),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            border: Border.all(
              color: errorText != null ? AppColors.statusCritical : AppColors.border,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: options.contains(value) ? value : null,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: Text(
                    resolvedHint,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                  icon: value != null && options.contains(value)
                      ? const SizedBox.shrink()
                      : const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  dropdownColor: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  selectedItemBuilder: optionLabel == null
                      ? null
                      : (context) => options
                          .map(
                            (opt) => Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                optionLabel!(opt),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  items: options
                      .map(
                        (opt) => DropdownMenuItem<String>(
                          value: opt,
                          child: Text(
                            optionLabel?.call(opt) ?? opt,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
              if (value != null && options.contains(value))
                GestureDetector(
                  onTap: () => onChanged(null),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textMuted.withValues(alpha: 0.7),
                    ),
                  ),
                )
              else
                const SizedBox(width: AppSpacing.xxxl),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.statusCritical,
            ),
          ),
        ],
      ],
    );
  }
}
