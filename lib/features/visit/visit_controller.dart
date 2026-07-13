import 'package:flutter/foundation.dart';

import '../../core/db/encounter_dao.dart';
import '../../core/db/local_assessment_dao.dart' show AssessmentDraftRow;
import '../../core/models/programme.dart';
import 'encounter_repository.dart';
import 'symptom_catalog.dart';
import 'visit_session.dart';

/// Controller for managing visit flow state.
///
/// Holds the current [VisitSession] and provides methods to:
/// - Start a new visit
/// - Update symptoms and vitals
/// - Persist each step to local DB
/// - Navigate between steps
///
/// Use via Provider to share state across visit step screens.
class VisitController extends ChangeNotifier {
  VisitController(this._repo);

  final EncounterRepository _repo;

  VisitSession? _session;
  bool _loading = false;
  String? _error;

  /// Current visit session. Null if no visit in progress.
  VisitSession? get session => _session;

  /// Whether an async operation is in progress.
  bool get loading => _loading;

  /// Last error message, if any.
  String? get error => _error;

  /// Whether a visit is currently active.
  bool get hasActiveVisit => _session != null;

  /// Returns [patientId]'s resumable draft (last touched today), or null —
  /// discarding it silently first if it's from a prior day. See
  /// [EncounterRepository.findTodayDraft].
  Future<AssessmentDraftRow?> checkTodayDraft(String patientId) =>
      _repo.findTodayDraft(patientId);

  /// Discards a draft and its parent encounter — used when the SK picks
  /// "Start Over" on a same-day resume prompt.
  Future<void> discardDraft(String encounterId) =>
      _repo.discardDraft(encounterId);

  /// Start a new visit for a patient.
  ///
  /// Creates a local draft encounter and optionally POSTs to server.
  /// Returns the encounter ID.
  Future<String?> startVisit({
    required String patientId,
    required Programme programme,
    String? patientName,
    int? patientAge,
    String? patientGender,
    String? householdId,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      // Create the encounter via repository
      final id = await _repo.createVisit(patientId, programme);

      // Initialize symptoms from catalog
      final symptoms = SymptomCatalog.forProgramme(programme)
          .map((s) => SymptomSelection(code: s.code, label: s.label))
          .toList();

      // Initialize vitals from catalog
      final vitals = VitalCatalog.forProgramme(programme, patientAge)
          .map((v) => VitalInput(code: v.code, label: v.label, unit: v.unit))
          .toList();

      // Create session
      _session = VisitSession.create(
        id: id,
        patientId: patientId,
        programme: programme,
        patientName: patientName,
        patientAge: patientAge,
        patientGender: patientGender,
        householdId: householdId,
      ).copyWith(
        symptoms: symptoms,
        vitals: vitals,
        step: VisitStep.triage,
      );

      _setLoading(false);
      return id;
    } catch (e) {
      _error = 'Failed to start visit: $e';
      _setLoading(false);
      return null;
    }
  }

  /// Resume an existing visit from local storage.
  Future<bool> resumeVisit(String encounterId) async {
    _setLoading(true);
    _error = null;

    try {
      final encounter = await _repo.byId(encounterId);
      if (encounter == null) {
        _error = 'Visit not found';
        _setLoading(false);
        return false;
      }

      final programme = Programme.fromString(encounter.programme);

      // Determine current step from encounter status
      VisitStep step;
      switch (encounter.status) {
        case EncounterStatus.draft:
          step = VisitStep.triage;
          break;
        case EncounterStatus.triageComplete:
          step = VisitStep.vitals;
          break;
        case EncounterStatus.vitalsComplete:
          step = VisitStep.assessment;
          break;
        case EncounterStatus.completed:
        case EncounterStatus.synced:
          step = VisitStep.complete;
          break;
      }

      // Initialize symptoms and vitals
      final symptoms = SymptomCatalog.forProgramme(programme)
          .map((s) => SymptomSelection(code: s.code, label: s.label))
          .toList();

      final vitals = VitalCatalog.forProgramme(programme, null)
          .map((v) => VitalInput(code: v.code, label: v.label, unit: v.unit))
          .toList();

      _session = VisitSession(
        id: encounterId,
        patientId: encounter.patientId,
        programme: programme,
        serverVisitId: encounter.serverVisitId,
        step: step,
        symptoms: symptoms,
        vitals: vitals,
        startedAt: DateTime.fromMillisecondsSinceEpoch(encounter.startedAt),
      );

      // Restore triage data if present
      final triageData = encounter.triageData;
      if (triageData != null) {
        _restoreTriage(triageData);
      }

      // Restore vitals data if present
      final vitalsData = encounter.vitalsData;
      if (vitalsData != null) {
        _restoreVitals(vitalsData);
      }

      _setLoading(false);
      return true;
    } catch (e) {
      _error = 'Failed to resume visit: $e';
      _setLoading(false);
      return false;
    }
  }

