/// Loads and caches parsed [FormSchema] objects from the bundled canonical
/// assets (`field_library.json` + `layout_manifests.json`).
///
/// The [CanonicalFormTransformer] converts the canonical format to the legacy
/// `formInput` JSON string that [FormSchemaParser] expects, keeping the parser
/// and all downstream consumers unchanged.
///
/// Fallback: set [useCanonical] to false to revert to reading `program_forms.json`
/// directly (single-line rollback per form_sdk_migration_plan.md Phase 1).
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'models/form_schema.dart';
import 'parser/form_schema_parser.dart';
import 'transformer/canonical_form_transformer.dart';

class FormDataService {
  FormDataService({this.useCanonical = true});

  static const _canonicalLibraryPath = 'assets/forms/field_library.json';
  static const _canonicalManifestsPath = 'assets/forms/layout_manifests.json';
  static const _legacyAssetPath = 'assets/forms/program_forms.json';
  static const _parser = FormSchemaParser();

  /// Set to false to fall back to the legacy program_forms.json path.
  final bool useCanonical;

  final Map<String, FormSchema> _cache = {};

  // Canonical path state
  CanonicalFormTransformer? _transformer;
  List<Map<String, dynamic>>? _manifests;

  // Legacy path state
  List<Map<String, dynamic>>? _rawForms;

  /// Returns the [FormSchema] for [formType] (e.g. 'anc', 'ncd').
  ///
  /// [formType] is matched case-insensitively. Returns null if no match found.
  Future<FormSchema?> schemaForType(String formType) async {
    final key = formType.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];

    if (useCanonical) {
      return _schemaFromCanonical(formType, key);
    } else {
      return _schemaFromLegacy(formType, key);
    }
  }

  /// Returns schemas for all form types.
  Future<List<FormSchema>> allSchemas() async {
    if (useCanonical) {
      await _ensureCanonicalLoaded();
      final result = <FormSchema>[];
      for (final manifest in _manifests!) {
        final ft = manifest['formType']?.toString() ?? '';
        final schema = await schemaForType(ft);
        if (schema != null) result.add(schema);
      }
      return result;
    } else {
      await _ensureLegacyLoaded();
      final result = <FormSchema>[];
      for (final entry in _rawForms!) {
        final ft = entry['formType']?.toString() ?? '';
        final schema = await schemaForType(ft);
        if (schema != null) result.add(schema);
      }
      return result;
    }
  }

  // ── Canonical path ──────────────────────────────────────────────────────────

  Future<FormSchema?> _schemaFromCanonical(String formType, String key) async {
    await _ensureCanonicalLoaded();

    for (final manifest in _manifests!) {
      final rawType = manifest['formType']?.toString().toLowerCase() ?? '';
      if (rawType == key) {
        final formInput = _transformer!.toLegacyFormInput(
          formType: formType,
          layoutManifest: manifest,
        );
        final schema = _parser.parse(formType, formInput);
        _cache[key] = schema;
        return schema;
      }
    }
    return null;
  }

  Future<void> _ensureCanonicalLoaded() async {
    if (_transformer != null) return;

    final libJson = await rootBundle.loadString(_canonicalLibraryPath);
    final rawLib = jsonDecode(libJson) as Map<String, dynamic>;
    final library = rawLib.map(
      (k, v) => MapEntry(k, v as Map<String, dynamic>),
    );

    final manifestsJson = await rootBundle.loadString(_canonicalManifestsPath);
    _manifests =
        (jsonDecode(manifestsJson) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();

    _transformer = CanonicalFormTransformer(library);
  }

  // ── Legacy path (fallback) ──────────────────────────────────────────────────

  Future<FormSchema?> _schemaFromLegacy(String formType, String key) async {
    await _ensureLegacyLoaded();

    for (final entry in _rawForms!) {
      final rawType = entry['formType']?.toString().toLowerCase() ?? '';
      if (rawType == key) {
        final formInput = entry['formInput'] as String? ?? '{}';
        final schema = _parser.parse(formType, formInput);
        _cache[key] = schema;
        return schema;
      }
    }
    return null;
  }

  Future<void> _ensureLegacyLoaded() async {
    if (_rawForms != null) return;
    final jsonString = await rootBundle.loadString(_legacyAssetPath);
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final entity = decoded['entity'] as Map<String, dynamic>? ?? decoded;
    _rawForms =
        (entity['formData'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
  }
}
