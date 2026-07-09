import 'dart:convert';

import 'package:flutter/services.dart';

/// Exception thrown when a form config asset cannot be parsed.
class FormConfigException implements Exception {
  const FormConfigException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'FormConfigException: $message (cause: $cause)'
      : 'FormConfigException: $message';
}

enum WidgetHint {
  radioGroup,
  dialogCheckbox,
  spinner,
  bloodGlucose,
  bloodGlucoseEntry,
  pregnancyProfile,
  numeric,
  dateField,
  bpField,
  ageYmd,
  infoLabel,
  textLabel,
  unknown;

  static WidgetHint fromString(String? raw) {
    switch (raw) {
      case 'RadioGroup':
        return WidgetHint.radioGroup;
      // SingleSelectionView is a Yes/No radio group in the Android SPICE app.
      case 'SingleSelectionView':
        return WidgetHint.radioGroup;
      case 'DialogCheckbox':
        return WidgetHint.dialogCheckbox;
      case 'Spinner':
        return WidgetHint.spinner;
      case 'bloodGlucose':
        return WidgetHint.bloodGlucose;
      case 'BloodGlucoseEntry':
        return WidgetHint.bloodGlucoseEntry;
      case 'pregnancyProfile':
        return WidgetHint.pregnancyProfile;
      case 'DateField':
      case 'DatePicker':
        return WidgetHint.dateField;
      // "BP" is the hint used in field_library.json (Android export).
      case 'BP':
      case 'BpField':
        return WidgetHint.bpField;
      case 'AgeYmd':
        return WidgetHint.ageYmd;
      case 'InfoLabel':
      case 'InformationLabel':
        return WidgetHint.infoLabel;
      case 'TextLabel':
      case 'Instruction':
        return WidgetHint.textLabel;
      // EditText is a generic text/numeric input; inputType governs decimals.
      case 'EditText':
        return WidgetHint.numeric;
      default:
        return WidgetHint.unknown;
    }
  }
}

class FieldOption {
  const FieldOption({required this.id, required this.name});

  final String id;
  final String name;

