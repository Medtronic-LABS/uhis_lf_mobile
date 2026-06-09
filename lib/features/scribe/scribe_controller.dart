import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/api/scribe_api_service.dart';
import 'scribe_permission_service.dart';
import 'scribe_session.dart';

/// Manages the full scribe lifecycle for one visit:
/// permission → record → upload → poll → review → accept/reject.
///
/// Provide above [VisitAssessmentStep] via [ChangeNotifierProvider].
class ScribeController extends ChangeNotifier {
  ScribeController({
    required ScribeApiService api,
    required ScribePermissionService permissionService,
  })  : _api = api,
        _perm = permissionService;

  final ScribeApiService _api;
  final ScribePermissionService _perm;
  final AudioRecorder _recorder = AudioRecorder();

  ScribeSession _session = const ScribeSession();
  ScribeSession get session => _session;

  Timer? _elapsedTimer;
  Timer? _pollTimer;
  String? _recordingPath;

  // Context bound during the recording tap — needed for permission rationale.
  BuildContext? _context;

  void bindContext(BuildContext ctx) => _context = ctx;

  // ── public API ────────────────────────────────────────────────────────────

  Future<void> startRecording({
    String? patientId,
    String? encounterId,
    String? programme,
  }) async {
    if (_session.isActive) return;

    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;

    _setState(ScribeState.requestingPermission);

    final granted = await _perm.ensureMicPermission(ctx);
    if (!granted) {
      _setState(ScribeState.idle);
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordingPath =
          '${dir.path}/scribe_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _recordingPath!,
      );

      _session = const ScribeSession(state: ScribeState.recording);
      notifyListeners();

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _session =
            _session.copyWith(elapsedSeconds: _session.elapsedSeconds + 1);
        notifyListeners();
      });
    } catch (e) {
      _session = ScribeSession(
        state: ScribeState.error,
        errorMessage: 'Could not start recording: $e',
      );
      notifyListeners();
    }
  }

  Future<void> stopRecording({
    String? patientId,
    String? encounterId,
    String? programme,
  }) async {
    if (_session.state != ScribeState.recording) return;
    _elapsedTimer?.cancel();

    try {
      final path = await _recorder.stop();
      if (path == null) {
        _setError('Recording produced no output.');
        return;
      }
      _recordingPath = path;
    } catch (e) {
      _setError('Stop recording failed: $e');
      return;
    }

    _session = _session.copyWith(
      state: ScribeState.uploading,
      uploadProgressPercent: 0,
    );
    notifyListeners();

    try {
      final file = File(_recordingPath!);
      final jobId = await _api.submitAudio(
        file,
        patientId: patientId,
        encounterId: encounterId,
        programme: programme,
      );

      _session = _session.copyWith(
        state: ScribeState.processing,
        jobId: jobId,
      );
      notifyListeners();

      _startPolling(jobId);
    } catch (e) {
      _setError('Upload failed: $e');
    } finally {
      // Clean up local audio file — audio lives on the service S3, not device.
      try {
        if (_recordingPath != null) {
          await File(_recordingPath!).delete();
        }
      } catch (_) {}
    }
  }

  Future<void> acceptNote({SoapNote? edits}) async {
    final noteId = _session.noteId;
    if (noteId == null) return;
    try {
      await _api.acceptNote(noteId, edits: edits);
      _session = _session.copyWith(state: ScribeState.accepted);
      notifyListeners();
    } catch (e) {
      _setError('Accept failed: $e');
    }
  }

  Future<void> rejectNote({String? reason}) async {
    final noteId = _session.noteId;
    if (noteId == null) return;
    try {
      await _api.rejectNote(noteId, reason: reason);
      _session = _session.copyWith(state: ScribeState.rejected);
      notifyListeners();
    } catch (e) {
      _setError('Reject failed: $e');
    }
  }

  /// Retry after an upload/processing error.
  void retryUpload({
    String? patientId,
    String? encounterId,
    String? programme,
  }) {
    if (_recordingPath == null) {
      _setState(ScribeState.idle);
      return;
    }
    _setError(''); // clear error
    _session = _session.copyWith(
      state: ScribeState.uploading,
      errorMessage: null,
    );
    notifyListeners();

    _retrySubmit(
      path: _recordingPath!,
      patientId: patientId,
      encounterId: encounterId,
      programme: programme,
    );
  }

  // ── private helpers ───────────────────────────────────────────────────────

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      final result = await _api.pollResult(jobId);
      if (result == null) return; // transient network issue — keep polling

      switch (result.status) {
        case ScribeJobStatus.completed:
          _pollTimer?.cancel();

          // Fetch full note to get rationale (poll response omits it).
          ScribeRationale? rationale = result.rationale;
          SoapNote? soap = result.soap;
          if (result.noteId != null) {
            final note = await _api.getNote(result.noteId!);
            if (note != null) {
              soap = note.soap ?? soap;
              rationale = note.rationale ?? rationale;
            }
          }

          _session = _session.copyWith(
            state: ScribeState.reviewReady,
            noteId: result.noteId,
            soap: soap,
            transcriptText: result.transcriptText,
            rationale: rationale,
          );
          notifyListeners();
          break;

        case ScribeJobStatus.failed:
          _pollTimer?.cancel();
          _setError(result.errorMessage ?? 'Transcription failed.');
          break;

        default:
          break; // queued / processing — keep polling
      }
    });
  }

  Future<void> _retrySubmit({
    required String path,
    String? patientId,
    String? encounterId,
    String? programme,
  }) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        _setError('Audio file not found. Please re-record.');
        return;
      }
      final jobId = await _api.submitAudio(
        file,
        patientId: patientId,
        encounterId: encounterId,
        programme: programme,
      );
      _session = _session.copyWith(
        state: ScribeState.processing,
        jobId: jobId,
      );
      notifyListeners();
      _startPolling(jobId);
    } catch (e) {
      _setError('Retry failed: $e');
    }
  }

  void _setState(ScribeState state) {
    _session = _session.copyWith(state: state);
    notifyListeners();
  }

  void _setError(String message) {
    _session = _session.copyWith(
      state: ScribeState.error,
      errorMessage: message,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _pollTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
