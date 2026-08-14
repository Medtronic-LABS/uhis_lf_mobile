import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/api/scribe_api_service.dart';
import '../../core/audio/scribe_record_config.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/domain_exceptions.dart';
import '../../core/preferences/scribe_audio_settings_notifier.dart';
import '../visit/triage/ai_scribe_triage_vocab.dart';
import '../visit/triage/triage_transcript_matcher.dart';
import 'form_field_schema_builder.dart';
import 'models/ai_extracted_field.dart';
import 'scribe_permission_service.dart';
import 'scribe_session.dart';

/// Manages the full scribe lifecycle for one visit:
/// permission → record → upload → poll → review → accept/reject.
///
/// Provide above the visit form via [ChangeNotifierProvider].
class ScribeController extends ChangeNotifier {
  ScribeController({
    required ScribeApiService api,
    required ScribePermissionService permissionService,
    ScribeAudioSettingsNotifier? audioSettings,
  }) : _api = api,
       _perm = permissionService,
       _audioSettings = audioSettings;

  final ScribeApiService _api;
  final ScribePermissionService _perm;

  /// Supplies the on-device microphone capture preference. Nullable so
  /// tests (and any caller without the provider registered) fall back to
  /// [AppConfig.rawMicCaptureDefault] rather than needing the whole
  /// preferences stack — same accommodation [RealtimeAsrController] makes
  /// for [VadTuningNotifier].
  final ScribeAudioSettingsNotifier? _audioSettings;

  /// Read at each recording start, not cached, so flipping the setting
  /// applies to the next recording without restarting the app.
  RecordConfig get _captureConfig => ScribeRecordConfig.batch(
    rawMicCapture:
        _audioSettings?.rawMicCaptureEnabled ?? AppConfig.rawMicCaptureDefault,
  );

  /// Captures the audio file uploaded to the backend (`record` / AAC-LC).
  final AudioRecorder _audioRecorder = AudioRecorder();

  ScribeSession _session = const ScribeSession();
  ScribeSession get session => _session;

  /// File extension for captured audio — matches [ScribeRecordConfig.batch]
  /// (`AudioEncoder.aacLc`).
  static const String _recordingExtension = 'm4a';

  Timer? _elapsedTimer;
  Timer? _pollTimer;
  String? _recordingPath;

  static const Duration _pollInterval = Duration(milliseconds: 2500);
  // Triage jobs are shorter (ASR only, no SOAP render); poll faster so the
  // SK sees symptom chips appear within ~1s of the worker finishing.
  static const Duration _triagePollInterval = Duration(milliseconds: 1000);
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
  String? _triageNotes;

