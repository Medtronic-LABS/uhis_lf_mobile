import 'package:flutter/material.dart';

import '../models/tb_assessment.dart';

/// TB Assessment form with WHO 4-symptom screen and contact tracing.
class TbAssessmentForm extends StatefulWidget {
  const TbAssessmentForm({
    super.key,
    this.initialData,
    this.onChanged,
  });

  final TbAssessment? initialData;
  final ValueChanged<TbAssessment>? onChanged;

  @override
  State<TbAssessmentForm> createState() => _TbAssessmentFormState();
}

class _TbAssessmentFormState extends State<TbAssessmentForm> {
  late TbAssessment _data;
  late TbScreening _screening;
  late ContactTracing _contactTracing;

  String? _otherRelationship;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ?? const TbAssessment();
    _screening = _data.tbScreening ?? const TbScreening();
    _contactTracing = _data.contactTracing ?? const ContactTracing();
    _otherRelationship = _contactTracing.otherRelationshipIC;
  }

  void _updateData() {
    _data = TbAssessment(
      tbScreening: _screening,
      contactTracing: _contactTracing,
    );
    widget.onChanged?.call(_data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // TB Screening section
        _SectionHeader(
          title: 'TB Symptom Screening',
          subtitle: 'WHO 4-symptom screen',
          icon: Icons.masks,
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              _SymptomTile(
                title: 'Cough',
                subtitle: 'Any duration',
                value: _screening.hasCough,
                onChanged: (value) {
                  setState(() {
                    _screening = _screening.copyWith(hasCough: value);
                  });
                  _updateData();
                },
              ),
              if (_screening.hasCough == true)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SymptomTile(
                    title: 'Cough ≥2 weeks',
                    subtitle: 'Prolonged cough',
                    value: _screening.hasCoughLastedLonger,
                    onChanged: (value) {
                      setState(() {
                        _screening =
                            _screening.copyWith(hasCoughLastedLonger: value);
                      });
                      _updateData();
                    },
                  ),
                ),
              const Divider(height: 1),
              _SymptomTile(
                title: 'Night sweats',
                subtitle: 'Drenching sweats at night',
                value: _screening.hasNightSweats,
                onChanged: (value) {
                  setState(() {
                    _screening = _screening.copyWith(hasNightSweats: value);
                  });
                  _updateData();
                },
              ),
              const Divider(height: 1),
              _SymptomTile(
                title: 'Fever',
                subtitle: 'Ongoing or recurrent fever',
                value: _screening.hasFever,
                onChanged: (value) {
                  setState(() {
                    _screening = _screening.copyWith(hasFever: value);
                  });
                  _updateData();
                },
              ),
              const Divider(height: 1),
              _SymptomTile(
                title: 'Weight loss',
                subtitle: 'Unintentional weight loss',
                value: _screening.hasWeightLoss,
                onChanged: (value) {
                  setState(() {
                    _screening = _screening.copyWith(hasWeightLoss: value);
                  });
                  _updateData();
                },
              ),
            ],
          ),
        ),

        // Screening result banner
        if (_screening.isPositiveScreen) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TB Screen Positive',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      Text(
                        '${_screening.symptomCount} symptom(s) present. '
                        'Referral recommended for further evaluation.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Date of onset
        _SectionHeader(
          title: 'Symptom Onset',
          icon: Icons.calendar_today,
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(
              _screening.dateOfOnset != null
                  ? '${_screening.dateOfOnset!.day}/${_screening.dateOfOnset!.month}/${_screening.dateOfOnset!.year}'
                  : 'Select date',
            ),
            subtitle: const Text('When did symptoms start?'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _screening.dateOfOnset ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                setState(() {
                  _screening = _screening.copyWith(dateOfOnset: date);
                });
                _updateData();
              }
            },
          ),
        ),

        const SizedBox(height: 24),

        // Contact tracing section
        _SectionHeader(
          title: 'Contact Tracing',
          subtitle: 'If this is a contact of a TB case',
          icon: Icons.people,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Relationship to index case',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TbRelationshipOptions.values.map((option) {
                    final selected = _contactTracing.relationshipToIC == option;
                    return ChoiceChip(
                      label: Text(option),
                      selected: selected,
                      onSelected: (value) {
                        setState(() {
                          _contactTracing = _contactTracing.copyWith(
                            relationshipToIC: value ? option : null,
                          );
                        });
                        _updateData();
                      },
                    );
                  }).toList(),
                ),
                if (_contactTracing.relationshipToIC == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Specify relationship',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      _otherRelationship = value;
                      _contactTracing = _contactTracing.copyWith(
                        otherRelationshipIC: value,
                      );
                      _updateData();
                    },
                    controller:
                        TextEditingController(text: _otherRelationship),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Sleep location',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ...TbSleepLocationOptions.values.map((option) {
                  return RadioListTile<String>(
                    title: Text(option),
                    value: option,
                    groupValue: _contactTracing.sleepLocation,
                    onChanged: (value) {
                      setState(() {
                        _contactTracing =
                            _contactTracing.copyWith(sleepLocation: value);
                      });
                      _updateData();
                    },
                    contentPadding: EdgeInsets.zero,
                  );
                }),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Previously treated for TB'),
                  value: _contactTracing.hasPreviouslyTreatedForTB ?? false,
                  onChanged: (value) {
                    setState(() {
                      _contactTracing = _contactTracing.copyWith(
                        hasPreviouslyTreatedForTB: value,
                      );
                    });
                    _updateData();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SymptomTile extends StatelessWidget {
  const _SymptomTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            label: 'Yes',
            selected: value == true,
            onTap: () => onChanged(true),
            isPositive: false,
          ),
          const SizedBox(width: 8),
          _ToggleButton(
            label: 'No',
            selected: value == false,
            onTap: () => onChanged(false),
            isPositive: true,
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isPositive,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? (isPositive
            ? theme.colorScheme.primary
            : theme.colorScheme.error)
        : theme.colorScheme.surfaceContainerHighest;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
