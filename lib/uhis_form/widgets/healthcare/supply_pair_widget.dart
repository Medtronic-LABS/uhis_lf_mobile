/// Supply pair composite widget — [FieldKind.supplyPair].
///
/// Consumed (last month) + Provided today pair on one row.
/// Value shape: `{"consumed": 30, "provided": 30}`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';

class SupplyPairWidget extends StatefulWidget {
  const SupplyPairWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;

  /// Map with keys 'consumed' and 'provided' (int values).
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<SupplyPairWidget> createState() => _SupplyPairWidgetState();
}

class _SupplyPairWidgetState extends State<SupplyPairWidget> {
  late final TextEditingController _consumedCtrl;
  late final TextEditingController _providedCtrl;

  @override
  void initState() {
    super.initState();
    _consumedCtrl = TextEditingController(
        text: widget.value?['consumed']?.toString() ?? '');
    _providedCtrl = TextEditingController(
        text: widget.value?['provided']?.toString() ?? '');
  }

  @override
  void dispose() {
    _consumedCtrl.dispose();
    _providedCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final c = int.tryParse(_consumedCtrl.text);
    final p = int.tryParse(_providedCtrl.text);
    final result = <String, dynamic>{};
    if (c != null) result['consumed'] = c;
    if (p != null) result['provided'] = p;
    if (result.isNotEmpty) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.schema.label,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SupplyInput(
                ctrl: _consumedCtrl,
                label: 'Consumed',
                readOnly: widget.readOnly,
                onChanged: (_) => _emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SupplyInput(
                ctrl: _providedCtrl,
                label: 'Provided today',
                readOnly: widget.readOnly,
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SupplyInput extends StatelessWidget {
  const _SupplyInput({
    required this.ctrl,
    required this.label,
    required this.onChanged,
    this.readOnly = false,
  });

  final TextEditingController ctrl;
  final String label;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: ctrl,
          readOnly: readOnly,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding:
                EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
