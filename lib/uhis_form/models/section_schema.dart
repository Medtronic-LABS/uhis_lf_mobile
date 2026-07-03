/// A named group of [FieldSchema]s corresponding to a `CardView` in the
/// program_forms.json layout.
library;

import 'field_schema.dart';

class SectionSchema {
  const SectionSchema({
    required this.sectionId,
    required this.title,
    required this.fields,
  });

  /// Stable identifier from the CardView `id` field.
  final String sectionId;

  /// Display title shown in the section card header.
  final String title;

  /// Ordered fields inside this section.
  final List<FieldSchema> fields;

  @override
  String toString() =>
      'SectionSchema($sectionId, ${fields.length} fields)';

  @override
  bool operator ==(Object other) =>
      other is SectionSchema && other.sectionId == sectionId;

  @override
  int get hashCode => sectionId.hashCode;
}
