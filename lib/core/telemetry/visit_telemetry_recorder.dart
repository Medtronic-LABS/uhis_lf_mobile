/// In-memory state behind the one-row-per-visit telemetry event
/// ([TelemetryEventType.visit]).
///
/// One recorder per open of the visit flow. Screens feed it as the visit
/// happens; [TelemetryService.saveVisit] snapshots [toPayload] into the
/// `telemetry_events` row (id = [visitUuid]) at each save point — visit open,
/// each forward step change, Step 3 Done and leaving the visit.
///
/// The payload starts with the existing `visit_completed` keys **unchanged**
/// (same names, same shape, see [VisitCompletedPayload.toJson]) so a reader of
/// historical rows reads the same path on new rows. New fields live in new
/// keys: visit-level, `step1`, `step2`, `step3`.
///
/// Same non-PHI rule as every other `telemetry_events` row: field ids, symptom
/// codes, counts, durations and coarse categories only — never a value, a
/// patient id or free text. Those stay in the visit-content / value-audit
/// tables under the same [visitUuid].
///
/// Pure Dart with an injectable clock so the timing rules are unit-testable.
library;

/// [VisitTelemetryRecorder.status] values.
abstract final class VisitTelemetryStatus {
  VisitTelemetryStatus._();

  static const String inProgress = 'in_progress';
  static const String completed = 'completed';
  static const String abandoned = 'abandoned';
}

/// `inputMode` values for Step 1 and Step 2.
abstract final class VisitTelemetryInputMode {
  VisitTelemetryInputMode._();

  static const String manual = 'manual';
  static const String scribe = 'scribe';
  static const String mixed = 'mixed';

  static String of({required bool scribe, required bool manual}) {
    if (scribe && manual) return mixed;
    if (scribe) return VisitTelemetryInputMode.scribe;
    return VisitTelemetryInputMode.manual;
  }
}

/// `whatsappMessageSource` values.
abstract final class VisitTelemetryMessageSource {
  VisitTelemetryMessageSource._();

  /// Written by the AI service.
  static const String online = 'online';

  /// The app's built-in rule-based template.
  static const String offline = 'offline';
}

/// Why the active-time clock is paused. More than one can hold at once (app
/// backgrounded while the Sukhee call screen is up), so they are a set.
abstract final class VisitTelemetryPause {
  VisitTelemetryPause._();

  static const String background = 'background';
  static const String teleconsult = 'teleconsult';
}

class _StepClock {
  int? startTime;
  int? endTime;
  int activeMs = 0;
  int? runningSince;
}

class VisitTelemetryRecorder {
  VisitTelemetryRecorder({
    required this.visitUuid,
    int Function()? clock,
  })  : _clock = clock ?? _wallClock,
        visitStartTime = (clock ?? _wallClock)();

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final int Function() _clock;

  /// Telemetry-only correlator; also the row id.
  final String visitUuid;

  /// Epoch ms, UTC — also the row's `occurred_at`.
  final int visitStartTime;

  // ── Envelope, resolved once at visit open ─────────────────────────────────
  String? skUserId;
  int? capturedTenantId;

  // ── Visit level ───────────────────────────────────────────────────────────
  String _status = VisitTelemetryStatus.inProgress;
  String get status => _status;
  bool get isOpen => _status == VisitTelemetryStatus.inProgress;

  int _lastStep = 1;
  int get lastStep => _lastStep;

  int? _visitEndTime;
  bool? isOnline;
  List<String> _programmes = const [];

  // ── Step clocks ───────────────────────────────────────────────────────────
  final Map<int, _StepClock> _clocks = {1: _StepClock(), 2: _StepClock(), 3: _StepClock()};
  int? _currentStep;
  final Set<String> _pauses = {};

  /// Steps whose block is written to the payload — a step is written once it
  /// is finished (Step 1 Next, Step 2 submit, Step 3 Done), never mid-step.
  final Set<int> _finishedSteps = {};

  // ── Step 1 ────────────────────────────────────────────────────────────────
  List<String> _symptomsManual = const [];
  List<String> _symptomsScribe = const [];
  List<String> _symptomsDeselected = const [];
  int? _step1ScribeStart;
  int? _step1ScribeEnd;

