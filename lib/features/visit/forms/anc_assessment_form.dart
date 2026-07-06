import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/theme.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/scribe_controller.dart';
import '../../scribe/scribe_session.dart';
import '../models/anc_assessment.dart';

/// ANC Assessment form — matches apon_sushashthya_v12 screen s11 Step 2 design.
class AncAssessmentForm extends StatefulWidget {
  const AncAssessmentForm({
    super.key,
    this.initialData,
    this.onChanged,
    this.gestationalWeeks,
    this.previousWeight,
  });

  final AncAssessment? initialData;
  final ValueChanged<AncAssessment>? onChanged;
  final int? gestationalWeeks;
  final double? previousWeight;

  @override
  State<AncAssessmentForm> createState() => _AncAssessmentFormState();
}

class _AncAssessmentFormState extends State<AncAssessmentForm> {
  late AncAssessment _data;

  // Vitals
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

  // Urine
  String? _urinaryAlbumin;
  String? _urinaryBilirubin;
  String? _urinarySugar;

  // Blood
  final _hemoglobinController = TextEditingController();
  final _bsFastingController = TextEditingController();
  final _bsRandomController = TextEditingController();
  String _bsType = 'fasting';

  // Vaccination
  String? _ttTdStatus;
  final _folicConsumedController = TextEditingController();
  final _folicProvidedController = TextEditingController();
  final _ifaConsumedController = TextEditingController();
  final _ifaProvidedController = TextEditingController();
  final _calciumConsumedController = TextEditingController();
  final _calciumProvidedController = TextEditingController();

  // Danger signs by trimester
  final Set<String> _dangerSigns12 = {};
  final Set<String> _dangerSigns13To27 = {};
  final Set<String> _dangerSigns28To40 = {};

  // Birth preparedness
  String? _facilityIdentified;
  String? _ancOtherProviders;
  String? _ancMedicalDoctor;
  String? _ultrasound;

  // AI
  final Map<String, FieldSource> _fieldSources = {};
  ScribeController? _scribeCtrl;
  bool _listeningToScribe = false;

  bool _aiTrendExpanded = false;

