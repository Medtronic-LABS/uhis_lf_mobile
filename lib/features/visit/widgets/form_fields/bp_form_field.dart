/// Blood pressure form field — API viewType `BP`.
///
/// Renders two side-by-side numeric inputs (systolic / diastolic) separated by
/// a "/" divider, with a "mmHg" suffix. Value is serialized as `"sys/dia"`
/// (e.g. `"144/91"`) via [onChanged]. Validates each reading is within the
/// clinically safe range.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

class BpFormField extends StatefulWidget {
  const BpFormField({
    super.key,
    required this.labelText,
    required this.onChanged,
    this.currentValue,
  });

  final String labelText;

  /// Serialized as `"systolic/diastolic"` or null.
  final String? currentValue;

  /// Emits `"sys/dia"` string on every valid change.
  final ValueChanged<String> onChanged;

  @override
  State<BpFormField> createState() => _BpFormFieldState();
}

class _BpFormFieldState extends State<BpFormField> {
  late final TextEditingController _sysCtrl;
  late final TextEditingController _diaCtrl;

  @override
  void initState() {
    super.initState();
    final parts = widget.currentValue?.split('/');
    _sysCtrl = TextEditingController(
      text: parts != null && parts.length == 2 ? parts[0] : '',
    );
    _diaCtrl = TextEditingController(
      text: parts != null && parts.length == 2 ? parts[1] : '',
    );
  }

  @override
  void dispose() {
    _sysCtrl.dispose();
    _diaCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final sys = int.tryParse(_sysCtrl.text);
    final dia = int.tryParse(_diaCtrl.text);
    if (sys != null && dia != null) {
      widget.onChanged('$sys/$dia');
    }
  }

  String? _validateSystolic(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < 60 || n > 250) return ComposerStrings.bpValidationError;
    return null;
  }

  String? _validateDiastolic(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < 40 || n > 150) return ComposerStrings.bpValidationError;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.labelText,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _sysCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: ComposerStrings.bpSystolicHint,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                validator: _validateSystolic,
                onChanged: (_) => _emit(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text(
                '/',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: TextFormField(
                controller: _diaCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: ComposerStrings.bpDiastolicHint,
                  border: const OutlineInputBorder(),
                  suffixText: ComposerStrings.bpUnit,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                validator: _validateDiastolic,
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
