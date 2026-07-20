import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';
import '../cce_alert.dart';
import '../cce_repository.dart';

/// CCE update-status sheet — wireframe v14 design.
///
/// Presents 5 outcome-first options (colored dot + label in a bordered card).
/// "Other" expands a note field. Saves through [CceRepository.updateStatus].
class CceUpdateStatusSheet extends StatefulWidget {
  const CceUpdateStatusSheet({
    super.key,
    required this.alert,
    required this.repository,
  });

  final CceAlert alert;
  final CceRepository repository;

  static Future<bool> show(
    BuildContext context, {
    required CceAlert alert,
    required CceRepository repository,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          CceUpdateStatusSheet(alert: alert, repository: repository),
    );
    return saved ?? false;
  }

  @override
  State<CceUpdateStatusSheet> createState() => _CceUpdateStatusSheetState();
}

// ── Option model ─────────────────────────────────────────────────────────────

typedef _Option = ({
  String label,
  Color dot,
  ReferralStatus? status,
  String? autoReason,
});

// ── State ─────────────────────────────────────────────────────────────────────

class _CceUpdateStatusSheetState extends State<CceUpdateStatusSheet> {
  static final List<_Option> _options = [
    (
      label: CceStrings.updateOptReachedFacility,
      dot: AppColors.statusSuccess,
      status: ReferralStatus.arrived,
      autoReason: null,
    ),
    (
      label: CceStrings.updateOptTransportIssue,
      dot: AppColors.statusWarning,
      status: ReferralStatus.transportDeclined,
      autoReason: CceStrings.barrierTransport,
    ),
    (
      label: CceStrings.updateOptRefused,
      dot: AppColors.statusCritical,
      status: ReferralStatus.refused,
      autoReason: null,
    ),
    (
      label: CceStrings.updateOptRecoveredHome,
      dot: AppColors.aiPurple,
      status: ReferralStatus.closedRecovered,
      autoReason: null,
    ),
    (
      label: CceStrings.updateOptOther,
      dot: AppColors.textMuted,
      status: null,
      autoReason: null,
    ),
  ];

  int? _selectedIndex;
  final _noteController = TextEditingController();
  bool _saving = false;

  bool get _isOther =>
      _selectedIndex != null && _options[_selectedIndex!].status == null;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _titleBlock(),
            const SizedBox(height: 20),
            ..._options.asMap().entries.map((e) => _optionRow(e.key, e.value)),
            if (_isOther) ...[
              const SizedBox(height: 10),
              _noteField(),
            ],
            const SizedBox(height: 20),
            _confirmButton(),
            const SizedBox(height: 10),
            _cancelButton(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _titleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          CceStrings.updateSheetTitle,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          widget.alert.patientName,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Text(
          CceStrings.updateSyncNote,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.aiPurple,
          ),
        ),
      ],
    );
  }

  // ── Option rows ───────────────────────────────────────────────────────────

  Widget _optionRow(int index, _Option opt) {
    final selected = _selectedIndex == index;
    return GestureDetector(
      onTap: _saving ? null : () => setState(() => _selectedIndex = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? opt.dot.withValues(alpha: 0.06)
              : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? opt.dot : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: opt.dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                opt.label +
                    (opt.status == ReferralStatus.arrived ? ' ✓' : ''),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Note field (Other) ────────────────────────────────────────────────────

  Widget _noteField() {
    return TextField(
      controller: _noteController,
      enabled: !_saving,
      maxLines: 2,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: CceStrings.updateOtherHint,
        hintStyle:
            const TextStyle(color: AppColors.textMuted, fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  // ── Buttons ───────────────────────────────────────────────────────────────

  Widget _confirmButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.pinkWorklist,
          disabledBackgroundColor: AppColors.pinkWorklist.withValues(alpha: 0.5),
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
            : Text(
                CceStrings.updateConfirmSync,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _cancelButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.navy, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          CceStrings.updateCancel,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.navy,
          ),
        ),
      ),
    );
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CceStrings.selectStatus)),
      );
      return;
    }

    final opt = _options[_selectedIndex!];

    if (_isOther) {
      final note = _noteController.text.trim();
      if (note.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(CceStrings.updateOtherRequired)),
        );
        return;
      }
      // Other: no status transition — just pop and surface the note via snackbar.
      if (mounted) Navigator.of(context).pop(false);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.updateStatus(
        referralId: widget.alert.referralId,
        to: opt.status!,
        reason: opt.autoReason,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ReferralStrings.loadFailed)),
      );
    }
  }
}
