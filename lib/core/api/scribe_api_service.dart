import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../features/scribe/form_field_schema_builder.dart';
import '../../features/scribe/models/ai_extracted_field.dart';
import '../config/app_config.dart';
import 'api_repository.dart';
import 'endpoints.dart';

/// Mode for AI scribe transcription.
enum ScribeMode {
  /// Traditional SOAP note extraction.
  soap,

  /// Form field extraction with schema.
  formPrefill,

  /// Triage symptom extraction.
  triage,
}

/// SOAP note produced by the scribe service.
class SoapNote {
  const SoapNote({
    this.subjective,
    this.objective,
    this.assessment,
    this.plan,
  });

  final String? subjective;
  final String? objective;
  final String? assessment;
  final String? plan;

  factory SoapNote.fromJson(Map<String, dynamic> j) => SoapNote(
        subjective: j['subjective'] as String?,
        objective: j['objective'] as String?,
        assessment: j['assessment'] as String?,
        plan: j['plan'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'subjective': ?subjective,
        'objective': ?objective,
        'assessment': ?assessment,
        'plan': ?plan,
      };

  SoapNote copyWith({
    String? subjective,
    String? objective,
    String? assessment,
    String? plan,
  }) =>
      SoapNote(
        subjective: subjective ?? this.subjective,
        objective: objective ?? this.objective,
        assessment: assessment ?? this.assessment,
        plan: plan ?? this.plan,
      );
}

/// Rationale payload attached to every scribe result.
class ScribeRationale {
  const ScribeRationale({
    required this.confidence,
    required this.humanReviewRequired,
    this.modelVersion,
    this.asrProvider,
    this.llmModel,
  });

  final double confidence;
  final bool humanReviewRequired;
  final String? modelVersion;
  final String? asrProvider;
  final String? llmModel;

  factory ScribeRationale.fromJson(Map<String, dynamic> j) => ScribeRationale(
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        humanReviewRequired: j['humanReviewRequired'] as bool? ?? true,
        modelVersion: j['modelVersion'] as String?,
        asrProvider: j['asrProvider'] as String?,
        llmModel: j['llmModel'] as String?,
      );
}

/// Status of an async transcription job.
enum ScribeJobStatus { queued, processing, completed, failed }

ScribeJobStatus _parseStatus(String? s) {
  switch (s) {
    case 'completed':
      return ScribeJobStatus.completed;
    case 'failed':
      return ScribeJobStatus.failed;
    case 'processing':
      return ScribeJobStatus.processing;
    default:
      return ScribeJobStatus.queued;
  }
}

/// Polling result from GET /scribe/results/{jobId}.
class ScribeJobResult {
  const ScribeJobResult({
    required this.jobId,
    required this.status,
    this.mode = ScribeMode.soap,
    this.soap,
    this.formPrefill,
    this.triageResult,
    this.transcriptText,
    this.transcriptTranslation,
    this.noteId,
    this.rationale,
    this.errorMessage,
  });

  final String jobId;
  final ScribeJobStatus status;
  final ScribeMode mode;
  final SoapNote? soap;
  final FormPrefillResult? formPrefill;
  final TriageExtractionResult? triageResult;
  final String? transcriptText;
  final String? transcriptTranslation;
  final String? noteId;
  final ScribeRationale? rationale;
  final String? errorMessage;

