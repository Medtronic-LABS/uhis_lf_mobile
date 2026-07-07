/// Converts a raw `formInput` JSON string (from program_forms.json) into a
/// typed [FormSchema].
///
/// The parser performs three tasks:
///   1. Iterate the flat `formLayout` list, creating [SectionSchema] objects
///      whenever it encounters a `CardView` item.
///   2. Within each section, group logically-related fields into composite
///      [FieldSchema] objects (e.g. height + weight → anthropometry).
///   3. Parse conditions on each field and store them on the SOURCE [FieldSchema]
///      so the [DynamicFormController] can invert them at init time.
///
/// The resolved [FieldKind] drives widget dispatch in [FieldRenderer].
library;

import 'dart:convert';

import '../models/clinical_concept.dart';
import '../models/condition_schema.dart';
import '../models/field_kind.dart';
import '../models/field_schema.dart';
import '../models/form_schema.dart';
import '../models/section_schema.dart';

class FormSchemaParser {
  const FormSchemaParser();

  /// Parse a single formData entry.
  ///
  /// [formType] is the `formType` field from the formData root (e.g. 'anc').
  /// [formInputJson] is the raw `formInput` JSON string.
  FormSchema parse(String formType, String formInputJson) {
    final decoded = jsonDecode(formInputJson) as Map<String, dynamic>;
    final rawLayout = decoded['formLayout'] as List<dynamic>? ?? [];

    final sections = <SectionSchema>[];
    final allFields = <FieldSchema>[];
    final pendingFields = <FieldSchema>[];

    void flushPending(SectionSchema section) {
      section.fields.addAll(pendingFields);
      allFields.addAll(pendingFields);
      pendingFields.clear();
    }

    SectionSchema? currentSection;
    int i = 0;
    while (i < rawLayout.length) {
      final item = rawLayout[i] as Map<String, dynamic>;
      final viewType = item['viewType'] as String? ?? '';

      if (viewType == 'CardView') {
        if (currentSection != null) {
          flushPending(currentSection);
        }
        currentSection = SectionSchema(
          sectionId: item['id'] as String? ?? 'section_$i',
          title: item['title'] as String? ?? '',
          fields: [],
        );
        sections.add(currentSection);
        i++;
        continue;
      }

      // Ensure we have a section even if the form has no leading CardView.
      currentSection ??= () {
        final s = SectionSchema(
            sectionId: 'default', title: formType, fields: []);
        sections.add(s);
        return s;
      }();

      final (field, consumed) = _parseItem(rawLayout, i, formType);
      if (field != null && field.kind != FieldKind.sectionHeader) {
        pendingFields.add(field);
      }
      i += consumed;
    }

    if (currentSection != null) {
      flushPending(currentSection);
    }

    return FormSchema(
      formType: formType,
      sections: sections,
      allFields: allFields,
    );
  }

  // ── Item parser ────────────────────────────────────────────────────────────

