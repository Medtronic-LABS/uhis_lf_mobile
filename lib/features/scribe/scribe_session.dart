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
    this.errorMessage,
    this.fieldsJustPopulated = false,
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
  final String? errorMessage;
  /// True when fields were just populated - triggers notification.
  final bool fieldsJustPopulated;

  bool get isActive =>
      state == ScribeState.recording ||
      state == ScribeState.uploading ||
      state == ScribeState.processing;

  bool get hasResult => (state == ScribeState.reviewReady || state == ScribeState.fieldsPopulated) && 
      (soap != null || formPrefillResult != null);

  /// Whether this is a form prefill session with extracted fields.
  bool get hasFormPrefillResult => formPrefillResult != null && formPrefillResult!.fields.isNotEmpty;

  /// Count of fields pending review.
  int get pendingFieldCount => formPrefillResult?.pendingFieldCount ?? 0;
  
  /// Count of accepted fields.
  int get acceptedFieldCount => formPrefillResult?.fields.where((f) => f.source == FieldSource.aiAccepted).length ?? 0;

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
    String? errorMessage,
    bool? fieldsJustPopulated,
  }) =>
      ScribeSession(
        state: state ?? this.state,
        mode: mode ?? this.mode,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        uploadProgressPercent:
            uploadProgressPercent ?? this.uploadProgressPercent,
        jobId: jobId ?? this.jobId,
        noteId: noteId ?? this.noteId,
        soap: soap ?? this.soap,
        transcriptText: transcriptText ?? this.transcriptText,
        liveTranscript: liveTranscript ?? this.liveTranscript,
        rationale: rationale ?? this.rationale,
        formPrefillResult: formPrefillResult ?? this.formPrefillResult,
        errorMessage: errorMessage ?? this.errorMessage,
        fieldsJustPopulated: fieldsJustPopulated ?? this.fieldsJustPopulated,
      );
}
