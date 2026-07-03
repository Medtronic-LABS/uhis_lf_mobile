import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

/// Standardised label row for all SDK form fields.
///
/// Renders the field [schema] label in Nunito 12px w700 with an optional
/// pink required marker, and an optional [trailing] widget (e.g. SdkStatusBadge).
class SdkFieldLabel extends StatelessWidget {
  const SdkFieldLabel({
    super.key,
    required this.schema,
    this.fallback,
    this.trailing,
  });

  final FieldSchema schema;
  /// Displayed when [schema.label] is empty.
  final String? fallback;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = schema.label.isNotEmpty ? schema.label : (fallback ?? '');
    if (text.isEmpty && trailing == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            text: text,
            children: schema.required && text.isNotEmpty
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: AppColors.pink),
                    ),
                  ]
                : null,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}
