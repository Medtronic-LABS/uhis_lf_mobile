/// Ordering and exclusion for the visit history NABA receives.
///
/// Order is the dangerous part. The backend keeps `visits[-3:]` — the TAIL —
/// so a newest-first list silently delivers the three *oldest* visits, which
/// reads to the model as a worsening trend when it may be improving. Nothing
/// errors; the recommendation is just wrong.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/models/assessment_history_item.dart';
import 'package:uhis_next/features/visit/assessment_repository.dart';

AssessmentHistoryItem _at(
  DateTime date, {
  String encounterId = 'e',
  Map<String, dynamic>? observations,
}) =>
    AssessmentHistoryItem(
      householdMemberId: 'm1',
      encounterId: encounterId,
      visitDate: date,
      observations: observations,
    );

List<String> _dates(List<AssessmentHistoryItem> items) =>
    items.map((i) => i.visitDate.toIso8601String().substring(0, 10)).toList();

void main() {
  group('ordering', () {
    test('returns oldest-first whatever order the rows arrive in', () {
      final merged = AssessmentRepository.mergeHistoryForTesting(
        fromAssessments: [
          _at(DateTime(2026, 3, 1), encounterId: 'c'),
          _at(DateTime(2026, 1, 1), encounterId: 'a'),
          _at(DateTime(2026, 2, 1), encounterId: 'b'),
        ],
        fromLocal: const [],
      );

      expect(_dates(merged), ['2026-01-01', '2026-02-01', '2026-03-01']);
    });

    test('the newest visit is last, which is what the tail slice keeps', () {
      final merged = AssessmentRepository.mergeHistoryForTesting(
        fromAssessments: [
          for (var m = 1; m <= 5; m++)
            _at(DateTime(2026, m, 1), encounterId: 'e$m'),
        ],
        fromLocal: const [],
      );

      expect(_dates(merged).last, '2026-05-01');
      // Taking the tail must yield the most recent three.
      expect(_dates(merged.sublist(merged.length - 3)),
          ['2026-03-01', '2026-04-01', '2026-05-01']);
    });
  });

  group('the visit in progress', () {
    test('is excluded by encounter id', () {
      final merged = AssessmentRepository.mergeHistoryForTesting(
        fromAssessments: [
          _at(DateTime(2026, 1, 1), encounterId: 'old'),
          _at(DateTime(2026, 9, 12), encounterId: 'today'),
        ],
        fromLocal: const [],
        excludeEncounterId: 'today',
      );

      expect(_dates(merged), ['2026-01-01']);
    });

    test('is excluded by day, which is how a just-saved local row is caught',
        () {
      // A local row is filed under its own uuid, not the screen's encounter
      // id, so the id check alone never matches it.
      final merged = AssessmentRepository.mergeHistoryForTesting(
        fromAssessments: [_at(DateTime(2026, 1, 1), encounterId: 'old')],
        fromLocal: [
          _at(DateTime(2026, 9, 12, 16, 40), encounterId: 'local-uuid'),
        ],
        excludeEncounterId: 'encounter-from-the-screen',
        excludeVisitsOn: DateTime(2026, 9, 12, 9, 0),
      );

      expect(_dates(merged), ['2026-01-01']);
    });
  });

  group('same-day collision', () {
    test('the local row wins, as the fresher record of the visit', () {
      final merged = AssessmentRepository.mergeHistoryForTesting(
        fromAssessments: [_at(DateTime(2026, 5, 1), encounterId: 'synced')],
        fromLocal: [_at(DateTime(2026, 5, 1, 18), encounterId: 'local')],
      );

      expect(merged.single.encounterId, 'local');
    });

    test('but the synced row\'s measurements are carried across', () {
      // A local row has no flat `observations` map. Letting it win outright
      // would drop that day's readings — the very data this exists to send.
      final merged = AssessmentRepository.mergeHistoryForTesting(
        fromAssessments: [
          _at(DateTime(2026, 5, 1),
              encounterId: 'synced',
              observations: const {'bp': '144/91'}),
        ],
        fromLocal: [_at(DateTime(2026, 5, 1, 18), encounterId: 'local')],
      );

      expect(merged.single.encounterId, 'local');
      expect(merged.single.observations, {'bp': '144/91'});
    });
  });

  test('no history yields an empty list rather than throwing', () {
    expect(
      AssessmentRepository.mergeHistoryForTesting(
        fromAssessments: const [],
        fromLocal: const [],
      ),
      isEmpty,
    );
  });
}
