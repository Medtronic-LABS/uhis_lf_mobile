import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/scribe_controller.dart';
import '../../scribe/scribe_session.dart';
import '../models/iccm_assessment.dart';

/// ICCM Assessment form for children under 5.
///
/// Integrated Community Case Management following WHO IMCI guidelines.
/// Covers: danger signs, nutrition (MUAC), diarrhoea, fever, cough.
class IccmAssessmentForm extends StatefulWidget {
  const IccmAssessmentForm({
    super.key,
    this.initialData,
    this.onChanged,
    this.ageInMonths,
  });

  final IccmAssessment? initialData;
  final ValueChanged<IccmAssessment>? onChanged;
  final int? ageInMonths;

  @override
  State<IccmAssessmentForm> createState() => _IccmAssessmentFormState();
}

class _IccmAssessmentFormState extends State<IccmAssessmentForm> {
  late IccmAssessment _data;

  late GeneralDangerSigns _dangerSigns;
  late NutritionAssessment _nutrition;
  late DiarrhoeaAssessment _diarrhoea;
  late FeverAssessment _fever;
  late CoughAssessment _cough;

  final _muacController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _diarrhoeaDaysController = TextEditingController();
  final _breathsController = TextEditingController();
  final _feverDaysController = TextEditingController();
  final _coughDaysController = TextEditingController();

  // AI field tracking
  final Map<String, FieldSource> _fieldSources = {};
  ScribeController? _scribeCtrl;
  bool _listeningToScribe = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ?? IccmAssessment(ageInMonths: widget.ageInMonths);
    _initFromData();
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
      
