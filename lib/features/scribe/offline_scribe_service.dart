import '../../core/api/scribe_api_service.dart';
import '../../core/debug/console_log.dart';
import '../visit/triage/ai_scribe_triage_vocab.dart';
import 'form_field_schema_builder.dart';
import 'scribe_asr_service.dart';
import 'scribe_field_extractor.dart';

/// Orchestrates offline AI Scribe: WAV file → ASR → extraction → ScribeJobResult.
///
/// Supports triage (P1, keyword-based) and formPrefill (P2, Gemma 270M).
/// SOAP is online-only — returns null for that mode.
class OfflineScribeService {
  const OfflineScribeService({
    required ScribeAsrService asr,
    required ScribeFieldExtractor extractor,
  })  : _asr = asr,
        _extractor = extractor;

  final ScribeAsrService _asr;
  final ScribeFieldExtractor _extractor;

  Future<ScribeJobResult?> process({
    required String wavPath,
    required ScribeMode mode,
    List<FormFieldSchema>? formSchema,
    List<String>? symptomCatalog,
  }) async {
    ConsoleLog.step('[OfflineScribeService] processing mode=${mode.name}');
    final transcript = await _asr.transcribeFile(wavPath);
    if (transcript.isEmpty) {
      ConsoleLog.warn('[OfflineScribeService] empty transcript — aborting');
      return null;
    }

    final jobId = 'offline-${DateTime.now().millisecondsSinceEpoch}';

    switch (mode) {
      case ScribeMode.triage:
        final catalog = symptomCatalog ?? AiScribeTriageVocab.codes;
        final triage = _extractor.extractTriage(transcript, catalog);
        return ScribeJobResult(
          jobId: jobId,
          status: ScribeJobStatus.completed,
          mode: ScribeMode.triage,
          transcriptText: transcript,
          triageResult: triage,
        );

      case ScribeMode.formPrefill:
        final prefill = await _extractor.extractFields(
          transcript,
          formSchema ?? [],
        );
        return ScribeJobResult(
          jobId: jobId,
          status: ScribeJobStatus.completed,
          mode: ScribeMode.formPrefill,
          transcriptText: transcript,
          formPrefill: prefill,
        );

      case ScribeMode.soap:
        return null;
    }
  }
}
