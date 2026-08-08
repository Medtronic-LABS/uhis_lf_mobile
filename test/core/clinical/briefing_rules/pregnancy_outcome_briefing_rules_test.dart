import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/briefing_rules/pregnancy_outcome_briefing_rules.dart';

void main() {
  group('evaluatePregnancyOutcomeFindings', () {
    test('no record → empty', () {
      expect(evaluatePregnancyOutcomeFindings(latest: null), isEmpty);
    });

    test('stillbirth recorded (via deliveryOutcome) → flagged', () {
      final findings = evaluatePregnancyOutcomeFindings(latest: {
        'deliveryOutcomes': {'deliveryOutcome': 'stillbirth'},
      });
      expect(findings, hasLength(1));
      expect(findings.first.code, 'pregnancyOutcome.stillbirthOrNeonatalDeath');
    });

    test('stillbirth recorded (via stillbirthNumbers > 0) → flagged', () {
      final findings = evaluatePregnancyOutcomeFindings(latest: {
        'deliveryOutcomes': {'deliveryOutcome': 'liveBirth', 'stillbirthNumbers': 1},
      });
      expect(findings.first.code, 'pregnancyOutcome.stillbirthOrNeonatalDeath');
    });

    test('neonatal death (baby not alive) → flagged', () {
      final findings = evaluatePregnancyOutcomeFindings(latest: {
        'deliveryOutcomes': {'deliveryOutcome': 'liveBirth'},
        'newbornDetails': [
          {'isBabyAlive': false, 'causeOfNeonatalDeath': 'birthAsphyxia'},
        ],
      });
      expect(findings.first.code, 'pregnancyOutcome.stillbirthOrNeonatalDeath');
    });

    test('abortion recorded → pregnancy loss message with type', () {
      final findings = evaluatePregnancyOutcomeFindings(latest: {
        'abortion': {'typeOfAbortion': 'spontaneous'},
      });
      expect(findings.first.code, 'pregnancyOutcome.abortion');
      expect(findings.first.message, contains('spontaneous'));
    });

    test('live birth, mother and baby both well → healthy outcome message', () {
      final findings = evaluatePregnancyOutcomeFindings(latest: {
        'deliveryOutcomes': {
          'deliveryOutcome': 'liveBirth',
          'anyComplicationsDuringDelivery': 'No',
        },
        'newbornDetails': [
          {'isBabyAlive': true},
        ],
      });
      expect(findings, hasLength(1));
      expect(findings.first.code, 'pregnancyOutcome.healthy');
    });

    test('live birth with delivery complications → no healthy-outcome message', () {
      final findings = evaluatePregnancyOutcomeFindings(latest: {
        'deliveryOutcomes': {
          'deliveryOutcome': 'liveBirth',
          'anyComplicationsDuringDelivery': 'Yes',
        },
        'newbornDetails': [
          {'isBabyAlive': true},
        ],
      });
      expect(findings, isEmpty);
    });

    test('maternal death is never miscategorized as healthy', () {
      final findings = evaluatePregnancyOutcomeFindings(latest: {
        'deliveryOutcomes': {'deliveryOutcome': 'maternalDeath'},
        'maternalDeath': {'causeOfDeath': 'haemorrhage'},
      });
      expect(findings.any((f) => f.code == 'pregnancyOutcome.healthy'), isFalse);
    });
  });
}
