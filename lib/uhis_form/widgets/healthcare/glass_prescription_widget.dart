/// Glass prescription composite widget — [FieldKind.glassPrescription].
///
/// 2-column OD (right eye) / OS (left eye) grid with Sphere, Cylinder, Axis
/// inputs per column. Two toggle switches at the bottom.
/// Value shape: `{"od": {"sphere": -1.5, "cylinder": -0.5, "axis": 90},
///               "os": {"sphere": -1.0, "cylinder": -0.25, "axis": 85},
///               "glassesSold": true, "referredForOperation": false}`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';
import '../_shared/status_badge.dart';

class GlassPrescriptionWidget extends StatefulWidget {
  const GlassPrescriptionWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<GlassPrescriptionWidget> createState() =>
      _GlassPrescriptionWidgetState();
}

class _GlassPrescriptionWidgetState extends State<GlassPrescriptionWidget> {
  late final TextEditingController _odSphere;
  late final TextEditingController _odCylinder;
  late final TextEditingController _odAxis;
  late final TextEditingController _osSphere;
  late final TextEditingController _osCylinder;
  late final TextEditingController _osAxis;
  bool _glassesSold = false;
  bool _referredForOp = false;

  @override
  void initState() {
    super.initState();
    final v = widget.value ?? {};
    final od = (v['od'] as Map?)?.cast<String, dynamic>() ?? {};
    final os = (v['os'] as Map?)?.cast<String, dynamic>() ?? {};
    _odSphere   = TextEditingController(text: od['sphere']?.toString() ?? '');
    _odCylinder = TextEditingController(text: od['cylinder']?.toString() ?? '');
    _odAxis     = TextEditingController(text: od['axis']?.toString() ?? '');
    _osSphere   = TextEditingController(text: os['sphere']?.toString() ?? '');
    _osCylinder = TextEditingController(text: os['cylinder']?.toString() ?? '');
    _osAxis     = TextEditingController(text: os['axis']?.toString() ?? '');
    _glassesSold   = v['glassesSold'] == true;
    _referredForOp = v['referredForOperation'] == true;
  }

  @override
  void dispose() {
    for (final c in [_odSphere, _odCylinder, _odAxis, _osSphere, _osCylinder, _osAxis]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      'od': {
        'sphere':   double.tryParse(_odSphere.text),
        'cylinder': double.tryParse(_odCylinder.text),
        'axis':     double.tryParse(_odAxis.text),
      },
      'os': {
        'sphere':   double.tryParse(_osSphere.text),
        'cylinder': double.tryParse(_osCylinder.text),
        'axis':     double.tryParse(_osAxis.text),
      },
      'glassesSold': _glassesSold,
      'referredForOperation': _referredForOp,
    });
  }

  bool get _hasData =>
      _odSphere.text.isNotEmpty || _osSphere.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(
          schema: widget.schema,
          fallback: ComposerStrings.fieldGlassPrescription,
          trailing: _hasData
              ? SdkStatusBadge(
                  label: ComposerStrings.glassPrescriptionSummary,
                  textColor: AppColors.navy,
                  surfaceColor: AppColors.aiSurfaceStart,
                )
              : null,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _EyeColumn(
                eyeLabel: ComposerStrings.eyeOd,
                sphereCtrl: _odSphere,
                cylinderCtrl: _odCylinder,
                axisCtrl: _odAxis,
                readOnly: widget.readOnly,
                onChanged: _emit,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EyeColumn(
                eyeLabel: ComposerStrings.eyeOs,
                sphereCtrl: _osSphere,
                cylinderCtrl: _osCylinder,
                axisCtrl: _osAxis,
                readOnly: widget.readOnly,
                onChanged: _emit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ToggleRow(
          label: ComposerStrings.fieldGlassesSold,
          value: _glassesSold,
          readOnly: widget.readOnly,
          onChanged: (v) => setState(() {
            _glassesSold = v;
            _emit();
          }),
        ),
        const SizedBox(height: 8),
        _ToggleRow(
          label: ComposerStrings.fieldReferredForOperation,
          value: _referredForOp,
          readOnly: widget.readOnly,
          onChanged: (v) => setState(() {
            _referredForOp = v;
            _emit();
          }),
        ),
      ],
    );
  }
}

class _EyeColumn extends StatelessWidget {
  const _EyeColumn({
    required this.eyeLabel,
    required this.sphereCtrl,
    required this.cylinderCtrl,
    required this.axisCtrl,
    required this.readOnly,
    required this.onChanged,
  });

  final String eyeLabel;
  final TextEditingController sphereCtrl;
  final TextEditingController cylinderCtrl;
  final TextEditingController axisCtrl;
  final bool readOnly;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyeLabel,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _RxField(
          label: ComposerStrings.sphereLabel,
          ctrl: sphereCtrl,
          readOnly: readOnly,
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
        _RxField(
          label: ComposerStrings.cylinderLabel,
          ctrl: cylinderCtrl,
          readOnly: readOnly,
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
        _RxField(
          label: ComposerStrings.axisLabel,
          ctrl: axisCtrl,
          readOnly: readOnly,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RxField extends StatelessWidget {
  const _RxField({
    required this.label,
    required this.ctrl,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final TextEditingController ctrl;
  final bool readOnly;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
      ],
      style: const TextStyle(
        fontFamily: 'NunitoSans',
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => onChanged(),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool readOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textPrimary)),
        ),
        Switch(
          value: value,
          onChanged: readOnly ? null : onChanged,
        ),
      ],
    );
  }
}
