/// Years / Months / Days trio field — API viewType `AgeYMD`.
///
/// Three side-by-side numeric inputs for entering age as years, months, and
/// days. Value is serialized as `"Yy Mm Dd"` (e.g. `"2y 3m 14d"`) via
/// [onChanged] whenever all three fields hold a valid value.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

class AgeYmdField extends StatefulWidget {
  const AgeYmdField({
    super.key,
    required this.labelText,
    required this.onChanged,
    this.currentValue,
  });

  final String labelText;

  /// Serialized as `"Yy Mm Dd"` or null.
  final String? currentValue;

  final ValueChanged<String> onChanged;

  @override
  State<AgeYmdField> createState() => _AgeYmdFieldState();
}

class _AgeYmdFieldState extends State<AgeYmdField> {
  late final TextEditingController _yCtrl;
  late final TextEditingController _mCtrl;
  late final TextEditingController _dCtrl;

  @override
  void initState() {
    super.initState();
    int y = 0, m = 0, d = 0;
    final v = widget.currentValue;
    if (v != null) {
      final yMatch = RegExp(r'(\d+)y').firstMatch(v);
      final mMatch = RegExp(r'(\d+)m').firstMatch(v);
      final dMatch = RegExp(r'(\d+)d').firstMatch(v);
      if (yMatch != null) y = int.tryParse(yMatch.group(1)!) ?? 0;
      if (mMatch != null) m = int.tryParse(mMatch.group(1)!) ?? 0;
      if (dMatch != null) d = int.tryParse(dMatch.group(1)!) ?? 0;
    }
    _yCtrl = TextEditingController(text: y > 0 ? '$y' : '');
    _mCtrl = TextEditingController(text: m > 0 ? '$m' : '');
    _dCtrl = TextEditingController(text: d > 0 ? '$d' : '');
  }

  @override
  void dispose() {
    _yCtrl.dispose();
    _mCtrl.dispose();
    _dCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final y = int.tryParse(_yCtrl.text) ?? 0;
    final m = int.tryParse(_mCtrl.text) ?? 0;
    final d = int.tryParse(_dCtrl.text) ?? 0;
    if (y == 0 && m == 0 && d == 0) return;
    widget.onChanged('${y}y ${m}m ${d}d');
  }

  Widget _unitInput({
    required TextEditingController ctrl,
    required String label,
    required int max,
  }) {
    return Expanded(
      child: Column(
        children: [
          TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 9,
              ),
            ),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
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
            _unitInput(
              ctrl: _yCtrl,
              label: ComposerStrings.yearsShort,
              max: 120,
            ),
            const SizedBox(width: 8),
            _unitInput(
              ctrl: _mCtrl,
              label: ComposerStrings.monthsShort,
              max: 11,
            ),
            const SizedBox(width: 8),
            _unitInput(
              ctrl: _dCtrl,
              label: ComposerStrings.daysShort,
              max: 30,
            ),
          ],
        ),
      ],
    );
  }
}
