import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/models/risk.dart';
import 'package:uhis_next/core/risk/risk_scoring_service.dart';

void main() {
  const service = RiskScoringService();

  group('RiskScoringService.score — spec §2.8 band+modifier', () {
    test('healthy adult with no programmes → band4 routine', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p1',
        ageYears: 30,
      ));
      expect(assessment.band, Band.band4);
      expect(assessment.modifier, Modifier.none);
      expect(assessment.isUrgent, isFalse);
      expect(assessment.reasons, isNotEmpty);
    });

    test('under-5 with IMCI → band3', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p2',
        ageYears: 3,
        programmes: <Programme>{Programme.imci},
      ));
      expect(assessment.band, Band.band3);
      expect(
        assessment.reasons.any((r) => r.toLowerCase().contains('imci')),
        isTrue,
      );
    });

    test('TB patient → band2 default', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p3',
        ageYears: 45,
        programmes: <Programme>{Programme.tb},
      ));
      expect(assessment.band, Band.band2);
    });

    test('redFlag forces band1 regardless of other facts', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p4',
        ageYears: 25,
        redFlag: true,
      ));
      expect(assessment.band, Band.band1);
      expect(assessment.isUrgent, isTrue);
      expect(assessment.rationale?.humanReviewRequired, isTrue);
    });

    test('serverRiskLevel=HIGH alone escalates to band1', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'p5',
        ageYears: 25,
        serverRiskLevel: 'HIGH',
      ));
      expect(assessment.band, Band.band1);
    });

    test('empty facts still yields at least one reason', () {
      final assessment = service.score(const PatientFacts(patientId: 'p9'));
      expect(assessment.reasons, isNotEmpty);
      expect(assessment.band, Band.band4);
    });

    // ── ANC §2.8.1 ──────────────────────────────────────────────────────────
    test('ANC danger sign → band1', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc1',
        ageYears: 24,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(hasDangerSign: true),
      ));
      expect(assessment.band, Band.band1);
    });

    test('ANC severe anaemia Hb<7 → band1', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc2',
        ageYears: 30,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(hemoglobin: 6.5),
      ));
      expect(assessment.band, Band.band1);
    });

    test('ANC BP ≥160/110 → band1', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc3',
        ageYears: 30,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(systolicBp: 165, diastolicBp: 112),
      ));
      expect(assessment.band, Band.band1);
    });

    test('ANC BP 145/95 → band2', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc4',
        ageYears: 30,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(systolicBp: 145, diastolicBp: 95),
      ));
      expect(assessment.band, Band.band2);
    });

    test('ANC fasting glucose ≥5.1 → band2 (GDM risk)', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc5',
        ageYears: 28,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(fastingGlucoseMmolL: 5.5),
      ));
      expect(assessment.band, Band.band2);
    });

    test('ANC mild anaemia (Hb 10.5) → band3', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc6',
        ageYears: 30,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(hemoglobin: 10.5),
      ));
      expect(assessment.band, Band.band3);
    });

    test('ANC GA ≥36 → band3 with modifier a', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc7',
        ageYears: 28,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(gestationalAgeWeeks: 37),
      ));
      expect(assessment.band, Band.band3);
      expect(assessment.modifier, Modifier.a);
    });

    test('ANC primigravida + low-risk vitals → band4 with modifier a', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc8',
        ageYears: 22,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(parity: 0),
      ));
      // No clinical finding triggers a band — but anc-late-term hits band3
      // only if GA≥36. Primigravida alone is just a modifier — band stays
      // band4 (the routine default).
      expect(assessment.band, Band.band4);
      expect(assessment.modifier, Modifier.a);
    });

    test('ANC moderate anaemia Hb 7.0 → band2', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc-hb7',
        ageYears: 28,
        programmes: <Programme>{Programme.anc},
        vitals: ClinicalVitals(hemoglobin: 7.0),
      ));
      expect(assessment.band, Band.band2);
      expect(
        assessment.reasons.any((r) => r.toLowerCase().contains('anaemia')),
        isTrue,
      );
    });

    test('ANC enrolled without abnormal findings → band4, not no-programme',
        () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc-ok',
        ageYears: 25,
        programmes: <Programme>{Programme.anc},
      ));
      expect(assessment.band, Band.band4);
      expect(
        assessment.reasons.any((r) => r.toLowerCase().contains('no programme')),
        isFalse,
      );
      expect(
        assessment.reasons.any((r) => r.toLowerCase().contains('anc')),
        isTrue,
      );
    });

    test('NCD enrolled without abnormal findings → band4, not no-programme',
        () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd-ok',
        ageYears: 40,
        programmes: <Programme>{Programme.ncd},
      ));
      expect(assessment.band, Band.band4);
      expect(
        assessment.reasons.any((r) => r.toLowerCase().contains('no programme')),
        isFalse,
      );
    });

    test('ANC overdue nextDueAt → modifier b', () {
      final assessment = service.score(PatientFacts(
        patientId: 'anc-due',
        ageYears: 25,
        programmes: const <Programme>{Programme.anc},
        nextDueAt: DateTime.now().subtract(const Duration(days: 5)),
        vitals: const ClinicalVitals(),
      ));
      expect(assessment.modifier, Modifier.b);
    });

    test('ANC overdue ANC visit → modifier b on band4', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'anc9',
        ageYears: 25,
        programmes: <Programme>{Programme.anc},
        daysSinceLastVisit: 42,
        vitals: ClinicalVitals(),
      ));
      expect(assessment.modifier, Modifier.b);
    });

    // ── NCD §2.8.2 ──────────────────────────────────────────────────────────
    test('NCD stroke sign → band1', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd1',
        ageYears: 55,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(hasStrokeSign: true),
      ));
      expect(assessment.band, Band.band1);
    });

    test('NCD BP ≥180/110 → band1', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd2',
        ageYears: 60,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(systolicBp: 185, diastolicBp: 115),
      ));
      expect(assessment.band, Band.band1);
    });

    test('NCD fasting ≥18 mmol/L → band1', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd3',
        ageYears: 50,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(fastingGlucoseMmolL: 20.0),
      ));
      expect(assessment.band, Band.band1);
    });

    test('NCD BP 165/100 → band2', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd4',
        ageYears: 55,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(systolicBp: 165, diastolicBp: 100),
      ));
      expect(assessment.band, Band.band2);
    });

    test('NCD BP 145/92 → band3', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd5',
        ageYears: 55,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(systolicBp: 145, diastolicBp: 92),
      ));
      expect(assessment.band, Band.band3);
    });

    test('NCD pre-HTN 132/85 → band4', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd6',
        ageYears: 55,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(systolicBp: 132, diastolicBp: 86),
      ));
      expect(assessment.band, Band.band4);
    });

    test('NCD HTN+DM together → modifier a', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd7',
        ageYears: 55,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(
            systolicBp: 145, diastolicBp: 92, hasDiabetes: true),
      ));
      expect(assessment.modifier, Modifier.a);
    });

    test('NCD age≥60 → modifier a', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd8',
        ageYears: 65,
        programmes: <Programme>{Programme.ncd},
        vitals: ClinicalVitals(systolicBp: 145, diastolicBp: 92),
      ));
      expect(assessment.modifier, Modifier.a);
    });

    test('NCD overdue follow-up >42 days → modifier b on band4', () {
      final assessment = service.score(const PatientFacts(
        patientId: 'ncd9',
        ageYears: 55,
        programmes: <Programme>{Programme.ncd},
        daysSinceLastVisit: 60,
        vitals: ClinicalVitals(),
      ));
      expect(assessment.modifier, Modifier.b);
    });
  });

  group('sortRankFor — spec §2.8 sort sequence', () {
    test('emits 1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4 descending', () {
      final ranks = [
        sortRankFor(Band.band1, Modifier.a),
        sortRankFor(Band.band1, Modifier.b),
        sortRankFor(Band.band1, Modifier.none),
        sortRankFor(Band.band2, Modifier.a),
        sortRankFor(Band.band2, Modifier.b),
        sortRankFor(Band.band2, Modifier.none),
        sortRankFor(Band.band3, Modifier.a),
        sortRankFor(Band.band3, Modifier.b),
        sortRankFor(Band.band3, Modifier.none),
        sortRankFor(Band.band4, Modifier.none),
      ];
      final sorted = [...ranks]..sort((a, b) => b.compareTo(a));
      expect(ranks, equals(sorted));
    });
  });
}
