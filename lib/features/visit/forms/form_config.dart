import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/i18n/app_locale.dart';

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
  const FieldOption({
    required this.id,
    required this.name,
    this.cultureValue,
  });

  final String id;

  /// English option label from `"name"`.
  final String name;

  /// Bengali option label from `"cultureValue"`.
  final String? cultureValue;

  /// Locale-pure label for UI: Bangla when available in Bangla mode, else English.
  String get displayName {
    if (AppLocale.isBangla &&
        cultureValue != null &&
        cultureValue!.trim().isNotEmpty) {
      return cultureValue!;
    }
    return name;
  }

  factory FieldOption.fromJson(Map<String, dynamic> json) => FieldOption(
        // id can be bool (true/false) or int in some exports — coerce to string
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        cultureValue: json['cultureValue']?.toString(),
      );
}

/// A single `condition` entry declared on a *driver* field in
/// `field_library.json` — e.g. `pncNeonateSigns`'s `condition` array contains
/// `{eq: "Other", targetId: "otherPncNeonateSigns", visibility: "visible"}`,
/// meaning "when the driver field's value equals `eq`, set the target
/// field's (`targetId`) visibility to `visibility`". Some conditions use
/// `eqList` instead of `eq` — matches if the driver's value is any of
/// several values (e.g. `{eqList: ["nid", "brn"], ...}`) — or
/// `greaterThanOrEqual` for a numeric driver (e.g. `{greaterThanOrEqual: 1,
/// targetId: "typeOfAbortion", ...}`). Exactly one of [eq]/[eqList]/
/// [greaterThanOrEqual] is set per the source JSON.
class FieldCondition {
  const FieldCondition({
    required this.targetId,
    required this.visibility,
    this.eq,
    this.eqList = const [],
    this.greaterThanOrEqual,
  });

  final String targetId;
  final String visibility;

  /// Single acceptable trigger value, or null when this condition uses
  /// [eqList] or [greaterThanOrEqual] instead.
  final String? eq;

  /// Multiple acceptable trigger values (from the JSON's `eqList` array).
  /// Empty when this condition uses [eq]/[greaterThanOrEqual] instead.
  final List<String> eqList;

  /// Numeric threshold — matches when the driver's value, parsed as a
  /// number, is `>=` this. Null when this condition uses [eq]/[eqList].
  final num? greaterThanOrEqual;

  /// True when the driver's current value matches this condition's trigger.
  bool matches(String? driverValue) {
    if (driverValue == null) return false;
    if (greaterThanOrEqual != null) {
      final n = num.tryParse(driverValue);
      return n != null && n >= greaterThanOrEqual!;
    }
    if (eq != null) return driverValue == eq;
    return eqList.contains(driverValue);
  }

  factory FieldCondition.fromJson(Map<String, dynamic> json) {
    final rawEqList = json['eqList'] as List<dynamic>?;
    final rawGte = json['greaterThanOrEqual'] as num?;
    return FieldCondition(
      targetId: json['targetId'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'gone',
      eq: (rawEqList == null && rawGte == null) ? json['eq']?.toString() : null,
      eqList: rawEqList?.map((e) => e.toString()).toList() ?? const [],
      greaterThanOrEqual: rawGte,
    );
  }
}

/// A [FieldCondition] inverted and indexed by the *target* field id, with the
/// driver field id attached — built once in [FormConfig.load] so evaluating a
/// target field's visibility doesn't require scanning every other field.
class FieldVisibilityRule {
  const FieldVisibilityRule({
    required this.driverId,
    required this.visibility,
    this.eq,
    this.eqList = const [],
    this.greaterThanOrEqual,
  });

  final String driverId;
  final String visibility;
  final String? eq;
  final List<String> eqList;
  final num? greaterThanOrEqual;

  /// True when the driver's current value matches this rule's trigger.
  bool matches(String? driverValue) {
    if (driverValue == null) return false;
    if (greaterThanOrEqual != null) {
      final n = num.tryParse(driverValue);
      return n != null && n >= greaterThanOrEqual!;
    }
    if (eq != null) return driverValue == eq;
    return eqList.contains(driverValue);
  }
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
    this.visibility = 'visible',
    this.conditions = const [],
    this.compositeGroup,
    this.compositeRole,
    this.infoTitle,
    this.isInfoVisible = false,
    this.isSummary = false,
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

  /// Bengali field label from `"titleCulture"`. Prefer [displayLabel] in UI.
  final String? labelCulture;

  /// Locale-pure field label: Bangla when available in Bangla mode, else English.
  String get displayLabel {
    if (AppLocale.isBangla &&
        labelCulture != null &&
        labelCulture!.trim().isNotEmpty) {
      return labelCulture!;
    }
    return label;
  }

  /// Field family/group from `"family"` (e.g. `"maternalHealthAssessment"`),
  /// used to pick a fallback glyph when the field id is not explicitly mapped.
  final String? family;

