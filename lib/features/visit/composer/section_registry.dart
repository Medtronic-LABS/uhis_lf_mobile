/// Section registry — single home for all [FormSection] definitions.
///
/// Add new sections here; the [FormCompositor] picks them up automatically.
/// Ordering is by [FormSection.priority] — do not sort this list manually.
///
/// Engineering Design Standards:
///   - One home for section definitions (DRY).
///   - No I/O — static data only.
///   - Label keys are [ComposerStrings] constants; never raw strings.
library;

import '../../../core/models/programme.dart';
import '../../scribe/form_field_schema_builder.dart' as _scribe
    show FormFieldSchema, FieldType;
import 'form_section.dart';

/// Global section registry.
///
/// [SectionRegistry.all] is the authoritative list of sections.
/// Sections may be added for new programmes without modifying the compositor.
class SectionRegistry {
  SectionRegistry._();

  // ── RDT select option values ───────────────────────────────────────────────
  static const String rdtPositive = 'positive';
  static const String rdtNegative = 'negative';
  static const String rdtNotDone = 'not_done';

  // ── Section definitions ────────────────────────────────────────────────────

  static final List<FormSection> _sections = [
    // ── Vitals (priority 10) — ICCM + TB ─────────────────────────────────────
    FormSection(
      sectionId: 'vitals',
      programmes: {Programme.imci, Programme.tb},
      priority: 10,
      fields: const [
        FieldDef(
          fieldId: 'temperature',
          type: FieldType.doubleField,
          labelKey: 'fieldTemperature',
          unit: '°C',
          min: 30,
          max: 44,
        ),
        FieldDef(
          fieldId: 'breathsPerMinute',
          type: FieldType.intField,
          labelKey: 'fieldBreathsPerMinute',
          unit: '/min',
        ),
        FieldDef(
          fieldId: 'weightKg',
          type: FieldType.doubleField,
          labelKey: 'fieldWeightKg',
          unit: 'kg',
        ),
        FieldDef(
          fieldId: 'muacCm',
          type: FieldType.doubleField,
          labelKey: 'fieldMuacCm',
          unit: 'cm',
          min: 5,
          max: 20,
        ),
        FieldDef(
          fieldId: 'spo2',
          type: FieldType.intField,
          labelKey: 'fieldSpo2',
          unit: '%',
          min: 50,
          max: 100,
        ),
      ],
    ),

    // ── Danger Signs (priority 20) — ICCM + TB ────────────────────────────────
    FormSection(
      sectionId: 'danger-signs',
      programmes: {Programme.imci, Programme.tb},
      priority: 20,
      fields: const [
        FieldDef(
          fieldId: 'unableToBreastfeed',
          type: FieldType.booleanField,
          labelKey: 'fieldUnableToBreastfeed',
        ),
        FieldDef(
          fieldId: 'vomitsEverything',
          type: FieldType.booleanField,
          labelKey: 'fieldVomitsEverything',
        ),
        FieldDef(
          fieldId: 'hasConvulsions',
          type: FieldType.booleanField,
          labelKey: 'fieldHasConvulsions',
        ),
        FieldDef(
          fieldId: 'lethargicOrUnconscious',
          type: FieldType.booleanField,
          labelKey: 'fieldLethargic',
        ),
        FieldDef(
          fieldId: 'chestIndrawing',
          type: FieldType.booleanField,
          labelKey: 'fieldChestIndrawing',
        ),
        FieldDef(
          fieldId: 'stridor',
          type: FieldType.booleanField,
          labelKey: 'fieldStridor',
        ),
      ],
    ),

    // ── Symptom Detail (priority 30) — ICCM + TB ─────────────────────────────
    FormSection(
      sectionId: 'symptom-detail',
      programmes: {Programme.imci, Programme.tb},
      priority: 30,
      fields: [
        const FieldDef(
          fieldId: 'hasCough',
          type: FieldType.booleanField,
          labelKey: 'fieldHasCough',
        ),
        FieldDef(
          fieldId: 'coughDays',
          type: FieldType.intField,
          labelKey: 'fieldCoughDays',
          visibleWhen: const Condition(fieldId: 'hasCough', equalsValue: true),
        ),
        const FieldDef(
          fieldId: 'hasFever',
          type: FieldType.booleanField,
          labelKey: 'fieldHasFever',
        ),
        FieldDef(
          fieldId: 'feverDays',
          type: FieldType.intField,
          labelKey: 'fieldFeverDays',
          visibleWhen: const Condition(fieldId: 'hasFever', equalsValue: true),
        ),
        const FieldDef(
          fieldId: 'hasDiarrhea',
          type: FieldType.booleanField,
          labelKey: 'fieldHasDiarrhea',
        ),
      ],
    ),

    // ── ICCM Classify (priority 40) — ICCM only ───────────────────────────────
    FormSection(
      sectionId: 'iccm-classify',
      programmes: {Programme.imci},
      priority: 40,
      sharedFieldIds: const {'hasCough', 'hasFever', 'hasDiarrhea'},
      fields: [
        FieldDef(
          fieldId: 'isBloodyDiarrhea',
          type: FieldType.booleanField,
          labelKey: 'fieldIsBloodyDiarrhea',
          visibleWhen:
              const Condition(fieldId: 'hasDiarrhea', equalsValue: true),
        ),
        const FieldDef(
          fieldId: 'hasFastBreathing',
          type: FieldType.booleanField,
          labelKey: 'fieldHasFastBreathing',
        ),
        FieldDef(
          fieldId: 'rdtResult',
          type: FieldType.selectField,
          labelKey: 'fieldRdtResult',
          options: [rdtPositive, rdtNegative, rdtNotDone],
        ),
        FieldDef(
          fieldId: 'actDispensed',
          type: FieldType.booleanField,
          labelKey: 'fieldActDispensed',
          visibleWhen:
              const Condition(fieldId: 'rdtResult', equalsValue: rdtPositive),
        ),
        FieldDef(
          fieldId: 'orsDispensed',
          type: FieldType.booleanField,
          labelKey: 'fieldOrsDispensed',
          visibleWhen:
              const Condition(fieldId: 'hasDiarrhea', equalsValue: true),
        ),
        FieldDef(
          fieldId: 'zincDispensed',
          type: FieldType.booleanField,
          labelKey: 'fieldZincDispensed',
          visibleWhen:
              const Condition(fieldId: 'hasDiarrhea', equalsValue: true),
        ),
        FieldDef(
          fieldId: 'amoxicillinDispensed',
          type: FieldType.booleanField,
          labelKey: 'fieldAmoxicillinDispensed',
          visibleWhen:
              const Condition(fieldId: 'hasFastBreathing', equalsValue: true),
        ),
      ],
    ),

    // ── TB Screen Detail (priority 50) — TB only ──────────────────────────────
    FormSection(
      sectionId: 'tb-screen-detail',
      programmes: {Programme.tb},
      priority: 50,
      sharedFieldIds: const {
        'hasCough',
        'hasNightSweats',
        'hasFever',
        'hasWeightLoss'
      },
      fields: [
        const FieldDef(
          fieldId: 'hasCoughLastedLonger',
          type: FieldType.booleanField,
          labelKey: 'fieldHasCoughLastedLonger',
        ),
        const FieldDef(
          fieldId: 'hasNightSweats',
          type: FieldType.booleanField,
          labelKey: 'fieldHasNightSweats',
        ),
        const FieldDef(
          fieldId: 'hasWeightLoss',
          type: FieldType.booleanField,
          labelKey: 'fieldHasWeightLoss',
        ),
        FieldDef(
          fieldId: 'relationshipToIC',
          type: FieldType.selectField,
          labelKey: 'fieldRelationshipToIC',
          // Option values from TbRelationshipOptions.values (tb_assessment.dart)
          options: const [
            'Parent',
            'Child',
            'Sibling',
            'Spouse',
            'Grandparent',
            'Grandchild',
            'Other relative',
            'Non-relative household member',
            'Other',
          ],
        ),
        FieldDef(
          fieldId: 'sleepLocation',
          type: FieldType.selectField,
          labelKey: 'fieldSleepLocation',
          // Option values from TbSleepLocationOptions.values (tb_assessment.dart)
          options: const [
            'Same room as index case',
            'Different room, same house',
            'Different house',
          ],
        ),
        const FieldDef(
          fieldId: 'hasPreviouslyTreatedForTB',
          type: FieldType.booleanField,
          labelKey: 'fieldPreviouslyTreatedForTB',
        ),
      ],
    ),

    // ── ANC Vitals (priority 12) — ANC only ───────────────────────────────────
    // BP, weight, height, temperature, pulse shared with ncd-htn (42) and
    // pnc-mother (46). anc-vitals owns these fields when ANC is active
    // (lowest priority = first claim in compositor).
    FormSection(
      sectionId: 'anc-vitals',
      programmes: {Programme.anc},
      priority: 12,
      sharedFieldIds: const {
        'bloodPressureSystolic',
        'bloodPressureDiastolic',
        'weight',
        'height',
        'temperature',
        'pulse',
      },
      fields: const [
        FieldDef(
          fieldId: 'bloodPressureSystolic',
          type: FieldType.intField,
          labelKey: 'fieldBloodPressureSystolic',
          unit: 'mmHg',
          min: 50,
          max: 250,
        ),
        FieldDef(
          fieldId: 'bloodPressureDiastolic',
          type: FieldType.intField,
          labelKey: 'fieldBloodPressureDiastolic',
          unit: 'mmHg',
          min: 30,
          max: 150,
        ),
        FieldDef(
          fieldId: 'weight',
          type: FieldType.doubleField,
          labelKey: 'fieldWeight',
          unit: 'kg',
          min: 20,
          max: 200,
        ),
        FieldDef(
          fieldId: 'height',
          type: FieldType.doubleField,
          labelKey: 'fieldHeight',
          unit: 'cm',
          min: 100,
          max: 220,
        ),
        FieldDef(
          fieldId: 'temperature',
          type: FieldType.doubleField,
          labelKey: 'fieldTemperature',
          unit: '°C',
          min: 30,
          max: 44,
        ),
        FieldDef(
          fieldId: 'pulse',
          type: FieldType.intField,
          labelKey: 'fieldPulse',
          unit: 'bpm',
        ),
        FieldDef(
          fieldId: 'fundalHeight',
          type: FieldType.doubleField,
          labelKey: 'fieldFundalHeight',
          unit: 'cm',
          min: 10,
          max: 45,
        ),
      ],
    ),

    // ── ANC Specific (priority 45) — ANC only ────────────────────────────────
    FormSection(
      sectionId: 'anc-specific',
      programmes: {Programme.anc},
      priority: 45,
      sharedFieldIds: const {
        'edema',
        'hemoglobin',
        'bloodSugar',
        'bloodSugarFasting',
        'bloodSugarRandom',
        'urinaryAlbumin',
        'urinaryBilirubin',
        'referralFacility',
      },
      fields: [
        FieldDef(
          fieldId: 'edema',
          type: FieldType.selectField,
          labelKey: 'fieldEdema',
          options: const ['present', 'absent'],
        ),
        const FieldDef(
          fieldId: 'hemoglobin',
          type: FieldType.doubleField,
          labelKey: 'fieldHemoglobin',
          unit: 'g/dL',
          min: 0,
          max: 25,
        ),
        FieldDef(
          fieldId: 'bloodSugar',
          type: FieldType.selectField,
          labelKey: 'fieldBloodSugar',
          options: const ['fasting', 'random'],
        ),
        FieldDef(
          fieldId: 'bloodSugarFasting',
          type: FieldType.doubleField,
          labelKey: 'fieldBloodSugarFasting',
          unit: 'mmol/L',
          min: 0,
          max: 30,
          visibleWhen: const Condition(fieldId: 'bloodSugar', equalsValue: 'fasting'),
        ),
        FieldDef(
          fieldId: 'bloodSugarRandom',
          type: FieldType.doubleField,
          labelKey: 'fieldBloodSugarRandom',
          unit: 'mmol/L',
          min: 0,
          max: 30,
          visibleWhen: const Condition(fieldId: 'bloodSugar', equalsValue: 'random'),
        ),
        FieldDef(
          fieldId: 'urinaryAlbumin',
          type: FieldType.selectField,
          labelKey: 'fieldUrinaryAlbumin',
          options: const ['present', 'absent', 'NA'],
        ),
        FieldDef(
          fieldId: 'urinarySugar',
          type: FieldType.selectField,
          labelKey: 'fieldUrinarySugar',
          options: const ['present', 'absent', 'NA'],
        ),
        FieldDef(
          fieldId: 'urinaryBilirubin',
          type: FieldType.selectField,
          labelKey: 'fieldUrinaryBilirubin',
          options: const ['present', 'absent', 'na'],
        ),
        FieldDef(
          fieldId: 'ttTdCompleted',
          type: FieldType.selectField,
          labelKey: 'fieldTtTdCompleted',
          options: const ['yes', 'no'],
        ),
        const FieldDef(
          fieldId: 'folicAcidTotalConsumed',
          type: FieldType.intField,
          labelKey: 'fieldFolicAcidConsumed',
          unit: 'tablets',
        ),
        const FieldDef(
          fieldId: 'folicAcidProvided',
          type: FieldType.intField,
          labelKey: 'fieldFolicAcidProvided',
          unit: 'tablets',
        ),
        const FieldDef(
          fieldId: 'ifaTotalConsumed',
          type: FieldType.intField,
          labelKey: 'fieldIfaConsumed',
          unit: 'tablets',
        ),
        const FieldDef(
          fieldId: 'ifaProvided',
          type: FieldType.intField,
          labelKey: 'fieldIfaProvided',
          unit: 'tablets',
        ),
        const FieldDef(
          fieldId: 'calciumTotalConsumed',
          type: FieldType.intField,
          labelKey: 'fieldCalciumConsumed',
          unit: 'tablets',
        ),
        const FieldDef(
          fieldId: 'calciumProvided',
          type: FieldType.intField,
          labelKey: 'fieldCalciumProvided',
          unit: 'tablets',
        ),
        const FieldDef(
          fieldId: 'ancVisitsOtherProviders',
          type: FieldType.intField,
          labelKey: 'fieldAncVisitsOtherProviders',
          min: 0,
        ),
        FieldDef(
          fieldId: 'ancFromMedicalDoctor',
          type: FieldType.selectField,
          labelKey: 'fieldAncFromMedicalDoctor',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'ultrasound',
          type: FieldType.selectField,
          labelKey: 'fieldUltrasound',
          options: const ['done', 'notDone'],
        ),
        FieldDef(
          fieldId: 'facilityIdentifiedForDelivery',
          type: FieldType.selectField,
          labelKey: 'fieldFacilityIdentifiedForDelivery',
          options: const [
            'uhfwc',
            'mcwc',
            'uhc',
            'districtHospital',
            'medicalCollegeHospital',
            'ngoFacility',
            'privateFacility',
            'notIdentified',
            'homeDelivery',
          ],
        ),
        FieldDef(
          fieldId: 'previousPregnancyComplications',
          type: FieldType.multiSelectField,
          labelKey: 'fieldPreviousPregnancyComplications',
          options: const [
            'abortion_mr',
            'stillbirth',
            'caesarean_operation',
            'convulsions',
            'postpartum_hemorrhage',
            'assisted_delivery',
            'preterm_birth',
            'gestational_diabetes',
            'severe_anemia',
            'none',
          ],
        ),
        FieldDef(
          fieldId: 'dangerSignsExperienced12',
          type: FieldType.multiSelectField,
          labelKey: 'fieldDangerSigns12',
          options: const [
            'vaginalBleeding',
            'severeAbdominalPain',
            'severeHeadaches',
            'severeVomiting',
            'highFever',
            'shortnessOfBreath',
            'none',
            'other',
          ],
        ),
        FieldDef(
          fieldId: 'dangerSignsExperienced13To27',
          type: FieldType.multiSelectField,
          labelKey: 'fieldDangerSigns13to27',
          options: const [
            'vaginalBleeding',
            'leakingFluid',
            'regularContractions',
            'persistentHeadache',
            'epigastricPain',
            'highFever',
            'reducedFetalMovements',
            'none',
            'other',
          ],
        ),
        FieldDef(
          fieldId: 'dangerSignsExperienced28To40',
          type: FieldType.multiSelectField,
          labelKey: 'fieldDangerSigns28to40',
          options: const [
            'decreasedFetalMovements',
            'severeAbdominalPain',
            'vaginalBleeding',
            'leakingFluid',
            'severeHeadaches',
            'fever',
            'fits',
            'none',
            'other',
          ],
        ),
        FieldDef(
          fieldId: 'referralFacility',
          type: FieldType.selectField,
          labelKey: 'fieldReferralFacility',
          options: const [
            'uhfwc',
            'mcwc',
            'uhc',
            'districtHospital',
            'medicalCollegeHospital',
          ],
        ),
      ],
    ),

    // ── NCD HTN (priority 42) — NCD only ─────────────────────────────────────
    // BP, height, weight shared: anc-vitals (12) owns when ANC active;
    // pnc-mother (46) defers to ncd-htn when NCD+PNC co-active.
    FormSection(
      sectionId: 'ncd-htn',
      programmes: {Programme.ncd},
      priority: 42,
      sharedFieldIds: const {
        'bloodPressureSystolic',
        'bloodPressureDiastolic',
        'height',
        'weight',
      },
      fields: [
        FieldDef(
          fieldId: 'hasSymptoms',
          type: FieldType.selectField,
          labelKey: 'fieldHasSymptoms',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'ncdSymptoms',
          type: FieldType.multiSelectField,
          labelKey: 'fieldNcdSymptoms',
          options: const [
            'headache',
            'dizziness',
            'chest_pain',
            'shortness_of_breath',
            'palpitations',
            'blurred_vision',
            'nausea',
            'fatigue',
          ],
          visibleWhen: const Condition(fieldId: 'hasSymptoms', equalsValue: 'yes'),
        ),
        const FieldDef(
          fieldId: 'newWorseningSymptoms',
          type: FieldType.textField,
          labelKey: 'fieldNewWorseningSymptoms',
        ),
        FieldDef(
          fieldId: 'compliance',
          type: FieldType.selectField,
          labelKey: 'fieldCompliance',
          options: const ['yes', 'no'],
        ),
        const FieldDef(
          fieldId: 'height',
          type: FieldType.doubleField,
          labelKey: 'fieldHeight',
          unit: 'cm',
          min: 50,
          max: 300,
        ),
        const FieldDef(
          fieldId: 'weight',
          type: FieldType.doubleField,
          labelKey: 'fieldWeight',
          unit: 'kg',
          min: 10,
          max: 400,
        ),
        const FieldDef(
          fieldId: 'bloodPressureSystolic',
          type: FieldType.intField,
          labelKey: 'fieldBloodPressureSystolic',
          unit: 'mmHg',
          min: 50,
          max: 250,
        ),
        const FieldDef(
          fieldId: 'bloodPressureDiastolic',
          type: FieldType.intField,
          labelKey: 'fieldBloodPressureDiastolic',
          unit: 'mmHg',
          min: 30,
          max: 150,
        ),
        const FieldDef(
          fieldId: 'isRegularSmoker',
          type: FieldType.booleanField,
          labelKey: 'fieldIsRegularSmoker',
        ),
      ],
    ),

    // ── NCD DM (priority 43) — NCD only ──────────────────────────────────────
    FormSection(
      sectionId: 'ncd-dm',
      programmes: {Programme.ncd},
      priority: 43,
      fields: [
        FieldDef(
          fieldId: 'glucoseType',
          type: FieldType.selectField,
          labelKey: 'fieldGlucoseType',
          options: const ['fasting', 'random', 'postprandial'],
        ),
        const FieldDef(
          fieldId: 'glucoseValue',
          type: FieldType.doubleField,
          labelKey: 'fieldGlucoseValue',
          unit: 'mg/dL',
          min: 30,
          max: 600,
        ),
        const FieldDef(
          fieldId: 'hba1c',
          type: FieldType.doubleField,
          labelKey: 'fieldHba1c',
          unit: '%',
          min: 3,
          max: 20,
        ),
      ],
    ),

    // ── EPI Review (priority 60) — EPI only ──────────────────────────────────
    // overdueVaccines options are populated dynamically from
    // PatientContext.overdueImmunizations by the screen layer.
    FormSection(
      sectionId: 'epi-review',
      programmes: {Programme.epi},
      priority: 60,
      fields: const [
        FieldDef(
          fieldId: 'overdueVaccines',
          type: FieldType.multiSelectField,
          labelKey: 'fieldOverdueVaccines',
          options: [],
        ),
        FieldDef(
          fieldId: 'vaccinesGivenToday',
          type: FieldType.multiSelectField,
          labelKey: 'fieldVaccinesGivenToday',
          options: [],
        ),
      ],
    ),

    // ── NUTRITION Detail (priority 35) — NUTRITION only ───────────────────────
    // Priority 35: after symptom-detail (30), before iccm-classify (40).
    FormSection(
      sectionId: 'nutrition-detail',
      programmes: {Programme.nutrition},
      priority: 35,
      fields: [
        const FieldDef(
          fieldId: 'edemaOfBothFeet',
          type: FieldType.booleanField,
          labelKey: 'fieldEdemaOfBothFeet',
        ),
        const FieldDef(
          fieldId: 'visibleWasting',
          type: FieldType.booleanField,
          labelKey: 'fieldVisibleWasting',
        ),
        const FieldDef(
          fieldId: 'feedingDifficulty',
          type: FieldType.booleanField,
          labelKey: 'fieldFeedingDifficulty',
        ),
        const FieldDef(
          fieldId: 'supplementaryFoodGiven',
          type: FieldType.booleanField,
          labelKey: 'fieldSupplementaryFoodGiven',
        ),
        // referredForSam is visible when edema of both feet is true (in-form
        // gate). The MUAC red signal is also a trigger but is evaluated via the
        // CDS rules layer outside the compositor.
        FieldDef(
          fieldId: 'referredForSam',
          type: FieldType.booleanField,
          labelKey: 'fieldReferredForSam',
          visibleWhen: const Condition(
            fieldId: 'edemaOfBothFeet',
            equalsValue: true,
          ),
        ),
      ],
    ),

    // ── PNC Mother (priority 46) — PNC only ──────────────────────────────────
    // Vitals and BP shared with anc-vitals (12) and ncd-htn (42); pnc-mother
    // defers to whichever section processes first.
    FormSection(
      sectionId: 'pnc-mother',
      programmes: {Programme.pnc},
      priority: 46,
      sharedFieldIds: const {
        'bloodPressureSystolic',
        'bloodPressureDiastolic',
        'weight',
        'height',
        'temperature',
        'pulse',
        'edema',
        'hemoglobin',
        'bloodSugar',
        'bloodSugarFasting',
        'bloodSugarRandom',
        'urinaryAlbumin',
        'urinaryBilirubin',
        'referralFacility',
      },
      fields: [
        const FieldDef(
          fieldId: 'gravida',
          type: FieldType.intField,
          labelKey: 'fieldGravida',
          min: 1,
        ),
        const FieldDef(
          fieldId: 'parity',
          type: FieldType.intField,
          labelKey: 'fieldParity',
          min: 0,
        ),
        const FieldDef(
          fieldId: 'livingChildren',
          type: FieldType.intField,
          labelKey: 'fieldLivingChildren',
          min: 0,
        ),
        const FieldDef(
          fieldId: 'temperature',
          type: FieldType.doubleField,
          labelKey: 'fieldTemperature',
          unit: '°C',
          min: 30,
          max: 44,
        ),
        const FieldDef(
          fieldId: 'pulse',
          type: FieldType.intField,
          labelKey: 'fieldPulse',
          unit: 'bpm',
        ),
        const FieldDef(
          fieldId: 'weight',
          type: FieldType.doubleField,
          labelKey: 'fieldWeight',
          unit: 'kg',
          min: 20,
          max: 200,
        ),
        FieldDef(
          fieldId: 'htnPatient',
          type: FieldType.selectField,
          labelKey: 'fieldHtnPatient',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'eclampsia',
          type: FieldType.selectField,
          labelKey: 'fieldEclampsia',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'onTreatmentHtnEclampsia',
          type: FieldType.selectField,
          labelKey: 'fieldOnTreatmentHtnEclampsia',
          options: const ['yes', 'no'],
        ),
        const FieldDef(
          fieldId: 'bloodPressureSystolic',
          type: FieldType.intField,
          labelKey: 'fieldBloodPressureSystolic',
          unit: 'mmHg',
          min: 50,
          max: 250,
        ),
        const FieldDef(
          fieldId: 'bloodPressureDiastolic',
          type: FieldType.intField,
          labelKey: 'fieldBloodPressureDiastolic',
          unit: 'mmHg',
          min: 30,
          max: 150,
        ),
        FieldDef(
          fieldId: 'edema',
          type: FieldType.selectField,
          labelKey: 'fieldEdema',
          options: const ['present', 'absent'],
        ),
        FieldDef(
          fieldId: 'urinaryAlbumin',
          type: FieldType.selectField,
          labelKey: 'fieldUrinaryAlbumin',
          options: const ['present', 'absent', 'NA'],
        ),
        FieldDef(
          fieldId: 'urinaryBilirubin',
          type: FieldType.selectField,
          labelKey: 'fieldUrinaryBilirubin',
          options: const ['present', 'absent', 'na'],
        ),
        const FieldDef(
          fieldId: 'hemoglobin',
          type: FieldType.doubleField,
          labelKey: 'fieldHemoglobin',
          unit: 'g/dL',
          min: 0,
          max: 25,
        ),
        FieldDef(
          fieldId: 'dmPatient',
          type: FieldType.selectField,
          labelKey: 'fieldDmPatient',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'gdmPatient',
          type: FieldType.selectField,
          labelKey: 'fieldGdmPatient',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'onTreatmentDmGdm',
          type: FieldType.selectField,
          labelKey: 'fieldOnTreatmentDmGdm',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'bloodSugar',
          type: FieldType.selectField,
          labelKey: 'fieldBloodSugar',
          options: const ['fasting', 'random'],
        ),
        FieldDef(
          fieldId: 'fastingBloodSugar',
          type: FieldType.doubleField,
          labelKey: 'fieldFastingBloodSugar',
          unit: 'mmol/L',
          min: 0,
          max: 30,
          visibleWhen: const Condition(fieldId: 'bloodSugar', equalsValue: 'fasting'),
        ),
        FieldDef(
          fieldId: 'randomBloodSugar',
          type: FieldType.doubleField,
          labelKey: 'fieldRandomBloodSugar',
          unit: 'mmol/L',
          min: 0,
          max: 30,
          visibleWhen: const Condition(fieldId: 'bloodSugar', equalsValue: 'random'),
        ),
        FieldDef(
          fieldId: 'postpartumDangerSigns',
          type: FieldType.multiSelectField,
          labelKey: 'fieldPostpartumDangerSigns',
          options: const [
            'heavyBleeding',
            'foulSmellingDischarge',
            'severeAbdominalPain',
            'severeHeadacheVisionConvulsions',
            'perinealWoundDischarge',
            'breastPainSwellingFever',
            'none',
            'other',
          ],
        ),
        FieldDef(
          fieldId: 'vitaminAConsumed',
          type: FieldType.selectField,
          labelKey: 'fieldVitaminAConsumed',
          options: const ['yes', 'no'],
        ),
        const FieldDef(
          fieldId: 'ifaTabletsConsumed',
          type: FieldType.intField,
          labelKey: 'fieldIfaTabletsConsumed',
          unit: 'tablets',
          min: 0,
        ),
        const FieldDef(
          fieldId: 'ifaTabletsProvided',
          type: FieldType.intField,
          labelKey: 'fieldIfaTabletsProvided',
          unit: 'tablets',
          min: 0,
        ),
        const FieldDef(
          fieldId: 'calciumTabletsConsumed',
          type: FieldType.intField,
          labelKey: 'fieldCalciumTabletsConsumed',
          unit: 'tablets',
          min: 0,
        ),
        const FieldDef(
          fieldId: 'calciumTabletsProvided',
          type: FieldType.intField,
          labelKey: 'fieldCalciumTabletsProvided',
          unit: 'tablets',
          min: 0,
        ),
        FieldDef(
          fieldId: 'familyPlanningMethods',
          type: FieldType.selectField,
          labelKey: 'fieldFamilyPlanningMethods',
          options: const [
            'pills',
            'injectables',
            'implant',
            'iud',
            'condoms',
            'sterilizationFemale',
            'sterilizationMale',
            'none',
          ],
        ),
        FieldDef(
          fieldId: 'referralFacility',
          type: FieldType.selectField,
          labelKey: 'fieldReferralFacility',
          options: const [
            'uhfwc',
            'mcwc',
            'uhc',
            'districtHospital',
            'medicalCollegeHospital',
          ],
        ),
      ],
    ),

    // ── PNC Neonatal (priority 47) — PNC only ────────────────────────────────
    FormSection(
      sectionId: 'pnc-neonatal',
      programmes: {Programme.pnc},
      priority: 47,
      fields: [
        const FieldDef(
          fieldId: 'pncNeonateSigns',
          type: FieldType.multiSelectField,
          labelKey: 'fieldPncNeonateSigns',
          options: [],
        ),
        const FieldDef(
          fieldId: 'otherPncNeonateSigns',
          type: FieldType.textField,
          labelKey: 'fieldOtherPncNeonateSigns',
        ),
        FieldDef(
          fieldId: 'newbornReferredToSBCU',
          type: FieldType.selectField,
          labelKey: 'fieldNewbornReferredToSbcu',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'lowBirthWeight',
          type: FieldType.selectField,
          labelKey: 'fieldLowBirthWeight',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'deathOfNewborn',
          type: FieldType.selectField,
          labelKey: 'fieldDeathOfNewborn',
          options: const ['yes', 'no'],
        ),
      ],
    ),

    // ── PNC Child (priority 48) — PNC only ───────────────────────────────────
    FormSection(
      sectionId: 'pnc-child',
      programmes: {Programme.pnc},
      priority: 48,
      fields: [
        FieldDef(
          fieldId: 'congenitalDefect',
          type: FieldType.selectField,
          labelKey: 'fieldCongenitalDefect',
          options: const ['yes', 'no'],
        ),
        const FieldDef(
          fieldId: 'pncChildWeight',
          type: FieldType.doubleField,
          labelKey: 'fieldPncChildWeight',
          unit: 'kg',
          min: 0.5,
          max: 30,
        ),
        const FieldDef(
          fieldId: 'childFeedLast24Hrs',
          type: FieldType.multiSelectField,
          labelKey: 'fieldChildFeedLast24Hrs',
          options: [],
        ),
        const FieldDef(
          fieldId: 'hrsBreastFed',
          type: FieldType.intField,
          labelKey: 'fieldHrsBreastFed',
          min: 0,
          max: 72,
        ),
        FieldDef(
          fieldId: 'monthAdditionalFeedGiven',
          type: FieldType.selectField,
          labelKey: 'fieldMonthAdditionalFeedGiven',
          options: const ['7', '8', '9'],
        ),
        FieldDef(
          fieldId: 'childBreastFeeding',
          type: FieldType.selectField,
          labelKey: 'fieldChildBreastFeeding',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'additionalFood24Hrs',
          type: FieldType.selectField,
          labelKey: 'fieldAdditionalFood24Hrs',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'receivedVaccine',
          type: FieldType.selectField,
          labelKey: 'fieldReceivedVaccine',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'dewormingMedicine',
          type: FieldType.selectField,
          labelKey: 'fieldDewormingMedicine',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'anyIllness',
          type: FieldType.selectField,
          labelKey: 'fieldAnyIllness',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'childIllnessType',
          type: FieldType.multiSelectField,
          labelKey: 'fieldChildIllnessType',
          options: const [],
          visibleWhen: const Condition(fieldId: 'anyIllness', equalsValue: 'yes'),
        ),
        FieldDef(
          fieldId: 'childReferral',
          type: FieldType.selectField,
          labelKey: 'fieldChildReferral',
          options: const ['yes', 'no'],
        ),
        FieldDef(
          fieldId: 'childReferralFacilityType',
          type: FieldType.selectField,
          labelKey: 'fieldChildReferralFacilityType',
          options: const [
            'medicalCollegeHospital',
            'governmentHospital',
            'upazilaHealthComplex',
            'privateHospital',
            'hwc',
            'communityClinic',
          ],
          visibleWhen: const Condition(fieldId: 'childReferral', equalsValue: 'yes'),
        ),
      ],
    ),
  ];

