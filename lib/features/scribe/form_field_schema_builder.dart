/// Form field schema builder for AI Scribe form_prefill mode.
///
/// Generates [FormFieldSchema] definitions from assessment forms to send
/// to the AI scribe service. The service uses this schema to extract
/// structured field values from the consultation transcript.
library;

import '../../../core/models/programme.dart';

/// Field type for the AI scribe extraction contract.
enum FieldType {
  boolean,
  integer,
  decimal,
  string,
  enumType, // enum in API
  date,
}

/// Schema definition for a single form field.
///
/// Sent to the AI scribe service as part of the form_prefill request.
class FormFieldSchema {
  const FormFieldSchema({
    required this.fieldId,
    required this.type,
    required this.label,
    this.unit,
    this.allowedValues,
    this.description,
    this.clinicalContext,
  });

  /// Unique field identifier (matches form field key).
  final String fieldId;

  /// Data type for extraction.
  final FieldType type;

  /// Human-readable label for context.
  final String label;

  /// Unit of measurement (e.g., 'mmHg', 'mg/dL', 'cm').
  final String? unit;

  /// Allowed values for enum types.
  final List<String>? allowedValues;

  /// Additional description for the AI.
  final String? description;

  /// Clinical context to help AI extraction.
  final String? clinicalContext;

  Map<String, dynamic> toJson() => {
        'fieldId': fieldId,
        'type': type == FieldType.enumType ? 'enum' : type.name,
        'label': label,
        if (unit != null) 'unit': unit,
        if (allowedValues != null) 'allowedValues': allowedValues,
        if (description != null) 'description': description,
        if (clinicalContext != null) 'clinicalContext': clinicalContext,
      };
}

/// Builder for creating form schemas for each programme.
///
/// Provides the extraction contract for the AI scribe service to map
/// transcript content to form fields.
abstract final class FormFieldSchemaBuilder {
  FormFieldSchemaBuilder._();

  /// Build schema for a programme.
  static List<FormFieldSchema> forProgramme(Programme programme) {
    switch (programme) {
      case Programme.ncd:
        return _ncdSchema;
      case Programme.tb:
        return _tbSchema;
      case Programme.anc:
        return _ancSchema;
      case Programme.pnc:
        return _pncSchema;
      case Programme.imci:
        return _imciSchema;
      default:
        return _commonVitalsSchema;
    }
  }

