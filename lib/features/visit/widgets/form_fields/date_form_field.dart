/// Date picker form field — API viewType `DatePicker`.
///
/// Renders as a read-only [TextFormField] with a calendar icon. Tapping opens
/// Flutter's [showDatePicker]. Selected date is serialized as an ISO-8601 date
/// string (`yyyy-MM-dd`) via [onChanged].
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_strings.dart';

class DateFormField extends StatefulWidget {
  const DateFormField({
    super.key,
    required this.labelText,
    required this.onChanged,
    this.currentValue,
    this.hint,
    this.firstDate,
    this.lastDate,
  });

  final String labelText;

  /// ISO-8601 date string (`yyyy-MM-dd`) or null if not yet selected.
  final String? currentValue;

  /// Emits an ISO-8601 date string on selection.
  final ValueChanged<String> onChanged;

  /// Overrides the default "Select date" placeholder.
  final String? hint;

  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<DateFormField> createState() => _DateFormFieldState();
}

class _DateFormFieldState extends State<DateFormField> {
  static final _displayFormat = DateFormat('dd MMM yyyy');
  static final _isoFormat = DateFormat('yyyy-MM-dd');

  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatDisplay(widget.currentValue));
  }

  @override
  void didUpdateWidget(DateFormField old) {
    super.didUpdateWidget(old);
    if (old.currentValue != widget.currentValue) {
      _ctrl.text = _formatDisplay(widget.currentValue);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatDisplay(String? iso) {
    if (iso == null) return '';
    try {
      return _displayFormat.format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  Future<void> _pickDate() async {
    final initial = widget.currentValue != null
        ? DateTime.tryParse(widget.currentValue!) ?? DateTime.now()
        : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: widget.firstDate ?? DateTime(1900),
      lastDate:
          widget.lastDate ?? DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null) {
      widget.onChanged(_isoFormat.format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: _ctrl,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hint ?? ComposerStrings.selectDateHint,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      onTap: _pickDate,
    );
  }
}