  /// Set before starting a form recording to include Step 1 extra symptom
  /// notes in the SOAP generation context.
  void setTriageNotes(String? notes) {
    _triageNotes = notes?.trim().isEmpty == true ? null : notes?.trim();
  }

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
      final ts = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${dir.path}/scribe_$ts.$_recordingExtension';
      await _audioRecorder.start(_captureConfig, path: _recordingPath!);

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
        errorMessage: ScribeStrings.recordingStartFailed,
      );
      notifyListeners();
    }
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
      final ts = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${dir.path}/scribe_$ts.$_recordingExtension';
      await _audioRecorder.start(_captureConfig, path: _recordingPath!);

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
        errorMessage: ScribeStrings.recordingStartFailed,
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

    // Flip to uploading immediately so the banner swaps recording → spinner
    // without waiting for the native recorder stop call.
    _session = _session.copyWith(
      state: ScribeState.uploading,
      uploadProgressPercent: 0,
    );
    notifyListeners();

    debugPrint(
      '[AIScribe] Stopping recording after ${_session.elapsedSeconds}s',
    );

    final effectivePath = await _stopRecorderSafely();
    if (effectivePath == null) {
      debugPrint(
        '[AIScribe] recording not finalized — not uploading truncated audio',
      );
      _setRecordingError(ScribeStrings.recordingNotFinalized);
      return;
    }
    final audioFile = File(effectivePath);
    if (!audioFile.existsSync() || audioFile.lengthSync() == 0) {
      debugPrint('[AIScribe] Audio file missing or empty at $effectivePath');
      _setRecordingError(ScribeStrings.recordingNoOutput);
      return;
    }
    _recordingPath = effectivePath;
    debugPrint('[AIScribe] Recording saved to: $effectivePath');

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
            triageNotes: _triageNotes,
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
          jobId = await _api.submitAudioWithMode(
            file,
            mode: ScribeMode.soap,
            patientId: patientId,
            encounterId: encounterId,
            programmes: programme != null ? [programme] : [],
            triageNotes: _triageNotes,
          );
      }

      _session = _session.copyWith(state: ScribeState.processing, jobId: jobId);
      notifyListeners();

      _startPolling(jobId);
    } catch (e) {
      _setError(NetworkErrorMapper.friendly(e));
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
      _setError(NetworkErrorMapper.friendly(e));
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
      _setError(NetworkErrorMapper.friendly(e));
    }
  }

  /// Reset the current scribe session back to idle.
  ///
  /// Used by triage mode after extracted symptoms are consumed by
  /// [TriageViewModel], so the banner returns to the "tap to record" state.
  void resetSession() {
    debugPrint('[AIScribe] resetSession() — back to idle');
    _elapsedTimer?.cancel();
    _pollTimer?.cancel();
    _recordingPath = null;
    _currentFormSchema = null;
    _currentSymptomCatalog = null;
    _currentProgrammes = const [];
    _currentMode = ScribeMode.soap;
    _triageNotes = null;
    _session = const ScribeSession();
    notifyListeners();
  }

  /// Surface a user-visible error without throwing (e.g. empty triage result).
  void surfaceError(String message, {ScribeMode? mode}) {
    _elapsedTimer?.cancel();
    _pollTimer?.cancel();
    _session = ScribeSession(
      state: ScribeState.error,
      errorMessage: message,
      mode: mode ?? _currentMode,
    );
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


  /// Stops capture and waits for the recording to be fully finalized before
  /// returning its path. Returns null when the file never finalized (so the
  /// caller fails instead of uploading a truncated, undecodable file).
  Future<String?> _stopRecorderSafely() async {
    final String? capturedPath = await _audioRecorder
        .stop()
        .catchError((Object e) {
      debugPrint('[AIScribe] audioRecorder stop() error: $e');
      return null;
    });

    final path = capturedPath ?? _recordingPath;
    if (path != null) {
      final size = File(path).existsSync() ? File(path).lengthSync() : 0;
      debugPrint('[AIScribe] audio captured: path=$path size=${size}B');
    }

    notifyListeners();
    return path;
  }

  /// True when the recording has been finalized and is decodable.
  ///
  /// - WAV: the `RIFF`/`WAVE` header is written only when stop() patches the
  ///   placeholder, so its presence at the head is a precise finalized signal.
  /// - MP4/M4A: finalization writes the `moov` atom near the end of the file.
  ///
  /// A file lacking the relevant marker is still being written (or truncated)
  /// and must not be uploaded.
  void _startPolling(String jobId) {
    final interval = _currentMode == ScribeMode.triage ? _triagePollInterval : _pollInterval;
    debugPrint('[AIScribe] Starting to poll job: $jobId (interval=${interval.inMilliseconds}ms)');
    _pollTimer?.cancel();
    _pollStartedAt = DateTime.now();
    _consecutivePollErrors = 0;
    _pollInFlight = false;
    _pollTimer = Timer.periodic(interval, (timer) {
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
          break;

        case ScribeJobStatus.failed:
          timer.cancel();
          _pollTimer?.cancel();
          debugPrint('[AIScribe] Job failed: ${result.errorMessage}');
          _setRecordingError(
            result.errorMessage ?? ScribeStrings.transcriptionFailed,
          );
          break;

        default:
          // queued / processing — keep polling, but surface partial transcript
          // as liveTranscript so the banner shows what was heard so far.
          final partial = result.transcriptText;
          if (partial != null &&
              partial.isNotEmpty &&
              partial != _session.liveTranscript) {
            _session = _session.copyWith(liveTranscript: partial);
            notifyListeners();
          }
          break;
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

  /// Triage banner completion — lands on [ScribeState.reviewReady] when at
  /// least one symptom was extracted; otherwise [ScribeState.error].
  void _completeTriageJob({required ScribeJobResult? result}) {
    _pollTimer?.cancel();

    var triageResult = result?.triageResult;
    if (triageResult != null && triageResult.symptomCodes.isNotEmpty) {
      debugPrint(
        '[AIScribe] triage server payload: '
        '${triageResult.symptomCodes.length} codes '
        '(${triageResult.codes.join(', ')})',
      );
    }
    if (triageResult == null || triageResult.symptomCodes.isEmpty) {
      final fallbackText = TriageTranscriptMatcher.fallbackSearchText(
        transcriptText: result?.transcriptText,
        transcriptTranslation: result?.transcriptTranslation,
        soapSubjective: result?.soap?.subjective,
        soapObjective: result?.soap?.objective,
        soapAssessment: result?.soap?.assessment,
      );
      if (fallbackText != null) {
        triageResult = TriageTranscriptMatcher.match(
          fallbackText,
          catalog: _currentSymptomCatalog ?? AiScribeTriageVocab.codes,
          noteId: result?.noteId,
        );
        if (triageResult != null) {
          debugPrint(
            '[AIScribe] Triage fallback matched '
            '${triageResult.symptomCodes.length} codes from transcript/soap',
          );
        }
      }
    }

    final hasPayload =
        triageResult != null && triageResult.symptomCodes.isNotEmpty;
    debugPrint('[AIScribe] Triage job finished (payload=$hasPayload)');

    if (!hasPayload) {
      surfaceError(
        SymptomPickerStrings.scribeBannerNoSymptomsSubtitle,
        mode: ScribeMode.triage,
      );
      return;
    }

    _session = _session.copyWith(
      state: ScribeState.reviewReady,
      mode: ScribeMode.triage,
      noteId: result?.noteId,
      transcriptText: result?.transcriptText ?? triageResult.transcriptText,
      triageExtractionResult: triageResult,
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
      _setError(NetworkErrorMapper.friendly(e));
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

  /// Error during the record/finalize phase. Preserves the active mode so the
  /// triage / form-prefill banners render their own error affordance.
  void _setRecordingError(String message) {
    _session = _session.copyWith(
      state: ScribeState.error,
      errorMessage: message,
      mode: _currentMode,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _pollTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

}
