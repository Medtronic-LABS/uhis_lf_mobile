import 'package:flutter/material.dart';

import '../models/ncd_assessment.dart';

/// NCD Assessment form for blood pressure and glucose logging.
///
/// Used for hypertension and diabetes patients.
class NcdAssessmentForm extends StatefulWidget {
  const NcdAssessmentForm({
    super.key,
    this.initialData,
    this.onChanged,
    this.patientAge,
  });

  final NcdAssessment? initialData;
  final ValueChanged<NcdAssessment>? onChanged;
  final int? patientAge;

  @override
  State<NcdAssessmentForm> createState() => _NcdAssessmentFormState();
}

class _NcdAssessmentFormState extends State<NcdAssessmentForm> {
  late NcdAssessment _data;
  final _formKey = GlobalKey<FormState>();

  // BP controllers
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _temperatureController = TextEditingController();

  // Glucose controllers
  final _glucoseController = TextEditingController();
  final _hba1cController = TextEditingController();

  String _glucoseType = 'fasting';
  bool _isRegularSmoker = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ?? const NcdAssessment();
    _initControllers();
  }

  void _initControllers() {
    final bp = _data.bpLog;
    if (bp != null) {
      _weightController.text = bp.weight?.toString() ?? '';
      _heightController.text = bp.height?.toString() ?? '';
      _temperatureController.text = bp.temperature?.toString() ?? '';
      _isRegularSmoker = bp.isRegularSmoker ?? false;
    }

    final glucose = _data.glucoseLog;
    if (glucose != null) {
      _glucoseController.text = glucose.glucoseValue?.toString() ?? '';
      _hba1cController.text = glucose.hba1c?.toString() ?? '';
      _glucoseType = glucose.glucoseType ?? 'fasting';
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _temperatureController.dispose();
    _glucoseController.dispose();
    _hba1cController.dispose();
    super.dispose();
  }

  void _updateData() {
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);
    final bmi = (weight != null && height != null && height > 0)
        ? weight / ((height / 100) * (height / 100))
        : null;

    final bpLog = (_data.bpLog ?? const BpLog()).copyWith(
      weight: weight,
      height: height,
      bmi: bmi,
      bmiCategory: _getBmiCategory(bmi),
      temperature: double.tryParse(_temperatureController.text),
      isRegularSmoker: _isRegularSmoker,
      bpTakenOn: DateTime.now(),
    );

    final glucoseLog = (_data.glucoseLog ?? const GlucoseLog()).copyWith(
      glucoseValue: double.tryParse(_glucoseController.text),
      glucoseType: _glucoseType,
      hba1c: double.tryParse(_hba1cController.text),
      bgTakenOn: DateTime.now(),
    );

    _data = _data.copyWith(
      bpLog: bpLog,
      glucoseLog: glucoseLog,
    );

    widget.onChanged?.call(_data);
  }

  String? _getBmiCategory(double? bmi) {
    if (bmi == null) return null;
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  void _addBpReading() {
    showDialog(
      context: context,
      builder: (ctx) => _BpReadingDialog(
        onSave: (reading) {
          final currentReadings = _data.bpLog?.bpLogDetails ?? [];
          final updatedBp = (_data.bpLog ?? const BpLog()).copyWith(
            bpLogDetails: [...currentReadings, reading],
          );
          setState(() {
            _data = _data.copyWith(bpLog: updatedBp);
          });
          _updateData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bpReadings = _data.bpLog?.bpLogDetails ?? [];

    return Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Measurements section
          _SectionHeader(title: 'Measurements', icon: Icons.monitor_weight),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          decoration: const InputDecoration(
                            labelText: 'Weight',
                            suffixText: 'kg',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _updateData(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _heightController,
                          decoration: const InputDecoration(
                            labelText: 'Height',
                            suffixText: 'cm',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _updateData(),
                        ),
                      ),
                    ],
                  ),
                  if (_data.bpLog?.bmi != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'BMI: ${_data.bpLog!.bmi!.toStringAsFixed(1)}',
                            style: theme.textTheme.titleMedium,
                          ),
                          Chip(
                            label: Text(_data.bpLog!.bmiCategory ?? ''),
                            backgroundColor: _getBmiColor(_data.bpLog!.bmi!),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _temperatureController,
                    decoration: const InputDecoration(
                      labelText: 'Temperature (optional)',
                      suffixText: '°C',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateData(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Blood Pressure section
          _SectionHeader(title: 'Blood Pressure', icon: Icons.favorite),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bpReadings.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No BP readings yet. Add at least one reading.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    ...bpReadings.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final reading = entry.value;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text('${idx + 1}'),
                        ),
                        title: Text(
                          '${reading.systolic}/${reading.diastolic} mmHg',
                          style: theme.textTheme.titleMedium,
                        ),
                        subtitle: reading.pulse != null
                            ? Text('Pulse: ${reading.pulse} bpm')
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            final updated = List<BpLogDetails>.from(bpReadings);
                            updated.removeAt(idx);
                            setState(() {
                              _data = _data.copyWith(
                                bpLog: _data.bpLog?.copyWith(
                                  bpLogDetails: updated,
                                ),
                              );
                            });
                            _updateData();
                          },
                        ),
                      );
                    }),
                    const Divider(),
                    if (bpReadings.length >= 2)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Average',
                                  style: theme.textTheme.labelSmall,
                                ),
                                Text(
                                  '${_data.bpLog!.computedAvgSystolic.round()}/'
                                  '${_data.bpLog!.computedAvgDiastolic.round()}',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'mmHg',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                            if (_data.bpLog!.computedAvgPulse != null)
                              Column(
                                children: [
                                  Text(
                                    'Avg Pulse',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                  Text(
                                    '${_data.bpLog!.computedAvgPulse}',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'bpm',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _addBpReading,
                      icon: const Icon(Icons.add),
                      label: Text(bpReadings.isEmpty
                          ? 'Add BP Reading'
                          : 'Add Another Reading'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Glucose section
          _SectionHeader(title: 'Blood Glucose', icon: Icons.bloodtype),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'fasting', label: Text('Fasting')),
                      ButtonSegment(value: 'random', label: Text('Random')),
                      ButtonSegment(
                          value: 'postprandial', label: Text('Post-meal')),
                    ],
                    selected: {_glucoseType},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _glucoseType = selected.first;
                      });
                      _updateData();
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _glucoseController,
                    decoration: const InputDecoration(
                      labelText: 'Blood Glucose',
                      suffixText: 'mg/dL',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateData(),
                  ),
                  if (_data.glucoseLog?.glucoseStatus != null) ...[
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(_data.glucoseLog!.glucoseStatus!),
                      backgroundColor:
                          _getGlucoseStatusColor(_data.glucoseLog!.glucoseStatus!),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _hba1cController,
                    decoration: const InputDecoration(
                      labelText: 'HbA1c (optional)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _updateData(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Risk factors section
          _SectionHeader(title: 'Risk Factors', icon: Icons.warning_amber),
          Card(
            child: SwitchListTile(
              title: const Text('Regular smoker'),
              subtitle: const Text('Smokes daily or most days'),
              value: _isRegularSmoker,
              onChanged: (value) {
                setState(() {
                  _isRegularSmoker = value;
                });
                _updateData();
              },
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Color _getBmiColor(double bmi) {
    if (bmi < 18.5) return Colors.blue.shade100;
    if (bmi < 25) return Colors.green.shade100;
    if (bmi < 30) return Colors.orange.shade100;
    return Colors.red.shade100;
  }

  Color _getGlucoseStatusColor(String status) {
    switch (status) {
      case 'Normal':
        return Colors.green.shade100;
      case 'Prediabetes':
        return Colors.orange.shade100;
      case 'Diabetes':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade100;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
    );
  }
}

class _BpReadingDialog extends StatefulWidget {
  const _BpReadingDialog({required this.onSave});

  final ValueChanged<BpLogDetails> onSave;

  @override
  State<_BpReadingDialog> createState() => _BpReadingDialogState();
}

class _BpReadingDialogState extends State<_BpReadingDialog> {
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _pulseController = TextEditingController();

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add BP Reading'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _systolicController,
                  decoration: const InputDecoration(
                    labelText: 'Systolic',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('/'),
              ),
              Expanded(
                child: TextField(
                  controller: _diastolicController,
                  decoration: const InputDecoration(
                    labelText: 'Diastolic',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pulseController,
            decoration: const InputDecoration(
              labelText: 'Pulse (optional)',
              suffixText: 'bpm',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final systolic = int.tryParse(_systolicController.text);
            final diastolic = int.tryParse(_diastolicController.text);
            if (systolic != null && diastolic != null) {
              widget.onSave(BpLogDetails(
                systolic: systolic,
                diastolic: diastolic,
                pulse: int.tryParse(_pulseController.text),
              ));
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