  /// Raw `"visibility"` string from the field library — `"visible"` or
  /// `"gone"`. This is the field's *base* state, used when no
  /// [FieldVisibilityRule] targeting it matches (see `FieldVisibilityRules`
  /// in `unified_section_rules.dart`).
  final String visibility;

  /// `condition` entries declared on THIS field as the driver — i.e. rules
  /// this field's value applies to OTHER fields, not to itself.
  final List<FieldCondition> conditions;

  /// `compositeGroup`/`compositeRole` from the field library — used for the
  /// obstetric-history progressive-disclosure chain (Gravida → Parity →
  /// Living Children → Age of Last Child). Only that one group is currently
  /// interpreted for visibility; other composite groups (e.g. supplement
  /// consumed/provided pairs) are unrelated dedup metadata handled elsewhere.
  final String? compositeGroup;
  final String? compositeRole;

  /// Short clinical help/guidance text (e.g. "0 = if BP could not be
  /// measured") shown under the field when [isInfoVisible] is true.
  final String? infoTitle;
  final bool isInfoVisible;

  /// Android `isSummary`.
  ///
  /// On RMNCH / pregnancy-outcome fill forms, fields with this flag are
  /// summary-only (hidden while filling). On NCD/TB/etc., the flag means
  /// "also include on the summary screen" — the field still renders on fill.
  final bool isSummary;

  factory FieldDef.fromJson(String id, Map<String, dynamic> json) {
    final rawHint = json['widgetHint'] as String?;
    final optionsList = ((json['optionsList'] ?? json['options']) as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(FieldOption.fromJson)
        .toList();
    final programmeIds = (json['programmes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((p) => p['id'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    final conditions = (json['condition'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(FieldCondition.fromJson)
        .where((c) => c.targetId.isNotEmpty)
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
      visibility: json['visibility'] as String? ?? 'visible',
      conditions: conditions,
      compositeGroup: json['compositeGroup'] as String?,
      compositeRole: json['compositeRole'] as String?,
      infoTitle: json['infoTitle'] as String?,
      isInfoVisible: json['isInfo'] == 'visible',
      isSummary: json['isSummary'] as bool? ?? false,
    );
  }
}

class FieldRef {
  const FieldRef({
    required this.id,
    required this.isMandatory,
    required this.inputType,
    this.fieldName,
  });

  final String id;
  final bool isMandatory;

  /// inputType codes: 0=text, 2=numberDecimal, 3=number, 8192=date.
  final int inputType;

  /// Optional layout override label from `layout_manifests.json` `fieldName`.
  /// Prefer this in the UI when present so section-specific copy (e.g. BP vs
  /// diabetes medication) wins over the shared field_library label.
  final String? fieldName;

  factory FieldRef.fromJson(Map<String, dynamic> json) {
    final rawName = (json['fieldName'] as String?)?.trim();
    return FieldRef(
      id: json['id'] as String? ?? '',
      isMandatory: json['isMandatory'] as bool? ?? false,
      // inputType may be double (e.g. 8192.0) in some JSON tooling exports
      inputType: (json['inputType'] as num?)?.toInt() ?? 0,
      fieldName: (rawName == null || rawName.isEmpty) ? null : rawName,
    );
  }
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
    this.visibilityRulesByTargetId = const {},
  });

  /// fieldId → [FieldDef] (from `field_library.json`).
  final Map<String, FieldDef> fields;

  /// formType → ordered [FormSection] list (from `layout_manifests.json`).
  final Map<String, List<FormSection>> forms;

  /// Target fieldId → the [FieldVisibilityRule]s that control it, built once
  /// from every field's `condition` array (see [FieldCondition]). A separate,
  /// pure step from parsing so it's independently testable — see
  /// `buildVisibilityRules`.
  final Map<String, List<FieldVisibilityRule>> visibilityRulesByTargetId;

  /// Inverts every field's `condition` array (keyed by the *driver* field)
  /// into a lookup keyed by the *target* field id, so evaluating a field's
  /// visibility is an O(1) map lookup instead of a scan over every field.
  static Map<String, List<FieldVisibilityRule>> buildVisibilityRules(
      Map<String, FieldDef> fields) {
    final rules = <String, List<FieldVisibilityRule>>{};
    for (final field in fields.values) {
      for (final condition in field.conditions) {
        rules.putIfAbsent(condition.targetId, () => []).add(
              FieldVisibilityRule(
                driverId: field.id,
                eq: condition.eq,
                eqList: condition.eqList,
                greaterThanOrEqual: condition.greaterThanOrEqual,
                visibility: condition.visibility,
              ),
            );
      }
    }
    return rules;
  }

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

      return FormConfig(
        fields: fields,
        forms: forms,
        visibilityRulesByTargetId: buildVisibilityRules(fields),
      );
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
