import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/scribe_api_service.dart';
import '../../core/constants/app_strings.dart';
import 'form_field_schema_builder.dart';
import 'models/ai_extracted_field.dart';
import 'scribe_permission_service.dart';
import 'scribe_session.dart';
import 'soap_field_extractor.dart';

/// Manages the full scribe lifecycle for one visit:
/// permission → record → upload → poll → review → accept/reject.
///
/// Provide above [VisitAssessmentStep] via [ChangeNotifierProvider].
class ScribeController extends ChangeNotifier {
  ScribeController({
    required ScribeApiService api,
    required ScribePermissionService permissionService,
  }) : _api = api,
       _perm = permissionService;

  final ScribeApiService _api;
  final ScribePermissionService _perm;
  /// Records the consultation audio AND drives the live recording waveform.
  /// One mic, one recorder: audio_waveforms owns capture so the visualizer
  /// reacts to the same signal that gets uploaded for transcription.
  final RecorderController _recorder = RecorderController();

  ScribeSession _session = const ScribeSession();
  ScribeSession get session => _session;

  /// Live recorder controller backing the in-circle waveform visualizer.
  /// Owned here in the scribe layer; the banner widget only renders from it.
  RecorderController get waveformRecorder => _recorder;

  /// Capture settings — AAC-LC mono @16 kHz / 32 kbps, matched to what the AI
  /// Scribe service already accepts for transcription (same as before).
  static const RecorderSettings _recorderSettings = RecorderSettings(
    androidEncoderSettings: AndroidEncoderSettings(
      androidEncoder: AndroidEncoder.aacLc,
    ),
    sampleRate: 16000,
    bitRate: 32000,
  );

  Timer? _elapsedTimer;
  Timer? _pollTimer;
  String? _recordingPath;

  static const Duration _pollInterval = Duration(milliseconds: 2500);
  static const Duration _pollTimeout = Duration(seconds: 90);
  static const int _maxConsecutivePollErrors = 5;

  DateTime? _pollStartedAt;
  int _consecutivePollErrors = 0;
  bool _pollInFlight = false;

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

      await _recorder.record(
        path: _recordingPath,
        recorderSettings: _recorderSettings,
      );

      _session = const ScribeSession(state: ScribeState.recording);
      notifyListeners();

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _session = _session.copyWith(
          elapsedSeconds: _session.elapsedSeconds + 1,
        );
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
    debugPrint(
      '[AIScribe] Starting form prefill recording for programmes: $programmes',
    );
    debugPrint(
      '[AIScribe] Form schema has ${formSchema.length} fields: '
      '${formSchema.map((f) => f.fieldId).join(', ')}',
    );

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
    debugPrint(
      '[AIScribe] Starting triage recording with ${symptomCatalog.length} symptom codes',
    );

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

      await _recorder.record(
        path: _recordingPath,
        recorderSettings: _recorderSettings,
      );

      _session = ScribeSession(state: ScribeState.recording, mode: mode);
      notifyListeners();

      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _session = _session.copyWith(
          elapsedSeconds: _session.elapsedSeconds + 1,
        );
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

    // Flip to uploading immediately so the banner swaps waveform → spinner
    // without waiting for the native recorder stop call.
    _session = _session.copyWith(
      state: ScribeState.uploading,
      uploadProgressPercent: 0,
    );
    notifyListeners();

    debugPrint(
      '[AIScribe] Stopping recording after ${_session.elapsedSeconds}s',
    );

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

      _session = _session.copyWith(state: ScribeState.processing, jobId: jobId);
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

  /// Reset the current scribe session back to idle.
  ///
  /// Used by triage mode after extracted symptoms are consumed by
  /// [TriageViewModel], so the banner returns to the "tap to record" state.
  void resetSession() {
    _elapsedTimer?.cancel();
    _pollTimer?.cancel();
    _recordingPath = null;
    _currentFormSchema = null;
    _currentSymptomCatalog = null;
    _currentProgrammes = const [];
    _currentMode = ScribeMode.soap;
    _session = const ScribeSession();
    notifyListeners();
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
    debugPrint(
      '[AIScribe] Field modified: $fieldId: ${field?.value} → $newValue',
    );

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

    final pendingCount = result.fields
        .where((f) => f.source == FieldSource.aiPending)
        .length;
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

    final pendingCount = result.fields
        .where((f) => f.source == FieldSource.aiPending)
        .length;
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
    _pollStartedAt = DateTime.now();
    _consecutivePollErrors = 0;
    _pollInFlight = false;
    _pollTimer = Timer.periodic(_pollInterval, (timer) {
      unawaited(_pollOnce(jobId, timer));
    });
  }

