import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import 'followup_call_service.dart';
import 'followup_repository.dart';
import 'widgets/log_call_sheet.dart';

/// Section showing open follow-ups for a patient.
class OpenFollowupsSection extends StatefulWidget {
  const OpenFollowupsSection({
    super.key,
    required this.patientId,
    this.memberReference,
  });

  final String patientId;
  final String? memberReference;

  @override
  State<OpenFollowupsSection> createState() => _OpenFollowupsSectionState();
}

class _OpenFollowupsSectionState extends State<OpenFollowupsSection> {
  Future<List<FollowUp>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = context.read<FollowUpRepository>();
    // Use memberReference for follow-up API (like Android), fallback to patientId
    final memberId = widget.memberReference ?? widget.patientId;
    setState(() {
      _future = repo.openForPatient(memberId);
    });
  }

  /// The bare id the `follow_ups.patient_id` column stores (repo strips any
  /// `Patient/…` prefix on read, so we must store the stripped form).
  String get _barePatientId {
    final id = widget.memberReference ?? widget.patientId;
    final slash = id.lastIndexOf('/');
    return slash < 0 ? id : id.substring(slash + 1);
  }

  /// Create a follow-up for this patient (backend accepts a null-id follow-up
  /// as a create; it shows here immediately and pushes on the next sync).
  Future<void> _schedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    try {
      await context.read<FollowUpCallService>().scheduleLocal(
            patientId: _barePatientId,
            dueDate: date,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FollowUpCallStrings.scheduled)),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FollowUpCallStrings.scheduleFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Open Follow-ups',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _schedule,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text(FollowUpCallStrings.schedule,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<FollowUp>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              );
            }

            if (snap.hasError) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Failed to load follow-ups'),
                  trailing: IconButton(
                    tooltip: 'Retry loading follow-ups',
                    icon: const Icon(Icons.refresh),
                    onPressed: _load,
                  ),
                ),
              );
            }

            final followUps = snap.data ?? [];
            if (followUps.isEmpty) {
              return Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.green),
                      SizedBox(width: 12),
                      Text('No open follow-ups'),
                    ],
                  ),
                ),
              );
            }

            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < followUps.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _FollowUpTile(
                      fu: followUps[i],
                      typeLabel: _typeLabel(followUps[i].type),
                      onLogged: _load,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  String _typeLabel(FollowUpType type) {
    switch (type) {
      case FollowUpType.screening:
        return 'Screening follow-up';
      case FollowUpType.medicalReview:
        return 'Medical review';
      case FollowUpType.assessment:
        return 'Assessment follow-up';
      case FollowUpType.referred:
        return 'Referral — confirm facility arrival';
      case FollowUpType.householdVisit:
        return 'Household visit due';
      case FollowUpType.lost:
        return 'Lost to follow-up check';
      case FollowUpType.other:
        return 'Follow-up';
    }
  }
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({
    required this.fu,
    required this.typeLabel,
    required this.onLogged,
  });

  final FollowUp fu;
  final String typeLabel;

  /// Called after a call is logged so the parent can reload (the follow-up may
  /// now be completed, or its attempt count changed).
  final VoidCallback onLogged;

  Future<void> _logCall(BuildContext context) async {
    final saved = await LogCallSheet.show(
      context,
      followUpId: fu.id,
      title: typeLabel,
    );
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FollowUpCallStrings.saved)),
      );
      onLogged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverdue = fu.isOverdue;
    final daysOverdue = isOverdue
        ? DateTime.now().difference(fu.dueDate).inDays
        : 0;
    final dueDateStr =
        DateFormat('MMM d, yyyy · h:mm a').format(fu.dueDate);
    final iconColor =
        isOverdue ? theme.colorScheme.error : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_typeIcon(fu.type), size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        typeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (fu.programme != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          fu.programme!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Due date + overdue badge
                Row(
                  children: [
                    Text(
                      dueDateStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isOverdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isOverdue) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$daysOverdue d overdue',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                // Reason
                if (fu.reason != null && fu.reason!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    fu.reason!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Attempts
                if (fu.attempts > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    fu.unsuccessfulAttempts > 0
                        ? '${fu.attempts} attempt${fu.attempts > 1 ? 's' : ''} · ${fu.unsuccessfulAttempts} unsuccessful'
                        : '${fu.attempts} attempt${fu.attempts > 1 ? 's' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fu.unsuccessfulAttempts > 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                // Referral site
                if (fu.type == FollowUpType.referred &&
                    fu.referredSiteId != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.local_hospital_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        'Facility: ${fu.referredSiteId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _logCall(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.call, size: 15),
            label: Text(FollowUpCallStrings.logCall,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(FollowUpType type) {
    switch (type) {
      case FollowUpType.referred:
        return Icons.local_hospital;
      case FollowUpType.householdVisit:
        return Icons.home;
      case FollowUpType.lost:
        return Icons.person_search;
      case FollowUpType.medicalReview:
        return Icons.medical_services;
      case FollowUpType.screening:
        return Icons.health_and_safety;
      case FollowUpType.assessment:
        return Icons.assignment;
      case FollowUpType.other:
        return Icons.schedule;
    }
  }
}
