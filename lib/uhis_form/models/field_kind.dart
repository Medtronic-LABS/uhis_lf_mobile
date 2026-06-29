/// Canonical enum — one value per widget type in the uhis_form SDK.
///
/// All dispatch in [FieldRenderer] and all composite grouping logic in
/// [FormSchemaParser] key on this enum. Adding a new viewType requires:
///   1. A new [FieldKind] value here.
///   2. A composite-detection rule in [FormSchemaParser._tryParseComposite].
///   3. A new widget under [lib/uhis_form/widgets/].
///   4. A new arm in [FieldRenderer.build].
library;

enum FieldKind {
  // ── Basic inputs ──────────────────────────────────────────────────────────
  textInput, // EditText inputType 96 | 1 | -1
  integerInput, // EditText inputType 2 | 3
  decimalInput, // EditText inputType 8192
  datePicker, // DatePicker
  radioGroup, // RadioGroup + SingleSelectionView ≤ 4 options
  dropdown, // Spinner + SingleSelectionView > 4 options
  chipMultiSelect, // DialogCheckbox + MultiSelectSpinner
  toggleSwitch, // CheckBox (single boolean)
  qrScanner, // QRView
  ageOrDob, // AgeOrDob
  ageYmd, // AgeYMD

  // ── Healthcare composites ─────────────────────────────────────────────────
  bloodPressure, // BP viewType — systolic + diastolic + range strip
  anthropometry, // height + weight → auto-BMI card
  bloodGlucose, // type selector (fasting/random) + value + unit + flag
  vitalsBundle, // temperature + pulse + RR + SpO2 grid card
  muac, // MUAC + traffic-light band
  supplyPair, // consumed + provided inline pair (IFA, Folic, Calcium)
  dangerSigns, // critical-surface multiselect (danger-signs viewType)
  urineTest, // albumin + sugar + bilirubin dropdown card
  obstetricHistory, // gravida + parity + livingChildren trio
  labResult, // single measurement + reference range
  pregnancyProfile, // LMP → auto-EDD + gestational age
  glassPrescription, // eye care: power + type + frame + sold
  referralCard, // urgency + facility + reason

  // ── Display only ─────────────────────────────────────────────────────────
  computedLabel, // InformationLabel — read-only computed value (e.g. BMI)
  instruction, // Instruction block with left-border accent
  sectionHeader, // TextLabel used as group title — absorbed by SectionCard
}
