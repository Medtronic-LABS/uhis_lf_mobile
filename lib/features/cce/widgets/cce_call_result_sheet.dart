import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/db/follow_up_dao.dart';
import '../../patient/followup_call_service.dart';
import '../cce_alert.dart';

/// Android SK-style call result sheet for CCE referred follow-ups.
///
/// Outcomes: Successful / Unsuccessful / Wrong Number.
/// On Successful → Willing to visit UHC? Yes/No (+ reject reasons if No).
class CceCallResultSheet extends StatefulWidget {
  const CceCallResultSheet({
    super.key,
    required this.alert,
    required this.durationMinutes,
  });

  final CceAlert alert;
  final double? durationMinutes;

  static Future<bool> show(
    BuildContext context, {
    required CceAlert alert,
    double? durationMinutes,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CceCallResultSheet(
        alert: alert,
        durationMinutes: durationMinutes,
      ),
    );
    return saved ?? false;
  }

  @override
  State<CceCallResultSheet> createState() => _CceCallResultSheetState();
}

class _CceCallResultSheetState extends State<CceCallResultSheet> {
  String? _status;
  bool? _willingToVisit;
  String? _rejectReason;
  final _otherCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_status == null || _saving) return false;
    if (_status == FollowUpCallStatus.successful) {
      if (_willingToVisit == null) return false;
      if (_willingToVisit == false) {
        if (_rejectReason == null) return false;
        if (_rejectReason == CceStrings.rejectReasonOtherKey &&
            _otherCtrl.text.trim().isEmpty) {
          return false;
        }
      }
    }
    return true;
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
            Text(
              CceStrings.callResultTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.alert.patientName,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              CceStrings.callResultPrompt,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _outcomeChip(
              FollowUpCallStatus.successful,
              FollowUpCallStrings.outcomeSuccessful,
              AppColors.statusSuccess,
            ),
            _outcomeChip(
              FollowUpCallStatus.unsuccessful,
              FollowUpCallStrings.outcomeUnsuccessful,
              AppColors.statusWarning,
            ),
            _outcomeChip(
              FollowUpCallStatus.wrongNumber,
              FollowUpCallStrings.outcomeWrongNumber,
              AppColors.statusCritical,
            ),
            if (_status == FollowUpCallStatus.successful) ...[
              const SizedBox(height: 16),
              Text(
                CceStrings.willingToVisitUhc,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _yesNoChip(true, CceStrings.willingYes),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _yesNoChip(false, CceStrings.willingNo),
                  ),
                ],
              ),
              if (_willingToVisit == false) ...[
                const SizedBox(height: 12),
                Text(
                  CceStrings.notWillingReason,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...CceStrings.rejectReasonKeys.map(_reasonChip),
                if (_rejectReason == CceStrings.rejectReasonOtherKey) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _otherCtrl,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      hintText: CceStrings.otherReasonHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    minLines: 1,
                    maxLines: 2,
                  ),
                ],
              ],
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(CceStrings.callResultSubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outcomeChip(String status, String label, Color color) {
    final selected = _status == status;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _saving
            ? null
            : () => setState(() {
                  _status = status;
                  if (status != FollowUpCallStatus.successful) {
                    _willingToVisit = null;
                    _rejectReason = null;
                  }
                }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : const Color(0xFFE5E7EB),
              width: selected ? 2 : 1,
            ),
            color: selected ? color.withValues(alpha: 0.08) : Colors.white,
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _yesNoChip(bool value, String label) {
    final selected = _willingToVisit == value;
    return InkWell(
      onTap: _saving
          ? null
          : () => setState(() {
                _willingToVisit = value;
                if (value) _rejectReason = null;
              }),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.navy : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
          color: selected
              ? AppColors.navy.withValues(alpha: 0.08)
              : Colors.white,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// [reasonKey] is the stable key that gets stored and synced; only
  /// [CceStrings.rejectReasonLabel] output is ever rendered.
  Widget _reasonChip(String reasonKey) {
    final selected = _rejectReason == reasonKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap:
            _saving ? null : () => setState(() => _rejectReason = reasonKey),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.aiPurple : const Color(0xFFE5E7EB),
            ),
            color: selected
                ? AppColors.aiPurple.withValues(alpha: 0.08)
                : Colors.white,
          ),
          child: Text(CceStrings.rejectReasonLabel(reasonKey)),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final followUpId = widget.alert.followUpId;
    final status = _status;
    if (followUpId == null || status == null) return;

    setState(() => _saving = true);
    try {
      await context.read<FollowUpCallService>().logCall(
            followUpId: followUpId,
            status: status,
            durationMinutes: widget.durationMinutes,
            retryAttempts: FollowUpCallService.cceRetryAttempts,
            callType: 'SCREENED',
            isWillingToVisitUhc: status == FollowUpCallStatus.successful
                ? _willingToVisit
                : null,
            visitRejectReason: _willingToVisit == false ? _rejectReason : null,
            otherVisitRejectReason:
                _rejectReason == CceStrings.rejectReasonOtherKey
                    ? _otherCtrl.text.trim()
                    : null,
            reason: _willingToVisit == false ? _rejectReason : null,
            otherReason: _rejectReason == CceStrings.rejectReasonOtherKey
                ? _otherCtrl.text.trim()
                : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FollowUpCallStrings.failed)),
      );
    }
  }
}
