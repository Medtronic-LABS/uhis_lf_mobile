/// Blood pressure composite widget — [FieldKind.bloodPressure].
///
/// Renders systolic + diastolic inputs side-by-side with a clinical range
/// interpretation strip below. Value shape: `{"systolic": 120, "diastolic": 80}`.
///
/// Range thresholds (JNC 8 / ESC 2018):
///   Normal      : SYS < 120 && DIA < 80
///   Elevated    : 120 ≤ SYS ≤ 129 && DIA < 80
///   Stage 1 HTN : 130–139 or 80–89
///   Stage 2 HTN : ≥ 140 or ≥ 90
///   Crisis      : > 180 or > 120
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class BloodPressureWidget extends StatefulWidget {
  const BloodPressureWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys 'systolic' and 'diastolic' (int values), or null.
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<BloodPressureWidget> createState() => _BloodPressureWidgetState();
}

class _BloodPressureWidgetState extends State<BloodPressureWidget> {
  late final TextEditingController _sysCtrl;
  late final TextEditingController _diaCtrl;

  @override
  void initState() {
    super.initState();
    final sys = widget.value?['systolic'];
    final dia = widget.value?['diastolic'];
    _sysCtrl = TextEditingController(
        text: sys != null ? sys.toString() : '');
    _diaCtrl = TextEditingController(
        text: dia != null ? dia.toString() : '');
  }

  @override
  void didUpdateWidget(BloodPressureWidget old) {
    super.didUpdateWidget(old);
    final newSys = widget.value?['systolic'];
    final newDia = widget.value?['diastolic'];
    if (newSys?.toString() != _sysCtrl.text) {
      _sysCtrl.text = newSys?.toString() ?? '';
    }
    if (newDia?.toString() != _diaCtrl.text) {
      _diaCtrl.text = newDia?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _sysCtrl.dispose();
    _diaCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    setState(() {});
    final sys = int.tryParse(_sysCtrl.text);
    final dia = int.tryParse(_diaCtrl.text);
    if (sys != null && dia != null) {
      widget.onChanged({'systolic': sys, 'diastolic': dia});
    }
  }

  _BpRange? get _range {
    final sys = int.tryParse(_sysCtrl.text);
    final dia = int.tryParse(_diaCtrl.text);
    if (sys == null || dia == null) return null;
    if (sys > 180 || dia > 120) return _BpRange.crisis;
    if (sys >= 140 || dia >= 90) return _BpRange.stage2;
    if (sys >= 130 || dia >= 80) return _BpRange.stage1;
    if (sys >= 120 && dia < 80) return _BpRange.elevated;
    return _BpRange.normal;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = _range;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: widget.schema),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _NumericInput(
                ctrl: _sysCtrl,
                hint: ComposerStrings.bpSystolicHint,
                readOnly: widget.readOnly,
                onChanged: (_) => _emit(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Text(
                '/',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
            Expanded(
              child: _NumericInput(
                ctrl: _diaCtrl,
                hint: ComposerStrings.bpDiastolicHint,
                suffix: ComposerStrings.bpUnit,
                readOnly: widget.readOnly,
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
        if (range != null) ...[
          const SizedBox(height: 8),
          _RangeStrip(range: range),
        ],
      ],
    );
  }
}

class _NumericInput extends StatelessWidget {
  const _NumericInput({
    required this.ctrl,
    required this.hint,
    required this.onChanged,
    this.suffix,
    this.readOnly = false,
  });

  final TextEditingController ctrl;
  final String hint;
  final String? suffix;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: hint,
        suffixText: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onChanged: onChanged,
    );
  }
}

enum _BpRange { normal, elevated, stage1, stage2, crisis }

class _RangeStrip extends StatelessWidget {
  const _RangeStrip({required this.range});

  final _BpRange range;

  @override
  Widget build(BuildContext context) {
    final (label, color, surface) = switch (range) {
      _BpRange.normal  => (ComposerStrings.rangeNormal,   AppColors.rangeNormal,   AppColors.rangeNormalSurface),
      _BpRange.elevated => (ComposerStrings.rangeElevated, AppColors.rangeElevated, AppColors.rangeElevatedSurface),
      _BpRange.stage1  => (ComposerStrings.rangeBpStage1, AppColors.rangeAbnormal, AppColors.rangeAbnormalSurface),
      _BpRange.stage2  => (ComposerStrings.rangeBpStage2, AppColors.rangeCritical, AppColors.rangeCriticalSurface),
      _BpRange.crisis  => (ComposerStrings.rangeBpCrisis, AppColors.rangeCrisis,   AppColors.rangeCrisisSurface),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

