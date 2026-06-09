import '../../core/api/scribe_api_service.dart';
import 'models/ai_extracted_field.dart';

/// All possible states the scribe flow can be in during a single visit.
enum ScribeState {
  idle,
  requestingPermission,
  recording,
  uploading,
  processing,
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
    this.rationale,
    this.formPrefillResult,
    this.errorMessage,
  });

  final ScribeState state;
  final ScribeMode mode;
  final int elapsedSeconds;
  final double? uploadProgressPercent;
  final String? jobId;
  final String? noteId;
  final SoapNote? soap;
  final String? transcriptText;
  final ScribeRationale? rationale;
  final FormPrefillResult? formPrefillResult;
  final String? errorMessage;

  bool get isActive =>
      state == ScribeState.recording ||
      state == ScribeState.uploading ||
      state == ScribeState.processing;

  bool get hasResult => state == ScribeState.reviewReady && (soap != null || formPrefillResult != null);

  /// Whether this is a form prefill session with extracted fields.
  bool get hasFormPrefillResult => formPrefillResult != null && formPrefillResult!.fields.isNotEmpty;

  /// Count of fields pending review.
  int get pendingFieldCount => formPrefillResult?.pendingFieldCount ?? 0;

  ScribeSession copyWith({
    ScribeState? state,
    ScribeMode? mode,
    int? elapsedSeconds,
    double? uploadProgressPercent,
    String? jobId,
    String? noteId,
    SoapNote? soap,
    String? transcriptText,
    ScribeRationale? rationale,
    FormPrefillResult? formPrefillResult,
    String? errorMessage,
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
        rationale: rationale ?? this.rationale,
        formPrefillResult: formPrefillResult ?? this.formPrefillResult,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