  Future<void> _pollOnce(String jobId, Timer timer) async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      if (_pollStartedAt != null &&
          DateTime.now().difference(_pollStartedAt!) > _pollTimeout) {
        timer.cancel();
        _pollTimer?.cancel();
        debugPrint('[AIScribe] Poll timeout for job $jobId');
        if (_currentMode == ScribeMode.triage) {
          _completeTriageJob(result: null);
        } else {
          _setError(ScribeStrings.pollTimeout);
        }
        return;
      }

      final result = await _api.pollResult(jobId);
      if (result == null) {
        _consecutivePollErrors++;
        if (_consecutivePollErrors >= _maxConsecutivePollErrors) {
          timer.cancel();
          _pollTimer?.cancel();
          if (_currentMode == ScribeMode.triage) {
            _completeTriageJob(result: null);
          } else {
            _setError(ScribeStrings.pollUnreachable);
          }
        }
        return;
      }

      _consecutivePollErrors = 0;

      switch (result.status) {
        case ScribeJobStatus.completed:
          timer.cancel();
          _pollTimer?.cancel();
          debugPrint('[AIScribe] Job completed: mode=${result.mode.name}');

          // Handle result based on mode
          if (result.mode == ScribeMode.formPrefill &&
              result.formPrefill != null) {
            // Form prefill mode - auto-populate form fields inline (no review sheet)
            final fields = result.formPrefill!.fields;
            debugPrint(
              '[AIScribe] Form prefill extracted ${fields.length} fields:',
            );
            for (final f in fields) {
              debugPrint(
                '[AIScribe]   → ${f.fieldId}: ${f.value} '
                '(confidence=${(f.confidence * 100).toStringAsFixed(0)}%)',
              );
            }
            if (result.formPrefill!.unmappedFindings.isNotEmpty) {
              debugPrint(
                '[AIScribe] Unmapped findings: ${result.formPrefill!.unmappedFindings}',
              );
            }

            // Use fieldsPopulated state - fields appear inline, no review modal
            _session = _session.copyWith(
              state: ScribeState.fieldsPopulated,
              noteId: result.noteId,
              transcriptText: result.transcriptText,
              formPrefillResult: result.formPrefill,
              fieldsJustPopulated: true,
            );
            debugPrint(
              '[AIScribe] Fields populated inline - ${fields.length} fields ready for review in form',
            );
            notifyListeners();

            // Clear the "just populated" flag after a delay
            Future.delayed(const Duration(seconds: 5), () {
              if (_session.fieldsJustPopulated) {
                _session = _session.copyWith(fieldsJustPopulated: false);
                notifyListeners();
              }
            });
          } else if (_currentMode == ScribeMode.triage ||
              result.mode == ScribeMode.triage) {
            _completeTriageJob(result: result);
          } else {
            // SOAP mode (default) - get full note details
            debugPrint(
              '[AIScribe] SOAP note received, noteId=${result.noteId}',
            );
            ScribeRationale? rationale = result.rationale;
            SoapNote? soap = result.soap;
            debugPrint(
              '[AIScribe] Initial soap from result: ${soap != null}, subjective=${soap?.subjective?.length ?? 0} chars',
            );

            if (result.noteId != null) {
              final note = await _api.getNote(result.noteId!);
              debugPrint(
                '[AIScribe] Fetched note: ${note != null}, note.soap=${note?.soap != null}',
              );
              if (note != null) {
                soap = note.soap ?? soap;
                rationale = note.rationale ?? rationale;
              }
            }

            debugPrint('[AIScribe] Current mode: ${_currentMode.name}');
            debugPrint(
              '[AIScribe] Final SOAP: subjective=${soap?.subjective?.length ?? 0} chars, objective=${soap?.objective?.length ?? 0} chars',
            );
            if (soap?.subjective != null && soap!.subjective!.isNotEmpty) {
              debugPrint(
                '[AIScribe] SOAP subjective: ${soap.subjective!.substring(0, soap.subjective!.length.clamp(0, 200))}',
              );
            }
            if (soap?.objective != null && soap!.objective!.isNotEmpty) {
              debugPrint(
                '[AIScribe] SOAP objective: ${soap.objective!.substring(0, soap.objective!.length.clamp(0, 200))}',
              );
            }

            // If we're in formPrefill mode client-side but backend returned SOAP,
            // extract fields from SOAP and use the embedded flow
            if (_currentMode == ScribeMode.formPrefill && soap != null) {
              debugPrint(
                '[AIScribe] Converting SOAP to form fields (backend fallback)',
              );
              final extractedFields = SoapFieldExtractor.extractFromSoap(soap);
              debugPrint(
                '[AIScribe] Extracted ${extractedFields.length} fields from SOAP:',
              );
              for (final f in extractedFields) {
                debugPrint(
                  '[AIScribe]   → ${f.fieldId}: ${f.value} '
                  '(confidence=${(f.confidence * 100).toStringAsFixed(0)}%)',
                );
              }

              _session = _session.copyWith(
                state: ScribeState.fieldsPopulated,
                noteId: result.noteId,
                transcriptText: result.transcriptText,
                soap: soap,
                rationale: rationale,
                formPrefillResult: FormPrefillResult(
                  fields: extractedFields,
                  unmappedFindings: [],
                  transcriptText: result.transcriptText,
                  noteId: result.noteId,
                ),
                fieldsJustPopulated: true,
              );
              debugPrint(
                '[AIScribe] Fields populated inline from SOAP - ${extractedFields.length} fields ready',
              );
              notifyListeners();

              // Clear the "just populated" flag after a delay
              Future.delayed(const Duration(seconds: 5), () {
                if (_session.fieldsJustPopulated) {
                  _session = _session.copyWith(fieldsJustPopulated: false);
                  notifyListeners();
                }
              });
            } else {
              // Standard SOAP mode - show review sheet
              _session = _session.copyWith(
                state: ScribeState.reviewReady,
                noteId: result.noteId,
                soap: soap,
                transcriptText: result.transcriptText,
                rationale: rationale,
              );
              notifyListeners();
            }
          }
          break;

        case ScribeJobStatus.failed:
          timer.cancel();
          _pollTimer?.cancel();
          debugPrint('[AIScribe] Job failed: ${result.errorMessage}');
          _setError(result.errorMessage ?? ScribeStrings.transcriptionFailed);
          break;

        default:
          break; // queued / processing — keep polling
      }
    } catch (e, st) {
      debugPrint('[AIScribe] Poll error: $e\n$st');
      _consecutivePollErrors++;
      if (_consecutivePollErrors >= _maxConsecutivePollErrors) {
        timer.cancel();
        _pollTimer?.cancel();
        if (_currentMode == ScribeMode.triage) {
          _completeTriageJob(result: null);
        } else {
          _setError(ScribeStrings.pollUnreachable);
        }
      }
    } finally {
      _pollInFlight = false;
    }
  }

  /// Triage banner completion — always lands on [ScribeState.reviewReady] so
  /// the Step 1 mic orb can show the green check, even when the backend omits
  /// the triage payload or the poll times out.
  void _completeTriageJob({required ScribeJobResult? result}) {
    _pollTimer?.cancel();
    debugPrint(
      '[AIScribe] Triage job finished '
      '(payload=${result?.triageResult != null})',
    );
    _session = _session.copyWith(
      state: ScribeState.reviewReady,
      mode: ScribeMode.triage,
      noteId: result?.noteId,
      transcriptText: result?.transcriptText,
      triageExtractionResult: result?.triageResult,
    );
    notifyListeners();
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
      _session = _session.copyWith(state: ScribeState.processing, jobId: jobId);
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
