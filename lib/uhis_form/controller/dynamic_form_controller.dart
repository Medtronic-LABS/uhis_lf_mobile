/// ChangeNotifier controller for the uhis_form SDK.
///
/// Drop-in replacement for [SectionedAssessmentViewModel] — same Provider
/// injection pattern, same [AssessmentDraftDao] contract.
///
/// Composite field values (e.g. bloodPressure → {systolic, diastolic}) are
/// stored internally as nested Maps. [_flattenValues] expands them to a flat
/// `fieldId → value` map before persisting to [AssessmentDraftRow.fieldValues],
/// keeping the SQLite schema and [UnifiedSubmissionOrchestrator] unchanged.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../../core/db/local_assessment_dao.dart';
import '../models/field_kind.dart';
import '../models/field_schema.dart';
import '../models/form_schema.dart';
import 'condition_evaluator.dart';

class DynamicFormController extends ChangeNotifier {
  DynamicFormController({
    required this.formSchema,
    required this.encounterId,
    required this.patientId,
    required AssessmentDraftDao draftDao,
    this.memberId,
    this.formType = '',
    AssessmentDraftRow? restoredDraft,
  })  : _draftDao = draftDao {
    // Restore draft if provided
    if (restoredDraft != null) {
      final saved = jsonDecode(restoredDraft.fieldValues) as Map<String, dynamic>;
      _fieldValues.addAll(saved);
    }
    _recomputeVisibility();
  }

  // ── Public state ────────────────────────────────────────────────────────────

  final FormSchema formSchema;
  final String encounterId;
  final String patientId;
  final String? memberId;
  final String formType;

  Map<String, dynamic> get fieldValues => UnmodifiableMapView(_fieldValues);
  Map<String, bool> get fieldVisible => UnmodifiableMapView(_fieldVisible);
  Map<String, String> get validationErrors => UnmodifiableMapView(_validationErrors);

  bool get isSaving => _isSaving;
  bool get hasError => _errorMessage != null;
  String? get errorMessage => _errorMessage;

  // ── Private state ───────────────────────────────────────────────────────────

  final Map<String, dynamic> _fieldValues = {};
  final Map<String, bool> _fieldVisible = {};
  final Map<String, dynamic> _aiHints = {};
  final Set<String> _touchedByUser = {};
  Map<String, String> _validationErrors = {};

  bool _isSaving = false;
  String? _errorMessage;

  final AssessmentDraftDao _draftDao;

  // ── Field value API ─────────────────────────────────────────────────────────

  void setValue(String fieldId, dynamic value) {
    if (value == null) {
      _fieldValues.remove(fieldId);
    } else {
      _fieldValues[fieldId] = value;
    }
    _recomputeVisibility();
    notifyListeners();
  }

  bool isVisible(String fieldId) => _fieldVisible[fieldId] ?? true;

  // ── Validation ──────────────────────────────────────────────────────────────

  /// Returns a map of fieldId → error message for all visible required fields
  /// that are empty or unset. Stores the result and triggers a rebuild.
  Map<String, String> validate() {
    final errors = <String, String>{};
    for (final field in formSchema.allFields) {
      if (!field.required) continue;
      if (!isVisible(field.fieldId)) continue;
      final v = _fieldValues[field.fieldId];
      final isEmpty = v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is Map && v.isEmpty) ||
          (v is List && v.isEmpty);
      if (isEmpty) {
        errors[field.fieldId] = '${field.label} is required';
      }
    }
    _validationErrors = errors;
    notifyListeners();
    return errors;
  }

  // ── AI Scribe integration ───────────────────────────────────────────────────

  void applyPrefill(Map<String, dynamic> prefillValues) {
    for (final entry in prefillValues.entries) {
      // Only apply if user hasn't manually touched this field
      if (!_touchedByUser.contains(entry.key)) {
        _fieldValues[entry.key] = entry.value;
        _aiHints[entry.key] = entry.value;
      }
    }
    _recomputeVisibility();
    notifyListeners();
  }

  void markTouched(String fieldId) {
    _touchedByUser.add(fieldId);
    _aiHints.remove(fieldId);
    notifyListeners();
  }

  dynamic getAiHint(String fieldId) => _aiHints[fieldId];

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> saveDraft() async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final flat = _flattenValues();
      final draft = AssessmentDraftRow(
        encounterId: encounterId,
        patientId: patientId,
        memberId: memberId,
        activatedProgrammes: jsonEncode([formType]),
        fieldValues: jsonEncode(flat),
        sectionStatus: jsonEncode(_buildSectionStatus()),
      );
      await _draftDao.saveDraft(draft);
    } on DatabaseException catch (e) {
      _errorMessage = 'Failed to save draft: ${e.toString()}';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> submit(VoidCallback onSuccess) async {
    await saveDraft();
    if (_errorMessage == null) {
      onSuccess();
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  void _recomputeVisibility() {
    final updated = ConditionEvaluator.evaluate(formSchema, _fieldValues);
    _fieldVisible
      ..clear()
      ..addAll(updated);
  }

  /// Expands composite field values into constituent flat key-value pairs.
  ///
  /// e.g. {'bloodPressure': {'systolic': 120, 'diastolic': 80}}
  ///   → {'systolic': 120, 'diastolic': 80}
  Map<String, dynamic> _flattenValues() {
    final flat = <String, dynamic>{};
    for (final field in formSchema.allFields) {
      final value = _fieldValues[field.fieldId];
      if (value == null) continue;

      if (_isComposite(field.kind) && value is Map<String, dynamic>) {
        flat.addAll(value);
      } else {
        flat[field.fieldId] = value;
      }
    }
    // Also include any raw values not in the schema (e.g. AI-prefilled)
    for (final entry in _fieldValues.entries) {
      if (!flat.containsKey(entry.key)) {
        flat[entry.key] = entry.value;
      }
    }
    return flat;
  }

  Map<String, String> _buildSectionStatus() {
    return {
      for (final section in formSchema.sections)
        section.sectionId: _sectionComplete(section) ? 'done' : 'pending',
    };
  }

  bool _sectionComplete(dynamic section) {
    for (final field in (section as dynamic).fields as List<FieldSchema>) {
      if (field.required && isVisible(field.fieldId)) {
        final v = _fieldValues[field.fieldId];
        if (v == null || v.toString().isEmpty) return false;
      }
    }
    return true;
  }

  static bool _isComposite(FieldKind kind) {
    const composites = {
      FieldKind.bloodPressure,
      FieldKind.anthropometry,
      FieldKind.bloodGlucose,
      FieldKind.vitalsBundle,
      FieldKind.supplyPair,
      FieldKind.obstetricHistory,
      FieldKind.urineTest,
      FieldKind.glassPrescription,
      FieldKind.pregnancyProfile,
    };
    return composites.contains(kind);
  }
}
