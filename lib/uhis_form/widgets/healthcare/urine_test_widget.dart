/// Urine dipstick composite widget — [FieldKind.urineTest].
///
/// Three labelled dropdowns: albumin, sugar, bilirubin.
/// Value shape: `{"urinaryAlbumin": "absent", "urinarySugar": "absent", "urinaryBilirubin": "NA"}`.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

class UrineTestWidget extends StatelessWidget {
  const UrineTestWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys: urinaryAlbumin, urinarySugar, urinaryBilirubin.
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  static const _fields = [
    ('urinaryAlbumin', 'Albumin'),
    ('urinarySugar', 'Sugar'),
    ('urinaryBilirubin', 'Bilirubin'),
  ];

  static const _options = ['Absent', 'Present', 'Trace', 'N/A'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = value ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          schema.label.isEmpty ? 'Urine Dipstick' : schema.label,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        ..._fields.map((field) {
          final (key, label) = field;
          final currentVal = current[key]?.toString();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _options.contains(currentVal) ? currentVal : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    hint: const Text('Select'),
                    items: _options
                        .map((o) =>
                            DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: readOnly
                        ? null
                        : (v) {
                            if (v != null) {
                              onChanged({...current, key: v});
                            }
                          },
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