  // ── Step 2 ────────────────────────────────────────────────────────────────
  /// The existing `visit_completed` payload, verbatim. Null until the unified
  /// form is submitted, and stays null for visits that don't use it (EPI
  /// timeline, ANC-suppressed Step 2).
  Map<String, dynamic>? _visitCompleted;
  int _ocrScanAttempts = 0;
  int _ocrScanTimeMs = 0;

  /// A card scan (ANC, NCD or EPI) was applied to the visit.
  bool _scanApplied = false;

  /// EPI vaccine codes saved from a card scan. The EPI timeline has no
  /// unified-form payload, so these are merged into `fields.scanFilled`.
  final Set<String> _epiScanFilled = {};

  // ── Step 3 ────────────────────────────────────────────────────────────────
  int? _whatsappStart;
  int? _whatsappEnd;
  String? _whatsappSource;
  final List<Map<String, dynamic>> _shares = [];
  String? _isHelpful;
  bool? _referralRecommended;
  int? _shukiStart;
  int? _shukiEnd;

  // ══ Step navigation and active time ═══════════════════════════════════════

  /// The step now on screen (1-3). Moving forward finishes the step left
  /// behind; moving back (Step 2 → Step 1) only pauses it, so a revisit adds
  /// to its active time instead of resetting it.
  ///
  /// Returns true when this was a forward move — a save point.
  bool enterStep(int step) {
    if (!isOpen || step == _currentStep || !_clocks.containsKey(step)) {
      return false;
    }
    final now = _clock();
    final previous = _currentStep;
    if (previous != null) _stopClock(previous, now);

    final forward = previous != null && step > previous;
    if (forward) {
      for (var s = previous; s < step; s++) {
        // The latest time the step was left: after a Step 2 → Step 1
        // revisit, Step 1 ends when the SK moves on again, so endTime -
        // startTime always covers the active time measured in between.
        _clocks[s]!.endTime = now;
        _finishedSteps.add(s);
      }
    }

    _currentStep = step;
    final clock = _clocks[step]!;
    clock.startTime ??= now;
    if (step > _lastStep) _lastStep = step;
    _startClock(step, now);
    return forward;
  }

  /// Pauses the active-time clock for [reason]; idempotent.
  void pause(String reason) {
    final wasRunning = _pauses.isEmpty;
    if (!_pauses.add(reason) || !wasRunning) return;
    final step = _currentStep;
    if (step != null) _stopClock(step, _clock());
  }

