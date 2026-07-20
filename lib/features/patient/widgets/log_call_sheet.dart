import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/follow_up_dao.dart';
import '../followup_call_service.dart';

/// Bottom sheet the CHW uses to log a call attempt against a follow-up.
/// Writes through [FollowUpCallService.logCall] — records the attempt, closes
/// the ticket on a wrong number / exhausted retries, and queues the follow-up
/// for the next offline-sync push. Offline-safe.
class LogCallSheet extends StatefulWidget {
  const LogCallSheet({
    super.key,
    required this.followUpId,
    required this.title,
  });

  final String followUpId;
  final String title;

  /// Shows the sheet. Resolves to `true` if a call was logged.
  static Future<bool> show(
    BuildContext context, {
    required String followUpId,
    required String title,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LogCallSheet(followUpId: followUpId, title: title),
    );
    return saved ?? false;
  }

  @override
  State<LogCallSheet> createState() => _LogCallSheetState();
}

class _LogCallSheetState extends State<LogCallSheet> {
  static const _outcomes = <(String, String)>[
    (FollowUpCallStatus.successful, FollowUpCallStrings.outcomeSuccessful),
    (FollowUpCallStatus.unsuccessful, FollowUpCallStrings.outcomeUnsuccessful),
    (FollowUpCallStatus.wrongNumber, FollowUpCallStrings.outcomeWrongNumber),
  ];

  String? _status;
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
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
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(FollowUpCallStrings.sheetTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(widget.title,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          Text(FollowUpCallStrings.outcomePrompt,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ..._outcomes.map(_outcomeTile),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonCtrl,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: FollowUpCallStrings.reasonLabel,
              hintText: FollowUpCallStrings.reasonHint,
              border: OutlineInputBorder(),
              isDense: true,
            ),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(FollowUpCallStrings.save),
            ),
          ),
        ],
      ),
    );
  }

  Widget _outcomeTile((String, String) opt) {
    final theme = Theme.of(context);
    final selected = _status == opt.$1;
    return InkWell(
      onTap: _saving ? null : () => setState(() => _status = opt.$1),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Text(opt.$2,
                style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final status = _status;
    if (status == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FollowUpCallStrings.selectOutcome)),
      );
      return;
    }
    setState(() => _saving = true);
    final reason =
        _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim();
    try {
      await context.read<FollowUpCallService>().logCall(
            followUpId: widget.followUpId,
            status: status,
            reason: reason,
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