  // ── Public API ─────────────────────────────────────────────────────────────

  /// All registered sections, in definition order.
  ///
  /// The compositor sorts them by [FormSection.priority] — this order is
  /// documentation only.
  static List<FormSection> get all => List.unmodifiable(_sections);

  /// Look up a section by its stable [sectionId].
  static FormSection? byId(String sectionId) {
    for (final section in _sections) {
      if (section.sectionId == sectionId) return section;
    }
    return null;
  }

  /// Return all sections whose [FormSection.programmes] intersects [programmes].
  ///
  /// Results are returned in [FormSection.priority] ascending order.
  static List<FormSection> forProgrammes(Set<Programme> programmes) {
    final result = _sections
        .where((s) => s.programmes.any((p) => programmes.contains(p)))
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return result;
  }

  /// Project [fieldValues] down to the fields relevant to [programme],
  /// returning a map keyed by canonical API field name.
  ///
  /// Field IDs used in the composer map 1-to-1 to API field names for all
  /// existing sections; the projection is therefore an identity filter over
  /// the programme's field set.
  static Map<String, dynamic> projectionFor(
    Programme programme,
    Map<String, dynamic> fieldValues,
  ) {
    // Collect all fieldIds owned by this programme's sections.
    final relevantFields = <String>{};
    for (final section in _sections) {
      if (!section.programmes.contains(programme)) continue;
      for (final field in section.fields) {
        // Include owned fields; shared fields are broadcast from the
        // owning section and are therefore also valid for this programme's
        // projection.
        relevantFields.add(field.fieldId);
      }
    }

    // Build projection: field → value, keeping only programme-relevant keys.
    final projection = <String, dynamic>{};
    for (final entry in fieldValues.entries) {
      if (relevantFields.contains(entry.key)) {
        projection[entry.key] = entry.value;
      }
    }
    return projection;
  }

