/// Form field schema builder for AI Scribe form_prefill mode.
///
/// Generates [FormFieldSchema] definitions from assessment forms to send
/// to the AI scribe service. The service uses this schema to extract
/// structured field values from the consultation transcript.
library;

import '../../core/models/programme.dart';
import '../visit/forms/form_config.dart';

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
/// Sent to the AI scribe service as part of the form_fill request.
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

  /// Server `assessmentType` for a Step 2 realtime ASR session, or null when
  /// auto-fill is not yet supported for this visit's programme mix.
  ///
  /// v1 scope is NCD and ANC only. PNC intentionally returns null: the PNC
  /// screen renders mother + child + outcome forms together and a
  /// mother-only extraction would silently drop every newborn utterance —
  /// worse than no fill. ANC outranks NCD in combined visits (maternal
  /// danger signs are the higher-stakes capture).
  static String? assessmentTypeFor(List<String> activeFormTypes) {
    final programmes =
        activeFormTypes.map(Programme.fromString).toSet();
    if (programmes.contains(Programme.pnc)) return null;
    final hasAnc = programmes.contains(Programme.anc);
    final hasNcd = programmes.contains(Programme.ncd);
    if (hasAnc && hasNcd) return 'anc,ncd';
    if (hasAnc) return 'anc';
    if (hasNcd) return 'ncd';
    return null;
  }

  /// Build the combined schema for a list of programme name strings.
  ///
  /// Deduplicates fields that appear in multiple programmes (e.g. `systolic`
  /// shared by ANC and NCD). [config] defaults to the loaded [FormConfig]
  /// singleton; overridable for unit tests that don't load real assets.
  static List<FormFieldSchema> forProgrammeNames(
    List<String> names, {
    FormConfig? config,
  }) {
    final resolvedConfig = config ?? FormConfig.instance;
    final seen = <String>{};
    final result = <FormFieldSchema>[];
    for (final name in names) {
      for (final field in _forProgramme(name, resolvedConfig)) {
        if (seen.add(field.fieldId)) result.add(field);
      }
    }
    return result;
  }

  /// Fields that are extractable despite not being their own literal
  /// fieldRef in `layout_manifests.json` — a companion value the SAME
  /// rendered widget also writes (mirrors leapfrog-ai-service's
  /// `KNOWN_DUAL_SIBLING_EXTRAS`, verified the same way: `glucoseType`'s
  /// `_BloodGlucoseEntryField` widget writes both `glucoseType` and
  /// `glucose` on every manual entry — see unified_form_screen.dart's
  /// `_BloodGlucoseEntryField`).
  static const _knownDualSiblingExtras = <String, Set<String>>{
    'ncd': {'glucose'},
  };

  /// Widget hints that carry no directly extractable value (composite,
  /// label-only, or container widgets) — mirrors leapfrog-ai-service's
  /// `SKIP_WIDGET_HINTS`. `unknown` catches hints this app's [WidgetHint]
  /// enum doesn't recognize (e.g. a plain CardView container).
  static const _skipWidgetHints = {
    WidgetHint.textLabel,
    WidgetHint.infoLabel,
    WidgetHint.dateField,
    WidgetHint.pregnancyProfile,
    WidgetHint.bloodGlucose,
    WidgetHint.unknown,
  };

  /// Build schema for a single formType string (e.g. `'ncd'`, `'anc'`).
  ///
  /// v1 scope is NCD and ANC only — mirrors [assessmentTypeFor]'s own gate.
  /// Every other formType (pncMother, pncChild, imci, tb, ...) returns an
  /// empty list even though `config.forms` may have real layout data for
  /// them; [assessmentTypeFor] never emits those names today (PNC's
  /// mother-only-extraction risk is exactly why), so this stays an explicit
  /// allow-list rather than silently supporting them the moment a future
  /// caller passes one directly.
  static List<FormFieldSchema> _forProgramme(String formType, FormConfig config) {
    if (formType != 'ncd' && formType != 'anc') return const [];

    final sections = config.forms[formType] ?? const [];
    final inputTypeById = <String, int>{
      for (final section in sections)
        for (final ref in section.fieldRefs) ref.id: ref.inputType,
    };
    final extras = _knownDualSiblingExtras[formType] ?? const {};

    final result = <FormFieldSchema>[];
    for (final field in config.fields.values) {
      if (!field.programmeIds.contains(formType)) continue;
      if (!inputTypeById.containsKey(field.id) && !extras.contains(field.id)) {
        continue;
      }
      final schema = _buildFieldSchema(field, inputTypeById[field.id]);
      if (schema != null) result.add(schema);
    }
    result.sort((a, b) => a.fieldId.compareTo(b.fieldId));
    return result;
  }

  /// Maps a [FieldDef] (+ its layout `inputType`, when it has a real
  /// fieldRef) to the AI-extraction contract. Returns null for
  /// composite/label-only widgets that carry no directly extractable value.
  static FormFieldSchema? _buildFieldSchema(FieldDef field, int? inputType) {
    if (_skipWidgetHints.contains(field.widgetHint)) return null;

    FieldType type;
    List<String>? allowedValues;
    if (field.options.isNotEmpty) {
      type = FieldType.enumType;
      allowedValues = field.options.map((o) => o.name).toList();
    } else if (inputType == 3) {
      // FieldRef.inputType: 3 = number (integer).
      type = FieldType.integer;
    } else if (inputType == 2 || field.widgetHint == WidgetHint.numeric) {
      // FieldRef.inputType: 2 = numberDecimal.
      type = FieldType.decimal;
    } else {
      type = FieldType.string;
    }

    return FormFieldSchema(
      fieldId: field.id,
      type: type,
      label: field.label,
      unit: field.unitMeasurement,
      allowedValues: allowedValues,
    );
  }
}
