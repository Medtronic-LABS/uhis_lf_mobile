/// Pill-button single-select widget — replaces RadioGroupWidget visually.
///
/// Matches HTML `.pill-btn` style exactly:
///   unselected: white bg, 2px solid #E5E7EB, borderRadius 10, padding 9px all
///   selected (2-option neutral): #1B2B5E bg, white text
///   selected (3-option traffic-light): range surface bg, range border + text
///
/// Traffic-light mode activates automatically for exactly 3 options whose
/// labels loosely match none/mild/severe or absent/trace/present or
/// normal/elevated/high patterns.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class PillSelectorWidget extends StatelessWidget {
  const PillSelectorWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  static const _trafficPatterns = [
    ['none', 'mild', 'severe'],
    ['absent', 'trace', 'present'],
    ['normal', 'elevated', 'high'],
    ['no', 'mild', 'severe'],
    ['no', 'borderline', 'yes'],
  ];

  bool get _isTrafficLight {
    if (schema.options.length != 3) return false;
    final labels = schema.options.map((o) => o.label.toLowerCase()).toList();
    return _trafficPatterns.any((pattern) =>
        labels.every((l) => pattern.any((p) => l.contains(p))));
  }

  (Color bg, Color border, Color text) _colorsForIndex(int index, bool selected) {
    if (!_isTrafficLight || !selected) {
      return selected
          ? (AppColors.navy, AppColors.navy, AppColors.textOnNavy)
          : (AppColors.cardSurface, AppColors.border, AppColors.textMuted);
    }
    final (color, surface) = switch (index) {
      0 => (AppColors.rangeNormal,   AppColors.rangeNormalSurface),
      1 => (AppColors.rangeElevated, AppColors.rangeElevatedSurface),
      _ => (AppColors.rangeCritical, AppColors.rangeCriticalSurface),
    };
    return (surface, color, color);
  }

  @override
  Widget build(BuildContext context) {
    final options = schema.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: schema),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < options.length; i++)
              _PillButton(
                label: options[i].label,
                selected: value == options[i].value,
                readOnly: readOnly,
                colors: _colorsForIndex(i, value == options[i].value),
                onTap: () {
                  if (!readOnly) onChanged(options[i].value);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.selected,
    required this.readOnly,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool readOnly;
  final (Color bg, Color border, Color text) colors;
  final VoidCallback onTap;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final (bg, border, text) = widget.colors;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 2),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ),
      ),
    );
  }
}