  /// Returns (FieldSchema?, items_consumed).
  ///
  /// May consume more than one layout item for composite fields.
  (FieldSchema?, int) _parseItem(
      List<dynamic> layout, int i, String formType) {
    final item = layout[i] as Map<String, dynamic>;
    final viewType = item['viewType'] as String? ?? '';

    // ── Standalone typed viewTypes ──────────────────────────────────────────
    switch (viewType) {
      case 'pregnancyProfile':
        return (_buildField(item, FieldKind.pregnancyProfile), 1);
      case 'BP':
        return (_buildField(item, FieldKind.bloodPressure), 1);
      case 'AgeOrDob':
        return (_buildField(item, FieldKind.ageOrDob), 1);
      case 'AgeYMD':
        return (_buildField(item, FieldKind.ageYmd), 1);
      case 'InformationLabel':
        return (_buildField(item, FieldKind.computedLabel), 1);
      case 'Instruction':
        return (_buildField(item, FieldKind.instruction), 1);
      case 'QRView':
        return (_buildField(item, FieldKind.qrScanner), 1);
      case 'CheckBox':
        return (_buildField(item, FieldKind.toggleSwitch), 1);
      case 'DatePicker':
        return (_buildField(item, FieldKind.datePicker), 1);
      case 'RadioGroup':
        return (_buildField(item, FieldKind.radioGroup), 1);
      case 'DialogCheckbox':
      case 'MultiSelectSpinner':
        return (_buildCompositeOrDangerSigns(item), 1);
      case 'TextLabel':
        return (_buildField(item, FieldKind.sectionHeader), 1);
    }

    // ── Selection views — radio vs dropdown based on option count ───────────
    if (viewType == 'SingleSelectionView' || viewType == 'Spinner') {
      final opts = _parseOptions(item);
      final kind = opts.length <= 4 ? FieldKind.radioGroup : FieldKind.dropdown;
      return (_buildField(item, kind, options: opts), 1);
    }

    // ── EditText — look-ahead composite detection ───────────────────────────
    if (viewType == 'EditText') {
      return _parseEditText(layout, i);
    }

    // Unknown viewType — treat as text input
    return (_buildField(item, FieldKind.textInput), 1);
  }

  // ── EditText composite detection ───────────────────────────────────────────

  static const _vitalFieldIds = {
    'temperature', 'pulse', 'breathsPerMinute',
    'spo2', 'SpO2', 'respiratoryRate',
  };
  static const _heightFieldIds = {'height', 'heightInFeet', 'patientHeight'};
  static const _weightFieldIds = {'weight', 'patientWeight', 'ancWeight'};
  static const _supplyConsumedSuffixes = ['Consumed', 'consumed', 'LastMonth'];
  static const _supplyProvidedSuffixes = ['Provided', 'provided', 'Today'];

  (FieldSchema?, int) _parseEditText(List<dynamic> layout, int i) {
    final item = layout[i] as Map<String, dynamic>;
    final fieldId = _fieldId(item);

    // ── compositeGroup path (canonical JSON) ─────────────────────────────
    // When the item carries an explicit compositeGroup, use it to build the
    // composite instead of relying on heuristic look-ahead.
    final compositeGroup = item['compositeGroup'] as String?;
    final compositeRole = item['compositeRole'] as String?;
    if (compositeGroup != null && compositeRole == 'trigger') {
      final (schema, consumed) =
          _buildCompositeFromGroup(layout, i, compositeGroup);
      if (schema != null) return (schema, consumed);
    }

    // ── Heuristic look-ahead (fallback for items without compositeGroup) ──

    // Vitals bundle: temperature is the trigger, look ahead for pulse+RR+SpO2
    if (_vitalFieldIds.contains(fieldId)) {
      final vitalItems = _collectVitals(layout, i);
      if (vitalItems.length >= 2) {
        return (_buildVitalsBundle(vitalItems), vitalItems.length);
      }
    }

    // Anthropometry: height triggers weight look-ahead
    if (_heightFieldIds.contains(fieldId)) {
      final next = _peekNext(layout, i);
      if (next != null && _weightFieldIds.contains(_fieldId(next))) {
        return (_buildAnthropometry(item, next), 2);
      }
    }

    // Supply pair: consumed prefix triggers provided look-ahead
    if (_supplyConsumedSuffixes.any((s) => fieldId.contains(s))) {
      final next = _peekNext(layout, i);
      if (next != null &&
          _supplyProvidedSuffixes.any((s) => _fieldId(next).contains(s))) {
        return (_buildSupplyPair(item, next), 2);
      }
    }

    // Obstetric history: gravida triggers parity + livingChildren
    if (fieldId == 'gravida') {
      final obs = _collectObstetric(layout, i);
      if (obs.length >= 2) {
        return (_buildObstetricHistory(obs), obs.length);
      }
    }

    // Fall through — plain number or text input
    final inputType = (item['inputType'] as num?)?.toInt() ?? 96;
    final kind = _editTextKind(inputType);
    return (_buildField(item, kind), 1);
  }

