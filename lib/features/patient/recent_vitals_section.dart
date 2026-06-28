import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'vitals_repository.dart';

enum _Trend { up, down, stable }

_Trend? _trendFor(List<VitalReading> all, VitalType type, double current) {
  final prev = all.where((r) => r.type == type).skip(1).firstOrNull;
  if (prev == null) return null;
  final prevVal = type == VitalType.bloodPressure ? prev.systolic : prev.value;
  if (prevVal == null) return null;
  final diff = current - prevVal;
  if (diff.abs() < 1.0) return _Trend.stable;
  return diff > 0 ? _Trend.up : _Trend.down;
}

String? _classify(VitalType type, double? value, double? systolic, double? diastolic) {
  switch (type) {
    case VitalType.bloodPressure:
      if (systolic == null || diastolic == null) return null;
      if (systolic >= 180 || diastolic >= 110) return 'Critical';
      if (systolic >= 140 || diastolic >= 90) return 'High';
      if (systolic >= 120) return 'Elevated';
      return 'Normal';
    case VitalType.spO2:
      if (value == null) return null;
      if (value < 90) return 'Critical';
      if (value < 94) return 'Low';
      return 'Normal';
    case VitalType.respiratoryRate:
      if (value == null) return null;
      if (value < 12 || value > 25) return 'Abnormal';
      return 'Normal';
    case VitalType.temperature:
      if (value == null) return null;
      if (value >= 39.0) return 'High Fever';
      if (value >= 37.5) return 'Fever';
      if (value < 35.5) return 'Low';
      return 'Normal';
    case VitalType.glucose:
      if (value == null) return null;
      if (value >= 200) return 'High';
      if (value < 70) return 'Low';
      return 'Normal';
    case VitalType.bmi:
      if (value == null) return null;
      if (value >= 30) return 'Obese';
      if (value >= 25) return 'Overweight';
      if (value < 18.5) return 'Underweight';
      return 'Normal';
    default:
      return null;
  }
}

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
                    tooltip: 'Retry loading vitals',
                    icon: const Icon(Icons.refresh),
                    onPressed: _load,
                  ),
                ),
              );
            }

            final vitals = snap.data;
            if (vitals == null || vitals.isEmpty) {
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

            final all = vitals.allReadings;

            // Build visible rows, separated by dividers
            final rows = <Widget>[];
            void addRow(Widget row) {
              if (rows.isNotEmpty) rows.add(const Divider(height: 24));
              rows.add(row);
            }

            if (vitals.latestBp != null) {
              final bp = vitals.latestBp!;
              addRow(_VitalRow(
                icon: Icons.favorite,
                label: 'Blood Pressure',
                value: bp.displayValue,
                unit: 'mmHg',
                date: bp.date,
                classification: _classify(
                    VitalType.bloodPressure, null, bp.systolic, bp.diastolic),
                trend: bp.systolic != null
                    ? _trendFor(all, VitalType.bloodPressure, bp.systolic!)
                    : null,
              ));
            }

            if (vitals.latestSpO2 != null) {
              final r = vitals.latestSpO2!;
              addRow(_VitalRow(
                icon: Icons.air,
                label: 'SpO₂',
                value: r.displayValue,
                unit: '%',
                date: r.date,
                classification: _classify(VitalType.spO2, r.value, null, null),
                trend: r.value != null
                    ? _trendFor(all, VitalType.spO2, r.value!)
                    : null,
              ));
            }

            if (vitals.latestRr != null) {
              final r = vitals.latestRr!;
              addRow(_VitalRow(
                icon: Icons.waves,
                label: 'Respiratory Rate',
                value: r.displayValue,
                unit: '/min',
                date: r.date,
                classification:
                    _classify(VitalType.respiratoryRate, r.value, null, null),
                trend: r.value != null
                    ? _trendFor(all, VitalType.respiratoryRate, r.value!)
                    : null,
              ));
            }

            if (vitals.latestGlucose != null) {
              final r = vitals.latestGlucose!;
              addRow(_VitalRow(
                icon: Icons.bloodtype,
                label: 'Blood Glucose',
                value: r.displayValue,
                unit: 'mg/dL',
                date: r.date,
                classification: _classify(VitalType.glucose, r.value, null, null),
                trend: r.value != null
                    ? _trendFor(all, VitalType.glucose, r.value!)
                    : null,
              ));
            }

            if (vitals.latestWeight != null) {
              final r = vitals.latestWeight!;
              addRow(_VitalRow(
                icon: Icons.monitor_weight,
                label: 'Weight',
                value: r.displayValue,
                unit: 'kg',
                date: r.date,
                trend: r.value != null
                    ? _trendFor(all, VitalType.weight, r.value!)
                    : null,
              ));
            }

            if (vitals.latestBmi != null) {
              final r = vitals.latestBmi!;
              addRow(_VitalRow(
                icon: Icons.person,
                label: 'BMI',
                value: r.displayValue,
                unit: 'kg/m²',
                date: r.date,
                classification: _classify(VitalType.bmi, r.value, null, null),
                trend: r.value != null
                    ? _trendFor(all, VitalType.bmi, r.value!)
                    : null,
              ));
            }

            if (vitals.latestTemperature != null) {
              final r = vitals.latestTemperature!;
              addRow(_VitalRow(
                icon: Icons.thermostat,
                label: 'Temperature',
                value: r.displayValue,
                unit: '°C',
                date: r.date,
                classification:
                    _classify(VitalType.temperature, r.value, null, null),
                trend: r.value != null
                    ? _trendFor(all, VitalType.temperature, r.value!)
                    : null,
              ));
            }

            if (rows.isEmpty) {
              return const SizedBox.shrink();
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: rows),
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
    this.unit,
    this.classification,
    this.trend,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final DateTime date;
  final String? classification;
  final _Trend? trend;

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (trend != null) ...[
                    const SizedBox(width: 4),
                    _TrendBadge(trend: trend!),
                  ],
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (classification != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
    if (lower.contains('critical') || lower.contains('severe')) {
      return theme.colorScheme.errorContainer;
    }
    if (lower.contains('high') || lower.contains('fever') ||
        lower.contains('obese') || lower.contains('abnormal')) {
      return Colors.orange.shade100;
    }
    if (lower.contains('low') || lower.contains('underweight') ||
        lower.contains('elevated') || lower.contains('overweight')) {
      return Colors.yellow.shade100;
    }
    return theme.colorScheme.surfaceContainerHighest;
  }

  Color _classificationTextColor(String c, ThemeData theme) {
    final lower = c.toLowerCase();
    if (lower.contains('normal')) return Colors.green.shade800;
    if (lower.contains('critical') || lower.contains('severe')) {
      return theme.colorScheme.error;
    }
    if (lower.contains('high') || lower.contains('fever') ||
        lower.contains('obese') || lower.contains('abnormal')) {
      return Colors.orange.shade800;
    }
    if (lower.contains('low') || lower.contains('underweight') ||
        lower.contains('elevated') || lower.contains('overweight')) {
      return Colors.yellow.shade900;
    }
    return theme.colorScheme.onSurface;
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});
  final _Trend trend;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (trend) {
      _Trend.up => (Icons.arrow_upward, Colors.orange.shade600),
      _Trend.down => (Icons.arrow_downward, Colors.blue.shade600),
      _Trend.stable => (Icons.remove, Colors.grey.shade500),
    };
    return Icon(icon, size: 14, color: color);
  }
}