  factory ScribeJobResult.fromJson(Map<String, dynamic> j) {
    final soapJson = j['soap'] as Map<String, dynamic>?;
    debugPrint('[ScribeJobResult] fromJson - soapJson: ${soapJson?.keys.toList()}');
    if (soapJson != null) {
      debugPrint('[ScribeJobResult] fromJson - subjective: ${soapJson['subjective']?.toString().substring(0, (soapJson['subjective']?.toString().length ?? 0).clamp(0, 100))}');
    }
    final ratJson = j['rationale'] as Map<String, dynamic>?;
    final errJson = j['error'] as Map<String, dynamic>?;
    final transcriptJson = j['transcript'] as Map<String, dynamic>?;
    final formPrefillJson = j['formPrefill'] as Map<String, dynamic>?;
    final triageJson = j['triage'] as Map<String, dynamic>?;
    final detectedSymptoms = (j['detectedSymptoms'] as List?)
        ?.whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList() ?? const <String>[];

    // Determine mode from response
    ScribeMode mode = ScribeMode.soap;
    if (formPrefillJson != null) {
      mode = ScribeMode.formPrefill;
    } else if (triageJson != null || detectedSymptoms.isNotEmpty) {
      mode = ScribeMode.triage;
    }

    return ScribeJobResult(
      jobId: j['jobId'] as String? ?? '',
      status: _parseStatus(j['status'] as String?),
      mode: mode,
      soap: soapJson != null ? SoapNote.fromJson(soapJson) : null,
      formPrefill: formPrefillJson != null
          ? FormPrefillResult.fromJson({
              ...formPrefillJson,
              'transcriptText': transcriptJson?['text'],
              'noteId': j['noteId'],
            })
          : null,
      triageResult: triageJson != null
          ? TriageExtractionResult.fromJson({
              ...triageJson,
              'transcriptText': transcriptJson?['text'],
              'noteId': j['noteId'],
            })
          : detectedSymptoms.isNotEmpty
              ? TriageExtractionResult(
                  symptomCodes: detectedSymptoms
                      .map((code) => AIExtractedField(
                            fieldId: code,
                            value: true,
                            confidence: 1.0,
                            source: FieldSource.aiPending,
                            extractedAt: DateTime.now(),
                          ))
                      .toList(),
                  transcriptText: transcriptJson?['text'] as String?,
                  noteId: j['noteId'] as String?,
                )
              : null,
      transcriptText: transcriptJson?['text'] as String?,
      transcriptTranslation: transcriptJson?['translation'] as String?,
      noteId: j['noteId'] as String?,
      rationale: ratJson != null ? ScribeRationale.fromJson(ratJson) : null,
      errorMessage: errJson?['message'] as String?,
    );
  }
}

/// HTTP client for the ai-scribe-service.
///
/// Routes to [AppConfig.scribeBaseUrl] which defaults to the local container
/// (`http://10.0.2.2:8095/` from the Android emulator). The nginx gateway
/// adds an `/ai-scribe-service/` routing prefix; the container itself does
/// not. [_scribeUrl] strips that prefix before building the absolute URL.
class ScribeApiService extends ApiRepository {
  ScribeApiService(super.api);

  static const int _chunkThresholdBytes = 1 * 1024 * 1024; // 1 MB

  static const String _nginxPrefix = '/ai-scribe-service';

  static String _scribeUrl(String path) {
    final p = path.startsWith(_nginxPrefix) ? path.substring(_nginxPrefix.length) : path;
    final base = AppConfig.scribeBaseUrl;
    return base.endsWith('/') ? '$base${p.startsWith('/') ? p.substring(1) : p}' : '$base$p';
  }

  /// Submit audio for async transcription.
  ///
  /// Uses chunked upload when file ≥ 1 MB (2G-resilient path).
  /// Returns jobId on success.
  Future<String> submitAudio(
    File audioFile, {
    String? patientId,
    String? encounterId,
    String? programme,
    String language = 'bn',
  }) async {
    return submitAudioWithMode(
      audioFile,
      mode: ScribeMode.soap,
      patientId: patientId,
      encounterId: encounterId,
      programmes: programme != null ? [programme] : [],
      language: language,
    );
  }

  /// Submit audio for form field extraction (form_prefill mode).
  ///
  /// Extracts field values matching the provided [formSchema] from the
  /// consultation recording. Returns structured fields with confidence
  /// scores and source segments for audit trail.
  Future<String> submitAudioForFormPrefill(
    File audioFile, {
    required List<FormFieldSchema> formSchema,
    String? patientId,
    String? encounterId,
    List<String> programmes = const [],
    String language = 'bn',
  }) async {
    return submitAudioWithMode(
      audioFile,
      mode: ScribeMode.formPrefill,
      patientId: patientId,
      encounterId: encounterId,
      programmes: programmes,
      language: language,
      formSchema: formSchema,
    );
  }

