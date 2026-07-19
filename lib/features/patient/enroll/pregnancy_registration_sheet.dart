import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../../core/mission/mission_pregnancy_facts.dart';

/// Bottom sheet for first-time pregnancy registration.
///
/// Shown after ANC is selected in [ProgrammeEnrollScreen].
/// Collects LMP → auto-computes EDD + gestational age.
/// Gravida/parity captured for the first ANC visit form.
/// Saves [PregnancySnapshotRow] (lmpDate, eddDate, highRisk) locally.
///
/// Returns [PregnancyRegistrationResult] on pop or null if skipped.
class PregnancyRegistrationSheet extends StatefulWidget {
  const PregnancyRegistrationSheet({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientAge,
  });

  final String patientId;
  final String patientName;
  final int? patientAge;

  static Future<PregnancyRegistrationResult?> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
    int? patientAge,
  }) {
    return showModalBottomSheet<PregnancyRegistrationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PregnancyRegistrationSheet(
        patientId: patientId,
        patientName: patientName,
        patientAge: patientAge,
      ),
    );
  }

  @override
  State<PregnancyRegistrationSheet> createState() =>
      _PregnancyRegistrationSheetState();
}

class _PregnancyRegistrationSheetState
    extends State<PregnancyRegistrationSheet> {
  DateTime? _lmp;
  int _gravida = 1;
  int _parity = 0;
  bool _condHtn = false;
  bool _condDiabetes = false;
  bool _condCsection = false;
  bool _condComplicated = false;
  bool _saving = false;

  // ---------------------------------------------------------------------------
  // Derived values
  // ---------------------------------------------------------------------------

  DateTime? get _edd => _lmp?.add(const Duration(days: 280));

  int? get _gaWeeks {
    if (_lmp == null) return null;
    return DateTime.now().difference(_lmp!).inDays ~/ 7;
  }

  int? get _gaDays {
    if (_lmp == null) return null;
    return DateTime.now().difference(_lmp!).inDays % 7;
  }

  bool get _tooEarly {
    if (_lmp == null) return false;
    return DateTime.now().difference(_lmp!).inDays < 42;
  }

  bool get _isHighRisk {
    final age = widget.patientAge ?? 0;
    return age < 18 ||
        age > 35 ||
        _gravida > 4 ||
        _condHtn ||
        _condDiabetes ||
        _condCsection ||
        _condComplicated;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _pickLmp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lmp ?? now.subtract(const Duration(days: 60)),
      firstDate: now.subtract(const Duration(days: 280)),
      lastDate: now,
      helpText: PregnancyRegStrings.lmpLabel,
    );
    if (picked != null) setState(() => _lmp = picked);
  }

  Future<void> _save() async {
    debugPrint('[_PregnancyRegistrationSheetState] _save patientId=${widget.patientId}');
    if (_lmp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PregnancyRegStrings.lmpRequiredError)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final dao = context.read<PregnancySnapshotDao>();
      final row = PregnancySnapshotRow(
        patientId: widget.patientId,
        facts: PregnancyFacts(
          highRiskPregnantWoman: _isHighRisk,
          hasGapsInAnc: false,
          isPostpartumWindow: false,
          isNearTermAnc: (_gaWeeks ?? 0) >= 36,
          hadDeliveryComplications: _condComplicated || _condCsection,
          hasPncIllness: false,
        ),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        lmpDate: _lmp!.millisecondsSinceEpoch,
        eddDate: _edd?.millisecondsSinceEpoch,
      );
      await dao.upsertOne(row);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PregnancyRegStrings.savedToast)),
      );
      Navigator.of(context).pop(PregnancyRegistrationResult(
        lmp: _lmp!,
        edd: _edd,
        gravida: _gravida,
        parity: _parity,
        isHighRisk: _isHighRisk,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF2F8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('🤰', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        PregnancyRegStrings.sheetTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B2B5E),
                        ),
                      ),
                      Text(
                        PregnancyRegStrings.forPatient(widget.patientName),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                const _SectionHeader(PregnancyRegStrings.sectionDates),
                const SizedBox(height: 12),
                _LmpField(lmp: _lmp, onTap: _pickLmp),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _InfoChip(
                        label: PregnancyRegStrings.eddLabel,
                        value: _edd == null ? '—' : _formatDate(_edd!),
                        color: const Color(0xFFFDF2F8),
                        borderColor: const Color(0xFFF9A8D4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoChip(
                        label: PregnancyRegStrings.gaLabel,
                        value: _lmp == null
                            ? '—'
                            : '${_gaWeeks}w ${_gaDays}d',
                        color: const Color(0xFFEFF6FF),
                        borderColor: const Color(0xFF93C5FD),
                      ),
                    ),
                  ],
                ),
                if (_tooEarly) ...[
                  const SizedBox(height: 10),
                  const _TooEarlyBanner(),
                ],
                const SizedBox(height: 24),
                const _SectionHeader(PregnancyRegStrings.sectionHistory),
                const SizedBox(height: 12),
                _StepperField(
                  label: PregnancyRegStrings.gravidaLabel,
                  value: _gravida,
                  min: 1,
                  max: 12,
                  valueLabel: _gravida == 1
                      ? PregnancyRegStrings.firstPregnancy
                      : '$_gravida',
                  onChanged: (v) => setState(() => _gravida = v),
                ),
                const SizedBox(height: 12),
                _StepperField(
                  label: PregnancyRegStrings.parityLabel,
                  value: _parity,
                  min: 0,
                  max: 11,
                  valueLabel: '$_parity',
                  onChanged: (v) => setState(() => _parity = v),
                ),
                if (_gravida > 4) ...[
                  const SizedBox(height: 8),
                  const _WarningChip(PregnancyRegStrings.multiparaWarning),
                ],
                if (!_tooEarly) ...[
                  const SizedBox(height: 24),
                  const _SectionHeader(PregnancyRegStrings.sectionRisk),
                  const SizedBox(height: 12),
                  _AgeRiskChip(age: widget.patientAge),
                  const SizedBox(height: 12),
                  const Text(
                    PregnancyRegStrings.conditionsLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ConditionCheck(
                    label: PregnancyRegStrings.conditionHtn,
                    value: _condHtn,
                    onChanged: (v) => setState(() => _condHtn = v),
                  ),
                  _ConditionCheck(
                    label: PregnancyRegStrings.conditionDiabetes,
                    value: _condDiabetes,
                    onChanged: (v) => setState(() => _condDiabetes = v),
                  ),
                  _ConditionCheck(
                    label: PregnancyRegStrings.conditionCsection,
                    value: _condCsection,
                    onChanged: (v) => setState(() => _condCsection = v),
                  ),
                  _ConditionCheck(
                    label: PregnancyRegStrings.conditionComplicated,
                    value: _condComplicated,
                    onChanged: (v) => setState(() => _condComplicated = v),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEC4899),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          PregnancyRegStrings.registerCta,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    PregnancyRegStrings.skipCta,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} '
      '${_monthName(d.month)} ${d.year}';

  String _monthName(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m];
}

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

