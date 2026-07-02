/// Parity test: [CanonicalFormTransformer] must produce the same [FormSchema]
/// as the legacy [FormSchemaParser] path for every formType in program_forms.json.
///
/// Asserts that field IDs, section titles, field kinds, and required flags
/// are identical between the two paths (per form_sdk_migration_plan.md CI
/// validation algorithm).
///
/// This test uses dart:io to read the assets directly — no Flutter widget
/// harness needed, so it runs in `flutter test` without an emulator.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/uhis_form/models/form_schema.dart';
import 'package:uhis_next/uhis_form/parser/form_schema_parser.dart';
import 'package:uhis_next/uhis_form/transformer/canonical_form_transformer.dart';

void main() {
  const parser = FormSchemaParser();

  // ── Load assets once ──────────────────────────────────────────────────────

  late Map<String, FormSchema> legacySchemas;
  late Map<String, FormSchema> canonicalSchemas;

  setUpAll(() {
    legacySchemas = _loadLegacySchemas(parser);
    canonicalSchemas = _loadCanonicalSchemas(parser);
  });

  // ── Parity tests ──────────────────────────────────────────────────────────

  test('canonical and legacy paths cover the same formTypes', () {
    expect(
      canonicalSchemas.keys.toSet(),
      equals(legacySchemas.keys.toSet()),
      reason: 'Both paths must cover the same set of formTypes',
    );
  });

  test('field IDs match for all formTypes', () {
    for (final formType in legacySchemas.keys) {
      final legacy = legacySchemas[formType]!;
      final canonical = canonicalSchemas[formType]!;

      final legacyIds = legacy.allFields.map((f) => f.fieldId).toList();
      final canonicalIds = canonical.allFields.map((f) => f.fieldId).toList();

      expect(
        canonicalIds,
        orderedEquals(legacyIds),
        reason: 'Field ID mismatch for formType="$formType"\n'
            '  legacy:    $legacyIds\n'
            '  canonical: $canonicalIds',
      );
    }
  });

  test('section titles match for all formTypes', () {
    for (final formType in legacySchemas.keys) {
      final legacy = legacySchemas[formType]!;
      final canonical = canonicalSchemas[formType]!;

      final legacyTitles = legacy.sections.map((s) => s.title).toList();
      final canonicalTitles = canonical.sections.map((s) => s.title).toList();

      expect(
        canonicalTitles,
        orderedEquals(legacyTitles),
        reason: 'Section title mismatch for formType="$formType"\n'
            '  legacy:    $legacyTitles\n'
            '  canonical: $canonicalTitles',
      );
    }
  });

  test('field kinds match for all formTypes', () {
    for (final formType in legacySchemas.keys) {
      final legacy = legacySchemas[formType]!;
      final canonical = canonicalSchemas[formType]!;

      for (var i = 0; i < legacy.allFields.length; i++) {
        final lf = legacy.allFields[i];
        final cf = canonical.allFields[i];
        expect(
          cf.kind,
          equals(lf.kind),
          reason: 'Field kind mismatch for formType="$formType" '
              'field="${lf.fieldId}": legacy=${lf.kind} canonical=${cf.kind}',
        );
      }
    }
  });

  test('required flags match for all formTypes', () {
    for (final formType in legacySchemas.keys) {
      final legacy = legacySchemas[formType]!;
      final canonical = canonicalSchemas[formType]!;

      for (var i = 0; i < legacy.allFields.length; i++) {
        final lf = legacy.allFields[i];
        final cf = canonical.allFields[i];
        expect(
          cf.required,
          equals(lf.required),
          reason: 'Required flag mismatch for formType="$formType" '
              'field="${lf.fieldId}": legacy=${lf.required} canonical=${cf.required}',
        );
      }
    }
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Loads all FormSchemas from the legacy program_forms.json.
Map<String, FormSchema> _loadLegacySchemas(FormSchemaParser parser) {
  final file = File('assets/forms/program_forms.json');
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final entity = raw['entity'] as Map<String, dynamic>? ?? raw;
  final forms =
      (entity['formData'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();

  final result = <String, FormSchema>{};
  for (final entry in forms) {
    final formType = entry['formType'] as String? ?? '';
    final formInput = entry['formInput'] as String? ?? '{}';
    result[formType.toLowerCase()] = parser.parse(formType, formInput);
  }
  return result;
}

/// Loads all FormSchemas from field_library.json + layout_manifests.json
/// via [CanonicalFormTransformer].
Map<String, FormSchema> _loadCanonicalSchemas(FormSchemaParser parser) {
  final libFile = File('assets/forms/field_library.json');
  final rawLib = jsonDecode(libFile.readAsStringSync()) as Map<String, dynamic>;
  final library = rawLib.map(
    (k, v) => MapEntry(k, v as Map<String, dynamic>),
  );

  final manifestsFile = File('assets/forms/layout_manifests.json');
  final manifests =
      (jsonDecode(manifestsFile.readAsStringSync()) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();

  final transformer = CanonicalFormTransformer(library);

  final result = <String, FormSchema>{};
  for (final manifest in manifests) {
    final formType = manifest['formType'] as String? ?? '';
    final formInput = transformer.toLegacyFormInput(
      formType: formType,
      layoutManifest: manifest,
    );
    result[formType.toLowerCase()] = parser.parse(formType, formInput);
  }
  return result;
}
