/// Age-or-DOB hybrid field — API viewType `AgeOrDob`.
///
/// Two-mode segmented widget: the SK picks "Age" (integer number of years) or
/// "Date of Birth" (date picker). In Age mode the value serializes as a plain
/// integer string (`"32"`); in DOB mode as an ISO-8601 date (`"1992-03-15"`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

enum _AgeMode { age, dob }

class AgeOrDobField extends StatefulWidget {
  const AgeOrDobField({
    super.key,
    required this.labelText,
    required this.onChanged,
    this.currentValue,
  });

  final String labelText;

  /// Plain integer string (age mode) or ISO-8601 date string (DOB mode).
  final String? currentValue;

  final ValueChanged<String> onChanged;

  @override
  State<AgeOrDobField> createState() => _AgeOrDobFieldState();
}

class _AgeOrDobFieldState extends State<AgeOrDobField> {
  late _AgeMode _mode;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _dobCtrl;

  static final _displayFormat = DateFormat('dd MMM yyyy');
  static final _isoFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    final v = widget.currentValue;
    if (v != null && v.contains('-') && v.length > 4) {
      _mode = _AgeMode.dob;
      _ageCtrl = TextEditingController();
      _dobCtrl = TextEditingController(text: _formatDob(v));
    } else {
      _mode = _AgeMode.age;
      _ageCtrl = TextEditingController(text: v ?? '');
      _dobCtrl = TextEditingController();
    }
  }

  @override
  void didUpdateWidget(AgeOrDobField old) {
    super.didUpdateWidget(old);
    if (old.currentValue != widget.currentValue && _mode == _AgeMode.dob) {
      _dobCtrl.text = _formatDob(widget.currentValue);
    }
  }

  @override
  void dispose() {
    _ageCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  String _formatDob(String? iso) {
    if (iso == null || !iso.contains('-')) return '';
    try {
      return _displayFormat.format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  Future<void> _pickDob() async {
    final initial = widget.currentValue != null
        ? DateTime.tryParse(widget.currentValue!) ??
            DateTime.now().subtract(const Duration(days: 365 * 25))
        : DateTime.now().subtract(const Duration(days: 365 * 25));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      widget.onChanged(_isoFormat.format(picked));
    }
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
        const SizedBox(height: 8),
        SegmentedButton<_AgeMode>(
          segments: const [
            ButtonSegment(value: _AgeMode.age, label: Text(ComposerStrings.ageLabel)),
            ButtonSegment(value: _AgeMode.dob, label: Text(ComposerStrings.dobLabel)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            setState(() {
              _mode = s.first;
              _ageCtrl.clear();
              _dobCtrl.clear();
            });
          },
        ),
        const SizedBox(height: 8),
        if (_mode == _AgeMode.age)
          TextFormField(
            controller: _ageCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '0–120',
              suffixText: 'yrs',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
            ),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n >= 0 && n <= 120) widget.onChanged(v);
            },
          )
        else
          TextFormField(
            readOnly: true,
            controller: _dobCtrl,
            decoration: InputDecoration(
              hintText: ComposerStrings.selectDateHint,
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
            ),
            onTap: _pickDob,
          ),
      ],
    );
  }
}