  /// Build schema for multiple programmes (merged, deduplicated).
  static List<FormFieldSchema> forProgrammes(List<Programme> programmes) {
    final seen = <String>{};
    final result = <FormFieldSchema>[];
    for (final programme in programmes) {
      for (final field in forProgramme(programme)) {
        if (!seen.contains(field.fieldId)) {
          seen.add(field.fieldId);
          result.add(field);
        }
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMON VITALS (shared across programmes)
  // ═══════════════════════════════════════════════════════════════════════════

  static const _commonVitalsSchema = <FormFieldSchema>[
    FormFieldSchema(
      fieldId: 'temperature',
      type: FieldType.decimal,
      label: 'Temperature',
      unit: '°C',
      clinicalContext: 'Body temperature reading, usually 36-38°C normal',
    ),
    FormFieldSchema(
      fieldId: 'bpSystolic',
      type: FieldType.integer,
      label: 'Systolic Blood Pressure',
      unit: 'mmHg',
      clinicalContext:
          'First/top number in blood pressure reading, e.g., 120 in 120/80',
    ),
    FormFieldSchema(
      fieldId: 'bpDiastolic',
      type: FieldType.integer,
      label: 'Diastolic Blood Pressure',
      unit: 'mmHg',
      clinicalContext:
          'Second/bottom number in blood pressure reading, e.g., 80 in 120/80',
    ),
    FormFieldSchema(
      fieldId: 'pulse',
      type: FieldType.integer,
      label: 'Pulse Rate',
      unit: 'bpm',
      clinicalContext: 'Heart rate in beats per minute',
    ),
    FormFieldSchema(
      fieldId: 'respiratoryRate',
      type: FieldType.integer,
      label: 'Respiratory Rate',
      unit: 'breaths/min',
      clinicalContext: 'Breathing rate in breaths per minute',
    ),
    FormFieldSchema(
      fieldId: 'spO2',
      type: FieldType.integer,
      label: 'Oxygen Saturation',
      unit: '%',
      clinicalContext: 'SpO2 percentage, normally 95-100%',
    ),
    FormFieldSchema(
      fieldId: 'weight',
      type: FieldType.decimal,
      label: 'Weight',
      unit: 'kg',
      clinicalContext: 'Body weight in kilograms',
    ),
    FormFieldSchema(
      fieldId: 'height',
      type: FieldType.decimal,
      label: 'Height',
      unit: 'cm',
      clinicalContext: 'Height in centimeters',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // NCD (Hypertension, Diabetes, CVD Risk)
  // ═══════════════════════════════════════════════════════════════════════════

  static const _ncdSchema = <FormFieldSchema>[
    ..._commonVitalsSchema,
    // Blood glucose
    FormFieldSchema(
      fieldId: 'bloodGlucoseFasting',
      type: FieldType.decimal,
      label: 'Fasting Blood Glucose',
      unit: 'mg/dL',
      clinicalContext:
          'Blood sugar measured after 8+ hours fasting. Normal <100, pre-diabetes 100-125, diabetes ≥126',
    ),
    FormFieldSchema(
      fieldId: 'bloodGlucoseRandom',
      type: FieldType.decimal,
      label: 'Random Blood Glucose',
      unit: 'mg/dL',
      clinicalContext:
          'Blood sugar measured at any time. Normal <140, diabetes ≥200 with symptoms',
    ),
    FormFieldSchema(
      fieldId: 'hba1c',
      type: FieldType.decimal,
      label: 'HbA1c',
      unit: '%',
      clinicalContext:
          '3-month average blood sugar. Normal <5.7%, pre-diabetes 5.7-6.4%, diabetes ≥6.5%',
    ),
    // Lipids
    FormFieldSchema(
      fieldId: 'cholesterolTotal',
      type: FieldType.decimal,
      label: 'Total Cholesterol',
      unit: 'mg/dL',
      clinicalContext: 'Total cholesterol. Desirable <200, borderline 200-239, high ≥240',
    ),
    // CVD Risk factors
    FormFieldSchema(
      fieldId: 'smokingStatus',
      type: FieldType.enumType,
      label: 'Smoking Status',
      allowedValues: ['never', 'former', 'current'],
      clinicalContext: 'Current smoking status for CVD risk assessment',
    ),
    FormFieldSchema(
      fieldId: 'alcoholUse',
      type: FieldType.enumType,
      label: 'Alcohol Use',
      allowedValues: ['none', 'occasional', 'regular', 'heavy'],
      clinicalContext: 'Alcohol consumption pattern',
    ),
    FormFieldSchema(
      fieldId: 'physicalActivity',
      type: FieldType.enumType,
      label: 'Physical Activity Level',
      allowedValues: ['sedentary', 'light', 'moderate', 'vigorous'],
      clinicalContext: 'Weekly physical activity level',
    ),
    // Symptoms
    FormFieldSchema(
      fieldId: 'chestPain',
      type: FieldType.boolean,
      label: 'Chest Pain',
      clinicalContext: 'Presence of chest pain or discomfort',
    ),
    FormFieldSchema(
      fieldId: 'shortnessOfBreath',
      type: FieldType.boolean,
      label: 'Shortness of Breath',
      clinicalContext: 'Difficulty breathing or dyspnea',
    ),
    FormFieldSchema(
      fieldId: 'dizziness',
      type: FieldType.boolean,
      label: 'Dizziness',
      clinicalContext: 'Feeling lightheaded or dizzy',
    ),
    FormFieldSchema(
      fieldId: 'headache',
      type: FieldType.boolean,
      label: 'Headache',
      clinicalContext: 'Presence of headache',
    ),
    FormFieldSchema(
      fieldId: 'blurredVision',
      type: FieldType.boolean,
      label: 'Blurred Vision',
      clinicalContext: 'Visual disturbances or blurred vision',
    ),
    FormFieldSchema(
      fieldId: 'polyuria',
      type: FieldType.boolean,
      label: 'Frequent Urination',
      clinicalContext: 'Excessive urination (polyuria), common in diabetes',
    ),
    FormFieldSchema(
      fieldId: 'polydipsia',
      type: FieldType.boolean,
      label: 'Excessive Thirst',
      clinicalContext: 'Excessive thirst (polydipsia), common in diabetes',
    ),
    FormFieldSchema(
      fieldId: 'numbness',
      type: FieldType.boolean,
      label: 'Numbness/Tingling',
      clinicalContext: 'Numbness or tingling in extremities, may indicate neuropathy',
    ),
    FormFieldSchema(
      fieldId: 'footWound',
      type: FieldType.boolean,
      label: 'Foot Wound/Ulcer',
      clinicalContext: 'Presence of foot wound or ulcer, important in diabetes',
    ),
    // Medications
    FormFieldSchema(
      fieldId: 'onAntihypertensives',
      type: FieldType.boolean,
      label: 'On Antihypertensive Medication',
      clinicalContext:
          'Currently taking blood pressure medication (amlodipine, losartan, etc.)',
    ),
    FormFieldSchema(
      fieldId: 'onDiabetesMedication',
      type: FieldType.boolean,
      label: 'On Diabetes Medication',
      clinicalContext:
          'Currently taking diabetes medication (metformin, gliclazide, insulin, etc.)',
    ),
    FormFieldSchema(
      fieldId: 'onStatins',
      type: FieldType.boolean,
      label: 'On Cholesterol Medication',
      clinicalContext:
          'Currently taking cholesterol medication (atorvastatin, rosuvastatin, etc.)',
    ),
    // Clinical notes
    FormFieldSchema(
      fieldId: 'clinicalNotes',
      type: FieldType.string,
      label: 'Clinical Notes',
      clinicalContext: 'Any additional clinical observations or notes',
    ),
    FormFieldSchema(
      fieldId: 'followUpInterval',
      type: FieldType.enumType,
      label: 'Follow-up Interval',
      allowedValues: ['1 week', '2 weeks', '1 month', '3 months', '6 months'],
      clinicalContext: 'Recommended follow-up interval',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // TB SCREENING
  // ═══════════════════════════════════════════════════════════════════════════

  static const _tbSchema = <FormFieldSchema>[
    ..._commonVitalsSchema,
    // 4-symptom screen
    FormFieldSchema(
      fieldId: 'cough',
      type: FieldType.boolean,
      label: 'Cough',
      clinicalContext: 'Presence of cough',
    ),
    FormFieldSchema(
      fieldId: 'coughDuration',
      type: FieldType.integer,
      label: 'Cough Duration',
      unit: 'days',
      clinicalContext: 'Duration of cough in days. ≥14 days is presumptive TB',
    ),
    FormFieldSchema(
      fieldId: 'fever',
      type: FieldType.boolean,
      label: 'Fever',
      clinicalContext: 'Presence of fever',
    ),
    FormFieldSchema(
      fieldId: 'nightSweats',
      type: FieldType.boolean,
      label: 'Night Sweats',
      clinicalContext: 'Presence of night sweats (drenching)',
    ),
    FormFieldSchema(
      fieldId: 'weightLoss',
      type: FieldType.boolean,
      label: 'Unintentional Weight Loss',
      clinicalContext: 'Unintentional weight loss in past 3 months',
    ),
    FormFieldSchema(
      fieldId: 'hemoptysis',
      type: FieldType.boolean,
      label: 'Coughing Blood',
      clinicalContext: 'Hemoptysis - coughing up blood (danger sign)',
    ),
    FormFieldSchema(
      fieldId: 'chestPain',
      type: FieldType.boolean,
      label: 'Chest Pain',
      clinicalContext: 'Chest pain or discomfort',
    ),
    // Risk factors
    FormFieldSchema(
      fieldId: 'tbContact',
      type: FieldType.boolean,
      label: 'TB Contact',
      clinicalContext: 'Close contact with known TB case',
    ),
    FormFieldSchema(
      fieldId: 'hivPositive',
      type: FieldType.boolean,
      label: 'HIV Positive',
      clinicalContext: 'Known HIV positive status',
    ),
    FormFieldSchema(
      fieldId: 'previousTb',
      type: FieldType.boolean,
      label: 'Previous TB',
      clinicalContext: 'History of previous TB treatment',
    ),
    // Result
    FormFieldSchema(
      fieldId: 'tbScreenResult',
      type: FieldType.enumType,
      label: 'TB Screen Result',
      allowedValues: ['negative', 'presumptive', 'confirmed'],
      clinicalContext:
          'TB screening result. Presumptive if cough ≥14 days or 2+ symptoms',
    ),
    FormFieldSchema(
      fieldId: 'sputumCollected',
      type: FieldType.boolean,
      label: 'Sputum Collected',
      clinicalContext: 'Whether sputum sample was collected for testing',
    ),
    FormFieldSchema(
      fieldId: 'referredForDiagnosis',
      type: FieldType.boolean,
      label: 'Referred for Diagnosis',
      clinicalContext: 'Referred to facility for TB diagnosis',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // ANC (Antenatal Care)
  // ═══════════════════════════════════════════════════════════════════════════

  static const _ancSchema = <FormFieldSchema>[
    ..._commonVitalsSchema,
    // Pregnancy details
    FormFieldSchema(
      fieldId: 'gestationalWeeks',
      type: FieldType.integer,
      label: 'Gestational Age',
      unit: 'weeks',
      clinicalContext: 'Weeks of pregnancy',
    ),
    FormFieldSchema(
      fieldId: 'lmp',
      type: FieldType.date,
      label: 'Last Menstrual Period',
      clinicalContext: 'Date of last menstrual period for calculating due date',
    ),
    FormFieldSchema(
      fieldId: 'edd',
      type: FieldType.date,
      label: 'Expected Delivery Date',
      clinicalContext: 'Estimated due date',
    ),
    FormFieldSchema(
      fieldId: 'gravida',
      type: FieldType.integer,
      label: 'Gravida',
      clinicalContext: 'Total number of pregnancies including current',
    ),
    FormFieldSchema(
      fieldId: 'parity',
      type: FieldType.integer,
      label: 'Parity',
      clinicalContext: 'Number of previous deliveries',
    ),
    FormFieldSchema(
      fieldId: 'ancVisitNumber',
      type: FieldType.integer,
      label: 'ANC Visit Number',
      clinicalContext: 'Which antenatal visit this is (1st, 2nd, etc.)',
    ),
    // Physical exam
    FormFieldSchema(
      fieldId: 'fundalHeight',
      type: FieldType.decimal,
      label: 'Fundal Height',
      unit: 'cm',
      clinicalContext: 'Fundal height measurement in centimeters',
    ),
    FormFieldSchema(
      fieldId: 'fetalHeartRate',
      type: FieldType.integer,
      label: 'Fetal Heart Rate',
      unit: 'bpm',
      clinicalContext: 'Fetal heart rate in beats per minute. Normal 110-160',
    ),
    FormFieldSchema(
      fieldId: 'fetalMovement',
      type: FieldType.enumType,
      label: 'Fetal Movement',
      allowedValues: ['normal', 'decreased', 'absent'],
      clinicalContext: 'Presence and quality of fetal movement',
    ),
    FormFieldSchema(
      fieldId: 'presentation',
      type: FieldType.enumType,
      label: 'Presentation',
      allowedValues: ['cephalic', 'breech', 'transverse', 'unknown'],
      clinicalContext: 'Fetal presentation (head down, breech, etc.)',
    ),
    // Danger signs
    FormFieldSchema(
      fieldId: 'vaginalBleeding',
      type: FieldType.boolean,
      label: 'Vaginal Bleeding',
      clinicalContext: 'Presence of vaginal bleeding (danger sign)',
    ),
    FormFieldSchema(
      fieldId: 'severeHeadache',
      type: FieldType.boolean,
      label: 'Severe Headache',
      clinicalContext: 'Severe headache (possible pre-eclampsia)',
    ),
    FormFieldSchema(
      fieldId: 'blurredVision',
      type: FieldType.boolean,
      label: 'Blurred Vision',
      clinicalContext: 'Visual disturbances (possible pre-eclampsia)',
    ),
    FormFieldSchema(
      fieldId: 'swellingFaceHands',
      type: FieldType.boolean,
      label: 'Swelling of Face/Hands',
      clinicalContext: 'Edema of face or hands (possible pre-eclampsia)',
    ),
    FormFieldSchema(
      fieldId: 'convulsions',
      type: FieldType.boolean,
      label: 'Convulsions',
      clinicalContext: 'History of convulsions (eclampsia)',
    ),
    FormFieldSchema(
      fieldId: 'laborSigns',
      type: FieldType.boolean,
      label: 'Signs of Labor',
      clinicalContext: 'Contractions, water break, or other labor signs',
    ),
    FormFieldSchema(
      fieldId: 'abdominalPain',
      type: FieldType.boolean,
      label: 'Abdominal Pain',
      clinicalContext: 'Severe abdominal pain',
    ),
    // Labs
    FormFieldSchema(
      fieldId: 'hemoglobin',
      type: FieldType.decimal,
      label: 'Hemoglobin',
      unit: 'g/dL',
      clinicalContext: 'Hemoglobin level. Normal pregnancy ≥11, anemia <11',
    ),
    FormFieldSchema(
      fieldId: 'urineProtein',
      type: FieldType.enumType,
      label: 'Urine Protein',
      allowedValues: ['negative', 'trace', '1+', '2+', '3+', '4+'],
      clinicalContext: 'Urine protein dipstick result (proteinuria = pre-eclampsia risk)',
    ),
    // Interventions
    FormFieldSchema(
      fieldId: 'ironFolateGiven',
      type: FieldType.boolean,
      label: 'Iron/Folate Given',
      clinicalContext: 'Iron and folic acid supplementation provided',
    ),
    FormFieldSchema(
      fieldId: 'tetanusToxoidGiven',
      type: FieldType.boolean,
      label: 'Tetanus Toxoid Given',
      clinicalContext: 'Tetanus toxoid vaccination given this visit',
    ),
    FormFieldSchema(
      fieldId: 'dewormingGiven',
      type: FieldType.boolean,
      label: 'Deworming Given',
      clinicalContext: 'Deworming tablet given (after 1st trimester)',
    ),
    // Risk classification
    FormFieldSchema(
      fieldId: 'riskLevel',
      type: FieldType.enumType,
      label: 'Risk Level',
      allowedValues: ['low', 'moderate', 'high'],
      clinicalContext: 'Overall pregnancy risk classification',
    ),
    FormFieldSchema(
      fieldId: 'referralRecommended',
      type: FieldType.boolean,
      label: 'Referral Recommended',
      clinicalContext: 'Whether referral to facility is recommended',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // PNC (Postnatal Care)
  // ═══════════════════════════════════════════════════════════════════════════

  static const _pncSchema = <FormFieldSchema>[
    ..._commonVitalsSchema,
    // Timing
    FormFieldSchema(
      fieldId: 'deliveryDate',
      type: FieldType.date,
      label: 'Delivery Date',
      clinicalContext: 'Date of delivery',
    ),
    FormFieldSchema(
      fieldId: 'daysPostpartum',
      type: FieldType.integer,
      label: 'Days Postpartum',
      unit: 'days',
      clinicalContext: 'Number of days since delivery',
    ),
    FormFieldSchema(
      fieldId: 'pncVisitNumber',
      type: FieldType.integer,
      label: 'PNC Visit Number',
      clinicalContext: 'Which postnatal visit this is (1st within 24h, etc.)',
    ),
    // Delivery details
    FormFieldSchema(
      fieldId: 'deliveryType',
      type: FieldType.enumType,
      label: 'Type of Delivery',
      allowedValues: ['vaginal', 'cesarean', 'assisted'],
      clinicalContext: 'Mode of delivery',
    ),
    FormFieldSchema(
      fieldId: 'deliveryPlace',
      type: FieldType.enumType,
      label: 'Place of Delivery',
      allowedValues: ['home', 'facility', 'enRoute'],
      clinicalContext: 'Where delivery took place',
    ),
    // Maternal assessment
    FormFieldSchema(
      fieldId: 'vaginalBleeding',
      type: FieldType.enumType,
      label: 'Vaginal Bleeding',
      allowedValues: ['none', 'normal', 'heavy'],
      clinicalContext: 'Postpartum bleeding status',
    ),
    FormFieldSchema(
      fieldId: 'lochia',
      type: FieldType.enumType,
      label: 'Lochia',
      allowedValues: ['normal', 'foulSmelling', 'excessive'],
      clinicalContext: 'Postpartum vaginal discharge',
    ),
    FormFieldSchema(
      fieldId: 'uterusContracted',
      type: FieldType.boolean,
      label: 'Uterus Well Contracted',
      clinicalContext: 'Uterine involution status',
    ),
    FormFieldSchema(
      fieldId: 'breastfeeding',
      type: FieldType.enumType,
      label: 'Breastfeeding',
      allowedValues: ['exclusive', 'mixed', 'notBreastfeeding'],
      clinicalContext: 'Breastfeeding status',
    ),
    FormFieldSchema(
      fieldId: 'breastProblems',
      type: FieldType.boolean,
      label: 'Breast Problems',
      clinicalContext: 'Mastitis, engorgement, or other breast issues',
    ),
    // Danger signs
    FormFieldSchema(
      fieldId: 'fever',
      type: FieldType.boolean,
      label: 'Fever',
      clinicalContext: 'Postpartum fever (possible infection)',
    ),
    FormFieldSchema(
      fieldId: 'convulsions',
      type: FieldType.boolean,
      label: 'Convulsions',
      clinicalContext: 'Postpartum convulsions (eclampsia)',
    ),
    FormFieldSchema(
      fieldId: 'severeHeadache',
      type: FieldType.boolean,
      label: 'Severe Headache',
      clinicalContext: 'Severe headache (postpartum pre-eclampsia)',
    ),
    // Mental health
    FormFieldSchema(
      fieldId: 'moodAssessment',
      type: FieldType.enumType,
      label: 'Mood Assessment',
      allowedValues: ['normal', 'babyBlues', 'concerningSymptoms'],
      clinicalContext: 'Postpartum mental health screening',
    ),
    // Newborn (brief)
    FormFieldSchema(
      fieldId: 'newbornAlive',
      type: FieldType.boolean,
      label: 'Newborn Alive',
      clinicalContext: 'Whether newborn is alive and well',
    ),
    FormFieldSchema(
      fieldId: 'newbornWeight',
      type: FieldType.decimal,
      label: 'Newborn Weight',
      unit: 'kg',
      clinicalContext: 'Birth weight or current weight of newborn',
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // IMCI/ICCM (Child Health)
  // ═══════════════════════════════════════════════════════════════════════════

  static const _imciSchema = <FormFieldSchema>[
    // Vitals
    FormFieldSchema(
      fieldId: 'temperature',
      type: FieldType.decimal,
      label: 'Temperature',
      unit: '°C',
      clinicalContext: 'Body temperature',
    ),
    FormFieldSchema(
      fieldId: 'weight',
      type: FieldType.decimal,
      label: 'Weight',
      unit: 'kg',
      clinicalContext: 'Current weight',
    ),
    FormFieldSchema(
      fieldId: 'respiratoryRate',
      type: FieldType.integer,
      label: 'Respiratory Rate',
      unit: 'breaths/min',
      clinicalContext:
          'Breathing rate. Fast breathing: <2mo ≥60, 2-12mo ≥50, 1-5y ≥40',
    ),
    FormFieldSchema(
      fieldId: 'muac',
      type: FieldType.decimal,
      label: 'MUAC',
      unit: 'cm',
      clinicalContext:
          'Mid-upper arm circumference. Red <11.5cm (SAM), Yellow 11.5-12.5 (MAM)',
    ),
    // Chief complaints
    FormFieldSchema(
      fieldId: 'cough',
      type: FieldType.boolean,
      label: 'Cough',
      clinicalContext: 'Presence of cough',
    ),
    FormFieldSchema(
      fieldId: 'coughDays',
      type: FieldType.integer,
      label: 'Cough Duration',
      unit: 'days',
      clinicalContext: 'Duration of cough in days',
    ),
    FormFieldSchema(
      fieldId: 'diarrhea',
      type: FieldType.boolean,
      label: 'Diarrhea',
      clinicalContext: 'Presence of diarrhea (3+ loose stools/day)',
    ),
    FormFieldSchema(
      fieldId: 'diarrheaDays',
      type: FieldType.integer,
      label: 'Diarrhea Duration',
      unit: 'days',
      clinicalContext: 'Duration of diarrhea in days',
    ),
    FormFieldSchema(
      fieldId: 'fever',
      type: FieldType.boolean,
      label: 'Fever',
      clinicalContext: 'Presence of fever or history of fever',
    ),
    FormFieldSchema(
      fieldId: 'feverDays',
      type: FieldType.integer,
      label: 'Fever Duration',
      unit: 'days',
      clinicalContext: 'Duration of fever in days',
    ),
    // Danger signs
    FormFieldSchema(
      fieldId: 'convulsions',
      type: FieldType.boolean,
      label: 'Convulsions',
      clinicalContext: 'History of convulsions with this illness (danger sign)',
    ),
    FormFieldSchema(
      fieldId: 'unableToFeed',
      type: FieldType.boolean,
      label: 'Unable to Feed/Drink',
      clinicalContext: 'Not able to drink or breastfeed (danger sign)',
    ),
    FormFieldSchema(
      fieldId: 'vomitsEverything',
      type: FieldType.boolean,
      label: 'Vomits Everything',
      clinicalContext: 'Vomits everything (danger sign)',
    ),
    FormFieldSchema(
      fieldId: 'lethargicUnconscious',
      type: FieldType.boolean,
      label: 'Lethargy/Unconscious',
      clinicalContext: 'Lethargic or unconscious (danger sign)',
    ),
    // Respiratory assessment
    FormFieldSchema(
      fieldId: 'chestIndrawing',
      type: FieldType.boolean,
      label: 'Chest Indrawing',
      clinicalContext: 'Lower chest wall indrawing (severe pneumonia)',
    ),
    FormFieldSchema(
      fieldId: 'stridor',
      type: FieldType.boolean,
      label: 'Stridor',
      clinicalContext: 'Stridor when calm (danger sign)',
    ),
    FormFieldSchema(
      fieldId: 'wheezing',
      type: FieldType.boolean,
      label: 'Wheezing',
      clinicalContext: 'Audible wheezing',
    ),
    // Diarrhea assessment
    FormFieldSchema(
      fieldId: 'bloodyStool',
      type: FieldType.boolean,
      label: 'Blood in Stool',
      clinicalContext: 'Presence of blood in stool (dysentery)',
    ),
    FormFieldSchema(
      fieldId: 'sunkenEyes',
      type: FieldType.boolean,
      label: 'Sunken Eyes',
      clinicalContext: 'Eyes appear sunken (dehydration sign)',
    ),
    FormFieldSchema(
      fieldId: 'skinPinch',
      type: FieldType.enumType,
      label: 'Skin Pinch',
      allowedValues: ['normal', 'slow', 'verySlowOrStanding'],
      clinicalContext: 'Skin pinch goes back: immediately=normal, slowly, very slowly',
    ),
    FormFieldSchema(
      fieldId: 'drinkingStatus',
      type: FieldType.enumType,
      label: 'Drinking/Feeding',
      allowedValues: ['drinkingNormally', 'drinkingPoorly', 'notAbleToDrink'],
      clinicalContext: 'Ability to drink or breastfeed',
    ),
    // Nutrition
    FormFieldSchema(
      fieldId: 'visibleWasting',
      type: FieldType.boolean,
      label: 'Visible Wasting',
      clinicalContext: 'Visible severe wasting',
    ),
    FormFieldSchema(
      fieldId: 'edemaBothFeet',
      type: FieldType.boolean,
      label: 'Edema Both Feet',
      clinicalContext: 'Bilateral pitting edema (kwashiorkor)',
    ),
    // Ear
    FormFieldSchema(
      fieldId: 'earPain',
      type: FieldType.boolean,
      label: 'Ear Pain/Problem',
      clinicalContext: 'Ear pain or discharge',
    ),
    FormFieldSchema(
      fieldId: 'earDischarge',
      type: FieldType.boolean,
      label: 'Ear Discharge',
      clinicalContext: 'Pus draining from ear',
    ),
    // Malaria (endemic areas)
    FormFieldSchema(
      fieldId: 'mrdtResult',
      type: FieldType.enumType,
      label: 'Malaria RDT Result',
      allowedValues: ['notDone', 'negative', 'positive'],
      clinicalContext: 'Malaria rapid diagnostic test result',
    ),
    // Classification
    FormFieldSchema(
      fieldId: 'classification',
      type: FieldType.string,
      label: 'IMCI Classification',
      clinicalContext:
          'Primary IMCI classification (e.g., Pneumonia, Severe Diarrhea)',
    ),
    FormFieldSchema(
      fieldId: 'referralRequired',
      type: FieldType.boolean,
      label: 'Urgent Referral Required',
      clinicalContext: 'Whether urgent referral to facility is required',
    ),
    // Treatment
    FormFieldSchema(
      fieldId: 'orsGiven',
      type: FieldType.boolean,
      label: 'ORS Given',
      clinicalContext: 'Oral rehydration solution provided',
    ),
    FormFieldSchema(
      fieldId: 'zincGiven',
      type: FieldType.boolean,
      label: 'Zinc Given',
      clinicalContext: 'Zinc supplementation provided for diarrhea',
    ),
    FormFieldSchema(
      fieldId: 'amoxicillinGiven',
      type: FieldType.boolean,
      label: 'Amoxicillin Given',
      clinicalContext: 'Oral amoxicillin for pneumonia',
    ),
    FormFieldSchema(
      fieldId: 'artemisininGiven',
      type: FieldType.boolean,
      label: 'Antimalarial Given',
      clinicalContext: 'ACT given for malaria',
    ),
    FormFieldSchema(
      fieldId: 'paracetamolGiven',
      type: FieldType.boolean,
      label: 'Paracetamol Given',
      clinicalContext: 'Paracetamol for fever',
    ),
  ];
}