  /// Build a composite FieldSchema by collecting all consecutive items that
  /// share [compositeGroup] starting from [start] (the trigger item).
  ///
  /// Returns (null, 1) if no members are found so callers fall through to
  /// heuristic detection.
  (FieldSchema?, int) _buildCompositeFromGroup(
      List<dynamic> layout, int start, String compositeGroup) {
    // Collect trigger + all adjacent members with the same compositeGroup
    final members = <Map<String, dynamic>>[];
    for (int j = start; j < layout.length; j++) {
      final it = layout[j] as Map<String, dynamic>;
      if (it['viewType'] == 'CardView') break;
      final grp = it['compositeGroup'] as String?;
      if (grp != compositeGroup) break;
      members.add(it);
    }

    if (members.length < 2) return (null, 1);

    // Dispatch to the appropriate composite builder based on group name.
    switch (compositeGroup) {
      case 'vitalsBundle':
        return (_buildVitalsBundle(members), members.length);
      case 'anthropometry':
        return (_buildAnthropometry(members.first, members[1]), members.length);
      case 'obstetricHistory':
        return (_buildObstetricHistory(members), members.length);
      default:
        // Supply pair or any custom group — treat as supply pair if 2 items
        if (members.length == 2) {
          return (_buildSupplyPair(members[0], members[1]), 2);
        }
        return (null, 1);
    }
  }

  // ── Composite builders ─────────────────────────────────────────────────────

  FieldSchema _buildVitalsBundle(List<Map<String, dynamic>> items) {
    return FieldSchema(
      fieldId: 'vitalsBundle',
      label: 'Vitals',
      kind: FieldKind.vitalsBundle,
      subFieldIds: items.map(_fieldId).toList(),
      conditions: items.expand((it) => _parseConditions(it)).toList(),
    );
  }

  FieldSchema _buildAnthropometry(
      Map<String, dynamic> heightItem, Map<String, dynamic> weightItem) {
    return FieldSchema(
      fieldId: 'anthropometry',
      label: 'Anthropometry',
      kind: FieldKind.anthropometry,
      subFieldIds: [_fieldId(heightItem), _fieldId(weightItem)],
      conditions: [
        ..._parseConditions(heightItem),
        ..._parseConditions(weightItem),
      ],
    );
  }

  FieldSchema _buildSupplyPair(
      Map<String, dynamic> consumedItem, Map<String, dynamic> providedItem) {
    final label = _labelFromFieldId(_fieldId(consumedItem));
    return FieldSchema(
      fieldId: '${_fieldId(consumedItem)}_pair',
      label: label,
      kind: FieldKind.supplyPair,
      subFieldIds: [_fieldId(consumedItem), _fieldId(providedItem)],
      conditions: [
        ..._parseConditions(consumedItem),
        ..._parseConditions(providedItem),
      ],
    );
  }

  FieldSchema _buildObstetricHistory(List<Map<String, dynamic>> items) {
    return FieldSchema(
      fieldId: 'obstetricHistory',
      label: 'Obstetric History',
      kind: FieldKind.obstetricHistory,
      subFieldIds: items.map(_fieldId).toList(),
      conditions: items.expand((it) => _parseConditions(it)).toList(),
    );
  }

  FieldSchema _buildCompositeOrDangerSigns(Map<String, dynamic> item) {
    // compositeGroup path: explicit kind hint overrides heuristic
    final compositeGroup = item['compositeGroup'] as String?;
    if (compositeGroup != null) {
      // Only a group name is provided here — treat as a chip multi-select
      // since the composite builder handles grouping at EditText dispatch.
      return _buildField(item, FieldKind.chipMultiSelect);
    }
    // Heuristic: danger-signs fields typically have titles mentioning danger/signs
    final title = (item['title'] as String? ?? '').toLowerCase();
    if (title.contains('danger') || title.contains('sign')) {
      return _buildField(item, FieldKind.dangerSigns);
    }
    return _buildField(item, FieldKind.chipMultiSelect);
  }

  // ── Look-ahead helpers ─────────────────────────────────────────────────────

