/// Complete parsed form schema produced by [FormSchemaParser].
///
/// One [FormSchema] corresponds to a single `formData` entry from
/// program_forms.json — i.e. one programme form (ANC, NCD, pncMother, etc.).
library;

import 'section_schema.dart';
import 'field_schema.dart';

class FormSchema {
  const FormSchema({
    required this.formType,
    required this.sections,
    required this.allFields,
  });

  /// Form identifier matching the programme name (e.g. 'anc', 'ncd').
  final String formType;

  /// Ordered sections as they appear in the layout.
  final List<SectionSchema> sections;

  /// Flat list of every [FieldSchema] across all sections — for O(1) lookup.
  final List<FieldSchema> allFields;

  FieldSchema? fieldById(String id) {
    for (final f in allFields) {
      if (f.fieldId == id) return f;
    }
    return null;
  }

  @override
  String toString() =>
      'FormSchema($formType, ${sections.length} sections, '
      '${allFields.length} fields)';
}
