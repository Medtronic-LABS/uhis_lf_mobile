import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/db/local_assessment_dao.dart';
import '../assessment_repository.dart';
import 'canonical_visit_data.dart';
import 'unified_payload_mapper.dart';
import 'vitals_trend.dart';

/// Manages in-progress canonical form state for a single visit.
///
/// Autosaves field changes to [assessment_draft] via [AssessmentDraftDao].
/// On submit, decomposes to per-programme payloads and enqueues as
/// [local_assessments] rows for offline sync.
class UnifiedFormNotifier extends ChangeNotifier {
  UnifiedFormNotifier({
    required String encounterId,
    required String patientId,
    required List<String> activeFormTypes,
    required AssessmentDraftDao draftDao,
    required AssessmentRepository assessmentRepo,
    String? memberId,
    String? householdId,
    String? villageId,
    int householdMemberLocalId = 0,
    String? pregnancyEpisodeId,
  })  : _encounterId = encounterId,
        _patientId = patientId,
        _activeFormTypes = activeFormTypes,
        _draftDao = draftDao,
        _assessmentRepo = assessmentRepo,
        _memberId = memberId,
        _householdId = householdId,
        _villageId = villageId,
        _householdMemberLocalId = householdMemberLocalId,
        _pregnancyEpisodeId = pregnancyEpisodeId;

  final String _encounterId;
  final String _patientId;
  final List<String> _activeFormTypes;
  final AssessmentDraftDao _draftDao;
  final AssessmentRepository _assessmentRepo;
  final String? _memberId;
  final String? _householdId;
  final String? _villageId;
  final int _householdMemberLocalId;
  final String? _pregnancyEpisodeId;

  CanonicalVisitData _data = const CanonicalVisitData();
  bool _submitting = false;
  String? _submitError;
  Set<String> _validationErrors = const {};

  CanonicalVisitData get data => _data;
  bool get submitting => _submitting;
  String? get submitError => _submitError;
  Set<String> get validationErrors => _validationErrors;

  /// FHIR encounter id for this visit.
  String get encounterId => _encounterId;

  /// FHIR patient id for this visit (empty when unknown). Exposed so the
  /// vitals-trend card can look up prior-visit history.
  String get patientId => _patientId;

  /// Loads prior ANC visit snapshots for the vitals-trend card, oldest-first.
  Future<List<VisitVitals>> ancVitalsHistory() =>
      _assessmentRepo.ancVitalsHistory(_patientId);

  /// Returns the most-recent weight (kg) recorded for this patient from ANY
  /// prior visit, or `null` when no prior weight exists.
  Future<double?> lastRecordedWeight() =>
      _assessmentRepo.lastRecordedWeight(_patientId);

  /// Marks the given field IDs as having validation errors and notifies
  /// listeners so the form can highlight them.
  void setValidationErrors(Set<String> errors) {
    _validationErrors = errors;
    notifyListeners();
  }

  /// Load existing draft from DB on screen init.
  ///
  /// Merges draft values ON TOP of any values already in [_data] (e.g. triage
  /// pre-fills seeded before this call).  This means the draft wins for any
  /// field it contains, but triage-derived defaults are preserved for fields
  /// not yet saved in the draft.
  Future<void> loadDraft() async {
    final row = await _draftDao.getDraft(_encounterId);
    if (row == null) return;
    try {
      final map = jsonDecode(row.fieldValues) as Map<String, dynamic>;
      _data = _data.merge(CanonicalVisitData(map));
      notifyListeners();
    } catch (e) {
      debugPrint('[UnifiedForm] draft parse error: $e');
    }
  }

  /// Update a single field and autosave draft.
  ///
  /// When `height` or `weight` changes, BMI is automatically recomputed and
  /// stored under the `bmi` field so the `_InfoLabelField` stays in sync.
  void updateField(String fieldId, dynamic value) {
    _data = _data.setValue(fieldId, value);
    if (fieldId == 'height' || fieldId == 'weight') {
      _recomputeBmi();
    }
    notifyListeners();
    _saveDraft();
  }

  void _recomputeBmi() {
    final h = _toDouble(_data.getValue('height'));
    final w = _toDouble(_data.getValue('weight'));
    if (h != null && h > 0 && w != null && w > 0) {
      final bmi = w / ((h / 100) * (h / 100));
      _data = _data.setValue('bmi', double.parse(bmi.toStringAsFixed(1)));
    }
  }

  static double? _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Merge AI Scribe pre-filled fields into canonical data.
  void applyScribePrefill(Map<String, dynamic> fields) {
    _data = _data.merge(CanonicalVisitData(fields));
    notifyListeners();
    _saveDraft();
  }

  /// Decompose canonical data into per-programme payloads and save as
  /// [local_assessments] rows (sync_status=pending).
  ///
  /// Draft deletion is left to [_VisitFormScreenState._onSectionedSubmit] so it
  /// can extract vitals from [field_values] before deleting the draft row.
  ///
  /// Returns list of saved local IDs. Throws on DB error.
  Future<List<String>> submit({
    bool isReferred = false,
    String? referralStatus,
    List<String>? referredReasons,
  }) async {
    if (_submitting) return const [];
    _submitting = true;
    _submitError = null;
    notifyListeners();

    try {
      final payloads = UnifiedPayloadMapper.decompose(
        _data,
        _activeFormTypes.toSet(),
      );

      final savedIds = <String>[];
      for (final payload in payloads) {
        final id = await _assessmentRepo.saveAssessment(
          assessmentType: payload.assessmentType,
          assessmentDetails: payload.details,
          householdMemberLocalId: _householdMemberLocalId,
          memberId: _memberId,
          householdId: _householdId,
          patientId: _patientId,
          villageId: _villageId,
          encounterId: _encounterId,
          isReferred: isReferred,
          referralStatus: referralStatus,
          referredReasons: referredReasons,
          pregnancyEpisodeId: _pregnancyEpisodeId,
        );
        savedIds.add(id);
      }
      return savedIds;
    } catch (e) {
      _submitError = e.toString();
      rethrow;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void _saveDraft() {
    final row = AssessmentDraftRow(
      encounterId: _encounterId,
      patientId: _patientId,
      memberId: _memberId,
      activatedProgrammes: jsonEncode(_activeFormTypes),
      fieldValues: jsonEncode(_data.values),
      sectionStatus: '{}',
    );
    _draftDao.saveDraft(row).catchError((e) {
      debugPrint('[UnifiedForm] autosave error: $e');
    });
  }
}
