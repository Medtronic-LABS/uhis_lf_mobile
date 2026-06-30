import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import '../../core/models/referral.dart';
import '../referral/referral_repository.dart';
import '../visit/visit_controller.dart';

/// Row of action buttons for patient context screen.
class PatientActionsRow extends StatefulWidget {
  const PatientActionsRow({
    super.key,
    required this.patientId,
    this.patientName,
    this.patientAge,
    this.patientGender,
    this.householdId,
    this.villageId,
    this.programmes = const {},
    this.origin,
  });

  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final String? villageId;
  final Set<Programme> programmes;

  /// Origin screen for return navigation ('dashboard' or 'tasks').
  final String? origin;

  @override
  State<PatientActionsRow> createState() => _PatientActionsRowState();
}

class _PatientActionsRowState extends State<PatientActionsRow> {
  bool _starting = false;

  Future<void> _startVisit() async {
    if (_starting) return;
    setState(() => _starting = true);

    final controller = context.read<VisitController>();
    final encounterId = await controller.startVisit(
      patientId: widget.patientId,
      programme: Programme.unknown,
      patientName: widget.patientName,
      patientAge: widget.patientAge,
      patientGender: widget.patientGender,
      householdId: widget.householdId,
    );

    if (!mounted) return;

    if (encounterId != null) {
      final originParam = widget.origin != null ? '?origin=${widget.origin}' : '';
      context.go(
        '/patients/visit/$encounterId/flow$originParam',
        extra: {
          'patientId': widget.patientId,
          'patientName': widget.patientName,
          'patientAge': widget.patientAge,
          'patientGender': widget.patientGender,
          'householdId': widget.householdId,
          'memberId': null,
        },
      );
    } else {
      setState(() => _starting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.error ?? 'Failed to start visit')),
        );
      }
    }
  }

  Future<void> _openReferralSheet() async {
    final referrals = context.read<ReferralRepository>();
    final result = await showModalBottomSheet<_ReferralFormResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReferralCreateSheet(patientName: widget.patientName),
    );
    if (result == null || !mounted) return;
    try {
      await referrals.create(
        patientId: widget.patientId,
        slaTier: result.slaTier,
        householdId: widget.householdId,
        villageId: widget.villageId,
        diagnosisLabel: result.reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ReferralStrings.createSuccess)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(ReferralStrings.createFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PatientContextStrings.actionsTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _starting ? null : _startVisit,
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_starting ? 'Starting...' : PatientContextStrings.startVisit),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openReferralSheet,
                icon: const Icon(Icons.send),
                label: const Text(ReferralStrings.actionOpenReferral),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(PatientContextStrings.callComingSoon),
                    ),
                  );
                },
                icon: const Icon(Icons.phone),
                label: const Text(PatientContextStrings.callHousehold),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReferralFormResult {
  const _ReferralFormResult({required this.reason, required this.slaTier});
  final String reason;
  final SlaTier slaTier;
}

class _ReferralCreateSheet extends StatefulWidget {
  const _ReferralCreateSheet({this.patientName});
  final String? patientName;

  @override
  State<_ReferralCreateSheet> createState() => _ReferralCreateSheetState();
}

class _ReferralCreateSheetState extends State<_ReferralCreateSheet> {
  String? _selectedReason;
  SlaTier _selectedTier = SlaTier.urgent;
  bool _submitting = false;

  static const _tiers = [
    (SlaTier.emergency, ReferralStrings.tierEmergencyLabel),
    (SlaTier.urgent, ReferralStrings.tierUrgentLabel),
    (SlaTier.routine, ReferralStrings.tierRoutineLabel),
  ];

  void _submit() {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(ReferralStrings.createReasonRequired)),
      );
      return;
    }
    setState(() => _submitting = true);
    Navigator.of(context).pop(
      _ReferralFormResult(
        reason: _selectedReason!,
        slaTier: _selectedTier,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            ReferralStrings.createSheetTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.patientName != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.patientName!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            ReferralStrings.createReasonLabel,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedReason,
            hint: const Text(ReferralStrings.createReasonHint),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: ReferralStrings.defaultReferralReasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _selectedReason = v),
          ),
          const SizedBox(height: 16),
          Text(
            ReferralStrings.createTierLabel,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<SlaTier>(
            segments: _tiers
                .map((t) => ButtonSegment<SlaTier>(
                      value: t.$1,
                      label: Text(t.$2, textAlign: TextAlign.center),
                    ))
                .toList(),
            selected: {_selectedTier},
            onSelectionChanged: (s) =>
                setState(() => _selectedTier = s.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text(ReferralStrings.createCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(ReferralStrings.createSubmit),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
