/// Age + DOB hybrid field — API viewType `AgeOrDob` / `AgeYMD` (ageOfLastChild).
///
/// Matches Add Member: both DOB and Age stay visible in one row. Picking DOB
/// fills age; typing age (whole years) fills DOB as 1 January of
/// (current year − age). The canonical value is always a date string
/// (`yyyy-MM-dd` or an Android UTC timestamp) so existing `_asDobWire` save
/// paths keep working unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../household/enrollment/enrollment_dob.dart';

class AgeOrDobField extends StatefulWidget {
  const AgeOrDobField({
    super.key,
    required this.onChanged,
    this.currentValue,
    this.maxAgeYears = EnrollmentDob.maxAgeYears,
  });

  /// Date string (ISO / Android wire) or a whole-years age left by older drafts.
  final String? currentValue;

  /// Emits a `yyyy-MM-dd` DOB, or `null` when cleared.
  final ValueChanged<String?> onChanged;

  /// Cap for typed age (Android FP `ageOfLastChild` uses 18).
  final int maxAgeYears;

  @override
  State<AgeOrDobField> createState() => _AgeOrDobFieldState();
}

class _AgeOrDobFieldState extends State<AgeOrDobField> {
  late final TextEditingController _dobCtrl;
  late final TextEditingController _ageCtrl;
  DateTime? _dob;
  String _ageUnit = '';
  bool _syncing = false;

  static const _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  @override
  void initState() {
    super.initState();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();
    _applyIncoming(widget.currentValue, emit: false);
  }

  @override
  void didUpdateWidget(AgeOrDobField old) {
    super.didUpdateWidget(old);
    if (old.currentValue != widget.currentValue) {
      final incoming = EnrollmentDob.parse(widget.currentValue);
      // Avoid clobbering in-progress typing when the parent echoes our emit.
      if (incoming != null &&
          _dob != null &&
          incoming.year == _dob!.year &&
          incoming.month == _dob!.month &&
          incoming.day == _dob!.day) {
        return;
      }
      if (widget.currentValue == null && _dob == null && _ageCtrl.text.isEmpty) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyIncoming(widget.currentValue, emit: false);
      });
    }
  }

  @override
  void dispose() {
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  void _applyIncoming(String? raw, {required bool emit}) {
    final trimmed = raw?.toString().trim() ?? '';
    if (trimmed.isEmpty) {
      _dob = null;
      _dobCtrl.text = '';
      _ageCtrl.text = '';
      _ageUnit = '';
      if (mounted) setState(() {});
      return;
    }

    final asYears = int.tryParse(trimmed);
    if (asYears != null && !trimmed.contains('-') && !trimmed.contains('/')) {
      _applyAgeYears(asYears, emit: emit);
      return;
    }

    final dob = EnrollmentDob.parse(trimmed);
    if (dob != null) {
      _applyDob(dob, emit: emit);
    }
  }

  void _applyDob(DateTime dob, {required bool emit}) {
    _syncing = true;
    _dob = dob;
    _dobCtrl.text = EnrollmentDob.display(dob);
    final age = EnrollmentAge.from(dob);
    // Age field always shows whole years for typed/manual parity with Add
    // Member when years >= 1; under 1 year show months/days like enrollment.
    if (age.years >= 1) {
      _ageCtrl.text = age.years.toString();
      _ageUnit = age.years == 1 ? EnrollmentStrings.ageUnitYear : EnrollmentStrings.ageUnitYears;
    } else {
      _ageCtrl.text = age.value.toString();
      _ageUnit = age.unit;
    }
    _syncing = false;
    if (mounted) setState(() {});
    if (emit) widget.onChanged(EnrollmentDob.wire(dob));
  }

  void _applyAgeYears(int years, {required bool emit}) {
    final clamped = years < 0
        ? 0
        : (years > widget.maxAgeYears ? widget.maxAgeYears : years);
    _syncing = true;
    _dob = EnrollmentDob.fromAgeYears(clamped);
    _dobCtrl.text = EnrollmentDob.display(_dob!);
    _ageCtrl.text = clamped.toString();
    _ageUnit = clamped == 1 ? EnrollmentStrings.ageUnitYear : EnrollmentStrings.ageUnitYears;
    _syncing = false;
    if (mounted) setState(() {});
    if (emit) widget.onChanged(EnrollmentDob.wire(_dob!));
  }

  void _clear({required bool emit}) {
    _syncing = true;
    _dob = null;
    _dobCtrl.text = '';
    _ageCtrl.text = '';
    _ageUnit = '';
    _syncing = false;
    if (mounted) setState(() {});
    if (emit) widget.onChanged(null);
  }

  Future<void> _pickDob() async {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final first = EnrollmentDob.earliestBirthDate();
    // Last child cannot be older than [maxAgeYears] when capped below 130.
    final earliestForChild = widget.maxAgeYears < EnrollmentDob.maxAgeYears
        ? DateTime(today.year - widget.maxAgeYears, today.month, today.day)
        : first;
    final firstDate =
        earliestForChild.isAfter(first) ? earliestForChild : first;
    var initial = _dob ?? todayStart;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(todayStart)) initial = todayStart;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: todayStart,
    );
    if (picked != null) _applyDob(picked, emit: true);
  }

  void _onAgeChanged(String raw) {
    if (_syncing) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _clear(emit: true);
      return;
    }
    final years = int.tryParse(trimmed);
    if (years == null) return;
    _applyAgeYears(years, emit: true);
  }

  InputDecoration _decoration({
    String? hintText,
    String? suffixText,
    Widget? suffixIcon,
  }) {
    final enabled = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: const BorderSide(color: AppColors.border, width: 1),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: AppColors.cardSurfaceMuted,
      hintText: hintText,
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      border: enabled,
      enabledBorder: enabled,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(EnrollmentStrings.dateOfBirthLabel, style: _labelStyle),
              const SizedBox(height: 5),
              GestureDetector(
                onTap: _pickDob,
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: _dobCtrl,
                    readOnly: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: _decoration(
                      hintText: EnrollmentStrings.dateOfBirthHint,
                      suffixIcon: const Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _ageUnit.isEmpty
                    ? EnrollmentStrings.ageLabel
                    : '${EnrollmentStrings.ageLabel} ($_ageUnit)',
                style: _labelStyle,
              ),
              const SizedBox(height: 5),
              TextFormField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: _decoration(
                  hintText: EnrollmentStrings.ageHint,
                ),
                onChanged: _onAgeChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
