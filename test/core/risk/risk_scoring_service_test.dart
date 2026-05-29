import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/models/risk.dart';
import 'package:uhis_next/core/risk/risk_scoring_service.dart';

void main() {
  const service = RiskScoringService();

  group('RiskScoringService.score', () {
    test('healthy adult with no programmes → low band', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p1',
        ageYears: 30,
      ));
      expect(assessment.band, RiskBand.low);
      expect(assessment.score, lessThan(35));
      expect(assessment.isUrgent, isFalse);
      expect(assessment.reasons, isNotEmpty);
    });

    test('under-5 with IMCI → at least moderate, IMCI in reasons', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p2',
        ageYears: 3,
        programmes: <Programme>{Programme.imci},
      ));
      expect(assessment.band, isNot(RiskBand.low));
      expect(
        assessment.reasons.any((r) => r.contains('Under-5')),
        isTrue,
      );
      expect(
        assessment.reasons.any((r) => r.toLowerCase().contains('imci')),
        isTrue,
      );
    });

    test('TB + 3 missed visits → high or urgent', () {
      final assessment = service.score(PatientFacts(
        patientId: 'p3',
        ageYears: 45,
        programmes: const <Programme>{Programme.tb},
        missedVisitsLast90d: 3,
      ));
      expect(assessment.score, greaterThanOrEqualTo(50));
      expect(
          assessment.band == RiskBand.high ||
              assessment.band == RiskBand.urgent,
          isTrue);
    });

    test('redFlag forces urgent band regardless of base score', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p4',
        ageYears: 25,
        redFlag: true,
      ));
      expect(assessment.band, RiskBand.urgent);
      expect(assessment.score, greaterThanOrEqualTo(80));
    });

    test('serverRiskLevel=HIGH alone is enough to escalate to urgent', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p5',
        ageYears: 25,
        serverRiskLevel: 'HIGH',
      ));
      expect(assessment.band, RiskBand.urgent);
    });

    test('missed visits clamp at the cap', () {
      final low = service.score(const PatientFacts(
        patientId: 'p6',
        ageYears: 40,
        missedVisitsLast90d: 3,
      ));
      final huge = service.score(const PatientFacts(
        patientId: 'p6b',
        ageYears: 40,
        missedVisitsLast90d: 50,
      ));
      // Diff should plateau — huge isn't dramatically higher than low.
      expect(huge.score - low.score, lessThanOrEqualTo(0));
    });

    test('score never exceeds 100', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p7',
        ageYears: 2,
        programmes: <Programme>{
          Programme.imci,
          Programme.ncd,
          Programme.tb,
          Programme.anc,
        },
        missedVisitsLast90d: 10,
        lostToFollowUp: true,
        redFlag: true,
        serverRiskLevel: 'HIGH',
        serverRiskColor: 'RED',
      ));
      expect(assessment.score, lessThanOrEqualTo(100));
    });

    test('lost-to-follow-up adds reason and band moves up', () {
      final baseline = service.score(const PatientFacts(
        patientId: 'p8',
        ageYears: 50,
        programmes: <Programme>{Programme.ncd},
      ));
      final lost = service.score(const PatientFacts(
        patientId: 'p8b',
        ageYears: 50,
        programmes: <Programme>{Programme.ncd},
        lostToFollowUp: true,
      ));
      expect(lost.score, greaterThan(baseline.score));
      expect(
        lost.reasons.any((r) => r.toLowerCase().contains('lost')),
        isTrue,
      );
    });

    test('empty facts still yields at least one reason', () {
      final assessment = service.score(const PatientFacts(patientId: 'p9'));
      expect(assessment.reasons, isNotEmpty);
      expect(assessment.band, RiskBand.low);
    });
  });
}
