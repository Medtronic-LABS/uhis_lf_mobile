import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/scribe_controller.dart';
import '../../scribe/scribe_session.dart';
import '../models/anc_assessment.dart';

/// ANC Assessment form for pregnant women.
///
/// Contains 5 sections:
/// 1. Vaccination and supplements
/// 2. Danger signs by trimester
/// 3. Physical examination
/// 4. Point of care investigations
/// 5. Birth preparedness
class AncAssessmentForm extends StatefulWidget {
  const AncAssessmentForm({
    super.key,
    this.initialData,
    this.onChanged,
    this.gestationalWeeks,
  });

  final AncAssessment? initialData;
  final ValueChanged<AncAssessment>? onChanged;
  final int? gestationalWeeks;

  @override
  State<AncAssessmentForm> createState() => _AncAssessmentFormState();
}

class _AncAssessmentFormState extends State<AncAssessmentForm> {
  late AncAssessment _data;
  // Vaccination controllers
  String? _ttTdStatus;
  final _folicConsumedController = TextEditingController();
  final _folicProvidedController = TextEditingController();
  final _ifaConsumedController = TextEditingController();
  final _ifaProvidedController = TextEditingController();
  final _calciumConsumedController = TextEditingController();
  final _calciumProvidedController = TextEditingController();

  // Physical exam controllers
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _fundalHeightController = TextEditingController();
  final _fetalHrController = TextEditingController();
  String? _fetalMovement;
  String? _presentation;
  String? _oedema;
  String? _pallor;

  // Investigations controllers
  String? _urinaryAlbumin;
  String? _urinaryBilirubin;
  String? _urinarySugar;
  final _bsFastingController = TextEditingController();
  final _bsRandomController = TextEditingController();
  final _hemoglobinController = TextEditingController();

  // Birth preparedness
  String? _facilityIdentified;
  String? _ancOtherProviders;
  String? _ancMedicalDoctor;
  String? _ultrasound;

  // Danger signs
  final Set<String> _dangerSigns12 = {};
  final Set<String> _dangerSigns13To27 = {};
  final Set<String> _dangerSigns28To40 = {};

  // AI field tracking
  final Map<String, FieldSource> _fieldSources = {};
  ScribeController? _scribeCtrl;
  bool _listeningToScribe = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ??
        AncAssessment(gestationalWeeks: widget.gestationalWeeks);
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
    
    debugPrint('[AncForm] Scribe state changed: ${session.state.name}, '
        'fieldsJustPopulated=${session.fieldsJustPopulated}, '
        'hasFormPrefillResult=${session.formPrefillResult != null}');
    