      if (_scribeCtrl?.session.state == ScribeState.fieldsPopulated) {
        _applyAIValues();
      }
    } catch (_) {}
  }

  void _onScribeChanged() {
    final session = _scribeCtrl?.session;
    if (session == null) return;
    
    debugPrint('[IccmForm] Scribe state changed: ${session.state.name}');
    
    if (session.state == ScribeState.fieldsPopulated && 
        session.formPrefillResult != null) {
      _applyAIValues();
    }
  }

  void _applyAIValues() {
    final result = _scribeCtrl?.session.formPrefillResult;
    if (result == null) return;

    debugPrint('[IccmForm] Applying AI values from ${result.fields.length} fields');

    for (final field in result.fields) {
      if (field.source == FieldSource.aiRejected) continue;
      final value = field.value;
      if (value == null) continue;

      switch (field.fieldId) {
        case 'weight':
          if (_weightController.text.isEmpty) {
            _weightController.text = value.toString();
            _fieldSources['weight'] = FieldSource.aiPending;
            debugPrint('[IccmForm] AI filled weight: $value');
          }
          break;
        case 'height':
          if (_heightController.text.isEmpty) {
            _heightController.text = value.toString();
            _fieldSources['height'] = FieldSource.aiPending;
            debugPrint('[IccmForm] AI filled height: $value');
          }
          break;
        case 'temperature':
          if (_temperatureController.text.isEmpty) {
            _temperatureController.text = value.toString();
            _fieldSources['temperature'] = FieldSource.aiPending;
            debugPrint('[IccmForm] AI filled temperature: $value');
          }
          break;
        case 'muac':
          if (_muacController.text.isEmpty) {
            _muacController.text = value.toString();
            _fieldSources['muac'] = FieldSource.aiPending;
            debugPrint('[IccmForm] AI filled muac: $value');
          }
          break;
        case 'respiratoryRate':
          if (_breathsController.text.isEmpty) {
            _breathsController.text = value.toString();
            _fieldSources['respiratoryRate'] = FieldSource.aiPending;
            debugPrint('[IccmForm] AI filled respiratoryRate: $value');
          }
          break;
        case 'durationDays':
          // Apply to most relevant duration field
          if (_diarrhoea.hasDiarrhoea == true && _diarrhoeaDaysController.text.isEmpty) {
            _diarrhoeaDaysController.text = value.toString();
          } else if (_fever.hasFever == true && _feverDaysController.text.isEmpty) {
            _feverDaysController.text = value.toString();
          } else if (_cough.hasCough == true && _coughDaysController.text.isEmpty) {
            _coughDaysController.text = value.toString();
          }
          debugPrint('[IccmForm] AI filled durationDays: $value');
          break;
        // Symptoms
        case 'fever':
          if (value == 'true') {
            _fever = _fever.copyWith(hasFever: true);
            debugPrint('[IccmForm] AI detected fever');
          }
          break;
        case 'cough':
          if (value == 'true') {
            _cough = _cough.copyWith(hasCough: true);
            debugPrint('[IccmForm] AI detected cough');
          }
          break;
        case 'diarrhea':
          if (value == 'true') {
            _diarrhoea = _diarrhoea.copyWith(hasDiarrhoea: true);
            debugPrint('[IccmForm] AI detected diarrhoea');
          }
          break;
        case 'vomiting':
          if (value == 'true') {
            _dangerSigns = _dangerSigns.copyWith(vomitsEverything: true);
            debugPrint('[IccmForm] AI detected vomiting (danger sign)');
          }
          break;
        case 'convulsions':
          if (value == 'true') {
            _dangerSigns = _dangerSigns.copyWith(hasConvulsions: true);
            debugPrint('[IccmForm] AI detected convulsions (danger sign)');
          }
          break;
        case 'notEating':
          if (value == 'true') {
            _dangerSigns = _dangerSigns.copyWith(unableToBreastfeed: true);
            debugPrint('[IccmForm] AI detected not eating (danger sign)');
          }
          break;
        default:
          debugPrint('[IccmForm] Unhandled field: ${field.fieldId} = $value');
      }
    }

    if (mounted) {
      setState(() {});
      _updateData();
    }
  }

  void _initFromData() {
    _dangerSigns = _data.generalDangerSigns ?? const GeneralDangerSigns();
    _nutrition = _data.nutritionAssessment ?? const NutritionAssessment();
    _diarrhoea = _data.diarrhoeaAssessment ?? const DiarrhoeaAssessment();
    _fever = _data.feverAssessment ?? const FeverAssessment();
    _cough = _data.coughAssessment ?? const CoughAssessment();

    _muacController.text = _nutrition.muacCm?.toString() ?? '';
    _weightController.text = _nutrition.weightKg?.toString() ?? '';
    _heightController.text = _nutrition.heightCm?.toString() ?? '';
    _temperatureController.text = _fever.temperature?.toString() ?? '';
    _diarrhoeaDaysController.text = _diarrhoea.durationDays?.toString() ?? '';
    _breathsController.text = _cough.breathsPerMinute?.toString() ?? '';
    _feverDaysController.text = _fever.durationDays?.toString() ?? '';
    _coughDaysController.text = _cough.durationDays?.toString() ?? '';
  }

  @override
  void dispose() {
    _scribeCtrl?.removeListener(_onScribeChanged);
    _muacController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _temperatureController.dispose();
    _diarrhoeaDaysController.dispose();
    _breathsController.dispose();
    _feverDaysController.dispose();
    _coughDaysController.dispose();
    super.dispose();
  }

  void _updateData() {
    _data = IccmAssessment(
      ageInMonths: widget.ageInMonths,
      generalDangerSigns: _dangerSigns,
      nutritionAssessment: _nutrition,
      diarrhoeaAssessment: _diarrhoea,
      feverAssessment: _fever,
      coughAssessment: _cough,
    );
    widget.onChanged?.call(_data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgentReferral = _data.urgentReferralNeeded;

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Urgent referral banner
        if (urgentReferral)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.emergency, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'URGENT REFERRAL NEEDED',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      Text(
                        'Danger signs or severe condition present',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Age display
        if (widget.ageInMonths != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.child_care,
                    color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Text(
                  'Age: ${widget.ageInMonths} months',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        // General Danger Signs
        _SectionHeader(
          title: 'General Danger Signs',
          icon: Icons.warning_amber,
          hasAlert: _dangerSigns.hasDangerSigns,
        ),
        Card(
          child: Column(
            children: [
              _DangerSignTile(
                title: 'Unable to drink or breastfeed',
                value: _dangerSigns.unableToBreastfeed,
                onChanged: (v) {
                  setState(() {
                    _dangerSigns =
                        _dangerSigns.copyWith(unableToBreastfeed: v);
                  });
                  _updateData();
                },
              ),
              const Divider(height: 1),
              _DangerSignTile(
                title: 'Vomits everything',
                value: _dangerSigns.vomitsEverything,
                onChanged: (v) {
                  setState(() {
                    _dangerSigns = _dangerSigns.copyWith(vomitsEverything: v);
                  });
                  _updateData();
                },
              ),
              const Divider(height: 1),
              _DangerSignTile(
                title: 'Convulsions',
                value: _dangerSigns.hasConvulsions,
                onChanged: (v) {
                  setState(() {
                    _dangerSigns = _dangerSigns.copyWith(hasConvulsions: v);
                  });
                  _updateData();
                },
              ),
              const Divider(height: 1),
              _DangerSignTile(
                title: 'Lethargic or unconscious',
                value: _dangerSigns.lethargicOrUnconscious,
                onChanged: (v) {
                  setState(() {
                    _dangerSigns =
                        _dangerSigns.copyWith(lethargicOrUnconscious: v);
                  });
                  _updateData();
                },
              ),
              const Divider(height: 1),
              _DangerSignTile(
                title: 'Chest indrawing',
                value: _dangerSigns.chestIndrawing,
                onChanged: (v) {
                  setState(() {
                    _dangerSigns = _dangerSigns.copyWith(chestIndrawing: v);
                  });
                  _updateData();
                },
              ),
              const Divider(height: 1),
              _DangerSignTile(
                title: 'Stridor when calm',
                value: _dangerSigns.stridor,
                onChanged: (v) {
                  setState(() {
                    _dangerSigns = _dangerSigns.copyWith(stridor: v);
                  });
                  _updateData();
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Nutrition Assessment
        _SectionHeader(
          title: 'Nutrition (MUAC)',
          icon: Icons.straighten,
          hasAlert: _nutrition.referralNeeded,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _muacController,
                  decoration: const InputDecoration(
                    labelText: 'MUAC',
                    suffixText: 'cm',
                    border: OutlineInputBorder(),
                    helperText: 'Mid-upper arm circumference',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    _nutrition =
                        _nutrition.copyWith(muacCm: double.tryParse(v));
                    _updateData();
                    setState(() {});
                  },
                ),
                if (_nutrition.muacColorCode != null) ...[
                  const SizedBox(height: 12),
                  _MuacIndicator(
                    colorCode: _nutrition.muacColorCode!,
                    status: _nutrition.nutritionStatus!,
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Oedema of both feet'),
                  value: _nutrition.hasOedemaOfBothFeet,
                  onChanged: (v) {
                    setState(() {
                      _nutrition = _nutrition.copyWith(hasOedemaOfBothFeet: v);
                    });
                    _updateData();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        decoration: const InputDecoration(
                          labelText: 'Weight',
                          suffixText: 'kg',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          _nutrition =
                              _nutrition.copyWith(weightKg: double.tryParse(v));
                          _updateData();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _heightController,
                        decoration: const InputDecoration(
                          labelText: 'Height',
                          suffixText: 'cm',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          _nutrition =
                              _nutrition.copyWith(heightCm: double.tryParse(v));
                          _updateData();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Diarrhoea
        _SectionHeader(
          title: 'Diarrhoea',
          icon: Icons.water_drop,
          hasAlert: _diarrhoea.referralNeeded,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Does child have diarrhoea?'),
                  value: _diarrhoea.hasDiarrhoea,
                  onChanged: (v) {
                    setState(() {
                      _diarrhoea = _diarrhoea.copyWith(hasDiarrhoea: v);
                    });
                    _updateData();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (_diarrhoea.hasDiarrhoea) ...[
                  const Divider(),
                  TextField(
                    controller: _diarrhoeaDaysController,
                    decoration: const InputDecoration(
                      labelText: 'Duration',
                      suffixText: 'days',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      _diarrhoea =
                          _diarrhoea.copyWith(durationDays: int.tryParse(v));
                      _updateData();
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Blood in stool'),
                    value: _diarrhoea.isBloodyDiarrhoea,
                    onChanged: (v) {
                      setState(() {
                        _diarrhoea = _diarrhoea.copyWith(isBloodyDiarrhoea: v);
                      });
                      _updateData();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Signs of severe dehydration'),
                    subtitle:
                        const Text('Sunken eyes, skin pinch very slow, unable to drink'),
                    value: _diarrhoea.hasSevereDehydration,
                    onChanged: (v) {
                      setState(() {
                        _diarrhoea = _diarrhoea.copyWith(hasSevereDehydration: v);
                      });
                      _updateData();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Signs of some dehydration'),
                    subtitle: const Text('Restless, drinks eagerly, skin pinch slow'),
                    value: _diarrhoea.hasModerateDehydration,
                    onChanged: (v) {
                      setState(() {
                        _diarrhoea =
                            _diarrhoea.copyWith(hasModerateDehydration: v);
                      });
                      _updateData();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_diarrhoea.classification != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: _diarrhoea.referralNeeded
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _diarrhoea.referralNeeded
                                ? Icons.warning
                                : Icons.info_outline,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _diarrhoea.classification!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text('Treatment provided:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  CheckboxListTile(
                    title: const Text('ORS'),
                    value: _diarrhoea.orsDispensed,
                    onChanged: (v) {
                      setState(() {
                        _diarrhoea = _diarrhoea.copyWith(orsDispensed: v);
                      });
                      _updateData();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Zinc'),
                    value: _diarrhoea.zincDispensed,
                    onChanged: (v) {
                      setState(() {
                        _diarrhoea = _diarrhoea.copyWith(zincDispensed: v);
                      });
                      _updateData();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Fever
        _SectionHeader(
          title: 'Fever',
          icon: Icons.thermostat,
          hasAlert: _fever.referralNeeded,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Does child have fever?'),
                  value: _fever.hasFever,
                  onChanged: (v) {
                    setState(() {
                      _fever = _fever.copyWith(hasFever: v);
                    });
                    _updateData();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (_fever.hasFever) ...[
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _temperatureController,
                          decoration: const InputDecoration(
                            labelText: 'Temperature',
                            suffixText: '°C',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            _fever =
                                _fever.copyWith(temperature: double.tryParse(v));
                            _updateData();
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _feverDaysController,
                          decoration: const InputDecoration(
                            labelText: 'Duration',
                            suffixText: 'days',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            _fever =
                                _fever.copyWith(durationDays: int.tryParse(v));
                            _updateData();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('RDT Result:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String?>(
                    segments: const [
                      ButtonSegment(value: null, label: Text('Not done')),
                      ButtonSegment(value: 'negative', label: Text('Negative')),
                      ButtonSegment(value: 'positive', label: Text('Positive')),
                    ],
                    selected: {_fever.rdtResult},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _fever = _fever.copyWith(rdtResult: selected.first);
                      });
                      _updateData();
                    },
                  ),
                  if (_fever.isRdtPositive) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning,
                              color: theme.colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Text(
                            'Malaria - ACT treatment indicated',
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CheckboxListTile(
                      title: const Text('ACT dispensed'),
                      value: _fever.actDispensed,
                      onChanged: (v) {
                        setState(() {
                          _fever = _fever.copyWith(actDispensed: v);
                        });
                        _updateData();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Cough/ARI
        _SectionHeader(
          title: 'Cough / Difficulty Breathing',
          icon: Icons.air,
          hasAlert: _cough.referralNeeded,
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Does child have cough or difficulty breathing?'),
                  value: _cough.hasCough,
                  onChanged: (v) {
                    setState(() {
                      _cough = _cough.copyWith(hasCough: v);
                    });
                    _updateData();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (_cough.hasCough) ...[
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _breathsController,
                          decoration: InputDecoration(
                            labelText: 'Breaths/minute',
                            border: const OutlineInputBorder(),
                            helperText: widget.ageInMonths != null
                                ? 'Fast: ≥${FastBreathingThresholds.getThreshold(widget.ageInMonths!)}'
                                : null,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final breaths = int.tryParse(v);
                            final isFast = breaths != null &&
                                widget.ageInMonths != null &&
                                FastBreathingThresholds.isFastBreathing(
                                    breaths, widget.ageInMonths!);
                            _cough = _cough.copyWith(
                              breathsPerMinute: breaths,
                              hasFastBreathing: isFast,
                            );
                            _updateData();
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _coughDaysController,
                          decoration: const InputDecoration(
                            labelText: 'Duration',
                            suffixText: 'days',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            _cough =
                                _cough.copyWith(durationDays: int.tryParse(v));
                            _updateData();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Chest indrawing'),
                    subtitle: const Text('Lower chest wall draws in when breathing'),
                    value: _cough.hasChestIndrawing,
                    onChanged: (v) {
                      setState(() {
                        _cough = _cough.copyWith(hasChestIndrawing: v);
                      });
                      _updateData();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_cough.classification != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: _cough.referralNeeded
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _cough.referralNeeded
                                ? Icons.warning
                                : Icons.info_outline,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _cough.classification!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  if (_cough.hasFastBreathing && !_cough.hasChestIndrawing) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Amoxicillin dispensed'),
                      value: _cough.amoxicillinDispensed,
                      onChanged: (v) {
                        setState(() {
                          _cough = _cough.copyWith(amoxicillinDispensed: v);
                        });
                        _updateData();
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),

        // Summary
        if (_data.conditionsSummary.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader(title: 'Summary', icon: Icons.summarize),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _data.conditionsSummary
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.circle, size: 8),
                              const SizedBox(width: 8),
                              Expanded(child: Text(c)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],

        const SizedBox(height: 32),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.hasAlert = false,
  });

  final String title;
  final IconData icon;
  final bool hasAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: hasAlert ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: hasAlert ? theme.colorScheme.error : null,
            ),
          ),
          if (hasAlert) ...[
            const SizedBox(width: 8),
            Icon(Icons.warning, size: 16, color: theme.colorScheme.error),
          ],
        ],
      ),
    );
  }
}

class _DangerSignTile extends StatelessWidget {
  const _DangerSignTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: value ? theme.colorScheme.error : null,
          fontWeight: value ? FontWeight.bold : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            label: 'Yes',
            selected: value,
            onTap: () => onChanged(true),
            isWarning: true,
          ),
          const SizedBox(width: 8),
          _ToggleButton(
            label: 'No',
            selected: !value,
            onTap: () => onChanged(false),
            isWarning: false,
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
    required this.isWarning,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? (isWarning ? theme.colorScheme.error : theme.colorScheme.primary)
        : theme.colorScheme.surfaceContainerHighest;

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: InkWell(
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
      ),
    );
  }
}

class _MuacIndicator extends StatelessWidget {
  const _MuacIndicator({
    required this.colorCode,
    required this.status,
  });

  final String colorCode;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = switch (colorCode) {
      'red' => AppColors.statusCriticalSurface,
      'yellow' => AppColors.statusWarningSurface,
      'green' => AppColors.statusSuccessSurface,
      _ => AppColors.cardSurfaceMuted,
    };
    final fgColor = switch (colorCode) {
      'red' => AppColors.imciText,
      'yellow' => AppColors.ncdText,
      'green' => AppColors.tbText,
      _ => AppColors.textPrimary,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: switch (colorCode) {
                'red' => AppColors.statusCritical,
                'yellow' => AppColors.statusWarning,
                'green' => AppColors.statusSuccess,
                _ => AppColors.textMuted,
              },
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  colorCode.toUpperCase(),
                  style: TextStyle(
                    color: fgColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(color: fgColor),
                ),
              ],
            ),
          ),
          if (colorCode == 'red')
            Icon(Icons.warning, color: AppColors.statusCritical),
        ],
      ),
    );
  }
}