  /// Submit audio for triage symptom extraction (triage mode).
  ///
  /// Extracts symptom codes from the consultation recording based on
  /// the provided [symptomCatalog]. Returns symptom codes with confidence.
  Future<String> submitAudioForTriage(
    File audioFile, {
    required List<String> symptomCatalog,
    String? patientId,
    String? encounterId,
    String language = 'bn',
  }) async {
    return submitAudioWithMode(
      audioFile,
      mode: ScribeMode.triage,
      patientId: patientId,
      encounterId: encounterId,
      language: language,
      symptomCatalog: symptomCatalog,
    );
  }

  /// Submit audio with explicit mode selection.
  Future<String> submitAudioWithMode(
    File audioFile, {
    required ScribeMode mode,
    String? patientId,
    String? encounterId,
    List<String> programmes = const [],
    String language = 'bn',
    List<FormFieldSchema>? formSchema,
    List<String>? symptomCatalog,
  }) async {
    final size = await audioFile.length();
    if (size >= _chunkThresholdBytes) {
      return _chunkedUploadWithMode(
        audioFile,
        mode: mode,
        patientId: patientId,
        encounterId: encounterId,
        programmes: programmes,
        language: language,
        formSchema: formSchema,
        symptomCatalog: symptomCatalog,
      );
    }
    return _simpleUploadWithMode(
      audioFile,
      mode: mode,
      patientId: patientId,
      encounterId: encounterId,
      programmes: programmes,
      language: language,
      formSchema: formSchema,
      symptomCatalog: symptomCatalog,
    );
  }

  Map<String, dynamic> _buildMetadata({
    required ScribeMode mode,
    String? patientId,
    String? encounterId,
    List<String> programmes = const [],
    String language = 'bn',
    List<FormFieldSchema>? formSchema,
    List<String>? symptomCatalog,
  }) {
    return {
      'mode': mode.name == 'formPrefill' ? 'form_prefill' : mode.name,
      'language': language,
      'transcriptionModel': AppConfig.scribeTranscriptionModel,
      'patientId': ?patientId,
      'encounterId': ?encounterId,
      if (programmes.isNotEmpty) 'programmes': programmes,
      'removeNoise': true,
      'removeSilence': true,
      if (formSchema != null)
        'formSchema': formSchema.map((f) => f.toJson()).toList(),
      'symptomCatalog': ?symptomCatalog,
    };
  }

  Future<String> _simpleUploadWithMode(
    File audioFile, {
    required ScribeMode mode,
    String? patientId,
    String? encounterId,
    List<String> programmes = const [],
    String language = 'bn',
    List<FormFieldSchema>? formSchema,
    List<String>? symptomCatalog,
  }) async {
    final metadata = _buildMetadata(
      mode: mode,
      patientId: patientId,
      encounterId: encounterId,
      programmes: programmes,
      language: language,
      formSchema: formSchema,
      symptomCatalog: symptomCatalog,
    );

    final form = FormData.fromMap({
      'audio_file': await MultipartFile.fromFile(
        audioFile.path,
        filename: 'consultation.aac',
      ),
      'metadata': _jsonEncode(metadata),
    });

    final resp = await api.dio.post(
      _scribeUrl(Endpoints.scribeTranscribe),
      data: form,
    );
    if ((resp.statusCode ?? 0) != 202) {
      throw ApiException('scribe submit', resp.statusCode ?? 0);
    }
    return (resp.data as Map<String, dynamic>)['jobId'] as String;
  }

  /// JSON encode helper that handles nested structures.
  String _jsonEncode(Map<String, dynamic> data) {
    String encodeValue(dynamic val) {
      if (val == null) return 'null';
      if (val is String) return '"$val"';
      if (val is bool || val is num) return '$val';
      if (val is List) {
        return '[${val.map(encodeValue).join(',')}]';
      }
      if (val is Map<String, dynamic>) {
        return '{${val.entries.map((e) => '"${e.key}":${encodeValue(e.value)}').join(',')}}';
      }
      return '"$val"';
    }
    return encodeValue(data);
  }