  /// Lifts one pause reason; the clock restarts when none remain.
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
    final clock = _clocks[step]!;
    final since = clock.runningSince;
    if (since == null) return;
    if (now > since) clock.activeMs += now - since;
    clock.runningSince = null;
  }

  int _activeMs(int step, int now) {
    final clock = _clocks[step]!;
    final since = clock.runningSince;
    return clock.activeMs + (since != null && now > since ? now - since : 0);
  }

  // ══ Visit level ═══════════════════════════════════════════════════════════

  void setProgrammes(Iterable<String> programmes) {
    final list = programmes.toSet().toList()..sort();
    if (list.isNotEmpty) _programmes = list;
  }

  /// Step 3 Done.
  void complete({bool? referralRecommended}) {
    if (!isOpen) return;
    _referralRecommended = referralRecommended ?? _referralRecommended;
    _close(VisitTelemetryStatus.completed, finishCurrentStep: true);
  }

  /// The SK left the visit before Done. A Step 1 or Step 2 left mid-way is
  /// not finished, so its block is not written. Step 3 is the exception: it
  /// has no submit of its own, and a Sukhee call or share made there before
  /// leaving would otherwise be lost — so its block is written, ending at the
  /// leave time.
  void abandon() {
    if (!isOpen) return;
    _close(
      VisitTelemetryStatus.abandoned,
      finishCurrentStep: _currentStep == 3,
    );
  }

  void _close(String status, {required bool finishCurrentStep}) {
    final now = _clock();
    final step = _currentStep;
    if (step != null) {
      _stopClock(step, now);
      if (finishCurrentStep) {
        _clocks[step]!.endTime ??= now;
        _finishedSteps.add(step);
      }
    }
    _visitEndTime = now;
    _status = status;
  }

  // ══ Step 1 ════════════════════════════════════════════════════════════════

  /// Symptom provenance at Step 1 Next. Codes, not values — non-PHI.
  void recordStep1Symptoms({
    required Iterable<String> selected,
    required Iterable<String> scribeAdded,
    required Iterable<String> scribeDeselected,
  }) {
    final scribe = scribeAdded.toSet();
    final chosen = selected.toSet();
    _symptomsScribe = (chosen.intersection(scribe).toList()..sort());
    _symptomsManual = (chosen.difference(scribe).toList()..sort());
    _symptomsDeselected = (scribeDeselected.toSet().difference(chosen).toList()
      ..sort());
  }

  /// Widens the Step 1 scribe span — same semantics as the form's
  /// `markScribeSpan`: earliest start, latest end.
  void markStep1ScribeSpan({int? startedAtMs, int? endedAtMs}) {
    if (startedAtMs != null &&
        (_step1ScribeStart == null || startedAtMs < _step1ScribeStart!)) {
      _step1ScribeStart = startedAtMs;
    }
    if (endedAtMs != null &&
        (_step1ScribeEnd == null || endedAtMs > _step1ScribeEnd!)) {
      _step1ScribeEnd = endedAtMs;
    }
  }

  // ══ Step 2 ════════════════════════════════════════════════════════════════

  /// The existing `visit_completed` payload, copied in verbatim.
  void recordStep2VisitCompleted(Map<String, dynamic> payload) {
    _visitCompleted = Map<String, dynamic>.from(payload);
  }

  /// A card-scan screen was opened. Returns the open time to hand back to
  /// [ocrScanClosed].
  int ocrScanOpened() {
    _ocrScanAttempts++;
    return _clock();
  }

  /// The scan screen closed. Only a scan whose result was applied to the
  /// form counts toward `ocrScanTimeMs`; a cancelled one is still an attempt.
  void ocrScanClosed(int openedAt, {required bool applied}) {
    if (!applied) return;
    _scanApplied = true;
    final elapsed = _clock() - openedAt;
    if (elapsed > 0) _ocrScanTimeMs += elapsed;
  }

  /// An EPI dose detected on the scanned card was saved — the EPI
  /// equivalent of a form field filled by scan.
  void markEpiScanFilled(String vaccineCode) {
    _epiScanFilled.add(vaccineCode);
    _scanApplied = true;
  }

  // ══ Step 3 ════════════════════════════════════════════════════════════════

  /// The app asked for the recommendation / WhatsApp message.
  void markWhatsappRequested() {
    _whatsappStart = _clock();
    _whatsappEnd = null;
  }

  /// The message is ready to show, from [source].
  void markWhatsappReturned(String source) {
    _whatsappEnd = _clock();
    _whatsappSource = source;
  }

  void addShare({
    required String channel,
    required String surface,
    required bool hasMessage,
    required bool launched,
  }) {
    _shares.add({
      'channel': channel,
      'surface': surface,
      'hasMessage': hasMessage,
      'launched': launched,
      'at': _clock(),
    });
  }

  /// `up` / `down`; the latest vote wins.
  set isHelpful(String vote) => _isHelpful = vote;

  /// The Sukhee call connected. First connect wins.
  void markShukiStarted() {
    _shukiStart ??= _clock();
  }

  /// The call ended, or the SK left the call screen. First end wins.
  void markShukiEnded() {
    if (_shukiStart == null || _shukiEnd != null) return;
    _shukiEnd = _clock();
  }

  // ══ Payload ═══════════════════════════════════════════════════════════════

  Map<String, dynamic> toPayload() {
    final now = _clock();
    final p = <String, dynamic>{};

    // Existing visit_completed keys first, unchanged — including its own
    // `programmes`. Before Step 2 is submitted (or on visits without the
    // unified form) the flow's confirmed programmes stand in.
    final existing = _visitCompleted;
    if (existing != null) {
      p.addAll(existing);
    } else if (_programmes.isNotEmpty) {
      p['programmes'] = _programmes;
    }
    _mergeScan(p);

    p['status'] = _status;
    p['lastStep'] = _lastStep;
    if (isOnline != null) p['isOnline'] = isOnline;
    p['visitStartTime'] = visitStartTime;
    if (_visitEndTime != null) {
      p['visitEndTime'] = _visitEndTime;
      p['visitDurationMs'] = _visitEndTime! - visitStartTime;
    }
    p['visitActiveMs'] =
        _activeMs(1, now) + _activeMs(2, now) + _activeMs(3, now);

    if (_finishedSteps.contains(1)) p['step1'] = _step1(now);
    if (_finishedSteps.contains(2)) p['step2'] = _step2(now);
    if (_finishedSteps.contains(3)) p['step3'] = _step3(now);
    return p;
  }

  /// `scanUsed` / `fields.scanFilled` for visits the unified form never
  /// reported on (the EPI timeline on its own), so "was a card scan used"
  /// has an answer for every visit type.
  ///
  /// When the form did report, its keys are left exactly as it wrote them
  /// (its `scanFilled` must stay `scanCorrected ∪ scanAcceptedUnchanged` over
  /// form fields); EPI doses then go in `step2.epiScanFilled` instead.
  void _mergeScan(Map<String, dynamic> p) {
    if (_visitCompleted != null || !_scanApplied) return;
    p['scanUsed'] = true;
    if (_epiScanFilled.isNotEmpty) {
      p['fields'] = {'scanFilled': (_epiScanFilled.toList()..sort())};
    }
  }

  Map<String, dynamic> _times(int step, int now) {
    final c = _clocks[step]!;
    return {
      if (c.startTime != null) 'startTime': c.startTime,
      if (c.endTime != null) 'endTime': c.endTime,
      'activeMs': _activeMs(step, now),
    };
  }

  Map<String, dynamic> _step1(int now) {
    final scribeUsed = _step1ScribeStart != null ||
        _symptomsScribe.isNotEmpty ||
        _symptomsDeselected.isNotEmpty;
    final start = _step1ScribeStart;
    final end = _step1ScribeEnd;
    return {
      ..._times(1, now),
      'inputMode': VisitTelemetryInputMode.of(
        scribe: _symptomsScribe.isNotEmpty,
        manual: _symptomsManual.isNotEmpty,
      ),
      'symptomsManual': _symptomsManual,
      'symptomsScribe': _symptomsScribe,
      'symptomsDeselected': _symptomsDeselected,
      'scribeUsed': scribeUsed,
      'scribeDurationMs':
          start != null && end != null && end > start ? end - start : 0,
    };
  }

  Map<String, dynamic> _step2(int now) {
    final existing = _visitCompleted;
    final fields = existing?['fields'];
    final started = existing?['scribeStartedAt'];
    final ended = existing?['scribeEndedAt'];
    return {
      ..._times(2, now),
      if (fields is Map)
        'inputMode': VisitTelemetryInputMode.of(
          scribe: (fields['aiFilled'] as List?)?.isNotEmpty ?? false,
          manual: (fields['manual'] as List?)?.isNotEmpty ?? false,
        ),
      if (started is int && ended is int && ended > started)
        'scribeDurationMs': ended - started,
      'ocrScanTimeMs': _ocrScanTimeMs,
      'ocrScanAttempts': _ocrScanAttempts,
      if (existing != null && _epiScanFilled.isNotEmpty)
        'epiScanFilled': (_epiScanFilled.toList()..sort()),
    };
  }

  Map<String, dynamic> _step3(int now) {
    final shukiStart = _shukiStart;
    final shukiEnd = _shukiEnd;
    return {
      ..._times(3, now),
      if (_whatsappStart != null) 'whatsappMessageStartTime': _whatsappStart,
      if (_whatsappEnd != null) 'whatsappMessageEndTime': _whatsappEnd,
      if (_whatsappSource != null) 'whatsappMessageSource': _whatsappSource,
      'communicationShares': List<Map<String, dynamic>>.from(_shares),
      if (_isHelpful != null) 'isHelpful': _isHelpful,
      if (_referralRecommended != null)
        'referralRecommended': _referralRecommended,
      'isShukiUsed': shukiStart != null,
      'shukiStartTime': ?shukiStart,
      'shukiEndTime': ?shukiEnd,
      if (shukiStart != null && shukiEnd != null)
        'shukiDurationMs': shukiEnd - shukiStart,
    };
  }
}
