/// Loads and caches parsed [FormSchema] objects from the bundled canonical
/// assets (`field_library.json` + `layout_manifests.json`).
///
/// The [CanonicalFormTransformer] converts the canonical format to the legacy
/// `formInput` JSON string that [FormSchemaParser] expects, keeping the parser
/// and all downstream consumers unchanged.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'models/form_schema.dart';
import 'parser/form_schema_parser.dart';
import 'transformer/canonical_form_transformer.dart';

class FormDataService {
  FormDataService();

  static const _canonicalLibraryPath = 'assets/forms/field_library.json';
  static const _canonicalManifestsPath = 'assets/forms/layout_manifests.json';
  static const _parser = FormSchemaParser();

  final Map<String, FormSchema> _cache = {};

  CanonicalFormTransformer? _transformer;
  List<Map<String, dynamic>>? _manifests;

  /// Returns the [FormSchema] for [formType] (e.g. 'anc', 'ncd').
  ///
  /// [formType] is matched case-insensitively. Returns null if no match found.
  Future<FormSchema?> schemaForType(String formType) async {
    final key = formType.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];
    return _schemaFromCanonical(formType, key);
  }

  /// Returns schemas for all form types.
  Future<List<FormSchema>> allSchemas() async {
    await _ensureCanonicalLoaded();
    final result = <FormSchema>[];
    for (final manifest in _manifests!) {
      final ft = manifest['formType']?.toString() ?? '';
      final schema = await schemaForType(ft);
      if (schema != null) result.add(schema);
    }
    return result;
  }

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
}
