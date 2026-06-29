/// Form section model — core types for the sectioned assessment compositor.
///
/// A [FormSection] groups [FieldDef]s by clinical domain and is tagged with
/// the set of [Programme]s that require it.  The compositor deduplicates
/// shared fields across sections and renders them in priority order.
///
/// Engineering Design Standards:
///   - No I/O in these types — they are pure data containers.
///   - All UI copy is referenced by [FieldDef.labelKey], resolved at
///     render time via [ComposerStrings].
library;

import '../../../core/models/programme.dart';

// ── Field type ────────────────────────────────────────────────────────────────

/// The data kind of a form field, used by the renderer to pick the
/// appropriate input widget.
enum FieldType {
  booleanField,
  intField,
  doubleField,
  textField,
  selectField,
  multiSelectField,
  // ── Extended types (maps to API viewType values) ──────────────────────────
  /// API: RadioGroup — horizontal pill buttons for single selection.
  radioField,
  /// API: DialogCheckbox — chip summary + bottom-sheet multi-select.
  dialogMultiSelectField,
  /// API: DatePicker — tap-to-pick date, formatted display.
  dateField,
  /// API: BP — paired systolic / diastolic numeric inputs.
  bpField,
  /// API: AgeOrDob — segmented Age number or DOB date picker.
  ageOrDobField,
  /// API: AgeYMD — three-field Years / Months / Days row.
  ageYmdField,
  /// API: InformationLabel — read-only computed value display (e.g. BMI).
  infoLabelField,
  /// API: TextLabel / Instruction — static display text; no input.
  textLabelField,
}

// ── Condition ─────────────────────────────────────────────────────────────────

/// A simple equality/inequality condition used for field and section visibility gates.
///
/// Exactly one of [equalsValue] or [notEqualsValue] must be provided.
/// The condition is *true* when the field identified by [fieldId] currently
/// holds a value that equals [equalsValue], or does not equal [notEqualsValue].
class Condition {
  const Condition({
    required this.fieldId,
    this.equalsValue,
    this.notEqualsValue,
  }) : assert(
          (equalsValue != null) != (notEqualsValue != null),
          'Provide exactly one of equalsValue or notEqualsValue',
        );

  /// The field whose current value is inspected.
  final String fieldId;

  /// The value [fieldId] must equal for the condition to be true.
  final dynamic equalsValue;

  /// The value [fieldId] must NOT equal for the condition to be true.
  final dynamic notEqualsValue;

  /// Evaluate against [fieldValues], a map of fieldId → current value.
  bool evaluate(Map<String, dynamic> fieldValues) {
    final current = fieldValues[fieldId];
    if (notEqualsValue != null) return current != notEqualsValue;
    return current == equalsValue;
  }

  @override
  String toString() => notEqualsValue != null
      ? 'Condition($fieldId != $notEqualsValue)'
      : 'Condition($fieldId == $equalsValue)';

  @override
  bool operator ==(Object other) =>
      other is Condition &&
      other.fieldId == fieldId &&
      other.equalsValue == equalsValue &&
      other.notEqualsValue == notEqualsValue;

  @override
  int get hashCode => Object.hash(fieldId, equalsValue, notEqualsValue);
}

// ── Field definition ─────────────────────────────────────────────────────────

/// A single form field definition.
///
/// [labelKey] is a constant from [ComposerStrings] — never a raw string.
/// The renderer resolves the label at build time.
class FieldDef {
  const FieldDef({
    required this.fieldId,
    required this.type,
    required this.labelKey,
    this.visibleWhen,
    this.unit,
    this.min,
    this.max,
    this.options,
    this.required = false,
    this.hint,
    this.isInstruction = false,
  });

  /// Stable, unique identifier for this field (e.g. `'temperature'`).
  /// Used as the key in the [AssessmentDraftRow.fieldValues] map.
  final String fieldId;

  /// The data type rendered by the form.
  final FieldType type;

  /// Label constant key from [ComposerStrings].  Widgets resolve via
  /// [ComposerStrings.fieldLabel(labelKey)] — never inline.
  final String labelKey;

  /// If non-null, this field is hidden unless the condition is true.
  final Condition? visibleWhen;

  /// Optional display unit suffix (e.g. `'°C'`, `'/min'`).
  final String? unit;

  /// Inclusive minimum for numeric fields.
  final num? min;

  /// Inclusive maximum for numeric fields.
  final num? max;

  /// Option keys (into [ComposerStrings]) for [FieldType.selectField] /
  /// [FieldType.multiSelectField].  These are the *raw option values* stored
  /// in [AssessmentDraftRow.fieldValues], not localized labels.
  final List<String>? options;

  /// Whether a value is required before the section can be marked done.
  final bool required;

  /// Optional placeholder / helper text for fields that display a hint
  /// when empty (e.g. DatePicker, BP inputs).
  final String? hint;

  /// When true, a [FieldType.textLabelField] renders as an instruction block
  /// with a left border accent, rather than plain inline text.
  final bool isInstruction;

  @override
  String toString() => 'FieldDef($fieldId, $type)';

  @override
  bool operator ==(Object other) =>
      other is FieldDef && other.fieldId == fieldId;

  @override
  int get hashCode => fieldId.hashCode;
}

// ── Form section ──────────────────────────────────────────────────────────────

/// A named group of [FieldDef]s associated with one or more [Programme]s.
///
/// Sections are assembled by [FormCompositor] into a [ComposedForm].
/// Priority controls render order (lower = first).  [displayWhen] gates
/// section-level visibility (e.g. the `tb-screen-detail` section may be
/// hidden until coughDays ≥ 14).
class FormSection {
  const FormSection({
    required this.sectionId,
    required this.programmes,
    required this.priority,
    required this.fields,
    this.displayWhen,
    this.sharedFieldIds = const {},
  });

  /// Stable section identifier (e.g. `'vitals'`, `'danger-signs'`).
  final String sectionId;

  /// Which programmes include this section.
  final Set<Programme> programmes;

  /// Render priority — lower values render before higher values.
  final int priority;

  /// Ordered list of [FieldDef]s for this section.
  final List<FieldDef> fields;

  /// Optional section-level gate.  The section is visible when this is null
  /// or when it evaluates to true against the current field values.
  final Condition? displayWhen;

  /// Field IDs whose values are *owned* by another section (earlier in
  /// priority order) and merely *broadcast* into this section for reference.
  /// The compositor will not duplicate them in [ComposedForm.fieldOwnership].
  final Set<String> sharedFieldIds;

  @override
  String toString() =>
      'FormSection($sectionId, priority=$priority, '
      'programmes=${programmes.map((p) => p.name).join(",")})';

  @override
  bool operator ==(Object other) =>
      other is FormSection && other.sectionId == sectionId;

  @override
  int get hashCode => sectionId.hashCode;
}
