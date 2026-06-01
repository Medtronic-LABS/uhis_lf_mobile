import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'visit_controller.dart';
import 'visit_session.dart';
import 'vital_classifier.dart';

/// Visit Vitals Step — vital signs capture.
class VisitVitalsStep extends StatelessWidget {
  const VisitVitalsStep({
    super.key,
    required this.visitId,
  });

  final String visitId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<VisitController>(
      builder: (context, controller, _) {
        final session = controller.session;

        if (session == null || session.id != visitId) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vitals')),
            body: const Center(
              child: Text('Visit not found. Please start a new visit.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Vitals - ${session.programme.wireTag}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                controller.goToStep(VisitStep.triage);
                context.go('/patients/visit/$visitId/triage');
              },
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Instructions
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.medical_services_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Record vital signs for ${session.patientName ?? "the patient"}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Vital cards
              ...session.vitals.map((vital) {
                return _VitalCard(
                  vital: vital,
                  patientAge: session.patientAge,
                  onChanged: (value, {double? systolic, double? diastolic, bool? boolValue}) {
                    controller.updateVital(
                      vital.code,
                      value: value,
                      systolic: systolic,
                      diastolic: diastolic,
                      boolValue: boolValue,
                    );
                  },
                );
              }),

              const SizedBox(height: 48),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: controller.loading
                    ? null
                    : () async {
                        final success = await controller.persistVitals();
                        if (success && context.mounted) {
                          // Navigate to assessment (Phase 2 placeholder)
                          context.go(
                            '/patients/visit/$visitId/assessment/${session.programme.name}',
                          );
                        }
                      },
                icon: controller.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                label: const Text('Next: Assessment'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VitalCard extends StatefulWidget {
  const _VitalCard({
    required this.vital,
    required this.onChanged,
    this.patientAge,
  });

  final VitalInput vital;
  final int? patientAge;
  final void Function(
    double? value, {
    double? systolic,
    double? diastolic,
    bool? boolValue,
  }) onChanged;

  @override
  State<_VitalCard> createState() => _VitalCardState();
}

class _VitalCardState extends State<_VitalCard> {
  late TextEditingController _controller;
  late TextEditingController _systolicController;
  late TextEditingController _diastolicController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.vital.value?.toString() ?? '',
    );
    _systolicController = TextEditingController(
      text: widget.vital.systolic?.toString() ?? '',
    );
    _diastolicController = TextEditingController(
      text: widget.vital.diastolic?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _VitalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vital.value != widget.vital.value) {
      _controller.text = widget.vital.value?.toString() ?? '';
    }
    if (oldWidget.vital.systolic != widget.vital.systolic) {
      _systolicController.text = widget.vital.systolic?.toString() ?? '';
    }
    if (oldWidget.vital.diastolic != widget.vital.diastolic) {
      _diastolicController.text = widget.vital.diastolic?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vital = widget.vital;
    final isBp = vital.code.contains('bp_') || vital.code == 'bp';
    final isBool = vital.boolValue != null || vital.code.contains('edema') || vital.code.contains('indrawing');

    // Get classification
    VitalClassification? classification;
    if (vital.hasValue && !isBool) {
      if (isBp && vital.systolic != null && vital.diastolic != null) {
        classification = VitalClassifier.classifyBp(
          vital.systolic!,
          vital.diastolic!,
        );
      } else if (vital.value != null) {
        classification = VitalClassifier.classify(
          vital.code,
          vital.value!,
          patientAge: widget.patientAge,
        );
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    vital.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (vital.unit != null && !isBool)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      vital.unit!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Input based on type
            if (isBool)
              // Boolean toggle
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('No'),
                      selected: vital.boolValue == false,
                      onSelected: (_) {
                        widget.onChanged(null, boolValue: false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Yes'),
                      selected: vital.boolValue == true,
                      selectedColor: theme.colorScheme.errorContainer,
                      onSelected: (_) {
                        widget.onChanged(null, boolValue: true);
                      },
                    ),
                  ),
                ],
              )
            else if (isBp || vital.code == 'bp_systolic')
              // Blood pressure (systolic/diastolic) - only show for systolic
              if (vital.code == 'bp_systolic')
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _systolicController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Systolic',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          final sys = double.tryParse(v);
                          final dia = double.tryParse(_diastolicController.text);
                          widget.onChanged(null, systolic: sys, diastolic: dia);
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('/'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _diastolicController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Diastolic',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          final sys = double.tryParse(_systolicController.text);
                          final dia = double.tryParse(v);
                          widget.onChanged(null, systolic: sys, diastolic: dia);
                        },
                      ),
                    ),
                  ],
                )
              else
                const SizedBox.shrink() // Skip diastolic field
            else
              // Numeric input
              TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Enter value',
                  suffixText: vital.unit,
                ),
                onChanged: (v) {
                  widget.onChanged(double.tryParse(v));
                },
              ),

            // Classification badge
            if (classification != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _classificationColor(classification, theme),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _classificationIcon(classification),
                      size: 16,
                      color: _classificationTextColor(classification, theme),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      classification.label,
                      style: TextStyle(
                        color: _classificationTextColor(classification, theme),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _classificationColor(VitalClassification c, ThemeData theme) {
    switch (c) {
      case VitalClassification.normal:
        return Colors.green.shade100;
      case VitalClassification.low:
        return Colors.orange.shade100;
      case VitalClassification.high:
        return Colors.orange.shade100;
      case VitalClassification.critical:
        return theme.colorScheme.errorContainer;
    }
  }

  Color _classificationTextColor(VitalClassification c, ThemeData theme) {
    switch (c) {
      case VitalClassification.normal:
        return Colors.green.shade800;
      case VitalClassification.low:
        return Colors.orange.shade800;
      case VitalClassification.high:
        return Colors.orange.shade800;
      case VitalClassification.critical:
        return theme.colorScheme.error;
    }
  }

  IconData _classificationIcon(VitalClassification c) {
    switch (c) {
      case VitalClassification.normal:
        return Icons.check_circle;
      case VitalClassification.low:
        return Icons.arrow_downward;
      case VitalClassification.high:
        return Icons.arrow_upward;
      case VitalClassification.critical:
        return Icons.warning;
    }
  }
}
