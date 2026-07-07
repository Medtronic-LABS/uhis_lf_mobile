/// Converts canonical field library + layout manifest entries into the legacy
/// `formInput` JSON string expected by [FormSchemaParser].
///
/// This is the Phase 1 insertion point described in form_sdk_transformer_plan.md.
/// The parser, widgets, and all downstream consumers are unchanged — they still
/// receive the same formInput string shape they have always expected.
library;

import 'dart:convert';

class CanonicalFormTransformer {
  /// [fieldLibrary] is the decoded contents of `assets/forms/field_library.json`,
  /// keyed by field `id`.
  const CanonicalFormTransformer(this._fieldLibrary);

  final Map<String, Map<String, dynamic>> _fieldLibrary;

  /// Produces the legacy `formInput` JSON string for [formType].
  ///
  /// [layoutManifest] is one entry from `assets/forms/layout_manifests.json`.
  /// Returns a JSON string of the shape `{ "formLayout": [...] }` which is
  /// fed directly to `FormSchemaParser.parse(formType, formInput)`.
  String toLegacyFormInput({
    required String formType,
    required Map<String, dynamic> layoutManifest,
  }) {
    final sections =
        (layoutManifest['sections'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>();

    final formLayout = <Map<String, dynamic>>[];

    for (final section in sections) {
      final sectionId = section['sectionId'] as String? ?? '';
      final sectionTitle = section['title'] as String? ?? '';
      final fieldRefs = section['fieldRefs'] as List<dynamic>? ?? [];

      formLayout.add({
        'viewType': 'CardView',
        'id': sectionId,
        'title': sectionTitle,
      });

      for (final rawRef in fieldRefs) {
        // fieldRef is either a plain String or a Map with per-layout overrides:
        //   { id, fieldName?, inputType?, isMandatory? }
        final String fieldId;
        final Map<String, dynamic> overrides;
        if (rawRef is Map<String, dynamic>) {
          fieldId = rawRef['id'] as String? ?? '';
          overrides = rawRef;
        } else {
          fieldId = rawRef as String;
          overrides = const {};
        }

        final libEntry = _fieldLibrary[fieldId];
        if (libEntry == null) {
          // ignore: avoid_print
          print(
            '[CanonicalFormTransformer] WARNING: fieldRef "$fieldId" not found '
            'in field library for formType "$formType"',
          );
          continue;
        }
        formLayout.add(_toLegacyItem(libEntry, layoutOverrides: overrides));
      }
    }

    return jsonEncode({'formLayout': formLayout});
  }

  /// Converts one canonical field definition to the legacy formLayout item shape.
  ///
  /// [layoutOverrides] is the fieldRef object from the manifest, which may carry
  /// per-layout overrides for fieldName, inputType, and isMandatory.
  Map<String, dynamic> _toLegacyItem(
    Map<String, dynamic> entry, {
    Map<String, dynamic> layoutOverrides = const {},
  }) {
    final out = <String, dynamic>{};

    // widgetHint → viewType
    out['viewType'] = entry['widgetHint'] ?? 'EditText';

    // id: always present
    out['id'] = entry['id'];

    // fieldName: use per-layout override if present, else library entry's fieldName
    final effectiveFieldName =
        layoutOverrides['fieldName'] as String? ??
        entry['fieldName'] as String?;
    if (effectiveFieldName != null) {
      out['fieldName'] = effectiveFieldName;
    }

    // label → title
    out['title'] = entry['label'] ?? '';

    // clinicalConcept: pass through the full structured array so the parser
    // can populate FieldSchema.clinicalConcept directly.
    // Also emit snomedCode/snomedDisplay for any legacy consumers that
    // still look for those flat keys.
    final cc = entry['clinicalConcept'] as List<dynamic>?;
    if (cc != null) {
      out['clinicalConcept'] = cc;
      final snomed = cc
          .whereType<Map<String, dynamic>>()
          .where((e) => e['system'] == 'SNOMED_CT')
          .firstOrNull;
      if (snomed != null) {
        out['snomedCode'] = snomed['code'];
        out['snomedDisplay'] = snomed['display'];
      }
    }

    // programmes → programs (typed objects → string IDs)
    final programmes = entry['programmes'] as List<dynamic>?;
    if (programmes != null) {
      out['programs'] = programmes
          .whereType<Map<String, dynamic>>()
          .map((p) => p['id'] as String? ?? '')
          .toList();
    }

    // inputType: layout override (raw bitmask) > canonical name → bitmask
    if (layoutOverrides.containsKey('inputType')) {
      out['inputType'] = layoutOverrides['inputType'];
    } else if (entry.containsKey('inputType')) {
      out['inputType'] = _toAndroidInputType(entry['inputType'] as String?);
    }

    // isMandatory: layout override > library value
    if (layoutOverrides.containsKey('isMandatory')) {
      out['isMandatory'] = layoutOverrides['isMandatory'];
    } else if (entry.containsKey('isMandatory')) {
      out['isMandatory'] = entry['isMandatory'];
    }

    // optionsList: flatten per-option clinicalConcept → snomedCode/snomedDisplay
    final options = entry['optionsList'] as List<dynamic>?;
    if (options != null) {
      out['optionsList'] = options.map((o) {
        if (o is Map<String, dynamic>) return _toLegacyOption(o);
        return o;
      }).toList();
    }

    // Pass-through keys: preserved unchanged in the legacy output
    // (isMandatory handled above with override logic)
    const passthroughKeys = {
      'family', 'familyOrder', 'orderId', 'isEnabled',
      'readOnly', 'visibility', 'hint', 'hintCulture', 'titleCulture',
      'errorMessage', 'errorMessageCulture', 'unitMeasurement',
      'minValue', 'maxValue', 'minVal', 'maxVal', 'isSummary', 'titleSummary',
      'localDataCache', 'isBooleanAnswer', 'optionType',
      'isInfo', 'infoTitle', 'isNeededDefault', 'isNotDefault',
      'applyDecimalFilter', 'condition',
      // Composite grouping hints read by FormSchemaParser
      'compositeGroup', 'compositeRole',
    };
    for (final key in passthroughKeys) {
      if (entry.containsKey(key)) {
        out[key] = entry[key];
      }
    }

    return out;
  }

  Map<String, dynamic> _toLegacyOption(Map<String, dynamic> opt) {
    final out = Map<String, dynamic>.from(opt);

    // Flatten clinicalConcept → snomedCode/snomedDisplay, then remove structured array
    final cc = out.remove('clinicalConcept') as List<dynamic>?;
    if (cc != null) {
      final snomed = cc
          .whereType<Map<String, dynamic>>()
          .where((e) => e['system'] == 'SNOMED_CT')
          .firstOrNull;
      if (snomed != null) {
        out['snomedCode'] = snomed['code'];
        out['snomedDisplay'] = snomed['display'];
      }
    }

    return out;
  }

  /// Maps canonical inputType name to the Android InputType bitmask expected
  /// by FormSchemaParser._editTextKind().
  static int _toAndroidInputType(String? name) {
    switch (name) {
      case 'integer':
        return 2;
      case 'decimal':
        return 8192;
      default: // 'text' or null
        return 96;
    }
  }
}
