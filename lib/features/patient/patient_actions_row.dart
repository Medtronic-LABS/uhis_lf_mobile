import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import '../visit/visit_controller.dart';
import '../visit/visit_start_helper.dart';

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
    this.memberId,
    this.programmes = const {},
    this.origin,
  });

  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final String? villageId;
  /// Server-assigned household member ID (id column in members table).
  /// Populates encounter.memberId in the offline-sync payload so the
  /// FHIR mapper can link the assessment to the correct RelatedPerson.
  final String? memberId;
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

    // First-time patient (no programmes) → service selection screen first
    if (widget.programmes.isEmpty) {
      context.push(
        '/patients/${widget.patientId}/new-visit',
        extra: <String, dynamic>{
          if (widget.patientName != null) 'patientName': widget.patientName,
          if (widget.patientAge != null) 'patientAge': widget.patientAge,
          if (widget.patientGender != null) 'patientGender': widget.patientGender,
          if (widget.householdId != null) 'householdId': widget.householdId,
        },
      );
      return;
    }

    setState(() => _starting = true);

    final controller = context.read<VisitController>();
    final programme = widget.programmes.isNotEmpty
        ? widget.programmes.first
        : Programme.unknown;
    final encounterId = await startOrResumeVisit(
      context,
      controller: controller,
      patientId: widget.patientId,
      programme: programme,
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
          'villageId': widget.villageId,
          'memberId': widget.memberId,
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
      ],
    );
  }
}

