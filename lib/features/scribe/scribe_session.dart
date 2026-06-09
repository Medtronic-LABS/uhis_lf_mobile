import '../../core/api/scribe_api_service.dart';

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
    this.elapsedSeconds = 0,
    this.uploadProgressPercent,
    this.jobId,
    this.noteId,
    this.soap,
    this.transcriptText,
    this.rationale,
    this.errorMessage,
  });

  final ScribeState state;
  final int elapsedSeconds;
  final double? uploadProgressPercent;
  final String? jobId;
  final String? noteId;
  final SoapNote? soap;
  final String? transcriptText;
  final ScribeRationale? rationale;
  final String? errorMessage;

  bool get isActive =>
      state == ScribeState.recording ||
      state == ScribeState.uploading ||
      state == ScribeState.processing;

  bool get hasResult => state == ScribeState.reviewReady && soap != null;

  ScribeSession copyWith({
    ScribeState? state,
    int? elapsedSeconds,
    double? uploadProgressPercent,
    String? jobId,
    String? noteId,
    SoapNote? soap,
    String? transcriptText,
    ScribeRationale? rationale,
    String? errorMessage,
  }) =>
      ScribeSession(
        state: state ?? this.state,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        uploadProgressPercent:
            uploadProgressPercent ?? this.uploadProgressPercent,
        jobId: jobId ?? this.jobId,
        noteId: noteId ?? this.noteId,
        soap: soap ?? this.soap,
        transcriptText: transcriptText ?? this.transcriptText,
        rationale: rationale ?? this.rationale,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}
