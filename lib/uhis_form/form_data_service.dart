/// Loads and caches parsed [FormSchema] objects from the bundled asset
/// `assets/forms/program_forms.json`.
///
/// In a future release this will switch to fetching the JSON from the API
/// endpoint `/spice-service/static-data/form-data` using the workflow IDs
/// returned by [UserHierarchyService]. The interface stays the same — callers
/// receive a [FormSchema] regardless of the source.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'models/form_schema.dart';
import 'parser/form_schema_parser.dart';

class FormDataService {
  FormDataService();

  static const _assetPath = 'assets/forms/program_forms.json';
  static const _parser = FormSchemaParser();

  final Map<String, FormSchema> _cache = {};
  List<Map<String, dynamic>>? _rawForms;

  /// Returns the [FormSchema] for [formType] (e.g. 'anc', 'ncd').
  ///
  /// [formType] is matched case-insensitively against the `formType` field
  /// in program_forms.json. Returns null if no match is found.
  Future<FormSchema?> schemaForType(String formType) async {
    final key = formType.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];

    await _ensureLoaded();

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

  /// Returns schemas for all form types in the asset file.
  Future<List<FormSchema>> allSchemas() async {
    await _ensureLoaded();
    final result = <FormSchema>[];
    for (final entry in _rawForms!) {
      final rawType = entry['formType']?.toString() ?? '';
      final schema = await schemaForType(rawType);
      if (schema != null) result.add(schema);
    }
    return result;
  }

  Future<void> _ensureLoaded() async {
    if (_rawForms != null) return;
    final jsonString = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final entity = decoded['entity'] as Map<String, dynamic>? ?? decoded;
    _rawForms =
        (entity['formData'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
  }
}
