/// Parsed definition of a single form field produced by [FormSchemaParser].
///
/// For composite fields (e.g. [FieldKind.bloodPressure], [FieldKind.vitalsBundle])
/// the parser merges multiple JSON layout items into a single [FieldSchema] —
/// the [subFieldIds] list records which raw API field IDs were folded in.
/// Serialisation back to the flat [AssessmentDraftRow.fieldValues] map expands
/// a composite back to its constituent key-value pairs.
library;

import 'field_kind.dart';
import 'condition_schema.dart';

/// A single selectable option (label + stored value).
class FieldOption {
  const FieldOption({required this.label, required this.value});

  final String label;
  final String value;

  factory FieldOption.fromString(String raw) =>
      FieldOption(label: raw, value: raw);

  @override
  String toString() => 'FieldOption($value)';
}

class FieldSchema {
  const FieldSchema({
    required this.fieldId,
    required this.label,
    required this.kind,
    this.required = false,
    this.unit,
    this.min,
    this.max,
    this.hint,
    this.options = const [],
    this.conditions = const [],
    this.subFieldIds = const [],
    this.raw = const {},
  });

  /// Stable identifier used as the key in [AssessmentDraftRow.fieldValues].
  /// For composites this is the canonical composite ID (e.g. 'bloodPressure').
  final String fieldId;

  /// Display label shown above the widget.
  final String label;

  /// The widget kind — drives [FieldRenderer] dispatch.
  final FieldKind kind;

  /// Whether the user must fill this field before submitting.
  final bool required;

  /// Unit suffix displayed next to the input (e.g. '°C', 'mmHg').
  final String? unit;

  /// Inclusive minimum for numeric fields.
  final double? min;

  /// Inclusive maximum for numeric fields.
  final double? max;

  /// Placeholder / helper text for the input.
  final String? hint;

  /// Options for radio, dropdown, or multi-select fields.
  final List<FieldOption> options;

  /// Visibility conditions that reference this field as a target.
  final List<ConditionSchema> conditions;

  /// For composites: the raw API fieldIds folded into this schema.
  /// Used by [DynamicFormController] to expand composite values on save.
  final List<String> subFieldIds;

  /// Original JSON item — preserved for extension points.
  final Map<String, dynamic> raw;

  @override
  String toString() => 'FieldSchema($fieldId, $kind)';

  @override
  bool operator ==(Object other) =>
      other is FieldSchema && other.fieldId == fieldId;

  @override
  int get hashCode => fieldId.hashCode;
}
