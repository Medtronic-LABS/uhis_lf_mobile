import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../referral_api_service.dart';

/// Dialog/sheet for viewing prescription details.
class PrescriptionViewer extends StatelessWidget {
  const PrescriptionViewer({
    super.key,
    required this.prescriptions,
    required this.patientName,
    this.onShare,
    this.onPrint,
  });

  final List<Prescription> prescriptions;
  final String patientName;
  final VoidCallback? onShare;
  final VoidCallback? onPrint;

  /// Show the prescription viewer as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required List<Prescription> prescriptions,
    required String patientName,
    VoidCallback? onShare,
    VoidCallback? onPrint,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => PrescriptionViewer(
          prescriptions: prescriptions,
          patientName: patientName,
          onShare: onShare,
          onPrint: onPrint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (prescriptions.isEmpty) {
      return _buildEmptyState(context);
    }

    // Group prescriptions by active/inactive
    final activePrescriptions =
        prescriptions.where((p) => p.isActive).toList();
    final pastPrescriptions =
        prescriptions.where((p) => !p.isActive).toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.medication_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prescriptions',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        patientName,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onShare != null)
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
                    onPressed: onShare,
                    tooltip: 'Share',
                  ),
                if (onPrint != null)
                  IconButton(
                    icon: const Icon(Icons.print_rounded),
                    onPressed: onPrint,
                    tooltip: 'Print',
                  ),
              ],
            ),
          ),

          // Prescription list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (activePrescriptions.isNotEmpty) ...[
                  _buildSectionHeader(
                    context,
                    'Active Medications',
                    Icons.check_circle_rounded,
                    scheme.primary,
                  ),
                  for (final p in activePrescriptions)
                    _PrescriptionCard(prescription: p),
                ],
                if (pastPrescriptions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    context,
                    'Past Medications',
                    Icons.history_rounded,
                    scheme.outline,
                  ),
                  for (final p in pastPrescriptions)
                    _PrescriptionCard(prescription: p, isPast: true),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.medication_outlined,
                  size: 48,
                  color: scheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No Prescriptions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'No prescriptions found for this patient.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.outline,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({
    required this.prescription,
    this.isPast = false,
  });

  final Prescription prescription;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: isPast ? 0 : 1,
      color: isPast ? scheme.surfaceContainerLow : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPast
            ? BorderSide(color: scheme.outlineVariant)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Medication name
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isPast
                        ? scheme.outlineVariant.withValues(alpha: 0.3)
                        : scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.medication,
                    size: 18,
                    color: isPast ? scheme.outline : scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    prescription.medicationName ?? 'Unknown Medication',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isPast ? scheme.outline : null,
                    ),
                  ),
                ),
                if (prescription.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Active',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Details grid
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (prescription.dosage != null)
                  _DetailItem(
                    icon: Icons.straighten_rounded,
                    label: 'Dosage',
                    value: prescription.dosage!,
                    isPast: isPast,
                  ),
                if (prescription.frequency != null)
                  _DetailItem(
                    icon: Icons.schedule_rounded,
                    label: 'Frequency',
                    value: prescription.frequency!,
                    isPast: isPast,
                  ),
                if (prescription.duration != null)
                  _DetailItem(
                    icon: Icons.timelapse_rounded,
                    label: 'Duration',
                    value: '${prescription.duration} days',
                    isPast: isPast,
                  ),
              ],
            ),

            // Instructions
            if (prescription.instructions != null &&
                prescription.instructions!.isNotEmpty) ...[
              const Divider(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: scheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      prescription.instructions!,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Footer: Prescribed by/date
            if (prescription.prescribedAt != null ||
                prescription.prescribedBy != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (prescription.prescribedBy != null)
                    Text(
                      'Dr. ${prescription.prescribedBy}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  if (prescription.prescribedAt != null &&
                      prescription.prescribedBy != null)
                    Text(' • ', style: TextStyle(color: scheme.outline)),
                  if (prescription.prescribedAt != null)
                    Text(
                      DateFormat.yMMMd().format(prescription.prescribedAt!),
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isPast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isPast ? scheme.outlineVariant : scheme.tertiary,
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.outline,
          ),
        ),
        Text(
          value,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: isPast ? scheme.outline : null,
          ),
        ),
      ],
    );
  }
}
