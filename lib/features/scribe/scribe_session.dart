import '../../core/api/scribe_api_service.dart';
import 'models/ai_extracted_field.dart';

/// All possible states the scribe flow can be in during a single visit.
enum ScribeState {
  idle,
  requestingPermission,
  recording,
  uploading,
  processing,

  /// Fields are populated and ready for review inline (no modal).
  fieldsPopulated,

  /// Legacy: Ready to show review modal (SOAP mode only).
  reviewReady,
  accepted,
  rejected,
  error,
}

/// Snapshot of the scribe session for a single visit.
class ScribeSession {
  const ScribeSession({
    this.state = ScribeState.idle,
    this.mode = ScribeMode.soap,
    this.elapsedSeconds = 0,
    this.uploadProgressPercent,
    this.jobId,
    this.noteId,
    this.soap,
    this.transcriptText,
    this.liveTranscript,
    this.rationale,
    this.formPrefillResult,
    this.triageExtractionResult,
    this.errorMessage,
    this.fieldsJustPopulated = false,
    this.startedAtMs,
    this.endedAtMs,
  });

  final ScribeState state;
  final ScribeMode mode;
  final int elapsedSeconds;
  final double? uploadProgressPercent;
  final String? jobId;
  final String? noteId;
  final SoapNote? soap;
  final String? transcriptText;

  /// Live transcript shown during recording (partial, streaming).
  final String? liveTranscript;
  final ScribeRationale? rationale;
  final FormPrefillResult? formPrefillResult;
  final TriageExtractionResult? triageExtractionResult;
  final String? errorMessage;

  /// True when fields were just populated - triggers notification.
  final bool fieldsJustPopulated;

  /// Wall-clock bounds of the recording, epoch ms, or null before one has run.
  ///
  /// [elapsedSeconds] already counts the recording, but only while it is in
  /// flight and only as a duration — telemetry reports the actual start and
  /// end instants, so an SK's scribe session can be placed against the visit
  /// it belongs to. Set on the recording transitions in ScribeController, not
  /// derived from the fill: fields land after upload and processing, so a
  /// fill timestamp would overstate when the SK stopped talking.
  final int? startedAtMs;
  final int? endedAtMs;

  bool get isActive =>
      state == ScribeState.recording ||
      state == ScribeState.uploading ||
      state == ScribeState.processing;

  bool get hasResult =>
      (state == ScribeState.reviewReady ||
          state == ScribeState.fieldsPopulated) &&
      (soap != null ||
          formPrefillResult != null ||
          triageExtractionResult != null);

  /// Whether this is a form prefill session with extracted fields.
  bool get hasFormPrefillResult =>
      formPrefillResult != null && formPrefillResult!.fields.isNotEmpty;

  /// Count of fields pending review.
  int get pendingFieldCount => formPrefillResult?.pendingFieldCount ?? 0;

  /// Count of accepted fields.
  int get acceptedFieldCount =>
      formPrefillResult?.fields
          .where((f) => f.source == FieldSource.aiAccepted)
          .length ??
      0;

  ScribeSession copyWith({
    ScribeState? state,
    ScribeMode? mode,
    int? elapsedSeconds,
    double? uploadProgressPercent,
    String? jobId,
    String? noteId,
    SoapNote? soap,
    String? transcriptText,
    String? liveTranscript,
    ScribeRationale? rationale,
    FormPrefillResult? formPrefillResult,
    TriageExtractionResult? triageExtractionResult,
    String? errorMessage,
    bool? fieldsJustPopulated,
    int? startedAtMs,
    int? endedAtMs,
  }) => ScribeSession(
    state: state ?? this.state,
    mode: mode ?? this.mode,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    uploadProgressPercent: uploadProgressPercent ?? this.uploadProgressPercent,
    jobId: jobId ?? this.jobId,
    noteId: noteId ?? this.noteId,
    soap: soap ?? this.soap,
    transcriptText: transcriptText ?? this.transcriptText,
    liveTranscript: liveTranscript ?? this.liveTranscript,
    rationale: rationale ?? this.rationale,
    formPrefillResult: formPrefillResult ?? this.formPrefillResult,
    triageExtractionResult:
        triageExtractionResult ?? this.triageExtractionResult,
    errorMessage: errorMessage ?? this.errorMessage,
    fieldsJustPopulated: fieldsJustPopulated ?? this.fieldsJustPopulated,
    startedAtMs: startedAtMs ?? this.startedAtMs,
    endedAtMs: endedAtMs ?? this.endedAtMs,
  );
}
