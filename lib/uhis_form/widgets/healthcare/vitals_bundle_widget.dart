/// Vitals bundle composite widget — [FieldKind.vitalsBundle].
///
/// Four tap-to-edit cells in a 2×2 grid: Temperature · Pulse · RR · SpO2.
/// Value shape: `{"temperature": 37.2, "pulse": 88, "breathsPerMinute": 24, "spo2": 97}`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.schema.label.isEmpty ? 'Vitals' : widget.schema.label,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
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
    required this.onChanged,
    this.readOnly = false,
  });

  final TextEditingController ctrl;
  final String label;
  final String unit;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
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
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: '—',
              hintStyle: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textMuted,
              ),
              suffixText: unit,
              suffixStyle: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: onChanged,
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
