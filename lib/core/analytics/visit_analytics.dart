/// GA visit lifecycle and AI field accuracy (LEAP-152).
///
/// [GaVisit] follows one open of the visit flow and sends:
/// `visit_started`, `visit_step_completed`, `visit_step_back`,
/// `visit_completed` / `visit_abandoned`. Every event carries `visit_id`, a
/// random id made for GA only — it is not the encounter id, the patient id or
/// the in-house telemetry `visitUuid`, so GA can't link a visit to a patient.
///
/// [aiFieldOutcomes] turns the form's field provenance into one
/// `ai_field_outcome` per field for AI Scribe and card scan.
///
/// GA-only and separate from the in-house `TelemetryService`, which this file
/// neither reads nor changes. Pure Dart with an injectable clock so the timing
/// rules are unit-testable.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'analytics.dart';
import 'analytics_events.dart';

/// Why the active-time clock is paused. Several can hold at once (app
/// backgrounded while the teleconsult screen is up), so they form a set.
abstract final class GaVisitPause {
  static const background = 'background';
  static const teleconsult = 'teleconsult';
}

class _StepClock {
  int? startedAt;
  int activeMs = 0;
  int? runningSince;
  int completions = 0;
}

/// One open of the visit flow, as GA sees it.
class GaVisit {
  GaVisit._(this.encounterId, int Function()? clock)
      : _clock = clock ?? _wallClock,
        visitId = _newId() {
    startedAt = _clock();
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  // ── Registry: the open visit per encounter ────────────────────────────────

  static final Map<String, GaVisit> _open = {};

  /// Starts tracking a visit for [encounterId]. A visit still open for the
  /// same encounter (the flow was reopened without closing) is abandoned
  /// first, so each open of the flow is its own GA visit.
  static GaVisit start(String encounterId, {int Function()? clock}) {
    _open.remove(encounterId)?.abandon();
    final visit = GaVisit._(encounterId, clock);
    _open[encounterId] = visit;
    return visit;
  }

  /// The open visit for [encounterId], or null outside a visit.
  static GaVisit? of(String? encounterId) =>
      encounterId == null ? null : _open[encounterId];

  /// `visit_id` for events fired inside a visit, or null outside one.
  static String? idFor(String? encounterId) => of(encounterId)?.visitId;

  /// The most recently started visit that is still open. Only one visit flow
  /// is on screen at a time, so widgets that don't carry the encounter id
  /// (Step 3 cards, the symptom grid) use this.
  static GaVisit? get current {
    GaVisit? latest;
    for (final v in _open.values) {
      if (latest == null || v.startedAt >= latest.startedAt) latest = v;
    }
    return latest;
  }

  /// `visit_id` of [current], or null outside a visit.
  static String? get currentId => current?.visitId;

  @visibleForTesting
  static void resetForTesting() => _open.clear();

  final int Function() _clock;
  final String encounterId;

  /// Random id sent as `visit_id`.
  final String visitId;
  late final int startedAt;

  bool _active = true;
  bool get isOpen => _active;

  bool? isOnline;
  List<String> _programmes = const [];
  String get programmes => _programmes.join(',');

  final Map<int, _StepClock> _clocks = {
    1: _StepClock(),
    2: _StepClock(),
    3: _StepClock(),
  };
  int? _currentStep;
  int _lastStep = 1;
  int get lastStep => _lastStep;
  final Set<String> _pauses = {};

  /// `input_mode` reported on a step's `visit_step_completed`.
  final Map<int, String> _inputMode = {};
  final Map<int, int> _scribeStart = {};
  final Map<int, int> _scribeEnd = {};

  /// Mic-on time and number of mic sessions per step.
  final Map<int, int> _micMs = {};
  final Map<int, int> _micSessions = {};

  bool _scribeUsed = false;
  bool _scanUsed = false;

  /// Steps on which AI Scribe was used (mic on, or its result applied).
  final Set<int> _stepScribeUsed = {};
  int? _teleconsultStart;
  int? _teleconsultEnd;

  // ── Visit level ───────────────────────────────────────────────────────────

  /// Sends `visit_started`. Called once the network state is known.
  void announceStart({required bool online}) {
    isOnline = online;
    Analytics.event(AnalyticsEvent.visitStarted, {
      AnalyticsParam.visitId: visitId,
      AnalyticsParam.isOnline: online,
      AnalyticsParam.programmes: _programmes.isEmpty ? null : programmes,
    });
  }

  void setProgrammes(Iterable<String> names) {
    final list = names.toSet().toList()..sort();
    if (list.isNotEmpty) _programmes = list;
  }

  /// AI Scribe was used — on [step] when known, else just for the visit.
  void markScribeUsed({int? step}) {
    _scribeUsed = true;
    if (step != null) _stepScribeUsed.add(step);
  }
  void markScanUsed() => _scanUsed = true;

  /// Input mode of [step] (`manual`, `voice`, `scan`, `mixed`).
  void setInputMode(int step, String mode) => _inputMode[step] = mode;

  /// Widens [step]'s scribe span: earliest start, latest end.
  void markScribeSpan(int step, {int? startedAtMs, int? endedAtMs}) {
    if (startedAtMs != null) {
      markScribeUsed(step: step);
      final s = _scribeStart[step];
      if (s == null || startedAtMs < s) _scribeStart[step] = startedAtMs;
    }
    if (endedAtMs != null) {
      final e = _scribeEnd[step];
      if (e == null || endedAtMs > e) _scribeEnd[step] = endedAtMs;
    }
  }

  int? _scribeMs(int step) {
    final s = _scribeStart[step];
    final e = _scribeEnd[step];
    return s != null && e != null && e > s ? e - s : null;
  }

  /// One mic session of [ms] ended on [step]; adds to the step's total.
  void addMicSession(int step, int ms) {
    if (ms <= 0) return;
    markScribeUsed(step: step);
    _micMs[step] = (_micMs[step] ?? 0) + ms;
    _micSessions[step] = (_micSessions[step] ?? 0) + 1;
  }

  /// Total seconds the mic was on during [step] (rounded), or null if never.
  int? micSecTotal(int step) {
    final ms = _micMs[step];
    return ms == null ? null : (ms / 1000).round();
  }

  int? micSessions(int step) => _micSessions[step];

  void markTeleconsultStarted() => _teleconsultStart ??= _clock();

  void markTeleconsultEnded() {
    if (_teleconsultStart == null || _teleconsultEnd != null) return;
    _teleconsultEnd = _clock();
  }

  // ── Steps and active time ─────────────────────────────────────────────────

  /// The step now on screen (1-3). Moving forward reports each step left
  /// behind as completed; moving back reports `visit_step_back` and only
  /// pauses the step, so a revisit adds to its active time.
  void enterStep(int step) {
    if (!isOpen || step == _currentStep || !_clocks.containsKey(step)) return;
    final now = _clock();
    final previous = _currentStep;
    if (previous != null) {
      _stopClock(previous, now);
      if (step > previous) {
        for (var s = previous; s < step; s++) {
          _reportStepCompleted(s, now);
        }
      } else {
        Analytics.event(AnalyticsEvent.visitStepBack, {
          AnalyticsParam.visitId: visitId,
          AnalyticsParam.fromStep: previous,
          AnalyticsParam.toStep: step,
        });
      }
    }
    _currentStep = step;
    _clocks[step]!.startedAt ??= now;
    if (step > _lastStep) _lastStep = step;
    _startClock(step, now);
  }

  void pause(String reason) {
    final wasRunning = _pauses.isEmpty;
    if (!_pauses.add(reason) || !wasRunning) return;
    final step = _currentStep;
    if (step != null) _stopClock(step, _clock());
  }

  void resume(String reason) {
    if (!_pauses.remove(reason) || _pauses.isNotEmpty) return;
    final step = _currentStep;
    if (step != null && isOpen) _startClock(step, _clock());
  }

  void _startClock(int step, int now) {
    if (_pauses.isNotEmpty) return;
    _clocks[step]!.runningSince ??= now;
  }

  void _stopClock(int step, int now) {
    final c = _clocks[step]!;
    final since = c.runningSince;
    if (since == null) return;
    if (now > since) c.activeMs += now - since;
    c.runningSince = null;
  }

  int _activeMs(int step, int now) {
    final c = _clocks[step]!;
    final since = c.runningSince;
    return c.activeMs + (since != null && now > since ? now - since : 0);
  }

  int _totalActiveMs(int now) =>
      _activeMs(1, now) + _activeMs(2, now) + _activeMs(3, now);

  void _reportStepCompleted(int step, int now) {
    final c = _clocks[step]!;
    c.completions++;
    Analytics.event(AnalyticsEvent.visitStepCompleted, {
      AnalyticsParam.visitId: visitId,
      AnalyticsParam.step: step,
      AnalyticsParam.durationMs:
          c.startedAt == null ? null : now - c.startedAt!,
      AnalyticsParam.activeMs: _activeMs(step, now),
      AnalyticsParam.inputMode: _inputMode[step],
      AnalyticsParam.scribeUsed: _stepScribeUsed.contains(step),
      AnalyticsParam.scribeSpanMs: _scribeMs(step),
      AnalyticsParam.micSecTotal: micSecTotal(step),
      AnalyticsParam.micSessions: micSessions(step),
      AnalyticsParam.revisit: c.completions > 1,
      AnalyticsParam.programmes: _programmes.isEmpty ? null : programmes,
    });
  }

  // ── End of visit ──────────────────────────────────────────────────────────

  /// Step 3 Done.
  void complete({bool? referred}) {
    if (!isOpen) return;
    final now = _clock();
    final step = _currentStep;
    if (step != null) {
      _stopClock(step, now);
      _reportStepCompleted(step, now);
    }
    _close();
    final tStart = _teleconsultStart;
    final tEnd = _teleconsultEnd;
    Analytics.event(AnalyticsEvent.visitCompleted, {
      AnalyticsParam.visitId: visitId,
      AnalyticsParam.programmes: _programmes.isEmpty ? null : programmes,
      AnalyticsParam.durationMs: now - startedAt,
      AnalyticsParam.activeMs: _totalActiveMs(now),
      AnalyticsParam.scribeUsed: _scribeUsed,
      AnalyticsParam.scanUsed: _scanUsed,
      AnalyticsParam.teleconsultUsed: tStart != null,
      AnalyticsParam.teleconsultMs:
          tStart != null && tEnd != null ? tEnd - tStart : null,
      AnalyticsParam.referred: referred,
      AnalyticsParam.isOnline: isOnline,
    });
  }

  /// The SK left the flow before Step 3 Done.
  void abandon() {
    if (!isOpen) return;
    final now = _clock();
    final step = _currentStep;
    if (step != null) _stopClock(step, now);
    _close();
    Analytics.event(AnalyticsEvent.visitAbandoned, {
      AnalyticsParam.visitId: visitId,
      AnalyticsParam.lastStep: _lastStep,
      AnalyticsParam.programmes: _programmes.isEmpty ? null : programmes,
      AnalyticsParam.durationMs: now - startedAt,
      AnalyticsParam.activeMs: _totalActiveMs(now),
      AnalyticsParam.scribeUsed: _scribeUsed,
      AnalyticsParam.scanUsed: _scanUsed,
    });
  }

  void _close() {
    _active = false;
    if (identical(_open[encounterId], this)) _open.remove(encounterId);
  }
}

// ══ AI field accuracy ═════════════════════════════════════════════════════

/// One `ai_field_outcome`.
typedef AiFieldOutcome = ({
  String field,
  String feature,
  String outcome,
  String? filledBy,
});

/// `outcome` values.
abstract final class AiOutcome {
  /// AI filled it, SK left it.
  static const kept = 'kept';

