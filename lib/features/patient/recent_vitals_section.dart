import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'vitals_repository.dart';

/// Section showing recent vitals for a patient.
class RecentVitalsSection extends StatefulWidget {
  const RecentVitalsSection({
    super.key,
    required this.patientId,
    this.memberReference,
  });

  final String patientId;
  final String? memberReference;

  @override
  State<RecentVitalsSection> createState() => _RecentVitalsSectionState();
}

class _RecentVitalsSectionState extends State<RecentVitalsSection> {
  Future<RecentVitals>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // ignore: avoid_print
    print('[RecentVitalsSection] Loading vitals for patientId=${widget.patientId}, memberRef=${widget.memberReference}');
    final repo = context.read<VitalsRepository>();
    setState(() {
      _future = repo.recent(
        widget.patientId,
        memberReference: widget.memberReference,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Vitals',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<RecentVitals>(
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
                  title: const Text('Failed to load vitals'),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _load,
                  ),
                ),
              );
            }

            final vitals = snap.data;
            // ignore: avoid_print
            print('[RecentVitalsSection] Received vitals: isEmpty=${vitals?.isEmpty}, bp=${vitals?.latestBp?.displayValue}, glucose=${vitals?.latestGlucose?.displayValue}');
            if (vitals == null || vitals.isEmpty) {
              // ignore: avoid_print
              print('[RecentVitalsSection] No vitals data to display');
              return Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 12),
                      Text('No vitals recorded yet'),
                    ],
                  ),
                ),
              );
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // BP row
                    if (vitals.latestBp != null)
                      _VitalRow(
                        icon: Icons.favorite,
                        label: 'Blood Pressure',
                        value: vitals.latestBp!.displayValue,
                        date: vitals.latestBp!.date,
                        classification: vitals.latestBp!.classification,
                      ),
                    // Glucose row
                    if (vitals.latestGlucose != null) ...[
                      if (vitals.latestBp != null) const Divider(height: 24),
                      _VitalRow(
                        icon: Icons.bloodtype,
                        label: 'Blood Glucose',
                        value: vitals.latestGlucose!.displayValue,
                        date: vitals.latestGlucose!.date,
                        classification: vitals.latestGlucose!.classification,
                      ),
                    ],
                    // Weight row
                    if (vitals.latestWeight != null) ...[
                      if (vitals.latestBp != null || vitals.latestGlucose != null)
                        const Divider(height: 24),
                      _VitalRow(
                        icon: Icons.monitor_weight,
                        label: 'Weight',
                        value: vitals.latestWeight!.displayValue,
                        date: vitals.latestWeight!.date,
                      ),
                    ],
                    // Temperature row
                    if (vitals.latestTemperature != null) ...[
                      if (vitals.latestBp != null ||
                          vitals.latestGlucose != null ||
                          vitals.latestWeight != null)
                        const Divider(height: 24),
                      _VitalRow(
                        icon: Icons.thermostat,
                        label: 'Temperature',
                        value: vitals.latestTemperature!.displayValue,
                        date: vitals.latestTemperature!.date,
                        classification: vitals.latestTemperature!.classification,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _VitalRow extends StatelessWidget {
  const _VitalRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.date,
    this.classification,
  });

  final IconData icon;
  final String label;
  final String value;
  final DateTime date;
  final String? classification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat.MMMd().format(date);

    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (classification != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _classificationColor(classification!, theme),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  classification!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _classificationTextColor(classification!, theme),
                  ),
                ),
              ),
            const SizedBox(height: 2),
            Text(
              dateStr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _classificationColor(String c, ThemeData theme) {
    final lower = c.toLowerCase();
    if (lower.contains('normal')) return Colors.green.shade100;
    if (lower.contains('high') || lower.contains('elevated'))
      return Colors.orange.shade100;
    if (lower.contains('low')) return Colors.orange.shade100;
    if (lower.contains('critical') || lower.contains('severe'))
      return theme.colorScheme.errorContainer;
    return theme.colorScheme.surfaceContainerHighest;
  }

  Color _classificationTextColor(String c, ThemeData theme) {
    final lower = c.toLowerCase();
    if (lower.contains('normal')) return Colors.green.shade800;
    if (lower.contains('high') || lower.contains('elevated'))
      return Colors.orange.shade800;
    if (lower.contains('low')) return Colors.orange.shade800;
    if (lower.contains('critical') || lower.contains('severe'))
      return theme.colorScheme.error;
    return theme.colorScheme.onSurface;
  }
}