class PregnancyRegistrationResult {
  const PregnancyRegistrationResult({
    required this.lmp,
    required this.edd,
    required this.gravida,
    required this.parity,
    required this.isHighRisk,
  });

  final DateTime lmp;
  final DateTime? edd;
  final int gravida;
  final int parity;
  final bool isHighRisk;
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1B2B5E),
          letterSpacing: 0.8,
        ),
      );
}

class _LmpField extends StatelessWidget {
  const _LmpField({required this.lmp, required this.onTap});
  final DateTime? lmp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: lmp != null
                ? const Color(0xFFF9A8D4)
                : const Color(0xFFE5E7EB),
            width: lmp != null ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: Color(0xFF9D174D)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    PregnancyRegStrings.lmpLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9D174D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lmp == null
                        ? PregnancyRegStrings.lmpHint
                        : '${lmp!.day.toString().padLeft(2, '0')} / '
                            '${lmp!.month.toString().padLeft(2, '0')} / '
                            '${lmp!.year}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: lmp == null
                          ? Colors.grey.shade400
                          : const Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    required this.color,
    required this.borderColor,
  });

  final String label;
  final String value;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2B5E),
            ),
          ),
        ],
      ),
    );
  }
}

class _TooEarlyBanner extends StatelessWidget {
  const _TooEarlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠', style: TextStyle(fontSize: 14)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              PregnancyRegStrings.tooEarlyWarning,
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF92400E),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperField extends StatelessWidget {
  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String valueLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StepBtn(
              icon: Icons.remove,
              onTap: value > min ? () => onChanged(value - 1) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                ),
                child: Text(
                  valueLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B2B5E),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _StepBtn(
              icon: Icons.add,
              onTap: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color:
              onTap != null ? const Color(0xFF1B2B5E) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? Colors.white : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF92400E),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AgeRiskChip extends StatelessWidget {
  const _AgeRiskChip({this.age});
  final int? age;

  @override
  Widget build(BuildContext context) {
    if (age == null) return const SizedBox.shrink();
    final isLow = age! < 18;
    final isHigh = age! > 35;
    final isRisk = isLow || isHigh;
    final label = isLow
        ? PregnancyRegStrings.ageRiskLow(age!)
        : isHigh
            ? PregnancyRegStrings.ageRiskHigh(age!)
            : PregnancyRegStrings.ageRiskNormal(age!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isRisk ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              isRisk ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isRisk
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            size: 16,
            color: isRisk
                ? const Color(0xFF991B1B)
                : const Color(0xFF065F46),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isRisk
                  ? const Color(0xFF991B1B)
                  : const Color(0xFF065F46),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionCheck extends StatelessWidget {
  const _ConditionCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? const Color(0xFFEC4899) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value
                      ? const Color(0xFFEC4899)
                      : const Color(0xFFD1D5DB),
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
