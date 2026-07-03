import 'package:flutter/foundation.dart';

import '../../../core/models/programme.dart';
import '../pathway/pathway_engine.dart';
import '../triage/patient_context_builder.dart';
import 'programme_recommendation_models.dart';
import 'programme_recommendation_repository.dart';

/// View-model for the Step-2 programme selection screen.
///
/// Owns the lifecycle of one /programme-recommendation/recommend call and the
/// SK's accept / reject state. The screen is purely render-and-dispatch — no
/// business logic.
class ProgrammeSelectionViewModel extends ChangeNotifier {
  ProgrammeSelectionViewModel({
    required ProgrammeRecommendationRepository repository,
    required this.request,
    required this.currentProgrammes,
  }) : _repository = repository {
    // Seed selected with the current enrolment so the SK never accidentally
    // drops a programme the patient is already in.
    _selected = {...currentProgrammes};
  }

  final ProgrammeRecommendationRepository _repository;
  final Map<String, dynamic> request;
  final Set<Programme> currentProgrammes;

  bool _disposed = false;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  ProgrammeRecommendationResponse? _response;
  ProgrammeRecommendationResponse? get response => _response;

  late Set<Programme> _selected;
  Set<Programme> get selectedProgrammes => Set.unmodifiable(_selected);

  bool isSelected(Programme p) => _selected.contains(p);

  void toggle(Programme p) {
    if (p == Programme.unknown) return;
    if (_selected.contains(p)) {
      _selected.remove(p);
    } else {
      _selected.add(p);
    }
    notifyListeners();
  }

  void addProgramme(Programme p) {
    if (p == Programme.unknown) return;
    if (_selected.add(p)) notifyListeners();
  }

  void removeProgramme(Programme p) {
    if (_selected.remove(p)) notifyListeners();
  }

  /// Auto-accept every AI recommendation above [floor] confidence on first
  /// load. SK can untick afterwards — matches the spec ("AI recommendations
  /// should be fully editable; SK retains full control").
  void _autoAcceptHighConfidence({double floor = 0.80}) {
    final resp = _response;
    if (resp == null) return;
    for (final rec in resp.recommendations) {
      if (rec.confidence >= floor && rec.programme != Programme.unknown) {
        _selected.add(rec.programme);
      }
    }
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    if (!_disposed) notifyListeners();
    try {
      final resp = await _repository.recommend(request);
      if (_disposed) return;
      _response = resp;
      _autoAcceptHighConfidence();
      _isLoading = false;
      notifyListeners();
    } catch (e, stack) {
      debugPrint('[ProgrammeSelection] recommend failed — using rule-based fallback: $e\n$stack');
      if (_disposed) return;
      _response = _ruleBasedFallback(request, currentProgrammes);
      _autoAcceptHighConfidence();
      _isLoading = false;
      _error = null;
      notifyListeners();
    }
  }

  /// Derives programme recommendations from [PathwayEngine] when the AI
  /// service is unreachable. Confidence is 1.0 (rule fired = certain).
  static ProgrammeRecommendationResponse _ruleBasedFallback(
    Map<String, dynamic> request,
    Set<Programme> currentProgrammes,
  ) {
    final ageMonths = (request['ageMonths'] as int?) ?? 0;
    final isPregnant = (request['isPregnant'] as bool?) ?? false;
    final gestationalWeeks = request['gestationalWeeks'] as int?;
    final rawSymptoms = request['selectedSymptoms'];
    final symptoms = <String>{
      if (rawSymptoms is List)
        for (final s in rawSymptoms)
          if (s is String) s,
    };
    final gender = (request['gender'] as String?)?.toLowerCase();

    final ctx = PatientContext(
      patientId: (request['patientId'] as String?) ?? '',
      ageMonths: ageMonths,
      sex: gender == 'female'
          ? Sex.female
          : gender == 'male'
              ? Sex.male
              : Sex.unknown,
      isPregnant: isPregnant,
      gestationalWeeks: gestationalWeeks,
      activeProgrammes: currentProgrammes,
    );

    final pathways = PathwayEngine.activate(symptoms, ctx);

    final recommendations = pathways
        .where((p) => p.programme != Programme.unknown)
        .map((p) => ProgrammeRecommendation(
              programme: p.programme,
              confidence: 1.0,
              rationale: const [
                ProgrammeRationaleBullet(
                  text: 'Activated by symptom screening rules',
                  source: RationaleSource.general,
                ),
              ],
              isCurrent: currentProgrammes.contains(p.programme),
            ))
        .toList(growable: false);

    return ProgrammeRecommendationResponse(
      recommendations: recommendations,
      modelVersion: 'rule-based-fallback',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
