/// MUAC composite widget — [FieldKind.muac].
///
/// Mid-upper arm circumference input (cm, 1 decimal) with a traffic-light
/// classification band below.
///
/// WHO thresholds:
///   SAM    : MUAC < 11.5 cm → red
///   MAM    : 11.5 ≤ MUAC ≤ 12.5 → amber
///   Normal : > 12.5 cm → green
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';
import '../_shared/status_badge.dart';

class MuacWidget extends StatefulWidget {
  const MuacWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Numeric MUAC value in cm.
  final num? value;
  final ValueChanged<num> onChanged;
  final bool readOnly;

  @override
  State<MuacWidget> createState() => _MuacWidgetState();
}

class _MuacWidgetState extends State<MuacWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(MuacWidget old) {
    super.didUpdateWidget(old);
    final newText = widget.value?.toString() ?? '';
    if (newText != _ctrl.text) _ctrl.text = newText;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? get _parsed => double.tryParse(_ctrl.text);

  _MuacCategory? get _category {
    final v = _parsed;
    if (v == null) return null;
    if (v < 11.5) return _MuacCategory.sam;
    if (v <= 12.5) return _MuacCategory.mam;
    return _MuacCategory.normal;
  }

  @override
  Widget build(BuildContext context) {
    final cat = _category;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(
          schema: widget.schema,
          fallback: ComposerStrings.muacLabel,
          trailing: cat != null
              ? SdkStatusBadge(
                  label: cat.label,
                  textColor: cat.color,
                  surfaceColor: cat.surfaceColor,
                )
              : null,
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _ctrl,
          readOnly: widget.readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(
            fontFamily: 'NunitoSans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            suffixText: 'cm',
            hintText: schema.hint,
          ),
          onChanged: (v) {
            setState(() {});
            final parsed = double.tryParse(v);
            if (parsed != null) widget.onChanged(parsed);
          },
        ),
        if (cat != null) ...[
          const SizedBox(height: 8),
          _MuacBand(category: cat),
        ],
      ],
    );
  }

  FieldSchema get schema => widget.schema;
}

enum _MuacCategory { sam, mam, normal }

extension _MuacCategoryX on _MuacCategory {
  String get label {
    return switch (this) {
      _MuacCategory.sam    => ComposerStrings.muacSam,
      _MuacCategory.mam    => ComposerStrings.muacMam,
      _MuacCategory.normal => ComposerStrings.muacNormal,
    };
  }

  Color get color {
    return switch (this) {
      _MuacCategory.sam    => AppColors.rangeCritical,
      _MuacCategory.mam    => AppColors.rangeElevated,
      _MuacCategory.normal => AppColors.rangeNormal,
    };
  }

  Color get surfaceColor {
    return switch (this) {
      _MuacCategory.sam    => AppColors.rangeCriticalSurface,
      _MuacCategory.mam    => AppColors.rangeElevatedSurface,
      _MuacCategory.normal => AppColors.rangeNormalSurface,
    };
  }
}

class _MuacBand extends StatelessWidget {
  const _MuacBand({required this.category});

  final _MuacCategory category;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Segment(
          label: ComposerStrings.muacSam,
          color: AppColors.rangeCritical,
          flex: 23,
          active: category == _MuacCategory.sam,
        ),
        _Segment(
          label: ComposerStrings.muacMam,
          color: AppColors.rangeElevated,
          flex: 20,
          active: category == _MuacCategory.mam,
        ),
        _Segment(
          label: ComposerStrings.muacNormal,
          color: AppColors.rangeNormal,
          flex: 57,
          active: category == _MuacCategory.normal,
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.color,
    required this.flex,
    required this.active,
  });

  final String label;
  final Color color;
  final int flex;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: active ? 9 : 7,
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
