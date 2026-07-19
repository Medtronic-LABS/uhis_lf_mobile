import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/patient_programmes_dao.dart';
import '../../../core/models/programme.dart';
import '../../../core/theme/app_theme.dart' show LeapfrogColors;
import 'pregnancy_registration_sheet.dart';

/// First-time programme enrollment screen.
///
/// Shows health programmes filtered by the patient's gender and age.
/// ANC and PNC are gated behind a "Pregnant Woman" toggle (female + age 10-49).
/// Selections are persisted to [PatientProgrammesDao] on confirm.
class ProgrammeEnrollScreen extends StatefulWidget {
  const ProgrammeEnrollScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientAge,
    this.patientGender,
    this.villageName,
    this.existingProgrammes = const {},
  });

  final String patientId;
  final String patientName;
  final int? patientAge;
  final String? patientGender;
  final String? villageName;
  final Set<Programme> existingProgrammes;

  @override
  State<ProgrammeEnrollScreen> createState() => _ProgrammeEnrollScreenState();
}

class _ProgrammeEnrollScreenState extends State<ProgrammeEnrollScreen> {
  bool _pregnantWoman = false;
  final Set<Programme> _selected = {};
  bool _saving = false;

  bool get _isFemale {
    final g = (widget.patientGender ?? '').toUpperCase().trim();
    return g == 'F' ||
        g == 'FEMALE' ||
        g == 'WOMAN' ||
        g == 'W' ||
        g.startsWith('F');
  }

  /// Null = unknown age. Filters treat unknown age conservatively:
  /// - show adult programmes (NCD/TB) → yes
  /// - show child programmes (IMCI/EPI) → only if explicitly < 5
  /// - show pregnancy section → yes if female
  int? get _ageOrNull => widget.patientAge;
  int get _age => widget.patientAge ?? 0;

  // Show pregnancy section if female + age unknown OR age in [10-49]
  bool get _showPregnancySection =>
      _isFemale && (_ageOrNull == null || (_age >= 10 && _age <= 49));

  // Child section only when age is known AND < 5
  bool get _showChildSection => _ageOrNull != null && _age < 5;

  // NCD shown when age unknown (assume adult) or >= 18
  bool get _showNcd => _ageOrNull == null || _age >= 18;

  String get _subtitle {
    final parts = <String>[];
    if (_age > 0) parts.add('Age $_age');
    if (widget.patientGender != null) parts.add(widget.patientGender!);
    if (widget.villageName != null) parts.add(widget.villageName!);
    return parts.join(' · ');
  }

  void _togglePregnantWoman(bool v) {
    debugPrint('[_ProgrammeEnrollScreenState] _togglePregnantWoman v=$v');
    setState(() {
      _pregnantWoman = v;
      if (!v) {
        _selected.remove(Programme.anc);
        _selected.remove(Programme.pnc);
      }
    });
  }

  void _toggleProgramme(Programme p) {
    debugPrint('[_ProgrammeEnrollScreenState] _toggleProgramme p=$p');
    if (p == Programme.anc || p == Programme.pnc) {
      if (!_pregnantWoman) {
        final msg = p == Programme.anc
            ? EnrollStrings.lockedToastAnc
            : EnrollStrings.lockedToastPnc;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        return;
      }
    }
    setState(() {
      if (_selected.contains(p)) {
        _selected.remove(p);
      } else {
        _selected.add(p);
      }
    });
  }

