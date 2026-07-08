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
  ///
  static List<FormFieldSchema> forProgramme(Programme programme) => const [];

  static List<FormFieldSchema> forProgrammes(List<Programme> programmes) => const [];

}