  /// Generates the scribe service formSchema from a list of [FormSection]s.
  ///
  /// Deduplicates fieldIds — each fieldId appears at most once in the output,
  /// with the definition from the first section that declares it (mirroring
  /// the compositor's putIfAbsent ownership semantics).
  ///
  /// Maps [FieldType] → scribe service type strings:
  ///   [FieldType.booleanField]     → [ScribeFieldType.boolean]
  ///   [FieldType.intField]         → [ScribeFieldType.integer]
  ///   [FieldType.doubleField]      → [ScribeFieldType.decimal]
  ///   [FieldType.textField]        → [ScribeFieldType.string]
  ///   [FieldType.selectField]      → [ScribeFieldType.enumType]
  ///   [FieldType.multiSelectField] → [ScribeFieldType.enumType]
  static List<_scribe.FormFieldSchema> toScribeSchema(
    List<FormSection> sections,
  ) {
    final seen = <String>{};
    final result = <_scribe.FormFieldSchema>[];

    for (final section in sections) {
      for (final field in section.fields) {
        if (seen.contains(field.fieldId)) continue;
        seen.add(field.fieldId);

        final scribeType = _toScribeFieldType(field.type);
        result.add(_scribe.FormFieldSchema(
          fieldId: field.fieldId,
          type: scribeType,
          label: field.fieldId, // label resolved by ComposerStrings at runtime
          unit: field.unit,
          allowedValues: (field.options?.isNotEmpty ?? false)
              ? List<String>.unmodifiable(field.options!)
              : null,
        ));
      }
    }
    return result;
  }

