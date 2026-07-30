import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/triage/triage_transcript_matcher.dart';

void main() {
  group('TriageTranscriptMatcher', () {
    test('matches fever and headache from English transcript', () {
      final result = TriageTranscriptMatcher.match(
        'Patient has fever and headache for two days',
        catalog: const ['fever', 'headache', 'chest_pain'],
      );

      expect(result, isNotNull);
      expect(result!.codes, containsAll(['fever', 'headache']));
    });

    test('returns null for empty or too-short transcript', () {
      expect(
        TriageTranscriptMatcher.match('Mmm', catalog: const ['fever']),
        isNull,
      );
      expect(
        TriageTranscriptMatcher.match('', catalog: const ['fever']),
        isNull,
      );
    });

    test('respects catalog filter', () {
      final result = TriageTranscriptMatcher.match(
        'Patient has chest pain',
        catalog: const ['fever'],
      );

      expect(result, isNull);
    });

    test('skips negated symptoms', () {
      final result = TriageTranscriptMatcher.match(
        'No fever, no headache, feels fine',
        catalog: const ['fever', 'headache'],
      );

      expect(result, isNull);
    });

    test('fallbackSearchText includes SOAP subjective when transcript empty', () {
      final text = TriageTranscriptMatcher.fallbackSearchText(
        transcriptText: '',
        soapSubjective:
            'Patient reports vomiting for three days and fever since yesterday',
      );

      expect(text, isNotNull);
      final result = TriageTranscriptMatcher.match(
        text!,
        catalog: const ['vomiting', 'fever'],
      );
      expect(result!.codes, containsAll(['vomiting', 'fever']));
    });

    test('rejects empty-visit meta statements', () {
      expect(
        TriageTranscriptMatcher.fallbackSearchText(
          soapSubjective:
              'Patient did not provide any verbal complaints during the consultation.',
        ),
        isNull,
      );
      expect(
        TriageTranscriptMatcher.match(
          'Patient did not provide any verbal complaints during the consultation.',
          catalog: const ['fever'],
        ),
        isNull,
      );
    });
  });
}