    if (session.state == ScribeState.fieldsPopulated && 
        session.formPrefillResult != null) {
      _applyAIValues();
    }
  }

  void _applyAIValues() {
    final result = _scribeCtrl?.session.formPrefillResult;
    if (result == null) return;

    debugPrint('[AncForm] Applying AI values from ${result.fields.length} fields');

    for (final field in result.fields) {
      if (field.source == FieldSource.aiRejected) continue;
      
      final value = field.value;
      if (value == null) continue;

      switch (field.fieldId) {
        case 'weight':
          if (_weightController.text.isEmpty) {
            _weightController.text = value.toString();
            _fieldSources['weight'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled weight: $value');
          }
          break;
        case 'height':
          if (_heightController.text.isEmpty) {
            _heightController.text = value.toString();
            _fieldSources['height'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled height: $value');
          }
          break;
        case 'systolic':
          if (_systolicController.text.isEmpty) {
            _systolicController.text = value.toString();
            _fieldSources['systolic'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled systolic: $value');
          }
          break;
        case 'diastolic':
          if (_diastolicController.text.isEmpty) {
            _diastolicController.text = value.toString();
            _fieldSources['diastolic'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled diastolic: $value');
          }
          break;
        case 'hemoglobin':
          if (_hemoglobinController.text.isEmpty) {
            _hemoglobinController.text = value.toString();
            _fieldSources['hemoglobin'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled hemoglobin: $value');
          }
          break;
        case 'folicAcidConsumed':
          if (_folicConsumedController.text.isEmpty) {
            _folicConsumedController.text = value.toString();
            _fieldSources['folicAcidConsumed'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled folicAcidConsumed: $value');
          }
          break;
        case 'folicAcidProvided':
          if (_folicProvidedController.text.isEmpty) {
            _folicProvidedController.text = value.toString();
            _fieldSources['folicAcidProvided'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled folicAcidProvided: $value');
          }
          break;
        // ANC danger signs
        case 'vaginalBleeding':
        case 'headache':
        case 'fever':
        case 'blurredVision':
        case 'swellingHandsFace':
        case 'breathingDifficulty':
        case 'severeAbdominalPain':
          if (value == 'true') {
            // Add to appropriate trimester danger signs
            final weeks = widget.gestationalWeeks ?? 0;
            if (weeks <= 12) {
              _dangerSigns12.add(field.fieldId);
            } else if (weeks <= 27) {
              _dangerSigns13To27.add(field.fieldId);
            } else {
              _dangerSigns28To40.add(field.fieldId);
            }
            debugPrint('[AncForm] AI detected danger sign: ${field.fieldId}');
          }
          break;
        case 'ultrasound':
          if (_ultrasound == null) {
            _ultrasound = value == 'true' ? 'yes' : 'no';
            _fieldSources['ultrasound'] = FieldSource.aiPending;
            debugPrint('[AncForm] AI filled ultrasound: $_ultrasound');
          }
          break;
        default:
          debugPrint('[AncForm] Unhandled field: ${field.fieldId} = $value');
      }
    }

    if (mounted) {
      setState(() {});
      _updateData();
    }
  }

  void _initFromData() {
    final vacc = _data.vaccinationAndSupplements;
    if (vacc != null) {
      _ttTdStatus = vacc.ttTdCompleted;
      _folicConsumedController.text =
          vacc.folicAcidTotalConsumed?.toString() ?? '';
      _folicProvidedController.text = vacc.folicAcidProvided?.toString() ?? '';
      _ifaConsumedController.text = vacc.ifaTotalConsumed?.toString() ?? '';
      _ifaProvidedController.text = vacc.ifaProvided?.toString() ?? '';
      _calciumConsumedController.text =
          vacc.calciumTotalConsumed?.toString() ?? '';
      _calciumProvidedController.text = vacc.calciumProvided?.toString() ?? '';
    }

    final exam = _data.medicalHistoryPhysicalExamination;
    if (exam != null) {
      _systolicController.text = exam.bloodPressureSystolic?.toString() ?? '';
      _diastolicController.text = exam.bloodPressureDiastolic?.toString() ?? '';
      _weightController.text = exam.weight?.toString() ?? '';
      _heightController.text = exam.height?.toString() ?? '';
      _fundalHeightController.text = exam.fundalHeight?.toString() ?? '';
      _fetalHrController.text = exam.fetalHeartRate?.toString() ?? '';
      _fetalMovement = exam.fetalMovement;
      _presentation = exam.presentation;
      _oedema = exam.oedema;
      _pallor = exam.pallor;
    }

    final inv = _data.pointOfCareInvestigations;
    if (inv != null) {
      _urinaryAlbumin = inv.urinaryAlbumin;
      _urinaryBilirubin = inv.urinaryBilirubin;
      _urinarySugar = inv.urinarySugar;
      _bsFastingController.text = inv.bloodSugarFasting?.toString() ?? '';
      _bsRandomController.text = inv.bloodSugarRandom?.toString() ?? '';
      _hemoglobinController.text = inv.hemoglobin?.toString() ?? '';
    }

    final birth = _data.ancServicesBirthPreparedness;
    if (birth != null) {
      _facilityIdentified = birth.facilityIdentifiedForDelivery;
      _ancOtherProviders = birth.ancVisitsOtherProviders;
      _ancMedicalDoctor = birth.ancFromMedicalDoctor;
      _ultrasound = birth.ultrasound;
    }

    final danger = _data.dangerSignsRiskIdentification;
    if (danger != null) {
      _dangerSigns12.addAll(danger.dangerSignsExperienced12);
      _dangerSigns13To27.addAll(danger.dangerSignsExperienced13To27);
      _dangerSigns28To40.addAll(danger.dangerSignsExperienced28To40);
    }
  }

  @override
  void dispose() {
    _scribeCtrl?.removeListener(_onScribeChanged);
    _folicConsumedController.dispose();
    _folicProvidedController.dispose();
    _ifaConsumedController.dispose();
    _ifaProvidedController.dispose();
    _calciumConsumedController.dispose();
    _calciumProvidedController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _fundalHeightController.dispose();
    _fetalHrController.dispose();
    _bsFastingController.dispose();
    _bsRandomController.dispose();
    _hemoglobinController.dispose();
    super.dispose();
  }

  void _updateData() {
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);
    final bmi = (weight != null && height != null && height > 0)
        ? weight / ((height / 100) * (height / 100))
        : null;

    _data = AncAssessment(
      gestationalWeeks: widget.gestationalWeeks,
      vaccinationAndSupplements: VaccinationAndSupplements(
        ttTdCompleted: _ttTdStatus,
        folicAcidTotalConsumed: int.tryParse(_folicConsumedController.text),
        folicAcidProvided: int.tryParse(_folicProvidedController.text),
        ifaTotalConsumed: int.tryParse(_ifaConsumedController.text),
        ifaProvided: int.tryParse(_ifaProvidedController.text),
        calciumTotalConsumed: int.tryParse(_calciumConsumedController.text),
        calciumProvided: int.tryParse(_calciumProvidedController.text),
      ),
      dangerSignsRiskIdentification: DangerSignsRiskIdentification(
        dangerSignsExperienced12: _dangerSigns12.toList(),
        dangerSignsExperienced13To27: _dangerSigns13To27.toList(),
        dangerSignsExperienced28To40: _dangerSigns28To40.toList(),
      ),
      medicalHistoryPhysicalExamination: MedicalHistoryPhysicalExamination(
        bloodPressureSystolic: int.tryParse(_systolicController.text),
        bloodPressureDiastolic: int.tryParse(_diastolicController.text),
        weight: weight,
        height: height,
        bmi: bmi,
        bmiCategory: _getBmiCategory(bmi),
        fundalHeight: double.tryParse(_fundalHeightController.text),
        fetalHeartRate: int.tryParse(_fetalHrController.text),
        fetalMovement: _fetalMovement,
        presentation: _presentation,
        oedema: _oedema,
        pallor: _pallor,
      ),
      pointOfCareInvestigations: PointOfCareInvestigations(
        urinaryAlbumin: _urinaryAlbumin,
        urinaryBilirubin: _urinaryBilirubin,
        urinarySugar: _urinarySugar,
        bloodSugarFasting: double.tryParse(_bsFastingController.text),
        bloodSugarRandom: double.tryParse(_bsRandomController.text),
        hemoglobin: double.tryParse(_hemoglobinController.text),
      ),
      ancServicesBirthPreparedness: AncServicesBirthPreparedness(
        facilityIdentifiedForDelivery: _facilityIdentified,
        ancVisitsOtherProviders: _ancOtherProviders,
        ancFromMedicalDoctor: _ancMedicalDoctor,
        ultrasound: _ultrasound,
      ),
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

  int get _trimester {
    final weeks = widget.gestationalWeeks ?? 0;
    if (weeks <= 12) return 1;
    if (weeks <= 27) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        ..._buildVaccinationsSection(),
        const SizedBox(height: 20),
        ..._buildDangerSignsSection(),
        const SizedBox(height: 20),
        ..._buildPhysicalExamSection(),
        const SizedBox(height: 20),
        ..._buildInvestigationsSection(),
        const SizedBox(height: 20),
        ..._buildBirthPrepSection(),
      ],
    );
  }

  List<Widget> _buildVaccinationsSection() {
    return [
        _SectionHeader(title: 'TT/Td Vaccination', icon: Icons.vaccines),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              children: ['Completed', 'Partial', 'Not started', 'Unknown']
                  .map((status) => ChoiceChip(
                        label: Text(status),
                        selected: _ttTdStatus == status,
                        onSelected: (selected) {
                          setState(() {
                            _ttTdStatus = selected ? status : null;
                          });
                          _updateData();
                        },
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionHeader(title: 'Supplements', icon: Icons.medication),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SupplementRow(
                  label: 'Folic Acid',
                  consumedController: _folicConsumedController,
                  providedController: _folicProvidedController,
                  onChanged: _updateData,
                ),
                const SizedBox(height: 12),
                _SupplementRow(
                  label: 'IFA (Iron-Folic Acid)',
                  consumedController: _ifaConsumedController,
                  providedController: _ifaProvidedController,
                  onChanged: _updateData,
                ),
                const SizedBox(height: 12),
                _SupplementRow(
                  label: 'Calcium',
                  consumedController: _calciumConsumedController,
                  providedController: _calciumProvidedController,
                  onChanged: _updateData,
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildDangerSignsSection() {
    final theme = Theme.of(context);
    final trimesterOptions = _trimester == 1
        ? AncDangerSignsOptions.firstTrimester
        : _trimester == 2
            ? AncDangerSignsOptions.secondTrimester
            : AncDangerSignsOptions.thirdTrimester;
    final trimesterSigns = _trimester == 1
        ? _dangerSigns12
        : _trimester == 2
            ? _dangerSigns13To27
            : _dangerSigns28To40;

    final hasDanger = trimesterSigns.isNotEmpty;

    return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Trimester $_trimester (${widget.gestationalWeeks ?? 0} weeks)',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionHeader(
          title: 'Danger Signs Experienced',
          icon: Icons.warning_amber,
        ),
        Card(
          child: Column(
            children: trimesterOptions.map((sign) {
              final selected = trimesterSigns.contains(sign);
              return CheckboxListTile(
                title: Text(sign),
                value: selected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      trimesterSigns.add(sign);
                    } else {
                      trimesterSigns.remove(sign);
                    }
                  });
                  _updateData();
                },
              );
            }).toList(),
          ),
        ),
        if (hasDanger) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Danger signs present. Referral may be needed.',
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
    ];
  }

  List<Widget> _buildPhysicalExamSection() {
    return [
        _SectionHeader(title: 'Vitals', icon: Icons.favorite),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _systolicController,
                        decoration: const InputDecoration(
                          labelText: 'Systolic',
                          suffixText: 'mmHg',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _updateData(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _diastolicController,
                        decoration: const InputDecoration(
                          labelText: 'Diastolic',
                          suffixText: 'mmHg',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _updateData(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                        onChanged: (_) => _updateData(),
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
                        onChanged: (_) => _updateData(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionHeader(title: 'Obstetric Examination', icon: Icons.pregnant_woman),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _fundalHeightController,
                        decoration: const InputDecoration(
                          labelText: 'Fundal Height',
                          suffixText: 'cm',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _updateData(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _fetalHrController,
                        decoration: const InputDecoration(
                          labelText: 'Fetal HR',
                          suffixText: 'bpm',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _updateData(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'Fetal Movement',
                  value: _fetalMovement,
                  options: ['Present', 'Absent', 'Reduced'],
                  onChanged: (v) {
                    setState(() => _fetalMovement = v);
                    _updateData();
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'Presentation',
                  value: _presentation,
                  options: ['Cephalic', 'Breech', 'Transverse', 'Unknown'],
                  onChanged: (v) {
                    setState(() => _presentation = v);
                    _updateData();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DropdownField(
                        label: 'Oedema',
                        value: _oedema,
                        options: ['None', 'Mild', 'Moderate', 'Severe'],
                        onChanged: (v) {
                          setState(() => _oedema = v);
                          _updateData();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DropdownField(
                        label: 'Pallor',
                        value: _pallor,
                        options: ['None', 'Mild', 'Moderate', 'Severe'],
                        onChanged: (v) {
                          setState(() => _pallor = v);
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
    ];
  }

  List<Widget> _buildInvestigationsSection() {
    final hb = double.tryParse(_hemoglobinController.text);
    final anemiaStatus = _data.pointOfCareInvestigations?.anemiaStatus;

    return [
        _SectionHeader(title: 'Urine Tests', icon: Icons.science),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _DropdownField(
                  label: 'Urinary Albumin',
                  value: _urinaryAlbumin,
                  options: ['Negative', 'Trace', '+', '++', '+++'],
                  onChanged: (v) {
                    setState(() => _urinaryAlbumin = v);
                    _updateData();
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'Urinary Bilirubin',
                  value: _urinaryBilirubin,
                  options: ['Negative', 'Positive'],
                  onChanged: (v) {
                    setState(() => _urinaryBilirubin = v);
                    _updateData();
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'Urinary Sugar',
                  value: _urinarySugar,
                  options: ['Negative', 'Trace', '+', '++', '+++'],
                  onChanged: (v) {
                    setState(() => _urinarySugar = v);
                    _updateData();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionHeader(title: 'Blood Tests', icon: Icons.bloodtype),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bsFastingController,
                        decoration: const InputDecoration(
                          labelText: 'Fasting BS',
                          suffixText: 'mg/dL',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _updateData(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _bsRandomController,
                        decoration: const InputDecoration(
                          labelText: 'Random BS',
                          suffixText: 'mg/dL',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _updateData(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hemoglobinController,
                  decoration: const InputDecoration(
                    labelText: 'Hemoglobin',
                    suffixText: 'g/dL',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    _updateData();
                    setState(() {});
                  },
                ),
                if (hb != null && anemiaStatus != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getAnemiaColor(hb),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hb < 7 ? Icons.warning : Icons.info_outline,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(anemiaStatus),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  Color _getAnemiaColor(double hb) {
    if (hb >= 11) return AppColors.statusSuccessSurface;
    if (hb >= 10) return AppColors.statusWarningSurface;
    if (hb >= 7) return AppColors.statusWarningSurface;
    return AppColors.statusCriticalSurface;
  }

  List<Widget> _buildBirthPrepSection() {
    return [
        _SectionHeader(title: 'Birth Preparedness', icon: Icons.local_hospital),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _DropdownField(
                  label: 'Facility identified for delivery',
                  value: _facilityIdentified,
                  options: ['Yes', 'No', 'Undecided'],
                  onChanged: (v) {
                    setState(() => _facilityIdentified = v);
                    _updateData();
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'ANC visits from other providers',
                  value: _ancOtherProviders,
                  options: ['Yes', 'No'],
                  onChanged: (v) {
                    setState(() => _ancOtherProviders = v);
                    _updateData();
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'ANC from medical doctor',
                  value: _ancMedicalDoctor,
                  options: ['Yes', 'No'],
                  onChanged: (v) {
                    setState(() => _ancMedicalDoctor = v);
                    _updateData();
                  },
                ),
                const SizedBox(height: 12),
                _DropdownField(
                  label: 'Ultrasound',
                  value: _ultrasound,
                  options: ['Done', 'Not done', 'Planned'],
                  onChanged: (v) {
                    setState(() => _ultrasound = v);
                    _updateData();
                  },
                ),
              ],
            ),
          ),
        ),
    ];
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

class _SupplementRow extends StatelessWidget {
  const _SupplementRow({
    required this.label,
    required this.consumedController,
    required this.providedController,
    required this.onChanged,
  });

  final String label;
  final TextEditingController consumedController;
  final TextEditingController providedController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: consumedController,
                decoration: const InputDecoration(
                  labelText: 'Total consumed',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: providedController,
                decoration: const InputDecoration(
                  labelText: 'Provided today',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      initialValue: value,
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
