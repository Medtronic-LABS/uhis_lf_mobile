/// In-memory state behind the one-row-per-session assistant telemetry event
/// ([TelemetryEventType.assistantSession]).
///
/// One recorder per opening of the patient AI assistant sheet. The sheet
/// feeds it each question; [TelemetryService.saveAssistantSession] snapshots
/// [toPayload] into the `telemetry_events` row (id = [sessionId]) when the
/// sheet opens, after each answer or failure, and when the sheet closes.
///
/// Non-PHI like every `telemetry_events` row: timings, flags and coarse
/// categories only. The question text, the answer text and the patient id
/// stay in `assistant_content_telemetry` (wiped on SK change), joined to each
/// question here by its [AssistantSessionQuestion.correlator] — the same
/// per-question id the `assistant_ask` event and the content row already
/// share.
///
/// Pure Dart with an injectable clock so the timing rules are unit-testable.
library;

/// [AssistantSessionRecorder.status] values.
abstract final class AssistantSessionStatus {
  AssistantSessionStatus._();

  static const String inProgress = 'in_progress';
  static const String completed = 'completed';
}

/// How a question was asked.
abstract final class AssistantQuestionSource {
  AssistantQuestionSource._();

  static const String typed = 'typed';

  /// Speech filled the input, even if the SK edited it before sending.
  static const String voice = 'voice';

  /// A suggested-question chip.
  static const String suggested = 'suggested';

  /// The retry button after a failure.
  static const String retry = 'retry';
}

/// One question's outcome.
abstract final class AssistantQuestionStatus {
  AssistantQuestionStatus._();

  /// Sent, no reply yet (still in flight when the row was saved, or the app
  /// was killed before it came back).
  static const String pending = 'pending';
  static const String answered = 'answered';
  static const String failed = 'failed';
}

/// Why a question failed — coarse, no error text.
abstract final class AssistantFailureReason {
  AssistantFailureReason._();

  /// No connection to the server.
  static const String offline = 'offline';
  static const String timeout = 'timeout';

  /// The server replied with an error status.
  static const String serverError = 'server_error';

  /// The server replied without an answer.
  static const String emptyAnswer = 'empty_answer';
  static const String other = 'other';
}

class AssistantSessionQuestion {
  AssistantSessionQuestion({
    required this.correlator,
    required this.askedAt,
    required this.source,
    required this.askedAgain,
  });

  final String correlator;
  final int askedAt;
  final String source;
  final bool askedAgain;
  String status = AssistantQuestionStatus.pending;
  int? responseTimeMs;
  String? failureReason;

  Map<String, dynamic> toJson() => {
        'correlator': correlator,
        'askedAt': askedAt,
        'responseTimeMs': ?responseTimeMs,
        'askedAgain': askedAgain,
        'source': source,
        'status': status,
        'failureReason': ?failureReason,
      };
}

class AssistantSessionRecorder {
  AssistantSessionRecorder({
    required this.sessionId,
    required this.context,
    required this.appLanguage,
    this.deceasedContext = false,
    int Function()? clock,
  })  : _clock = clock ?? _wallClock,
        sessionStartTime = (clock ?? _wallClock)() {
    _runningSince = sessionStartTime;
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final int Function() _clock;

  /// Telemetry-only id for this opening of the sheet; also the row id.
  final String sessionId;

  /// `patient-scoped` | `community-health-worker`.
  final String context;

  /// `bn` | `en`.
  final String appLanguage;

  /// The patient is recorded as deceased.
  final bool deceasedContext;

  /// Epoch ms, UTC — also the row's `occurred_at`.
  final int sessionStartTime;

  // ── Envelope, resolved once at open ───────────────────────────────────────
  String? skUserId;
  int? capturedTenantId;

  bool? isOnline;

  String _status = AssistantSessionStatus.inProgress;
  String get status => _status;
  bool get isOpen => _status == AssistantSessionStatus.inProgress;

  int? _sessionEndTime;

  // ── Active time: paused while the app is in the background ───────────────
  int _activeMs = 0;
  int? _runningSince;

  final List<AssistantSessionQuestion> _questions = [];

  /// The question was sent. [askedAgain] is ignored for a retry — re-sending
  /// after a failure is not the SK asking the same thing twice.
  void questionAsked({
    required String correlator,
    required String source,
    required bool askedAgain,
  }) {
    _questions.add(AssistantSessionQuestion(
      correlator: correlator,
      askedAt: _clock(),
      source: source,
      askedAgain: source != AssistantQuestionSource.retry && askedAgain,
    ));
  }

  /// The answer came back after [responseTimeMs]. Accepted after the sheet
  /// closed too: an answer to a question asked just before closing still
  /// belongs to this session.
  void questionAnswered(String correlator, {required int responseTimeMs}) {
    final q = _find(correlator);
    if (q == null) return;
    q
      ..status = AssistantQuestionStatus.answered
      ..responseTimeMs = responseTimeMs;
  }

  /// The question failed after [responseTimeMs] for [reason].
  void questionFailed(
    String correlator, {
    required int responseTimeMs,
    required String reason,
  }) {
    final q = _find(correlator);
    if (q == null) return;
    q
      ..status = AssistantQuestionStatus.failed
      ..responseTimeMs = responseTimeMs
      ..failureReason = reason;
  }

  AssistantSessionQuestion? _find(String correlator) {
    for (final q in _questions) {
      if (q.correlator == correlator) return q;
    }
    return null;
  }

  void pause() {
    final since = _runningSince;
    if (since == null) return;
    final now = _clock();
    if (now > since) _activeMs += now - since;
    _runningSince = null;
  }

  void resume() {
    if (!isOpen) return;
    _runningSince ??= _clock();
  }

  /// The sheet closed.
  void complete() {
    if (!isOpen) return;
    pause();
    _sessionEndTime = _clock();
    _status = AssistantSessionStatus.completed;
  }

  int _currentActiveMs(int now) {
    final since = _runningSince;
    return _activeMs + (since != null && now > since ? now - since : 0);
  }

  Map<String, dynamic> toPayload() {
    final now = _clock();
    final answered = _questions
        .where((q) => q.status == AssistantQuestionStatus.answered)
        .toList();
    return {
      'sessionId': sessionId,
      'status': _status,
      'context': context,
      'appLanguage': appLanguage,
      'deceasedContext': deceasedContext,
      'isOnline': ?isOnline,
      'sessionStartTime': sessionStartTime,
      if (_sessionEndTime != null) ...{
        'sessionEndTime': _sessionEndTime,
        'sessionDurationMs': _sessionEndTime! - sessionStartTime,
      },
      'sessionActiveMs': _currentActiveMs(now),
      'questions': [for (final q in _questions) q.toJson()],
      'totalQuestions': _questions.length,
      'totalAnswered': answered.length,
      'totalResponseTimeMs':
          answered.fold<int>(0, (sum, q) => sum + (q.responseTimeMs ?? 0)),
    };
  }
}