  factory FieldOption.fromJson(Map<String, dynamic> json) => FieldOption(
        // id can be bool (true/false) or int in some exports — coerce to string
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class FieldDef {
  const FieldDef({
    required this.id,
    required this.label,
    required this.widgetHint,
    required this.isMandatory,
    required this.options,
    required this.programmeIds,
    this.unitMeasurement,
    this.hintText,
    this.labelCulture,
    this.family,
  });

  final String id;
  final String label;
  final WidgetHint widgetHint;
  final bool isMandatory;
  final List<FieldOption> options;

  /// Programme IDs from `"programmes[].id"` (e.g. `["anc", "ncd"]`).
  final List<String> programmeIds;

  /// Optional unit label shown as `suffixText` on numeric fields (e.g. `"mmol/L"`, `"kg"`).
  final String? unitMeasurement;

  /// Optional placeholder text for text input fields.
  final String? hintText;

  /// Localized (Bengali) field label from `"titleCulture"`, rendered as the
  /// second line of the field card's title so the SK sees both languages.
  final String? labelCulture;

  /// Field family/group from `"family"` (e.g. `"maternalHealthAssessment"`),
  /// used to pick a fallback glyph when the field id is not explicitly mapped.
  final String? family;

  factory FieldDef.fromJson(String id, Map<String, dynamic> json) {
    final rawHint = json['widgetHint'] as String?;
    final optionsList = (json['optionsList'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(FieldOption.fromJson)
        .toList();
    final programmeIds = (json['programmes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((p) => p['id'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    return FieldDef(
      id: id,
      label: json['label'] as String? ?? id,
      widgetHint: WidgetHint.fromString(rawHint),
      isMandatory: json['isMandatory'] as bool? ?? false,
      options: optionsList,
      programmeIds: programmeIds,
      unitMeasurement: json['unitMeasurement'] as String?,
      hintText: json['hint'] as String?,
      labelCulture: json['titleCulture'] as String?,
      family: json['family'] as String?,
    );
  }
}

class FieldRef {
  const FieldRef({
    required this.id,
    required this.isMandatory,
    required this.inputType,
  });

  final String id;
  final bool isMandatory;

  /// inputType codes: 0=text, 2=numberDecimal, 3=number, 8192=date.
  final int inputType;

  factory FieldRef.fromJson(Map<String, dynamic> json) => FieldRef(
        id: json['id'] as String? ?? '',
        isMandatory: json['isMandatory'] as bool? ?? false,
        // inputType may be double (e.g. 8192.0) in some JSON tooling exports
        inputType: (json['inputType'] as num?)?.toInt() ?? 0,
      );
}

class FormSection {
  const FormSection({
    required this.sectionId,
    required this.title,
    required this.formType,
    required this.fieldRefs,
  });

  final String sectionId;
  final String title;
  final String formType;
  final List<FieldRef> fieldRefs;

  factory FormSection.fromJson(String formType, Map<String, dynamic> json) {
    final rawRefs = json['fieldRefs'] as List<dynamic>? ?? [];
    final refs = <FieldRef>[];
    for (final r in rawRefs) {
      if (r is Map<String, dynamic>) {
        final ref = FieldRef.fromJson(r);
        if (ref.id.isNotEmpty) refs.add(ref);
      } else if (r is String && r.isNotEmpty) {
        // Bare-string shorthand: id only, no override metadata.
        refs.add(FieldRef(id: r, isMandatory: false, inputType: 0));
      }
    }
    return FormSection(
      sectionId: json['sectionId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      formType: formType,
      fieldRefs: refs,
    );
  }
}

/// Typed representation of all three `assets/forms/*.json` config files.
///
/// Load once via [FormConfig.load] and cache; it is immutable after load.
class FormConfig {
  const FormConfig({
    required this.fields,
    required this.forms,
  });

  /// fieldId → [FieldDef] (from `field_library.json`).
  final Map<String, FieldDef> fields;

  /// formType → ordered [FormSection] list (from `layout_manifests.json`).
  final Map<String, List<FormSection>> forms;

  /// Loads and parses all three form config assets.
  ///
  /// Throws [FormConfigException] on malformed JSON or missing required keys.
  static Future<FormConfig> load(AssetBundle bundle) async {
    try {
      final fieldLibraryJson = await bundle.loadString('assets/forms/field_library.json');
      final layoutManifestsJson = await bundle.loadString('assets/forms/layout_manifests.json');
      // program_forms.json loaded but not parsed into typed structures here;
      // programme gating is handled at the UI layer via activated formTypes.
      // Kept as a load check so missing asset surfaces early.
      await bundle.loadString('assets/forms/program_forms.json');

      final fieldLibraryRaw = jsonDecode(fieldLibraryJson);
      if (fieldLibraryRaw is! Map<String, dynamic>) {
        throw const FormConfigException('field_library.json must be a JSON object');
      }

      final fields = <String, FieldDef>{};
      for (final entry in fieldLibraryRaw.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          fields[entry.key] = FieldDef.fromJson(entry.key, value);
        }
      }

      final layoutManifestsRaw = jsonDecode(layoutManifestsJson);
      if (layoutManifestsRaw is! List) {
        throw const FormConfigException('layout_manifests.json must be a JSON array');
      }

      final forms = <String, List<FormSection>>{};
      for (final item in layoutManifestsRaw) {
        if (item is! Map<String, dynamic>) continue;
        final formType = item['formType'] as String? ?? '';
        if (formType.isEmpty) continue;
        final sectionsRaw = item['sections'] as List<dynamic>? ?? [];
        final sections = sectionsRaw
            .whereType<Map<String, dynamic>>()
            .map((s) => FormSection.fromJson(formType, s))
            .where((s) => s.sectionId.isNotEmpty)
            .toList();
        forms[formType] = sections;
      }

      return FormConfig(fields: fields, forms: forms);
    } on FormConfigException {
      rethrow;
    } on FormatException catch (e) {
      throw FormConfigException('JSON parse error in form config assets', cause: e);
    } catch (e) {
      throw FormConfigException('Failed to load form config assets', cause: e);
    }
  }

  /// Singleton cache — call [load] once at startup, then use [instance].
  static FormConfig? _instance;

  static FormConfig get instance {
    assert(_instance != null,
        'FormConfig.instance accessed before FormConfig.load() completed');
    return _instance!;
  }

  static Future<FormConfig> loadAndCache(AssetBundle bundle) async {
    _instance ??= await load(bundle);
    return _instance!;
  }
}
