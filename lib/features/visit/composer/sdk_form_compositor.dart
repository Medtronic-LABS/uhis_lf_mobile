/// SDK-based form compositor for multi-programme visit assessments.
///
/// Merges multiple [FormSchema] objects — one per pilot [Programme] — into a
/// single schema using the same deduplication logic as [FormCompositor]:
/// first-seen section wins; first-seen fieldId across sections wins.
///
/// Non-pilot programmes are silently filtered. Returns null when no schemas
/// could be loaded (e.g. assets missing).
library;

import '../../../core/models/programme.dart';
import '../../../uhis_form/form_data_service.dart';
import '../../../uhis_form/models/field_schema.dart';
import '../../../uhis_form/models/form_schema.dart';
import '../../../uhis_form/models/section_schema.dart';

class SdkFormCompositor {
  SdkFormCompositor._();

  static final FormDataService _service = FormDataService();

  /// Programme render priority — lower renders first (matches [FormCompositor]).
  static int _priority(Programme p) => switch (p) {
        Programme.imci => 10,
        Programme.anc => 20,
        Programme.pnc => 25,
        Programme.tb => 30,
        Programme.ncd => 40,
        _ => 50,
      };

  /// Maps a [Programme] to its canonical formType string in layout_manifests.json.
  ///
  /// PNC splits into pncMother / pncNeonatal / pncChild in the SDK assets —
  /// we load pncMother as the primary PNC form.
  /// IMCI is not yet in layout_manifests.json — returns null, caller skips.
  static String? _formTypeId(Programme p) => switch (p) {
        Programme.pnc => 'pncMother',
        Programme.imci => null, // not yet in SDK assets
        Programme.anc => 'anc',
        Programme.ncd => 'ncd',
        Programme.tb => 'tb',
        _ => p.name.toLowerCase(),
      };

  /// Compose a merged [FormSchema] for the given [programmes].
  ///
  /// Only [Programme.kPilotProgrammes] are included; others are skipped.
  /// Sections are merged in priority order with cross-section field dedup.
  /// Returns null if no schemas could be loaded.
  static Future<FormSchema?> compose(List<Programme> programmes) async {
    final pilots = programmes
        .where((p) => p.isPilot)
        .toSet()
        .toList()
      ..sort((a, b) => _priority(a) - _priority(b));

    if (pilots.isEmpty) return null;

    final schemas = <FormSchema>[];
    for (final programme in pilots) {
      final typeId = _formTypeId(programme);
      if (typeId == null) continue; // not yet in SDK assets — skip
      final schema = await _service.schemaForType(typeId);
      if (schema != null) schemas.add(schema);
    }

    if (schemas.isEmpty) return null;
    if (schemas.length == 1) return schemas.first;

    final seenSectionIds = <String>{};
    final seenFieldIds = <String>{};
    final mergedSections = <SectionSchema>[];

    for (final schema in schemas) {
      for (final section in schema.sections) {
        if (!seenSectionIds.add(section.sectionId)) continue;

        final uniqueFields = section.fields
            .where((f) => seenFieldIds.add(f.fieldId))
            .toList();
        if (uniqueFields.isEmpty) continue;

        mergedSections.add(SectionSchema(
          sectionId: section.sectionId,
          title: section.title,
          fields: uniqueFields,
        ));
      }
    }

    if (mergedSections.isEmpty) return null;

    final allFields = <FieldSchema>[
      for (final s in mergedSections) ...s.fields,
    ];
    final compositeFormType = pilots.map((p) => p.name).join('_');

    return FormSchema(
      formType: compositeFormType,
      sections: mergedSections,
      allFields: allFields,
    );
  }
}
