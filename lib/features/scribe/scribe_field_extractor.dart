import '../../core/debug/console_log.dart';
import '../training/offline_llm_service.dart';
import '../visit/triage/triage_transcript_matcher.dart';
import 'form_field_schema_builder.dart';
import 'models/ai_extracted_field.dart';

/// Offline extraction layer: triage via keyword matching; form prefill
/// via Gemma 270M key=value prompt.
class ScribeFieldExtractor {
  const ScribeFieldExtractor(this._llm);
  final OfflineLlmService _llm;

  static const int _maxTranscriptChars = 500;
  static const int _maxFields = 8;

  TriageExtractionResult? extractTriage(
    String transcript,
    List<String> catalog,
  ) =>
      TriageTranscriptMatcher.match(transcript, catalog: catalog);

  Future<FormPrefillResult?> extractFields(
    String transcript,
    List<FormFieldSchema> schema,
  ) async {
    if (transcript.isEmpty || schema.isEmpty) return null;

    final t = transcript.length > _maxTranscriptChars
        ? transcript.substring(0, _maxTranscriptChars)
        : transcript;

    final fieldLines = schema
        .take(_maxFields)
        .map((f) {
          final opts = f.allowedValues?.join(', ') ?? '';
          return '${f.fieldId}: ${f.type.name}${opts.isNotEmpty ? " ($opts)" : ""}';
        })
        .join('\n');

    final prompt = 'Clinical form assistant. Extract from transcript.\n'
        'Fields:\n$fieldLines\n\n'
        'Transcript: $t\n\n'
        'One line per field: field_id=value\n'
        'Skip unknown fields. No explanation.';

    ConsoleLog.step('[ScribeFieldExtractor] asking Gemma for form prefill');
    try {
      final raw = await _llm.ask(prompt);
      return _parse(raw, schema);
    } on OfflineLlmException catch (e) {
      ConsoleLog.warn('[ScribeFieldExtractor] Gemma failed: $e');
      return null;
    }
  }

  FormPrefillResult _parse(String raw, List<FormFieldSchema> schema) {
    final schemaMap = {for (final f in schema) f.fieldId: f};
    final fields = <AIExtractedField>[];
    final now = DateTime.now();

    for (final line in raw.split('\n')) {
      final idx = line.indexOf('=');
      if (idx < 1) continue;
      final key = line.substring(0, idx).trim();
      final val = line.substring(idx + 1).trim();
      if (val.isEmpty || !schemaMap.containsKey(key)) continue;
      fields.add(AIExtractedField(
        fieldId: key,
        value: val,
        confidence: 0.7,
        source: FieldSource.aiPending,
        sourceSegment: val,
        extractedAt: now,
      ));
    }

    ConsoleLog.step('[ScribeFieldExtractor] parsed ${fields.length} fields');
    return FormPrefillResult(fields: fields, transcriptText: raw);
  }
}