  static _scribe.FieldType _toScribeFieldType(FieldType composerType) {
    switch (composerType) {
      case FieldType.booleanField:
        return _scribe.FieldType.boolean;
      case FieldType.intField:
        return _scribe.FieldType.integer;
      case FieldType.doubleField:
        return _scribe.FieldType.decimal;
      case FieldType.textField:
        return _scribe.FieldType.string;
      case FieldType.selectField:
      case FieldType.multiSelectField:
        return _scribe.FieldType.enumType;
    }
  }

  // ── Test helper (package-visible) ─────────────────────────────────────────

  /// Register an extra section for the duration of a test.
  ///
  /// Call [_removeTestSection] in `tearDown` to restore the registry.
  /// Not part of the public API — visible only within the package so tests
  /// in `test/` can exercise the genericity invariant without modifying
  /// [FormCompositor].
  static void _addTestSection(FormSection section) {
    _sections.add(section);
  }

  static void _removeTestSection(String sectionId) {
    _sections.removeWhere((s) => s.sectionId == sectionId);
  }

  /// Visible test hook: add a transient section.
  // ignore: library_private_types_in_public_api
  static void addTestSection(FormSection section) => _addTestSection(section);

  /// Visible test hook: remove a transient section.
  // ignore: library_private_types_in_public_api
  static void removeTestSection(String sectionId) =>
      _removeTestSection(sectionId);
}