  void _restoreTriage(Map<String, dynamic> data) {
    if (_session == null) return;

    final symptomsData = data['symptoms'] as List<dynamic>?;
    if (symptomsData != null) {
      final updatedSymptoms = _session!.symptoms.map((s) {
        final match = symptomsData.firstWhere(
          (sd) => sd is Map && sd['code'] == s.code,
          orElse: () => null,
        );
        if (match != null && match['selected'] == true) {
          return s.copyWith(selected: true);
        }
        return s;
      }).toList();

      _session = _session!.copyWith(symptoms: updatedSymptoms);
    }

    final durationDays = data['durationDays'] as int?;
    if (durationDays != null) {
      SymptomDuration? duration;
      if (durationDays <= 1) {
        duration = SymptomDuration.oneDay;
      } else if (durationDays <= 3) {
        duration = SymptomDuration.twoToThreeDays;
      } else {
        duration = SymptomDuration.fourPlusDays;
      }
      _session = _session!.copyWith(duration: duration);
    }
  }

  void _restoreVitals(Map<String, dynamic> data) {
    if (_session == null) return;

    final vitalsData = data['vitals'] as List<dynamic>?;
    if (vitalsData != null) {
      final updatedVitals = _session!.vitals.map((v) {
        final match = vitalsData.firstWhere(
          (vd) => vd is Map && vd['code'] == v.code,
          orElse: () => null,
        );
        if (match is Map) {
          return v.copyWith(
            value: match['value'] is num ? (match['value'] as num).toDouble() : null,
            systolic: match['systolic'] is num ? (match['systolic'] as num).toDouble() : null,
            diastolic: match['diastolic'] is num ? (match['diastolic'] as num).toDouble() : null,
            boolValue: match['boolValue'] as bool?,
          );
        }
        return v;
      }).toList();

      _session = _session!.copyWith(vitals: updatedVitals);
    }
  }

  /// Toggle a symptom selection.
  void toggleSymptom(String code) {
    if (_session == null) return;

    final updatedSymptoms = _session!.symptoms.map((s) {
      if (s.code == code) {
        return s.copyWith(selected: !s.selected);
      }
      return s;
    }).toList();

    _session = _session!.copyWith(symptoms: updatedSymptoms);
    notifyListeners();
  }

  /// Set symptom duration.
  void setDuration(SymptomDuration duration) {
    if (_session == null) return;
    _session = _session!.copyWith(duration: duration);
    notifyListeners();
  }

  /// Update a vital value.
  void updateVital(String code, {double? value, double? systolic, double? diastolic, bool? boolValue}) {
    if (_session == null) return;

    final updatedVitals = _session!.vitals.map((v) {
      if (v.code == code) {
        return v.copyWith(
          value: value,
          systolic: systolic,
          diastolic: diastolic,
          boolValue: boolValue,
        );
      }
      return v;
    }).toList();

    _session = _session!.copyWith(vitals: updatedVitals);
    notifyListeners();
  }

  /// Persist triage data and advance to vitals step.
  Future<bool> persistTriage() async {
    if (_session == null) return false;

    _setLoading(true);
    _error = null;

    try {
      await _repo.saveTriage(_session!.id, _session!.triagePayload);
      _session = _session!.copyWith(step: VisitStep.vitals);
      _setLoading(false);
      return true;
    } catch (e) {
      _error = 'Failed to save triage: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Persist vitals data and advance to assessment step.
  Future<bool> persistVitals() async {
    if (_session == null) return false;

    _setLoading(true);
    _error = null;

    try {
      await _repo.saveVitals(_session!.id, _session!.vitalsPayload);
      _session = _session!.copyWith(step: VisitStep.assessment);
      _setLoading(false);
      return true;
    } catch (e) {
      _error = 'Failed to save vitals: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Complete the visit with assessment data.
  Future<bool> completeVisit(Map<String, dynamic> assessmentData) async {
    if (_session == null) return false;

    _setLoading(true);
    _error = null;

    try {
      await _repo.saveAssessment(_session!.id, assessmentData);
      _session = _session!.copyWith(
        step: VisitStep.complete,
        assessmentData: assessmentData,
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _error = 'Failed to complete visit: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Cancel and clear the current visit.
  void cancelVisit() {
    _session = null;
    _error = null;
    notifyListeners();
  }

  /// Navigate back to a previous step.
  void goToStep(VisitStep step) {
    if (_session == null) return;
    _session = _session!.copyWith(step: step);
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