  // ─── Lifecycle ───────────────────────────────────────────────

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
      if (_scribeCtrl?.session.state == ScribeState.fieldsPopulated) {
        _applyAIValues();
      }
    } catch (_) {}
  }

  void _onScribeChanged() {
    final session = _scribeCtrl?.session;
    if (session == null) return;
    if (session.state == ScribeState.fieldsPopulated &&
        session.formPrefillResult != null) {
      _applyAIValues();
    }
  }

  void _applyAIValues() {
    final result = _scribeCtrl?.session.formPrefillResult;
    if (result == null) return;
    for (final field in result.fields) {
      if (field.source == FieldSource.aiRejected) continue;
      final value = field.value;
      if (value == null) continue;
      switch (field.fieldId) {
        case 'weight':
          if (_weightController.text.isEmpty) {
            _weightController.text = value.toString();
            _fieldSources['weight'] = FieldSource.aiPending;
          }
        case 'height':
          if (_heightController.text.isEmpty) {
            _heightController.text = value.toString();
            _fieldSources['height'] = FieldSource.aiPending;
          }
        case 'systolic':
          if (_systolicController.text.isEmpty) {
            _systolicController.text = value.toString();
            _fieldSources['systolic'] = FieldSource.aiPending;
          }
        case 'diastolic':
          if (_diastolicController.text.isEmpty) {
            _diastolicController.text = value.toString();
            _fieldSources['diastolic'] = FieldSource.aiPending;
          }
        case 'hemoglobin':
          if (_hemoglobinController.text.isEmpty) {
            _hemoglobinController.text = value.toString();
            _fieldSources['hemoglobin'] = FieldSource.aiPending;
          }
        case 'folicAcidConsumed':
          if (_folicConsumedController.text.isEmpty) {
            _folicConsumedController.text = value.toString();
            _fieldSources['folicAcidConsumed'] = FieldSource.aiPending;
          }
        case 'folicAcidProvided':
          if (_folicProvidedController.text.isEmpty) {
            _folicProvidedController.text = value.toString();
            _fieldSources['folicAcidProvided'] = FieldSource.aiPending;
          }
        case 'vaginalBleeding':
        case 'headache':
        case 'fever':
        case 'blurredVision':
        case 'swellingHandsFace':
        case 'breathingDifficulty':
        case 'severeAbdominalPain':
          if (value == 'true') {
            final weeks = widget.gestationalWeeks ?? 0;
            if (weeks <= 12) {
              _dangerSigns12.add(field.fieldId);
            } else if (weeks <= 27) {
              _dangerSigns13To27.add(field.fieldId);
            } else {
              _dangerSigns28To40.add(field.fieldId);
            }
          }
        case 'ultrasound':
          if (_ultrasound == null) {
            _ultrasound = value == 'true' ? 'Done' : 'Not done';
            _fieldSources['ultrasound'] = FieldSource.aiPending;
          }
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
    _systolicController.dispose();
    _diastolicController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _fundalHeightController.dispose();
    _fetalHrController.dispose();
    _hemoglobinController.dispose();
    _bsFastingController.dispose();
    _bsRandomController.dispose();
    _folicConsumedController.dispose();
    _folicProvidedController.dispose();
    _ifaConsumedController.dispose();
    _ifaProvidedController.dispose();
    _calciumConsumedController.dispose();
    _calciumProvidedController.dispose();
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
        bloodSugarFasting: _bsType == 'fasting'
            ? double.tryParse(_bsFastingController.text)
            : null,
        bloodSugarRandom: _bsType == 'random'
            ? double.tryParse(_bsRandomController.text)
            : null,
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

  // ─── Helpers: BP / Hb status text ────────────────────────────

  String _bpStatusText() {
    final sys = int.tryParse(_systolicController.text);
    final dia = int.tryParse(_diastolicController.text);
    if (sys == null && dia == null) return '— —';
    final s = sys ?? 0;
    final d = dia ?? 0;
    if (s >= 160 || d >= 110) return '🚨 Urgent';
    if (s >= 140 || d >= 90) return '⚠ High';
    if (s >= 130 || d >= 85) return 'Elevated';
    return '✓ Normal';
  }

  Color _bpStatusColor() {
    final sys = int.tryParse(_systolicController.text);
    final dia = int.tryParse(_diastolicController.text);
    if (sys == null && dia == null) return AppColors.textMuted;
    final s = sys ?? 0;
    final d = dia ?? 0;
    if (s >= 160 || d >= 110) return AppColors.statusCritical;
    if (s >= 140 || d >= 90) return AppColors.statusCritical;
    if (s >= 130 || d >= 85) return AppColors.statusWarning;
    return AppColors.statusSuccess;
  }

  Widget _bpStatusBadge() {
    final text = _bpStatusText();
    final color = _bpStatusColor();
    late final Color bgColor;
    late final Color textColor;
    if (color == AppColors.statusCritical) {
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFF991B1B);
    } else if (color == AppColors.statusWarning) {
      bgColor = const Color(0xFFFEF3C7);
      textColor = const Color(0xFF92400E);
    } else {
      bgColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF166534);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  String _hbStatusText() {
    final hb = double.tryParse(_hemoglobinController.text);
    if (hb == null) return '';
    if (hb < 7) return 'Severe anaemia';
    if (hb < 10) return 'Moderate anaemia';
    if (hb < 11) return 'Mild anaemia';
    return '';
  }

  Color _hbStatusColor() {
    final hb = double.tryParse(_hemoglobinController.text);
    if (hb == null) return AppColors.textMuted;
    if (hb < 7) return AppColors.statusCritical;
    if (hb < 10) return AppColors.statusCritical;
    if (hb < 11) return AppColors.statusWarning;
    return AppColors.statusSuccess;
  }

  // ─── Urine display / storage helpers ─────────────────────────

  String? _urineAlbuminDisplay(String? stored) {
    switch (stored) {
      case 'Negative':
      case 'Absent':
        return 'Absent';
      case '+':
      case 'Present':
      case 'Positive':
        return 'Present';
      case 'Trace':
        return 'Trace';
      default:
        return null;
    }
  }

  String? _urineAlbuminStore(String? display) {
    switch (display) {
      case 'Absent':
        return 'Negative';
      case 'Present':
        return '+';
      case 'Trace':
        return 'Trace';
      default:
        return null;
    }
  }

  String? _urineBilirubinStore(String? display) {
    switch (display) {
      case 'Absent':
        return 'Negative';
      case 'Present':
        return 'Positive';
      case 'Trace':
        return 'Trace';
      default:
        return null;
    }
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildScribeBanner(),
        const SizedBox(height: 12),
        _buildPregnancyOverviewCard(),
        const SizedBox(height: 16),
        _sectionHeading("Today's vitals 👇"),
        const SizedBox(height: 8),
        ..._buildVitalCards(),
        const SizedBox(height: 16),
        _sectionHeading('Urine tests 🧪'),
        const SizedBox(height: 8),
        ..._buildUrineTestCards(),
        const SizedBox(height: 16),
        _sectionHeading('Blood tests 🩸'),
        const SizedBox(height: 8),
        ..._buildBloodTestCards(),
        const SizedBox(height: 16),
        _sectionHeading('Vaccination & supplements 💉'),
        const SizedBox(height: 8),
        ..._buildVaccinationCards(),
        const SizedBox(height: 16),
        _buildDangerSignsSection(),
        const SizedBox(height: 16),
        _buildBirthPrepCard(),
        const SizedBox(height: 12),
        _buildAiTrendCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeading(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      );

  // ─── AI Scribe banner ────────────────────────────────────────

  Widget _buildScribeBanner() {
    final isRecording =
        _scribeCtrl?.session.state == ScribeState.recording;
    final isActive = _scribeCtrl != null;

    return GestureDetector(
      onTap: isActive
          ? () {
              if (isRecording) {
                _scribeCtrl?.stopRecording();
              } else {
                _scribeCtrl?.startRecording();
              }
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isRecording
                ? [AppColors.aiPurpleDark, AppColors.aiPurple]
                : [AppColors.aiPurpleDark, AppColors.aiPurple],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  if (isRecording)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppColors.statusCritical,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.aiPurple,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRecording
                        ? '🎙 Recording…'
                        : '🎙 AI Scribe — tap to fill the form by voice',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isRecording
                        ? 'Tap to stop and fill the form'
                        : 'SK talks to her — fields fill automatically',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xA6FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Pregnancy overview ──────────────────────────────────────

  Widget _buildPregnancyOverviewCard() {
    final weeks = widget.gestationalWeeks;
    final weeksLabel = weeks != null ? '$weeks' : '—';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.navyMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.navyCta,
      ),
      child: Stack(
        children: [
          // Decorative arc
          Positioned(
            right: -10,
            top: -10,
            child: Opacity(
              opacity: 0.07,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 18),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gestational age hero row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GESTATIONAL AGE',
                          style: TextStyle(
                            color: Color(0x80FFFFFF),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              weeksLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'wks',
                              style: TextStyle(
                                color: Color(0xB3FFFFFF),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0x1AFFFFFF),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🤰', style: TextStyle(fontSize: 26)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // LMP + EDD sub-boxes
                Row(
                  children: [
                    Expanded(
                      child: _navySubBox(label: '📅 LMP', value: '—'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _navySubBox(
                        label: '🍼 EDD',
                        value: '—',
                        valueColor: const Color(0xFFFDE68A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navySubBox({
    required String label,
    required String value,
    Color valueColor = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0x80FFFFFF),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Vital cards ─────────────────────────────────────────────

  List<Widget> _buildVitalCards() {
    final sys = int.tryParse(_systolicController.text);
    final dia = int.tryParse(_diastolicController.text);
    final hasBp = sys != null || dia != null;
    final urineDisplay = _urineAlbuminDisplay(_urinaryAlbumin);

    final weeks = widget.gestationalWeeks;

    return [
      // Blood pressure
      _vitalCard(
        iconEmoji: '🩺',
        iconBg: AppColors.aiSurfaceStart,
        label: 'Blood pressure',
        banglaHint: 'রক্তচাপ · mmHg',
        statusWidget: hasBp ? _bpStatusBadge() : null,
        child: Row(
          children: [
            Expanded(
              child: _numInput(
                controller: _systolicController,
                hint: 'Systolic',
                onChanged: (_) {
                  setState(() {});
                  _updateData();
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '/',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              child: _numInput(
                controller: _diastolicController,
                hint: 'Diastolic',
                onChanged: (_) {
                  setState(() {});
                  _updateData();
                },
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),

      // Weight
      _vitalCard(
        iconEmoji: '⚖️',
        iconBg: const Color(0xFFF0FDF4),
        label: 'Weight',
        banglaHint: widget.previousWeight != null
            ? 'ওজন · kg · Last: ${widget.previousWeight!.toStringAsFixed(1)} kg'
            : 'ওজন · kg',
        child: _numInputSuffixed(
          controller: _weightController,
          hint: 'e.g. 58.5',
          suffix: 'kg',
          onChanged: (_) {
            setState(() {});
            _updateData();
          },
        ),
      ),
      const SizedBox(height: 8),

      // Urine protein (links to _urinaryAlbumin)
      _vitalCard(
        iconEmoji: '🧪',
        iconBg: const Color(0xFFFEF3C7),
        label: 'Urine protein',
        banglaHint: 'প্রস্রাবে প্রোটিন · dipstick',
        child: Row(
          children: [
            for (final opt in ['Absent', 'Trace', 'Present'])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: opt == 'Present' ? 0 : 6),
                  child: _pillOption(
                    label: opt,
                    selected: urineDisplay == opt,
                    selectedBg: opt == 'Present'
                        ? AppColors.statusCriticalSurface
                        : opt == 'Trace'
                            ? AppColors.statusWarningSurface
                            : AppColors.statusSuccessSurface,
                    selectedBorder: opt == 'Present'
                        ? AppColors.statusCritical
                        : opt == 'Trace'
                            ? AppColors.statusWarning
                            : AppColors.statusSuccess,
                    selectedText: opt == 'Present'
                        ? AppColors.statusCriticalText
                        : opt == 'Trace'
                            ? AppColors.statusWarningText
                            : AppColors.statusSuccessText,
                    onTap: () {
                      setState(() {
                        _urinaryAlbumin = _urineAlbuminStore(opt);
                      });
                      _updateData();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),

      // Fundal height
      _vitalCard(
        iconEmoji: '📏',
        iconBg: AppColors.ancSurface,
        label: 'Fundal height',
        banglaHint: weeks != null
            ? 'ফান্ডাল হাইট · expected ~$weeks cm at $weeks wks'
            : 'ফান্ডাল হাইট · cm',
        child: _numInputSuffixed(
          controller: _fundalHeightController,
          hint: 'e.g. 28',
          suffix: 'cm',
          onChanged: (_) {
            setState(() {});
            _updateData();
          },
        ),
      ),
      const SizedBox(height: 8),

      // Fetal movement
      _vitalCard(
        iconEmoji: '👶',
        iconBg: const Color(0xFFF0FDF4),
        label: 'Fetal movement',
        banglaHint: 'বাচ্চার নড়াচড়া · reported',
        child: Row(
          children: [
            for (final entry in const [
              ('Yes — normal', 'Present'),
              ('Less than usual', 'Reduced'),
              ('Not felt', 'Absent'),
            ])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: entry.$2 == 'Absent' ? 0 : 6,
                  ),
                  child: _pillOption(
                    label: entry.$1,
                    selected: _fetalMovement == entry.$2,
                    selectedBg: entry.$2 == 'Absent'
                        ? AppColors.statusCriticalSurface
                        : entry.$2 == 'Reduced'
                            ? AppColors.statusWarningSurface
                            : AppColors.statusSuccessSurface,
                    selectedBorder: entry.$2 == 'Absent'
                        ? AppColors.statusCritical
                        : entry.$2 == 'Reduced'
                            ? AppColors.statusWarning
                            : AppColors.statusSuccess,
                    selectedText: entry.$2 == 'Absent'
                        ? AppColors.statusCriticalText
                        : entry.$2 == 'Reduced'
                            ? AppColors.statusWarningText
                            : AppColors.statusSuccessText,
                    onTap: () {
                      setState(() => _fetalMovement = entry.$2);
                      _updateData();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  // ─── Urine test cards ─────────────────────────────────────────

  List<Widget> _buildUrineTestCards() {
    return [
      _fieldCard(
        label: 'Urinary albumin',
        banglaHint: 'প্রস্রাবে অ্যালবুমিন',
        child: _presentAbsentNa(
          selected: _urineAlbuminDisplay(_urinaryAlbumin),
          onChanged: (v) {
            setState(() => _urinaryAlbumin = _urineAlbuminStore(v));
            _updateData();
          },
        ),
      ),
      const SizedBox(height: 8),
      _fieldCard(
        label: 'Urinary sugar',
        banglaHint: 'প্রস্রাবে চিনি',
        child: _presentAbsentNa(
          selected: _urineAlbuminDisplay(_urinarySugar),
          onChanged: (v) {
            setState(() => _urinarySugar = _urineAlbuminStore(v));
            _updateData();
          },
        ),
      ),
      const SizedBox(height: 8),
      _fieldCard(
        label: 'Urinary bilirubin',
        banglaHint: 'প্রস্রাবে বিলিরুবিন',
        child: _presentAbsentNa(
          selected: _urineAlbuminDisplay(_urinaryBilirubin),
          onChanged: (v) {
            setState(() => _urinaryBilirubin = _urineBilirubinStore(v));
            _updateData();
          },
        ),
      ),
    ];
  }

  // ─── Blood test cards ─────────────────────────────────────────

  bool _showBsHint() {
    final bsCtrl = _bsType == 'fasting' ? _bsFastingController : _bsRandomController;
    final bs = double.tryParse(bsCtrl.text);
    if (bs == null) return false;
    // ANC GDM thresholds: fasting ≥ 5.1 mmol/L, random ≥ 7.8 mmol/L
    return _bsType == 'fasting' ? bs >= 5.1 : bs >= 7.8;
  }

  List<Widget> _buildBloodTestCards() {
    final hb = double.tryParse(_hemoglobinController.text);
    final hbStatus = hb != null ? _hbStatusText() : '';
    final hbStatusColor = hb != null ? _hbStatusColor() : AppColors.textMuted;
    final showHbHint = hb != null && hb < 11;

    return [
      // Hemoglobin
      _fieldCard(
        label: 'Hemoglobin',
        banglaHint: 'হিমোগ্লোবিন · g/dL',
        badge: hbStatus.isNotEmpty ? hbStatus : null,
        badgeColor: hbStatusColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _numInputSuffixed(
              controller: _hemoglobinController,
              hint: 'e.g. 10.5',
              suffix: 'g/dL',
              decimal: true,
              onChanged: (_) {
                setState(() {});
                _updateData();
              },
            ),
            if (showHbHint) ...[
              const SizedBox(height: 6),
              const Text(
                '⚠ Below 11 g/dL — anaemia. Counsel on iron-rich diet and IFA adherence.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.statusCriticalText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),

      // Blood sugar
      _fieldCard(
        label: 'Blood sugar',
        banglaHint: 'রক্তের শর্করা · mmol/L',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fasting / Random toggle
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _bsType = 'fasting';
                      _bsRandomController.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _bsType == 'fasting'
                            ? AppColors.aiSurfaceStart
                            : Colors.white,
                        border: Border.all(
                          color: _bsType == 'fasting'
                              ? AppColors.aiPurple
                              : AppColors.border,
                          width: 2,
                        ),
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(8),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Fasting',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _bsType == 'fasting'
                                ? AppColors.aiPurpleDark
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _bsType = 'random';
                      _bsFastingController.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _bsType == 'random'
                            ? AppColors.aiSurfaceStart
                            : Colors.white,
                        border: Border.all(
                          color: _bsType == 'random'
                              ? AppColors.aiPurple
                              : AppColors.border,
                          width: 2,
                        ),
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(8),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Random',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _bsType == 'random'
                                ? AppColors.aiPurpleDark
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _numInputSuffixed(
              controller: _bsType == 'fasting'
                  ? _bsFastingController
                  : _bsRandomController,
              hint: 'e.g. 5.5',
              suffix: 'mmol/L',
              decimal: true,
              onChanged: (_) {
                setState(() {});
                _updateData();
              },
            ),
            if (_showBsHint()) ...[
              const SizedBox(height: 6),
              const Text(
                '⚠ Elevated — advise dietary modification and refer for GDM screening.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.statusWarningText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  // ─── Vaccination cards ────────────────────────────────────────

  List<Widget> _buildVaccinationCards() {
    final ttValue = (_ttTdStatus == 'Completed' || _ttTdStatus == 'Yes')
        ? 'Yes'
        : (_ttTdStatus == 'Not started' || _ttTdStatus == 'No')
            ? 'No'
            : _ttTdStatus;

    return [
      // TT/TD
      _fieldCard(
        label: 'TT / TD completed',
        banglaHint: 'টিটি/টিডি সম্পন্ন',
        child: Row(
          children: [
            for (final opt in ['Yes', 'No'])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: opt == 'No' ? 0 : 6),
                  child: _pillOption(
                    label: opt,
                    selected: ttValue == opt,
                    selectedBg: opt == 'Yes'
                        ? AppColors.statusSuccessSurface
                        : AppColors.statusCriticalSurface,
                    selectedBorder: opt == 'Yes'
                        ? AppColors.statusSuccess
                        : AppColors.statusCritical,
                    selectedText: opt == 'Yes'
                        ? AppColors.statusSuccessText
                        : AppColors.statusCriticalText,
                    onTap: () {
                      setState(() => _ttTdStatus =
                          opt == 'Yes' ? 'Completed' : 'Not started');
                      _updateData();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),

      // Folic acid
      _supplementCard(
        label: 'Folic acid tablets',
        banglaHint: 'ফলিক অ্যাসিড',
        consumedCtrl: _folicConsumedController,
        providedCtrl: _folicProvidedController,
      ),
      const SizedBox(height: 8),

      // IFA
      _supplementCard(
        label: 'IFA tablets',
        banglaHint: 'আয়রন-ফলিক অ্যাসিড',
        consumedCtrl: _ifaConsumedController,
        providedCtrl: _ifaProvidedController,
      ),
      const SizedBox(height: 8),

      // Calcium
      _supplementCard(
        label: 'Calcium tablets',
        banglaHint: 'ক্যালসিয়াম',
        consumedCtrl: _calciumConsumedController,
        providedCtrl: _calciumProvidedController,
      ),
    ];
  }

  Widget _supplementCard({
    required String label,
    required String banglaHint,
    required TextEditingController consumedCtrl,
    required TextEditingController providedCtrl,
  }) {
    return _fieldCard(
      label: label,
      banglaHint: banglaHint,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cardSurfaceMuted,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Consumed last month',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: consumedCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '—',
                      hintStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textMuted,
                      ),
                    ),
                    onChanged: (_) => _updateData(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cardSurfaceMuted,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Provided this visit',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: providedCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      hintText: '—',
                      hintStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textMuted,
                      ),
                    ),
                    onChanged: (_) => _updateData(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Danger signs ─────────────────────────────────────────────

  Widget _buildDangerSignsSection() {
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Any danger signs now?',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'কোনো বিপদ লক্ষণ আছে? (tap any that apply)',
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              ...trimesterOptions.map((sign) {
                final selected = trimesterSigns.contains(sign);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (selected) {
                          trimesterSigns.remove(sign);
                        } else {
                          trimesterSigns.add(sign);
                        }
                      });
                      _updateData();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.statusCriticalSurface
                            : Colors.white,
                        border: Border.all(
                          color: selected
                              ? AppColors.statusCritical
                              : AppColors.border,
                          width: selected ? 2 : 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _dangerSignEmoji(sign) + sign,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: selected
                              ? AppColors.statusCriticalText
                              : AppColors.textPrimary,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // None of these
              GestureDetector(
                onTap: () {
                  setState(() => trimesterSigns.clear());
                  _updateData();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: trimesterSigns.isEmpty
                        ? AppColors.statusSuccessSurface
                        : Colors.white,
                    border: Border.all(
                      color: trimesterSigns.isEmpty
                          ? AppColors.statusSuccess
                          : AppColors.border,
                      width: trimesterSigns.isEmpty ? 2 : 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '✓ None of these',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: trimesterSigns.isEmpty
                          ? AppColors.statusSuccessText
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dangerSignEmoji(String sign) {
    if (sign.contains('bleeding') || sign.contains('Bleeding')) return '🩸 ';
    if (sign.contains('fluid') || sign.contains('Fluid')) return '💧 ';
    if (sign.contains('contraction') || sign.contains('Contraction')) {
      return '⏱️ ';
    }
    if (sign.contains('headache') || sign.contains('Headache') ||
        sign.contains('vision') || sign.contains('swelling') ||
        sign.contains('Swelling')) {
      return '🤕 ';
    }
    if (sign.contains('pain') || sign.contains('Pain')) return '😣 ';
    if (sign.contains('fever') || sign.contains('Fever')) return '🌡️ ';
    if (sign.contains('fetal') || sign.contains('Fetal') ||
        sign.contains('movement')) {
      return '👶 ';
    }
    if (sign.contains('vomiting') || sign.contains('Vomiting')) return '🤢 ';
    if (sign.contains('Convulsion')) return '⚡ ';
    if (sign.contains('breathing') || sign.contains('Breathing')) return '😮‍💨 ';
    return '• ';
  }

  // ─── Birth preparedness ───────────────────────────────────────

  static const List<String> _facilityOptions = [
    'UHFWC (Union Health & Family Welfare Centre)',
    'MCWC (Mother and Child Welfare Centre)',
    'UHC (Upazila Health Complex)',
    'District Hospital',
    'Medical College Hospital',
    'NGO Facility',
    'Private Facility',
    'Not identified yet',
    'Planned for home delivery',
  ];

  Widget _buildBirthPrepCard() {
    final hasSelection = _facilityIdentified != null &&
        _facilityIdentified!.isNotEmpty &&
        _facilityIdentified != 'No' &&
        _facilityIdentified != 'Undecided';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.aiSurfaceStart,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('🏥', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Birth preparedness',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'প্রসব প্রস্তুতি',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Facility question
          const Text(
            'Health facility for delivery?',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'কোথায় প্রসব করাতে চান?',
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),

          // Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.cardSurfaceMuted,
              border: Border.all(color: AppColors.aiBorder, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: _facilityOptions.contains(_facilityIdentified)
                  ? _facilityIdentified
                  : null,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              hint: const Text(
                '— Select facility —',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                fontFamily: 'Nunito',
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.aiPurple,
                size: 20,
              ),
              items: _facilityOptions
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(f),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => _facilityIdentified = v);
                _updateData();
              },
            ),
          ),

          // Confirmation chip (shown after selection)
          if (hasSelection) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.aiSurfaceStart,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppColors.aiPurple,
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'Delivery plan recorded',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.aiPurpleDark,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── AI trend card ────────────────────────────────────────────

  Widget _buildAiTrendCard() {
    final urineDisplay = _urineAlbuminDisplay(_urinaryAlbumin) ?? '—';

    return GestureDetector(
      onTap: () => setState(() => _aiTrendExpanded = !_aiTrendExpanded),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.statusWarningSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.statusWarningBorder),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.statusWarning,
                    size: 15,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'AI sees a trend across her visits',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.statusWarningText,
                      ),
                    ),
                  ),
                  Icon(
                    _aiTrendExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.statusWarningText,
                    size: 16,
                  ),
                ],
              ),
            ),
            if (_aiTrendExpanded) ...[
              const Divider(height: 1, color: AppColors.statusWarningBorder),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(1.2),
                        4: FlexColumnWidth(0.6),
                      },
                      children: [
                        // Header
                        TableRow(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.statusWarningBorder,
                              ),
                            ),
                          ),
                          children: [
                            _trendCell('', isHeader: true),
                            _trendCell('V1\n8 wks', isHeader: true),
                            _trendCell('V2\n4 wks', isHeader: true),
                            _trendCell('Today', isHeader: true),
                            _trendCell('↗', isHeader: true),
                          ],
                        ),
                        // Systolic
                        TableRow(children: [
                          _trendCell('Systolic', isRowLabel: true),
                          _trendCell('120'),
                          _trendCell('126'),
                          _trendCell(
                            _systolicController.text.isEmpty
                                ? '—'
                                : _systolicController.text,
                            rising: true,
                          ),
                          _trendCell('📈'),
                        ]),
                        // Diastolic
                        TableRow(children: [
                          _trendCell('Diastolic', isRowLabel: true),
                          _trendCell('78'),
                          _trendCell('82'),
                          _trendCell(
                            _diastolicController.text.isEmpty
                                ? '—'
                                : _diastolicController.text,
                            rising: true,
                          ),
                          _trendCell('📈'),
                        ]),
                        // Weight gain
                        TableRow(children: [
                          _trendCell('Weight gain', isRowLabel: true),
                          _trendCell('+1.5'),
                          _trendCell('+3.2'),
                          _trendCell(
                            _weightController.text.isEmpty
                                ? '—'
                                : '+${_weightController.text}',
                            rising: true,
                          ),
                          _trendCell('📈'),
                        ]),
                        // Urine protein
                        TableRow(children: [
                          _trendCell('Urine protein', isRowLabel: true),
                          _trendCell('Neg'),
                          _trendCell('Neg'),
                          _trendCell(
                            urineDisplay,
                            rising: urineDisplay != '—' &&
                                urineDisplay != 'Absent',
                          ),
                          _trendCell(
                            urineDisplay == 'Absent' || urineDisplay == '—'
                                ? '—'
                                : '📈',
                          ),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Each reading is below its alert line — but all three are climbing together. No single rule fires.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.statusWarningText,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.pink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'See what AI recommends →',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'AI পরামর্শ দেখুন',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
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

  // ─── Shared widget helpers ────────────────────────────────────

  /// White vital card with emoji icon + label + Bangla hint + optional status.
  Widget _vitalCard({
    required String iconEmoji,
    required Color iconBg,
    required String label,
    required String banglaHint,
    String? statusText,
    Color statusColor = AppColors.textMuted,
    Widget? statusWidget,
    required Widget child,
  }) {
    final showStatus =
        statusText != null && statusText.isNotEmpty && statusText != '— —';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child:
                      Text(iconEmoji, style: const TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      banglaHint,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (statusWidget != null)
                statusWidget
              else if (showStatus)
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  /// Simple field card without icon — label + Bangla + optional badge + child + optional hint.
  Widget _fieldCard({
    required String label,
    required String banglaHint,
    String? badge,
    Color badgeColor = AppColors.statusCritical,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            banglaHint,
            style:
                const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  /// Number input with suffix label (kg, cm, g/dL, mmol/L).
  Widget _numInputSuffixed({
    required TextEditingController controller,
    required String hint,
    required String suffix,
    bool decimal = false,
    required ValueChanged<String> onChanged,
  }) {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        TextField(
          controller: controller,
          keyboardType:
              TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            if (decimal)
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
            else
              FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: AppColors.cardSurfaceMuted,
            contentPadding: const EdgeInsets.fromLTRB(12, 9, 52, 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide:
                  const BorderSide(color: AppColors.navy, width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(
            suffix,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Number input without suffix (BP fields).
  Widget _numInput({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        textBaseline: TextBaseline.alphabetic,
      ),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: AppColors.cardSurfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
        ),
      ),
      onChanged: onChanged,
    );
  }

  /// Single pill option button (used in vitals + urine + vaccination).
  Widget _pillOption({
    required String label,
    required bool selected,
    required Color selectedBg,
    required Color selectedBorder,
    required Color selectedText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.white,
          border: Border.all(
            color: selected ? selectedBorder : AppColors.border,
            width: selected ? 2 : 1.5,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? selectedText : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  /// Present / Absent / N/A pill row (urine tests).
  Widget _presentAbsentNa({
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        for (final opt in ['Present', 'Absent', 'N/A'])
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: opt == 'N/A' ? 0 : 6),
              child: _pillOption(
                label: opt,
                selected: selected == opt,
                selectedBg: opt == 'Present'
                    ? AppColors.statusCriticalSurface
                    : opt == 'Absent'
                        ? AppColors.statusSuccessSurface
                        : AppColors.cardSurfaceMuted,
                selectedBorder: opt == 'Present'
                    ? AppColors.statusCritical
                    : opt == 'Absent'
                        ? AppColors.statusSuccess
                        : AppColors.textMuted,
                selectedText: opt == 'Present'
                    ? AppColors.statusCriticalText
                    : opt == 'Absent'
                        ? AppColors.statusSuccessText
                        : AppColors.textMuted,
                onTap: () => onChanged(selected == opt ? null : opt),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Trend cell helper ────────────────────────────────────────────────────────

Widget _trendCell(
  String text, {
  bool isHeader = false,
  bool isRowLabel = false,
  bool? rising,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
    child: Text(
      text,
      textAlign: isHeader || (!isRowLabel) ? TextAlign.center : TextAlign.left,
      style: isHeader
          ? const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.statusWarningText,
            )
          : isRowLabel
              ? const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7C2D12),
                )
              : TextStyle(
                  fontSize: 11,
                  fontWeight: rising == true ? FontWeight.w800 : FontWeight.w400,
                  color: rising == true
                      ? AppColors.statusWarningText
                      : const Color(0xFF78716C),
                ),
    ),
  );
}