  /// AI filled it, SK changed it.
  static const edited = 'edited';

  /// AI's value was cleared by the SK, or refused because the SK had
  /// already entered the field.
  static const rejected = 'rejected';

  /// The AI could have filled it and it was on screen, but it didn't.
  static const missed = 'missed';
}

/// `feature` values.
abstract final class AiFeature {
  static const scribe = 'scribe';
  static const cardScan = 'card_scan';

  /// EPI vaccination card scan; `field` is the vaccine code (e.g. `penta1`).
  static const epiCard = 'epi_card';
}

/// Maps the app's EPI vaccine-save classification (in-house wire values
/// `correct`, `date_fixed`, `wrongly_marked`, `missed`) to the shared
/// `ai_field_outcome` outcomes, so EPI accuracy reads like Scribe and scan.
String epiOutcome(String changeTypeWire) => switch (changeTypeWire) {
      'correct' => AiOutcome.kept,
      'date_fixed' => AiOutcome.edited,
      'wrongly_marked' => AiOutcome.rejected,
      _ => AiOutcome.missed,
    };

/// Builds the `ai_field_outcome` list for one submitted form.
///
/// AI Scribe outcomes are reported when scribe was used. [scribeCapture] is
/// the set of fields scribe could fill that were on screen — the same scoping
/// the in-house report uses — so `missed` = capture fields the AI did not
/// fill. Card-scan outcomes are reported when a scan was applied;
/// [scanTargets] are the fields the applied card(s) can fill that were on
/// screen. [filledBy] says how a missed field got its value (`manual`,
/// `scan`, `prefilled`, `derived`) or `empty`.
List<AiFieldOutcome> aiFieldOutcomes({
  required Set<String> scribeCapture,
  required Set<String> aiKept,
  required Set<String> aiEdited,
  required Set<String> aiRejected,
  required bool scribeUsed,
  required Set<String> scanTargets,
  required Set<String> scanKept,
  required Set<String> scanEdited,
  required Set<String> scanRejected,
  required bool scanUsed,
  required String Function(String field) filledBy,
}) {
  final out = <AiFieldOutcome>[];
  void add(Iterable<String> fields, String feature, String outcome,
      {bool withFilledBy = false}) {
    for (final f in fields.toList()..sort()) {
      out.add((
        field: f,
        feature: feature,
        outcome: outcome,
        filledBy: withFilledBy ? filledBy(f) : null,
      ));
    }
  }

  if (scribeUsed) {
    final edited = aiEdited;
    final kept = aiKept.difference(edited);
    final rejected = aiRejected.difference(kept).difference(edited);
    final touched = {...kept, ...edited, ...rejected};
    add(kept, AiFeature.scribe, AiOutcome.kept);
    add(edited, AiFeature.scribe, AiOutcome.edited);
    add(rejected, AiFeature.scribe, AiOutcome.rejected);
    add(scribeCapture.difference(touched), AiFeature.scribe, AiOutcome.missed,
        withFilledBy: true);
  }
  if (scanUsed) {
    final edited = scanEdited;
    final kept = scanKept.difference(edited);
    final rejected = scanRejected.difference(kept).difference(edited);
    final touched = {...kept, ...edited, ...rejected};
    add(kept, AiFeature.cardScan, AiOutcome.kept);
    add(edited, AiFeature.cardScan, AiOutcome.edited);
    add(rejected, AiFeature.cardScan, AiOutcome.rejected);
    add(scanTargets.difference(touched), AiFeature.cardScan, AiOutcome.missed,
        withFilledBy: true);
  }
  return out;
}

/// Sends one `ai_field_outcome` per entry of [outcomes].
void sendAiFieldOutcomes(
  List<AiFieldOutcome> outcomes, {
  required String? visitId,
  required String programmes,
}) {
  for (final o in outcomes) {
    Analytics.event(AnalyticsEvent.aiFieldOutcome, {
      AnalyticsParam.visitId: visitId,
      AnalyticsParam.feature: o.feature,
      AnalyticsParam.field: o.field,
      AnalyticsParam.outcome: o.outcome,
      AnalyticsParam.filledBy: o.filledBy,
      AnalyticsParam.programmes: programmes,
    });
  }
}

// ══ Fields outside scribe's capture list ═══════════════════════════════════

/// `field_source` values.
abstract final class FieldSourceValue {
  static const manual = 'manual';
  static const prefilled = 'prefilled';
  static const derived = 'derived';
  static const empty = 'empty';
}

/// Fields on the saved form that are NOT in scribe's capture list, with how
/// each got its value — one `field_source` each. Capture-list fields are
/// already named by `ai_field_outcome`, so they are left out here; internal
/// fields (ids starting with `_`, e.g. `_triageSymptoms`) are skipped.
List<({String field, String source})> fieldSourcesOutsideCapture({
  required Set<String> capture,
  required Set<String> manual,
  required Set<String> prefilled,
  required Set<String> derived,
  required Set<String> empty,
}) {
  final out = <({String field, String source})>[];
  final seen = <String>{};
  void add(Set<String> ids, String source) {
    for (final f in ids.toList()..sort()) {
      if (f.startsWith('_') || capture.contains(f) || !seen.add(f)) continue;
      out.add((field: f, source: source));
    }
  }

  add(manual, FieldSourceValue.manual);
  add(prefilled, FieldSourceValue.prefilled);
  add(derived, FieldSourceValue.derived);
  add(empty, FieldSourceValue.empty);
  return out;
}
