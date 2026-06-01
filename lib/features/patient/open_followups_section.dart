import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'followup_repository.dart';

/// Section showing open follow-ups for a patient.
class OpenFollowupsSection extends StatefulWidget {
  const OpenFollowupsSection({
    super.key,
    required this.patientId,
  });

  final String patientId;

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
    setState(() {
      _future = repo.openForPatient(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Open Follow-ups',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
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
                children: followUps.map((fu) {
                  final isOverdue = fu.isOverdue;
                  final dateStr = DateFormat.MMMd().format(fu.dueDate);
                  final daysOverdue = isOverdue
                      ? DateTime.now().difference(fu.dueDate).inDays
                      : 0;

                  return ListTile(
                    leading: Icon(
                      isOverdue ? Icons.warning_amber : Icons.schedule,
                      color: isOverdue
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    title: Text(_typeLabel(fu.type)),
                    subtitle: Text(
                      isOverdue
                          ? 'Overdue by $daysOverdue days'
                          : 'Due $dateStr',
                      style: TextStyle(
                        color: isOverdue ? theme.colorScheme.error : null,
                      ),
                    ),
                    trailing: fu.programme != null
                        ? Chip(
                            label: Text(
                              fu.programme!,
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  );
                }).toList(),
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
      case FollowUpType.lost:
        return 'Lost to follow-up check';
      case FollowUpType.other:
        return 'Follow-up';
    }
  }
}
