import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/scribe_controller.dart';
import '../../scribe/scribe_session.dart';
import '../models/ncd_assessment.dart';

/// NCD Assessment form for blood pressure and glucose logging.
///
/// Used for hypertension and diabetes patients.
/// Integrates with AI Scribe for auto-population of fields.
class NcdAssessmentForm extends StatefulWidget {
  const NcdAssessmentForm({
    super.key,
    this.initialData,
    this.onChanged,
    this.patientAge,
    this.previousWeight,
  });

  final NcdAssessment? initialData;
  final ValueChanged<NcdAssessment>? onChanged;
  final int? patientAge;
  final double? previousWeight;

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

  // Spec §5.2.2 HTN screening toggles. Nullable so AI Scribe can populate
  // them and the SK can leave a question unanswered without forcing a "No".
  bool? _morningHeadaches;
  bool? _chestTightnessOrSob;
  bool? _highSaltIntake;
  bool? _familyHistoryHtn;
  bool? _oneSidedWeakness;

  // AI field tracking
  final Map<String, FieldSource> _fieldSources = {};
  ScribeController? _scribeCtrl;
  bool _listeningToScribe = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ?? const NcdAssessment();
    _initControllers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindScribeController();
  }

  void _bindScribeController() {
    if (_listeningToScribe) return;
    
    try {
      _scribeCtrl = context.read<ScribeController>();
      _scribeCtrl?.addListener(_onScribeChanged);
      _listeningToScribe = true;
      
      // Apply any existing AI values
      if (_scribeCtrl?.session.state == ScribeState.fieldsPopulated) {
        _applyAIValues();
      }
    } catch (_) {
      // ScribeController not available in this context
    }
  }

  void _onScribeChanged() {
    final session = _scribeCtrl?.session;
    if (session == null) return;
    
    debugPrint('[NcdForm] Scribe state changed: ${session.state.name}, '
        'fieldsJustPopulated=${session.fieldsJustPopulated}, '
        'hasFormPrefillResult=${session.formPrefillResult != null}');
    
    // Apply AI values when fields are populated (either just now or previously)
    if (session.state == ScribeState.fieldsPopulated && 
        session.formPrefillResult != null) {
      _applyAIValues();
    }
  }

  void _applyAIValues() {
    final result = _scribeCtrl?.session.formPrefillResult;
    if (result == null) {
      debugPrint('[NcdForm] No formPrefillResult to apply');
      return;
    }

    debugPrint('[NcdForm] Applying AI values from ${result.fields.length} fields');

    for (final field in result.fields) {
      if (field.source == FieldSource.aiRejected) continue;
      
      final value = field.value;
      if (value == null) continue;

      switch (field.fieldId) {
        case 'weight':
          if (_weightController.text.isEmpty) {
            _weightController.text = value.toString();
            _fieldSources['weight'] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled weight: $value');
          }
          break;
        case 'height':
          if (_heightController.text.isEmpty) {
            _heightController.text = value.toString();
            _fieldSources['height'] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled height: $value');
          }
          break;
        case 'temperature':
          if (_temperatureController.text.isEmpty) {
            _temperatureController.text = value.toString();
            _fieldSources['temperature'] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled temperature: $value');
          }
          break;
        case 'glucoseValue':
        case 'glucose':
          if (_glucoseController.text.isEmpty) {
            _glucoseController.text = value.toString();
            _fieldSources['glucose'] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled glucose: $value');
          }
          break;
        case 'hba1c':
          if (_hba1cController.text.isEmpty) {
            _hba1cController.text = value.toString();
            _fieldSources['hba1c'] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled hba1c: $value');
          }
          break;
        case 'glucoseType':
          if (value is String) {
            _glucoseType = value;
            _fieldSources['glucoseType'] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled glucoseType: $value');
          }
          break;
        case 'isRegularSmoker':
        case 'smoker':
          // Handle both bool and string 'true'/'false'
          bool? boolValue;
          if (value is bool) {
            boolValue = value;
          } else if (value is String) {
            boolValue = value.toLowerCase() == 'true';
          }
          if (boolValue != null) {
            _isRegularSmoker = boolValue;
            _fieldSources['smoker'] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled smoker: $boolValue');
          }
          break;
        case 'morningHeadaches':
        case 'chestTightnessOrSob':
        case 'highSaltIntake':
        case 'familyHistoryHtn':
        case 'oneSidedWeakness':
          final boolValue = _coerceBool(value);
          if (boolValue != null) {
            switch (field.fieldId) {
              case 'morningHeadaches':
                _morningHeadaches = boolValue;
                break;
              case 'chestTightnessOrSob':
                _chestTightnessOrSob = boolValue;
                break;
              case 'highSaltIntake':
                _highSaltIntake = boolValue;
                break;
              case 'familyHistoryHtn':
                _familyHistoryHtn = boolValue;
                break;
              case 'oneSidedWeakness':
                _oneSidedWeakness = boolValue;
                break;
            }
            _fieldSources[field.fieldId] = FieldSource.aiPending;
            debugPrint('[NcdForm] AI filled ${field.fieldId}: $boolValue');
          }
          break;
        default:
          debugPrint('[NcdForm] Unhandled field: ${field.fieldId} = $value');
      }
    }

    if (mounted) {
      setState(() {});
      _updateData();
    }
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

    final screening = _data.htnScreening;
    if (screening != null) {
      _morningHeadaches = screening.morningHeadaches;
      _chestTightnessOrSob = screening.chestTightnessOrSob;
      _highSaltIntake = screening.highSaltIntake;
      _familyHistoryHtn = screening.familyHistoryHtn;
      _oneSidedWeakness = screening.oneSidedWeakness;
    }
  }

  @override
  void dispose() {
    _scribeCtrl?.removeListener(_onScribeChanged);
    _weightController.dispose();
    _heightController.dispose();
    _temperatureController.dispose();
    _glucoseController.dispose();
    _hba1cController.dispose();
    super.dispose();
  }

  /// Mark field as manually edited (clears AI source).
  void _onFieldEdited(String fieldId) {
    if (_fieldSources[fieldId] == FieldSource.aiPending) {
      _fieldSources[fieldId] = FieldSource.aiModified;
      _scribeCtrl?.modifyField(fieldId, null);
    }
  }

  /// Build AI indicator badge for a field.
  Widget? _buildAIBadge(String fieldId) {
    final source = _fieldSources[fieldId];
    if (source == null || source == FieldSource.manual) return null;
    
    Color color;
    String label;
    IconData icon;
    
    switch (source) {
      case FieldSource.aiPending:
        color = AppColors.aiPurple;
        label = 'AI';
        icon = Icons.auto_awesome;
        break;
      case FieldSource.aiAccepted:
        color = AppColors.statusSuccess;
        label = 'AI ✓';
        icon = Icons.check;
        break;
      case FieldSource.aiModified:
        color = AppColors.statusInfo;
        label = 'Edited';
        icon = Icons.edit;
        break;
      default:
        return null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Wrap a field with AI indicator if applicable.
  Widget _wrapWithAIIndicator(String fieldId, Widget child) {
    final badge = _buildAIBadge(fieldId);
    if (badge == null) return child;
    
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -8,
          right: 8,
          child: badge,
        ),
      ],
    );
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

    final screening = HtnScreening(
      morningHeadaches: _morningHeadaches,
      chestTightnessOrSob: _chestTightnessOrSob,
      highSaltIntake: _highSaltIntake,
      familyHistoryHtn: _familyHistoryHtn,
      oneSidedWeakness: _oneSidedWeakness,
    );

    _data = _data.copyWith(
      bpLog: bpLog,
      glucoseLog: glucoseLog,
      htnScreening: screening.hasAnswered ? screening : null,
    );

    widget.onChanged?.call(_data);
  }

  /// Coerce a JSON-ish scribe value (bool / string / int) into bool.
  bool? _coerceBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == 'yes' || lower == '1') return true;
      if (lower == 'false' || lower == 'no' || lower == '0') return false;
    }
    return null;
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _wrapWithAIIndicator(
                              'weight',
                              TextFormField(
                                controller: _weightController,
                                decoration: const InputDecoration(
                                  labelText: 'Weight',
                                  suffixText: 'kg',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) {
                                  _onFieldEdited('weight');
                                  _updateData();
                                },
                              ),
                            ),
                            if (widget.previousWeight != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Last: ${widget.previousWeight!.toStringAsFixed(1)} kg',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _wrapWithAIIndicator(
                          'height',
                          TextFormField(
                            controller: _heightController,
                            decoration: const InputDecoration(
                              labelText: 'Height',
                              suffixText: 'cm',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) {
                              _onFieldEdited('height');
                              _updateData();
                            },
                          ),
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
                  _wrapWithAIIndicator(
                    'temperature',
                    TextFormField(
                      controller: _temperatureController,
                      decoration: const InputDecoration(
                        labelText: 'Temperature (optional)',
                        suffixText: '°C',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        _onFieldEdited('temperature');
                        _updateData();
                      },
                    ),
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
                          tooltip: 'Delete BP reading ${idx + 1}',
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
                  _wrapWithAIIndicator(
                    'glucose',
                    TextFormField(
                      controller: _glucoseController,
                      decoration: const InputDecoration(
                        labelText: 'Blood Glucose',
                        suffixText: 'mg/dL',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        _onFieldEdited('glucose');
                        _updateData();
                      },
                    ),
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
                  _wrapWithAIIndicator(
                    'hba1c',
                    TextFormField(
                      controller: _hba1cController,
                      decoration: const InputDecoration(
                        labelText: 'HbA1c (optional)',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        _onFieldEdited('hba1c');
                        _updateData();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Spec §5.2.2 Hypertension screening — 4 Yes/No + stroke-sign
          // escalation. Stroke sign sits at top with a red icon so the SK
          // never misses it.
          _SectionHeader(
            title: NcdScreeningStrings.sectionTitle,
            icon: Icons.psychology_outlined,
            subtitle: NcdScreeningStrings.sectionSubtitle,
          ),
          Card(
            child: Column(
              children: [
                _wrapWithAIIndicator(
                  'oneSidedWeakness',
                  _NullableYesNoTile(
                    title: NcdScreeningStrings.strokeSignTitle,
                    bnLabel: NcdScreeningStrings.strokeSignBn,
                    subtitle: NcdScreeningStrings.strokeSignSubtitle,
                    icon: Icons.bolt,
                    iconColor: theme.colorScheme.error,
                    value: _oneSidedWeakness,
                    onChanged: (v) {
                      setState(() {
                        _oneSidedWeakness = v;
                        _onFieldEdited('oneSidedWeakness');
                      });
                      _updateData();
                    },
                  ),
                ),
                const Divider(height: 0),
                _wrapWithAIIndicator(
                  'morningHeadaches',
                  _NullableYesNoTile(
                    title: NcdScreeningStrings.morningHeadachesTitle,
                    bnLabel: NcdScreeningStrings.morningHeadachesBn,
                    value: _morningHeadaches,
                    onChanged: (v) {
                      setState(() {
                        _morningHeadaches = v;
                        _onFieldEdited('morningHeadaches');
                      });
                      _updateData();
                    },
                  ),
                ),
                const Divider(height: 0),
                _wrapWithAIIndicator(
                  'chestTightnessOrSob',
                  _NullableYesNoTile(
                    title: NcdScreeningStrings.chestTightnessTitle,
                    bnLabel: NcdScreeningStrings.chestTightnessBn,
                    value: _chestTightnessOrSob,
                    onChanged: (v) {
                      setState(() {
                        _chestTightnessOrSob = v;
                        _onFieldEdited('chestTightnessOrSob');
                      });
                      _updateData();
                    },
                  ),
                ),
                const Divider(height: 0),
                _wrapWithAIIndicator(
                  'highSaltIntake',
                  _NullableYesNoTile(
                    title: NcdScreeningStrings.highSaltTitle,
                    bnLabel: NcdScreeningStrings.highSaltBn,
                    value: _highSaltIntake,
                    onChanged: (v) {
                      setState(() {
                        _highSaltIntake = v;
                        _onFieldEdited('highSaltIntake');
                      });
                      _updateData();
                    },
                  ),
                ),
                const Divider(height: 0),
                _wrapWithAIIndicator(
                  'familyHistoryHtn',
                  _NullableYesNoTile(
                    title: NcdScreeningStrings.familyHistoryTitle,
                    bnLabel: NcdScreeningStrings.familyHistoryBn,
                    value: _familyHistoryHtn,
                    onChanged: (v) {
                      setState(() {
                        _familyHistoryHtn = v;
                        _onFieldEdited('familyHistoryHtn');
                      });
                      _updateData();
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Risk factors section
          _SectionHeader(title: 'Risk Factors', icon: Icons.warning_amber),
          _wrapWithAIIndicator(
            'smoker',
            Card(
              child: SwitchListTile(
                title: const Text('Regular smoker'),
                subtitle: const Text('Smokes daily or most days'),
                value: _isRegularSmoker,
                onChanged: (value) {
                  setState(() {
                    _isRegularSmoker = value;
                    _onFieldEdited('smoker');
                  });
                  _updateData();
                },
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Color _getBmiColor(double bmi) {
    if (bmi < 18.5) return AppColors.statusInfoSurface;
    if (bmi < 25) return AppColors.statusSuccessSurface;
    if (bmi < 30) return AppColors.statusWarningSurface;
    return AppColors.statusCriticalSurface;
  }

  Color _getGlucoseStatusColor(String status) {
    switch (status) {
      case 'Normal':
        return AppColors.statusSuccessSurface;
      case 'Prediabetes':
        return AppColors.statusWarningSurface;
      case 'Diabetes':
        return AppColors.statusCriticalSurface;
      default:
        return AppColors.cardSurfaceMuted;
    }
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
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
            const SizedBox(height: 4),
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
      ),
    );
  }
}

/// Tri-state Yes/No row with optional Bengali secondary label.
///
/// `null` value = unanswered (default). The SK selects Yes or No explicitly;
/// the row is unanswered until they do so. Stroke sign uses [iconColor] to
/// signal the band 1 escalation visually.
class _NullableYesNoTile extends StatelessWidget {
  const _NullableYesNoTile({
    required this.title,
    required this.bnLabel,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.iconColor,
  });

  final String title;
  final String bnLabel;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: iconColor ?? theme.colorScheme.primary, size: 22),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  bnLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<bool?>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Yes')),
              ButtonSegment(value: false, label: Text('No')),
            ],
            selected: value == null ? <bool?>{} : <bool?>{value},
            emptySelectionAllowed: true,
            onSelectionChanged: (selection) {
              onChanged(selection.isEmpty ? null : selection.first);
            },
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