  Future<void> _confirm() async {
    debugPrint('[_ProgrammeEnrollScreenState] _confirm patientId=${widget.patientId} selected=$_selected');
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      final dao = context.read<PatientProgrammesDao>();
      final merged = {...widget.existingProgrammes, ..._selected};
      await dao.replaceFor(widget.patientId, merged);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(EnrollStrings.savedToast)),
      );
      // ANC newly selected → collect pregnancy details before leaving.
      final needsPregnancyReg = _selected.contains(Programme.anc) &&
          !widget.existingProgrammes.contains(Programme.anc);
      if (needsPregnancyReg && mounted) {
        Navigator.of(context).pop(merged);
        await PregnancyRegistrationSheet.show(
          context,
          patientId: widget.patientId,
          patientName: widget.patientName,
          patientAge: widget.patientAge,
        );
        return;
      }
      Navigator.of(context).pop(merged);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B2B5E),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.patientName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            if (_subtitle.isNotEmpty)
              Text(
                _subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              children: [
                _HeaderSection(patientName: widget.patientName),
                const SizedBox(height: 20),
                if (_showPregnancySection) ...[
                  const _SectionLabel(EnrollStrings.sectionPregnancy),
                  const SizedBox(height: 10),
                  _PregnantWomanTile(
                    value: _pregnantWoman,
                    onChanged: _togglePregnantWoman,
                  ),
                  if (_pregnantWoman) ...[
                    const SizedBox(height: 10),
                    _TwocolGrid(children: [
                      _ProgrammeTile(
                        programme: Programme.anc,
                        emoji: '🩺',
                        label: EnrollStrings.ancLabel,
                        bengali: EnrollStrings.ancBengali,
                        bg: const Color(0xFFFDF2F8),
                        border: const Color(0xFFF9A8D4),
                        textColor: const Color(0xFF9D174D),
                        selected: _selected.contains(Programme.anc),
                        onTap: () => _toggleProgramme(Programme.anc),
                      ),
                      _ProgrammeTile(
                        programme: Programme.pnc,
                        emoji: '👶',
                        label: EnrollStrings.pncLabel,
                        bengali: EnrollStrings.pncBengali,
                        bg: const Color(0xFFF5F3FF),
                        border: const Color(0xFFC4B5FD),
                        textColor: const Color(0xFF4C1D95),
                        selected: _selected.contains(Programme.pnc),
                        onTap: () => _toggleProgramme(Programme.pnc),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 20),
                ],
                if (_showNcd) ...[
                  const _SectionLabel(EnrollStrings.sectionChronic),
                  const SizedBox(height: 10),
                  _TwocolGrid(children: [
                    _ProgrammeTile(
                      programme: Programme.ncd,
                      emoji: '💊',
                      label: EnrollStrings.ncdLabel,
                      bengali: EnrollStrings.ncdBengali,
                      bg: const Color(0xFFFFF7ED),
                      border: const Color(0xFFFCD34D),
                      textColor: const Color(0xFF92400E),
                      selected: _selected.contains(Programme.ncd),
                      onTap: () => _toggleProgramme(Programme.ncd),
                    ),
                  ]),
                ],
                if (_showChildSection) ...[
                  const SizedBox(height: 20),
                  const _SectionLabel(EnrollStrings.sectionChild),
                  const SizedBox(height: 10),
                  _TwocolGrid(children: [
                    _ProgrammeTile(
                      programme: Programme.imci,
                      emoji: '🧒',
                      label: EnrollStrings.imciLabel,
                      bengali: EnrollStrings.imciBengali,
                      bg: const Color(0xFFEFF6FF),
                      border: const Color(0xFF93C5FD),
                      textColor: const Color(0xFF1E40AF),
                      selected: _selected.contains(Programme.imci),
                      onTap: () => _toggleProgramme(Programme.imci),
                    ),
                    _ProgrammeTile(
                      programme: Programme.epi,
                      emoji: '💉',
                      label: EnrollStrings.epiLabel,
                      bengali: EnrollStrings.epiBengali,
                      bg: const Color(0xFFEFF6FF),
                      border: const Color(0xFF93C5FD),
                      textColor: const Color(0xFF1E40AF),
                      selected: _selected.contains(Programme.epi),
                      onTap: () => _toggleProgramme(Programme.epi),
                    ),
                  ]),
                ],
                if (!_showPregnancySection && !_showChildSection && !_showNcd)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        EnrollStrings.noProgrammes,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _ConfirmBar(
            selectedCount: _selected.length,
            saving: _saving,
            onConfirm: _selected.isEmpty ? null : _confirm,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.patientName});
  final String patientName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          EnrollStrings.selectFor(patientName),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1B2B5E),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          EnrollStrings.subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1B2B5E),
        letterSpacing: 0.8,
      ),
    );
  }
}

class _TwocolGrid extends StatelessWidget {
  const _TwocolGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) {
      return Row(children: [
        Expanded(child: children.first),
        const Expanded(child: SizedBox.shrink()),
      ]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class _PregnantWomanTile extends StatelessWidget {
  const _PregnantWomanTile({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFFDF2F8) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? const Color(0xFFEC4899) : const Color(0xFFE5E7EB),
            width: value ? 2 : 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('🤰', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    EnrollStrings.pregnantWomanLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: value
                          ? const Color(0xFF9D174D)
                          : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    EnrollStrings.pregnantWomanBengali,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? const Color(0xFFEC4899) : Colors.transparent,
                border: Border.all(
                  color: value
                      ? const Color(0xFFEC4899)
                      : const Color(0xFFD1D5DB),
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgrammeTile extends StatelessWidget {
  const _ProgrammeTile({
    required this.programme,
    required this.emoji,
    required this.label,
    required this.bengali,
    required this.bg,
    required this.border,
    required this.textColor,
    required this.selected,
    required this.onTap,
  });

  final Programme programme;
  final String emoji;
  final String label;
  final String bengali;
  final Color bg;
  final Color border;
  final Color textColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? bg : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? border : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 26)),
                if (selected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: border,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 14,
                      color: textColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? textColor : const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              bengali,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.selectedCount,
    required this.saving,
    required this.onConfirm,
  });

  final int selectedCount;
  final bool saving;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (selectedCount > 0) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1B2B5E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$selectedCount selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton(
              onPressed: saving ? null : onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: onConfirm != null
                    ? const Color(0xFFEC4899)
                    : Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      EnrollStrings.confirmCta(selectedCount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