  Future<String> _chunkedUploadWithMode(
    File audioFile, {
    required ScribeMode mode,
    String? patientId,
    String? encounterId,
    List<String> programmes = const [],
    String language = 'bn',
    List<FormFieldSchema>? formSchema,
    List<String>? symptomCatalog,
  }) async {
    final size = await audioFile.length();
    const chunkSize = 256 * 1024; // 256 KB

    // 1. Init
    final initResp = await postOk(
      _scribeUrl(Endpoints.scribeUploadInit),
      data: {'filename': 'consultation.opus', 'size': size},
      action: 'scribe upload init',
    ) as Map<String, dynamic>;
    final uploadId = initResp['uploadId'] as String;

    // 2. Check existing chunks (resume support)
    final statusResp = await getOk(
      _scribeUrl(Endpoints.scribeUploadStatus(uploadId)),
      action: 'scribe upload status',
    ) as Map<String, dynamic>;
    final received = ((statusResp['receivedChunks'] as List?)
            ?.map((e) => e as int)
            .toSet()) ??
        <int>{};

    // 3. Upload missing chunks
    final bytes = await audioFile.readAsBytes();
    var chunkNum = 0;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      if (!received.contains(chunkNum)) {
        final end = (offset + chunkSize).clamp(0, bytes.length);
        final chunk = bytes.sublist(offset, end);
        final resp = await api.dio.put(
          _scribeUrl(Endpoints.scribeUploadChunk(uploadId, chunkNum)),
          data: chunk,
          options: Options(contentType: 'application/octet-stream'),
        );
        if ((resp.statusCode ?? 0) >= 300) {
          throw ApiException('scribe upload chunk $chunkNum', resp.statusCode ?? 0);
        }
      }
      chunkNum++;
    }

    // 4. Complete
    final metadata = _buildMetadata(
      mode: mode,
      patientId: patientId,
      encounterId: encounterId,
      programmes: programmes,
      language: language,
      formSchema: formSchema,
      symptomCatalog: symptomCatalog,
    );
    final completeResp = await postOk(
      _scribeUrl(Endpoints.scribeUploadComplete(uploadId)),
      data: {'metadata': metadata},
      action: 'scribe upload complete',
    ) as Map<String, dynamic>;
    return completeResp['jobId'] as String;
  }

  /// Poll job status. Returns null if network fails (caller retries).
  Future<ScribeJobResult?> pollResult(String jobId) async {
    try {
      final body = await getOk(
        _scribeUrl(Endpoints.scribeResult(jobId)),
        action: 'scribe poll',
      );
      return ScribeJobResult.fromJson(body as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    } catch (e) {
      debugPrint('[scribe] pollResult failed, caller will retry: $e');
      return null;
    }
  }

  /// Fetch full note (includes rationale).
  Future<ScribeJobResult?> getNote(String noteId) async {
    try {
      final body = await getOk(
        _scribeUrl(Endpoints.scribeNote(noteId)),
        action: 'scribe get note',
      );
      debugPrint('[ScribeAPI] getNote response keys: ${body.keys.toList()}');
      // /notes/{id} returns the same shape as the sync endpoint; map it.
      final rendered = body['rendered'] as Map<String, dynamic>?;
      debugPrint('[ScribeAPI] rendered keys: ${rendered?.keys.toList()}');
      final subjText = rendered?['subjective']?.toString() ?? '';
      debugPrint('[ScribeAPI] rendered subjective (${subjText.length} chars): ${subjText.substring(0, subjText.length.clamp(0, 100))}');
      final ratJson = body['rationale'] as Map<String, dynamic>?;
      return ScribeJobResult(
        jobId: '',
        status: ScribeJobStatus.completed,
        noteId: body['noteId'] as String?,
        soap: rendered != null ? SoapNote.fromJson(rendered) : null,
        rationale: ratJson != null ? ScribeRationale.fromJson(ratJson) : null,
      );
    } catch (e) {
      debugPrint('[ScribeAPI] getNote error: $e');
      return null;
    }
  }

  /// Accept a draft note. [edits] overrides specific SOAP fields.
  Future<void> acceptNote(String noteId, {SoapNote? edits}) async {
    await postOk(
      _scribeUrl(Endpoints.scribeAccept(noteId)),
      data: {'edits': edits?.toJson() ?? {}},
      action: 'scribe accept',
    );
  }

  /// Reject a draft note.
  Future<void> rejectNote(String noteId, {String? reason}) async {
    await postOk(
      _scribeUrl(Endpoints.scribeReject(noteId)),
      data: {'reason': reason ?? ''},
      action: 'scribe reject',
    );
  }
}
