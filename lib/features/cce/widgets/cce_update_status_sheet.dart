import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';
import '../cce_alert.dart';
import '../cce_repository.dart';

/// Bottom sheet the SK uses to advance a referral's status and (optionally)
/// tag the barrier that is holding the patient up. Writes through
/// [CceRepository.updateStatus] → [ReferralRepository.transition], so the SLA
/// engine + timeline + notifications all update. Offline-safe.
class CceUpdateStatusSheet extends StatefulWidget {
  const CceUpdateStatusSheet({
    super.key,
    required this.alert,
    required this.repository,
  });

  final CceAlert alert;
  final CceRepository repository;

  /// Shows the sheet. Resolves to `true` if a status update was saved.
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

class _CceUpdateStatusSheetState extends State<CceUpdateStatusSheet> {
  static const _options = <(String, ReferralStatus)>[
    (CceStrings.updateOptNotLeft, ReferralStatus.acknowledged),
    (CceStrings.updateOptOnWay, ReferralStatus.inTransit),
    (CceStrings.updateOptArrived, ReferralStatus.arrived),
    (CceStrings.updateOptTreated, ReferralStatus.treatmentStarted),
    (CceStrings.updateOptDischarged, ReferralStatus.closedRecovered),
  ];

  static const _barriers = <String>[
    CceStrings.barrierTransport,
    CceStrings.barrierCost,
    CceStrings.barrierFamily,
    CceStrings.barrierDistance,
  ];

  ReferralStatus? _selected;
  final _selectedBarriers = <String>{};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    CceStrings.updateTitle(widget.alert.patientName),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(CceStrings.updatePrompt,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._options.map(_statusOption),
            const SizedBox(height: 14),
            const Text(CceStrings.barrierPrompt,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _barriers.map(_barrierChip).toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(CceStrings.saveUpdate,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(CceStrings.saveHint,
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusOption((String, ReferralStatus) opt) {
    final selected = _selected == opt.$2;
    return InkWell(
      onTap: _saving ? null : () => setState(() => _selected = opt.$2),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.navy : AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(opt.$1,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ),
            if (selected)
              const Icon(Icons.check, size: 16, color: AppColors.statusSuccess),
          ],
        ),
      ),
    );
  }

  Widget _barrierChip(String label) {
    final selected = _selectedBarriers.contains(label);
    return GestureDetector(
      onTap: _saving
          ? null
          : () => setState(() {
                if (selected) {
                  _selectedBarriers.remove(label);
                } else {
                  _selectedBarriers.add(label);
                }
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.statusWarningSurface
              : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.statusWarning : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color:
                selected ? AppColors.statusWarningText : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final to = _selected;
    if (to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(CceStrings.selectStatus)),
      );
      return;
    }
    setState(() => _saving = true);
    final reason =
        _selectedBarriers.isEmpty ? null : _selectedBarriers.join(', ');
    try {
      await widget.repository.updateStatus(
        referralId: widget.alert.referralId,
        to: to,
        reason: reason,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ReferralStrings.loadFailed)),
      );
    }
  }
}
