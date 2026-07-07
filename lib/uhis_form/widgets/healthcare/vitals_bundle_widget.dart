/// Vitals bundle composite widget — [FieldKind.vitalsBundle].
///
/// Four tap-to-edit cells in a 2×2 grid: Temperature · Pulse · RR · SpO2.
/// Value shape: `{"temperature": 37.2, "pulse": 88, "breathsPerMinute": 24, "spo2": 97}`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';

class VitalsBundleWidget extends StatefulWidget {
  const VitalsBundleWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys: temperature, pulse, breathsPerMinute, spo2.
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<VitalsBundleWidget> createState() => _VitalsBundleWidgetState();
}

class _VitalsBundleWidgetState extends State<VitalsBundleWidget> {
  late final TextEditingController _tempCtrl;
  late final TextEditingController _pulseCtrl;
  late final TextEditingController _rrCtrl;
  late final TextEditingController _spo2Ctrl;

  static const _vitalDefs = [
    ('temperature', 'Temp', '°C'),
    ('pulse', 'Pulse', '/min'),
    ('breathsPerMinute', 'RR', '/min'),
    ('spo2', 'SpO2', '%'),
  ];

  @override
  void initState() {
    super.initState();
    final v = widget.value ?? {};
    _tempCtrl  = TextEditingController(text: v['temperature']?.toString() ?? '');
    _pulseCtrl = TextEditingController(text: v['pulse']?.toString() ?? '');
    _rrCtrl    = TextEditingController(text: v['breathsPerMinute']?.toString() ?? '');
    _spo2Ctrl  = TextEditingController(text: v['spo2']?.toString() ?? '');
  }

  @override
  void dispose() {
    _tempCtrl.dispose();
    _pulseCtrl.dispose();
    _rrCtrl.dispose();
    _spo2Ctrl.dispose();
    super.dispose();
  }

  TextEditingController _ctrlFor(String key) {
    return switch (key) {
      'temperature'       => _tempCtrl,
      'pulse'             => _pulseCtrl,
      'breathsPerMinute'  => _rrCtrl,
      _                   => _spo2Ctrl,
    };
  }

  void _emit() {
    final result = <String, dynamic>{};
    for (final (key, _, _) in _vitalDefs) {
      final v = double.tryParse(_ctrlFor(key).text);
      if (v != null) result[key] = v;
    }
    if (result.isNotEmpty) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(schema: widget.schema, fallback: 'Vitals'),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            for (final (key, label, unit) in _vitalDefs)
              _VitalCell(
                ctrl: _ctrlFor(key),
                label: label,
                unit: unit,
                vitalKey: key,
                readOnly: widget.readOnly,
                onChanged: (_) => _emit(),
              ),
          ],
        ),
      ],
    );
  }
}

class _VitalCell extends StatelessWidget {
  const _VitalCell({
    required this.ctrl,
    required this.label,
    required this.unit,
    required this.vitalKey,
    required this.onChanged,
    this.readOnly = false,
  });

  final TextEditingController ctrl;
  final String label;
  final String unit;
  final String vitalKey;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: ctrl,
      builder: (context, textValue, _) {
        final rawValue = double.tryParse(textValue.text);
        final flag = _flagFor(vitalKey, rawValue);
        return _buildCell(flag);
      },
    );
  }

  Widget _buildCell((String, Color)? flag) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: AppShadows.statBox,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: ctrl,
            readOnly: readOnly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.center,
            style: AppTextStyles.vitalValue,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: '—',
              hintStyle: AppTextStyles.vitalValue.copyWith(
                color: AppColors.textMuted,
              ),
              suffix: flag == null
                  ? Text(unit, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(unit, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        const SizedBox(width: 4),
                        _VitalBadge(label: flag.$1, color: flag.$2),
                      ],
                    ),
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: onChanged,
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  static (String, Color)? _flagFor(String key, double? value) {
    if (value == null) return null;
    switch (key) {
      case 'temperature':
        if (value < 35.0 || value > 38.5) return (value > 38.5 ? 'High ⚠' : 'Low ⚠', AppColors.rangeCritical);
        if (value < 35.5 || value > 37.5) return (value > 37.5 ? 'High ⚠' : 'Low ⚠', AppColors.rangeElevated);
      case 'pulse':
        if (value < 50 || value > 120) return (value > 120 ? 'High ⚠' : 'Low ⚠', AppColors.rangeCritical);
        if (value < 60 || value > 100) return (value > 100 ? 'High ⚠' : 'Low ⚠', AppColors.rangeElevated);
      case 'breathsPerMinute':
        if (value < 8 || value > 30) return (value > 30 ? 'High ⚠' : 'Low ⚠', AppColors.rangeCritical);
        if (value < 12 || value > 20) return (value > 20 ? 'High ⚠' : 'Low ⚠', AppColors.rangeElevated);
      case 'spo2':
      case 'SpO2':
        if (value < 90) return ('Low ⚠', AppColors.rangeCritical);
        if (value < 95) return ('Low ⚠', AppColors.rangeElevated);
    }
    return null;
  }
}

class _VitalBadge extends StatelessWidget {
  const _VitalBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
