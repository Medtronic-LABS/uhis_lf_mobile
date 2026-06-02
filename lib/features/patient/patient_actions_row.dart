import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/programme.dart';
import '../visit/visit_landing_screen.dart';

/// Available programmes for visit selection.
const List<_ProgrammeOption> _programmeOptions = [
  _ProgrammeOption(
    programme: Programme.ncd,
    label: 'NCD',
    description: 'Hypertension, Diabetes screening',
    icon: Icons.monitor_heart, // Heart monitoring for BP/diabetes
    color: Colors.red,
  ),
  _ProgrammeOption(
    programme: Programme.tb,
    label: 'TB',
    description: 'Tuberculosis screening',
    icon: Icons.masks, // Respiratory/infectious disease
    color: Colors.orange,
  ),
  _ProgrammeOption(
    programme: Programme.anc,
    label: 'ANC',
    description: 'Antenatal care',
    icon: Icons.pregnant_woman, // Pregnancy
    color: Colors.pink,
  ),
  _ProgrammeOption(
    programme: Programme.imci,
    label: 'ICCM',
    description: 'Child illness (under 5)',
    icon: Icons.child_care, // Child health
    color: Colors.blue,
  ),
];

class _ProgrammeOption {
  const _ProgrammeOption({
    required this.programme,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final Programme programme;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

/// Row of action buttons for patient context screen.
class PatientActionsRow extends StatelessWidget {
  const PatientActionsRow({
    super.key,
    required this.patientId,
    this.patientName,
    this.patientAge,
    this.patientGender,
    this.householdId,
    this.programmes = const {},
    this.origin,
  });

  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? householdId;
  final Set<Programme> programmes;
  /// Origin screen for return navigation ('dashboard' or 'tasks').
  final String? origin;

  void _showProgrammeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ProgrammeSelectorSheet(
        programmes: programmes,
        onSelect: (programme) {
          Navigator.pop(ctx);
          _startVisit(context, programme);
        },
      ),
    );
  }

  void _startVisit(BuildContext context, Programme programme) {
    final data = VisitLandingData(
      patientId: patientId,
      patientName: patientName,
      patientAge: patientAge,
      patientGender: patientGender,
      householdId: householdId,
      programme: programme,
      origin: origin,
    );
    context.push(
      '/patients/visit/$patientId/start',
      extra: data,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _showProgrammeSelector(context),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Visit'),
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
                onPressed: () {
                  // TODO: Implement referral creation
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Referral creation coming soon'),
                    ),
                  );
                },
                icon: const Icon(Icons.send),
                label: const Text('Open Referral'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: Implement call household
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Call household coming soon'),
                    ),
                  );
                },
                icon: const Icon(Icons.phone),
                label: const Text('Call'),
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

/// Bottom sheet for selecting a programme before starting a visit.
class _ProgrammeSelectorSheet extends StatelessWidget {
  const _ProgrammeSelectorSheet({
    required this.programmes,
    required this.onSelect,
  });

  final Set<Programme> programmes;
  final void Function(Programme) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Programme',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the type of assessment for this visit',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // Programme options
            ...(_programmeOptions.map((option) {
              final isEnrolled = programmes.contains(option.programme);
              return _ProgrammeTile(
                option: option,
                isEnrolled: isEnrolled,
                onTap: () => onSelect(option.programme),
              );
            })),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Tile for a single programme option.
class _ProgrammeTile extends StatelessWidget {
  const _ProgrammeTile({
    required this.option,
    required this.isEnrolled,
    required this.onTap,
  });

  final _ProgrammeOption option;
  final bool isEnrolled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: option.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  option.icon,
                  color: option.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          option.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isEnrolled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Enrolled',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