  Map<String, dynamic>? _peekNext(List<dynamic> layout, int i) {
    if (i + 1 >= layout.length) return null;
    final next = layout[i + 1] as Map<String, dynamic>;
    if (next['viewType'] == 'CardView') return null;
    return next;
  }

  List<Map<String, dynamic>> _collectVitals(List<dynamic> layout, int start) {
    final result = <Map<String, dynamic>>[];
    for (int j = start;
        j < layout.length && j < start + 6;
        j++) {
      final item = layout[j] as Map<String, dynamic>;
      if (item['viewType'] == 'CardView') break;
      if (item['viewType'] != 'EditText') break;
      final id = _fieldId(item);
      if (_vitalFieldIds.contains(id)) {
        result.add(item);
      } else {
        break;
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _collectObstetric(
      List<dynamic> layout, int start) {
    const obsIds = {'gravida', 'parity', 'livingChildren', 'ageOfLastChild'};
    final result = <Map<String, dynamic>>[];
    for (int j = start;
        j < layout.length && j < start + 4;
        j++) {
      final item = layout[j] as Map<String, dynamic>;
      if (item['viewType'] == 'CardView') break;
      final id = _fieldId(item);
      if (obsIds.contains(id)) {
        result.add(item);
      } else {
        break;
      }
    }
    return result;
  }

  // ── Field builders ─────────────────────────────────────────────────────────

  FieldSchema _buildField(
    Map<String, dynamic> item,
    FieldKind kind, {
    List<FieldOption>? options,
  }) {
    return FieldSchema(
      fieldId: _fieldId(item),
      label: item['title'] as String? ?? '',
      kind: kind,
      required: item['isMandatory'] == true,
      unit: item['unitMeasurement'] as String?,
      min: _toDouble(item['minVal']),
      max: _toDouble(item['maxVal']),
      hint: item['hint'] as String?,
      options: options ?? _parseOptions(item),
      conditions: _parseConditions(item),
      clinicalConcept: _parseClinicalConcept(item),
      programmes: _parseProgrammes(item),
    );
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static String _fieldId(Map<String, dynamic> item) =>
      item['id'] as String? ??
      item['fieldName'] as String? ??
      'unknown';

  static List<ClinicalConcept> _parseClinicalConcept(
      Map<String, dynamic> item) {
    final raw = item['clinicalConcept'];
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(ClinicalConcept.fromJson)
          .toList();
    }
    return const [];
  }

  static List<String> _parseProgrammes(Map<String, dynamic> item) {
    final raw = item['programs'];
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const [];
  }

  static FieldKind _editTextKind(int inputType) {
    switch (inputType) {
      case 2:
      case 3:
        return FieldKind.integerInput;
      case 8192:
        return FieldKind.decimalInput;
      default:
        return FieldKind.textInput;
    }
  }

  static List<FieldOption> _parseOptions(Map<String, dynamic> item) {
    final raw = item['optionsList'] ?? item['options'];
    if (raw == null) return [];
    final list = raw as List<dynamic>;
    return list.map((o) {
      if (o is Map<String, dynamic>) {
        final id = o['id'];
        final name = o['name'] as String? ?? id.toString();
        return FieldOption(label: name, value: id.toString());
      }
      return FieldOption.fromString(o.toString());
    }).toList();
  }

  static List<ConditionSchema> _parseConditions(Map<String, dynamic> item) {
    final raw = item['condition'];
    if (raw == null) return [];
    final list = raw as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .where((c) => c.containsKey('targetId'))
        .map(ConditionSchema.fromJson)
        .toList();
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static String _labelFromFieldId(String fieldId) {
    // 'ifaTabletsConsumed' → 'IFA Tablets'
    if (fieldId.toLowerCase().contains('ifa')) return 'IFA Tablets';
    if (fieldId.toLowerCase().contains('folic')) return 'Folic Acid Tablets';
    if (fieldId.toLowerCase().contains('calcium')) return 'Calcium Tablets';
    return fieldId;
  }
}
