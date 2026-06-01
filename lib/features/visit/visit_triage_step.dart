import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'visit_controller.dart';
import 'visit_session.dart';

/// Visit Triage Step — symptom checklist and duration.
class VisitTriageStep extends StatelessWidget {
  const VisitTriageStep({
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
            appBar: AppBar(title: const Text('Triage')),
            body: const Center(
              child: Text('Visit not found. Please start a new visit.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Triage - ${session.programme.wireTag}'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Leave visit?'),
                    content: const Text(
                      'Your progress will be saved. You can resume later.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Stay'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.go('/patients/${session.patientId}');
                        },
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Greeting instruction
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ask ${session.patientName ?? "the patient"} about their symptoms',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Symptoms section
              Text(
                'Symptoms',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to select all that apply',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // Symptom chips grid
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: session.symptoms.map((symptom) {
                  final isSelected = symptom.selected;
                  return FilterChip(
                    selected: isSelected,
                    onSelected: (_) => controller.toggleSymptom(symptom.code),
                    label: Text(symptom.label),
                    showCheckmark: true,
                    selectedColor: theme.colorScheme.primaryContainer,
                    checkmarkColor: theme.colorScheme.primary,
                  );
                }).toList(),
              ),

              const SizedBox(height: 32),

              // Duration section
              Text(
                'Duration',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'How long has the patient had these symptoms?',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              // Duration radio buttons
              ...SymptomDuration.values.map((duration) {
                final isSelected = session.duration == duration;
                return RadioListTile<SymptomDuration>(
                  value: duration,
                  groupValue: session.duration,
                  onChanged: (value) {
                    if (value != null) controller.setDuration(value);
                  },
                  title: Text(duration.label),
                  selected: isSelected,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  tileColor: isSelected
                      ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                      : null,
                );
              }),

              const SizedBox(height: 32),

              // AI red-flag banner placeholder (Phase 3)
              // TODO: Add AI red-flag detection banner here

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
                        final success = await controller.persistTriage();
                        if (success && context.mounted) {
                          context.go('/patients/visit/$visitId/vitals');
                        }
                      },
                icon: controller.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                label: const Text('Next: Vitals'),
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
