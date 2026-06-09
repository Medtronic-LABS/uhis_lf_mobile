import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/api/scribe_api_service.dart';
import 'form_field_schema_builder.dart';
import 'models/ai_extracted_field.dart';
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

  // Form prefill mode state
  List<FormFieldSchema>? _currentFormSchema;
  List<String>? _currentSymptomCatalog;
  ScribeMode _currentMode = ScribeMode.soap;
  List<String> _currentProgrammes = const [];

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

  /// Start recording for form prefill mode.
  ///
  /// This extracts structured field values from the audio that can be
  /// used to auto-populate form fields with AI-extracted values.
  Future<void> startRecordingForFormPrefill({
    String? patientId,
    String? encounterId,
    required List<FormFieldSchema> formSchema,
    List<String> programmes = const [],
  }) async {
    debugPrint('[AIScribe] Starting form prefill recording for programmes: $programmes');
    debugPrint('[AIScribe] Form schema has ${formSchema.length} fields: '
        '${formSchema.map((f) => f.fieldId).join(', ')}');

    _currentMode = ScribeMode.formPrefill;
    _currentFormSchema = formSchema;
    _currentProgrammes = programmes;
    _currentSymptomCatalog = null;

    await _startRecordingInternal(
      patientId: patientId,
      encounterId: encounterId,
      mode: ScribeMode.formPrefill,
    );
  }

  /// Start recording for triage mode.
  ///
  /// This extracts symptom codes from the audio that can be
  /// used to determine which pathways to activate.
  Future<void> startRecordingForTriage({
    String? patientId,
    String? encounterId,
    required List<String> symptomCatalog,
  }) async {
    debugPrint('[AIScribe] Starting triage recording with ${symptomCatalog.length} symptom codes');

    _currentMode = ScribeMode.triage;
    _currentSymptomCatalog = symptomCatalog;
    _currentFormSchema = null;
    _currentProgrammes = const [];

    await _startRecordingInternal(
      patientId: patientId,
      encounterId: encounterId,
      mode: ScribeMode.triage,
    );
  }

  Future<void> _startRecordingInternal({
    String? patientId,
    String? encounterId,
    required ScribeMode mode,
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

      _session = ScribeSession(state: ScribeState.recording, mode: mode);
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
    
    debugPrint('[AIScribe] Stopping recording after ${_session.elapsedSeconds}s');

    try {
      final path = await _recorder.stop();
      if (path == null) {
        _setError('Recording produced no output.');
        return;
      }
      _recordingPath = path;
      debugPrint('[AIScribe] Recording saved to: $path');
    } catch (e) {
      debugPrint('[AIScribe] Stop recording failed: $e');
      _setError('Stop recording failed: $e');
      return;
    }

    _session = _session.copyWith(
      state: ScribeState.uploading,
      uploadProgressPercent: 0,
    );
    notifyListeners();

    debugPrint('[AIScribe] Uploading audio (mode=${_currentMode.name})...');

    try {
      final file = File(_recordingPath!);
      final String jobId;
      
      // Submit based on mode
      switch (_currentMode) {
        case ScribeMode.formPrefill:
          jobId = await _api.submitAudioForFormPrefill(
            file,
            formSchema: _currentFormSchema ?? [],
            patientId: patientId,
            encounterId: encounterId,
            programmes: _currentProgrammes,
          );
          break;
        case ScribeMode.triage:
          jobId = await _api.submitAudioForTriage(
            file,
            symptomCatalog: _currentSymptomCatalog ?? [],
            patientId: patientId,
            encounterId: encounterId,
          );
          break;
        case ScribeMode.soap:
          jobId = await _api.submitAudio(
            file,
            patientId: patientId,
            encounterId: encounterId,
            programme: programme,
          );
      }

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

  // ── Form prefill field management ─────────────────────────────────────────

  /// Accept a single AI-extracted field.
  void acceptField(String fieldId) {
    final result = _session.formPrefillResult;
    if (result == null) return;
    
    final field = result.getField(fieldId);
    debugPrint('[AIScribe] Field accepted: $fieldId = ${field?.value}');
    
    final updatedFields = result.fields.map((f) {
      if (f.fieldId == fieldId && f.source == FieldSource.aiPending) {
        return f.accept();
      }
      return f;
    }).toList();
    
    _session = _session.copyWith(
      formPrefillResult: FormPrefillResult(
        fields: updatedFields,
        unmappedFindings: result.unmappedFindings,
        transcriptText: result.transcriptText,
        noteId: result.noteId,
      ),
    );
    notifyListeners();
  }

  /// Reject a single AI-extracted field.
  void rejectField(String fieldId) {
    final result = _session.formPrefillResult;
    if (result == null) return;
    
    final field = result.getField(fieldId);
    debugPrint('[AIScribe] Field rejected: $fieldId (was: ${field?.value})');
    
    final updatedFields = result.fields.map((f) {
      if (f.fieldId == fieldId && f.source == FieldSource.aiPending) {
        return f.reject();
      }
      return f;
    }).toList();
    
    _session = _session.copyWith(
      formPrefillResult: FormPrefillResult(
        fields: updatedFields,
        unmappedFindings: result.unmappedFindings,
        transcriptText: result.transcriptText,
        noteId: result.noteId,
      ),
    );
    notifyListeners();
  }

  /// Modify a single AI-extracted field with a new value.
  void modifyField(String fieldId, dynamic newValue) {
    final result = _session.formPrefillResult;
    if (result == null) return;
    
    final field = result.getField(fieldId);
    debugPrint('[AIScribe] Field modified: $fieldId: ${field?.value} → $newValue');
    
    final updatedFields = result.fields.map((f) {
      if (f.fieldId == fieldId) {
        return f.modify(newValue);
      }
      return f;
    }).toList();
    
    _session = _session.copyWith(
      formPrefillResult: FormPrefillResult(
        fields: updatedFields,
        unmappedFindings: result.unmappedFindings,
        transcriptText: result.transcriptText,
        noteId: result.noteId,
      ),
    );
    notifyListeners();
  }

  /// Accept all pending AI-extracted fields.
  void acceptAllFields() {
    final result = _session.formPrefillResult;
    if (result == null) return;
    
    final pendingCount = result.fields.where((f) => f.source == FieldSource.aiPending).length;
    debugPrint('[AIScribe] Accepting all $pendingCount pending fields');
    
    final updatedFields = result.fields.map((f) {
      if (f.source == FieldSource.aiPending) {
        return f.accept();
      }
      return f;
    }).toList();
    
    _session = _session.copyWith(
      formPrefillResult: FormPrefillResult(
        fields: updatedFields,
        unmappedFindings: result.unmappedFindings,
        transcriptText: result.transcriptText,
        noteId: result.noteId,
      ),
    );
    notifyListeners();
  }

  /// Reject all pending AI-extracted fields.
  void rejectAllFields() {
    final result = _session.formPrefillResult;
    if (result == null) return;
    
    final pendingCount = result.fields.where((f) => f.source == FieldSource.aiPending).length;
    debugPrint('[AIScribe] Rejecting all $pendingCount pending fields');
    
    final updatedFields = result.fields.map((f) {
      if (f.source == FieldSource.aiPending) {
        return f.reject();
      }
      return f;
    }).toList();
    
    _session = _session.copyWith(
      formPrefillResult: FormPrefillResult(
        fields: updatedFields,
        unmappedFindings: result.unmappedFindings,
        transcriptText: result.transcriptText,
        noteId: result.noteId,
      ),
    );
    notifyListeners();
  }

  /// Get an extracted field by ID.
  AIExtractedField? getField(String fieldId) =>
      _session.formPrefillResult?.getField(fieldId);

  /// Get all extracted fields for audit.
  List<Map<String, dynamic>> getAuditTrail() {
    final result = _session.formPrefillResult;
    if (result == null) return [];
    return result.fields.map((f) => f.toAuditEntry()).toList();
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
    debugPrint('[AIScribe] Starting to poll job: $jobId');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      final result = await _api.pollResult(jobId);
      if (result == null) return; // transient network issue — keep polling

      switch (result.status) {
        case ScribeJobStatus.completed:
          _pollTimer?.cancel();
          debugPrint('[AIScribe] Job completed: mode=${result.mode.name}');
          
          // Handle result based on mode
          if (result.mode == ScribeMode.formPrefill && result.formPrefill != null) {
            // Form prefill mode - populate form fields
            final fields = result.formPrefill!.fields;
            debugPrint('[AIScribe] Form prefill extracted ${fields.length} fields:');
            for (final f in fields) {
              debugPrint('[AIScribe]   → ${f.fieldId}: ${f.value} '
                  '(confidence=${(f.confidence * 100).toStringAsFixed(0)}%)');
            }
            if (result.formPrefill!.unmappedFindings.isNotEmpty) {
              debugPrint('[AIScribe] Unmapped findings: ${result.formPrefill!.unmappedFindings}');
            }

            _session = _session.copyWith(
              state: ScribeState.reviewReady,
              noteId: result.noteId,
              transcriptText: result.transcriptText,
              formPrefillResult: result.formPrefill,
            );
            notifyListeners();
          } else if (result.mode == ScribeMode.triage && result.triageResult != null) {
            // Triage mode - just mark complete with triage results
            debugPrint('[AIScribe] Triage extracted symptoms: ${result.triageResult}');
            // The caller will handle the symptom codes
            _session = _session.copyWith(
              state: ScribeState.reviewReady,
              noteId: result.noteId,
              transcriptText: result.transcriptText,
            );
            notifyListeners();
          } else {
            // SOAP mode (default) - get full note details
            debugPrint('[AIScribe] SOAP note received, noteId=${result.noteId}');
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
          }
          break;

        case ScribeJobStatus.failed:
          _pollTimer?.cancel();
          debugPrint('[AIScribe] Job failed: ${result.errorMessage}');
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
