import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/briefing_rules/anc_briefing_rules.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

void main() {
  // These assert English copy, so pin the language. AppLocale defaults to
  // Bangla (BD-first), and Bangla localizes digits — '12 days' becomes
  // '১২ days' — so an unpinned test is really asserting the default locale.
  setUp(() => AppLocale.current = AppLanguage.english);

  group('evaluateAncFindings', () {
    test('no history → empty (no routine fallback without a visit)', () {
      final findings = evaluateAncFindings(
        latest: null,
        previous: null,
        ancVisitCount: 0,
        hasKnownHypertension: false,
      );
      expect(findings, isEmpty);
    });

    test('danger sign present → per-sign message', () {
      final findings = evaluateAncFindings(
        latest: {
          'dangerSignsRiskIdentification': {
            // Spice option id for Vaginal bleeding (weeks ≤12).
            'dangerSignsExperienced12': ['0'],
          },
        },
        previous: null,
        ancVisitCount: 1,
        hasKnownHypertension: false,
      );
      expect(findings.map((f) => f.code), contains('anc.dangerSign'));
      // Without FormConfig loaded, label falls back to the Spice option id.
      expect(
        findings.firstWhere((f) => f.code == 'anc.dangerSign').message,
        'Danger sign reported: 0.',
      );
    });

    test('BP >= 140/90 → pre-eclampsia watch message', () {
      final findings = evaluateAncFindings(
        latest: {
          'medicalHistoryPhysicalExamination': {
            'systolic': '142',
            'diastolic': '88',
          },
        },
        previous: null,
        ancVisitCount: 1,
        hasKnownHypertension: false,
      );
      expect(
        findings.map((f) => f.code),
        containsAll(['anc.highBp']),
      );
      expect(findings.map((f) => f.code), isNot(contains('anc.bpRisingTrend')));
    });

    test('known HTN with normal reading still triggers highBp', () {
      final findings = evaluateAncFindings(
        latest: {
          'medicalHistoryPhysicalExamination': {'systolic': '110', 'diastolic': '70'},
        },
        previous: null,
        ancVisitCount: 1,
        hasKnownHypertension: true,
      );
      expect(findings.map((f) => f.code), contains('anc.highBp'));
    });

    test('BP rising trend but not yet >=140/90', () {
      final findings = evaluateAncFindings(
        latest: {
          'medicalHistoryPhysicalExamination': {'systolic': '130', 'diastolic': '80'},
        },
        previous: {
          'medicalHistoryPhysicalExamination': {'systolic': '118', 'diastolic': '75'},
        },
        ancVisitCount: 2,
        hasKnownHypertension: false,
      );
      expect(findings.map((f) => f.code), contains('anc.bpRisingTrend'));
      expect(findings.map((f) => f.code), isNot(contains('anc.highBp')));
    });

    test('BP rising trend AND >=140/90 → only high-BP message fires (mutual exclusion)', () {
      final findings = evaluateAncFindings(
        latest: {
          'medicalHistoryPhysicalExamination': {'systolic': '145', 'diastolic': '92'},
        },
        previous: {
          'medicalHistoryPhysicalExamination': {'systolic': '118', 'diastolic': '75'},
        },
        ancVisitCount: 2,
        hasKnownHypertension: false,
      );
      expect(findings.map((f) => f.code), contains('anc.highBp'));
      expect(findings.map((f) => f.code), isNot(contains('anc.bpRisingTrend')));
    });

    test('Hb < 8 → severe anemia message', () {
      final findings = evaluateAncFindings(
        latest: {
          'pointOfCareInvestigations': {'hemoglobin': 7.2},
        },
        previous: null,
        ancVisitCount: 1,
        hasKnownHypertension: false,
      );
      expect(findings.map((f) => f.code), contains('anc.severeAnaemia'));
    });

    test('Hb 8-10.9 → anemia noted message', () {
      final findings = evaluateAncFindings(
        latest: {
          'pointOfCareInvestigations': {'hemoglobin': 9.5},
        },
        previous: null,
        ancVisitCount: 1,
        hasKnownHypertension: false,
      );
      expect(findings.map((f) => f.code), contains('anc.anaemiaNoted'));
    });

    test('IFA consumed < 30 → low intake message', () {
      final findings = evaluateAncFindings(
        latest: {
          'vaccinationAndSupplements': {'ifaTotalConsumed': 10},
        },
        previous: null,
        ancVisitCount: 1,
        hasKnownHypertension: false,
      );
      expect(findings.map((f) => f.code), contains('anc.supplementGap'));
    });

    test('missed ANC follow-up → gap-of-N-days message', () {
      final findings = evaluateAncFindings(
        latest: {},
        previous: null,
        ancVisitCount: 1,
        hasKnownHypertension: false,
        missedVisitDaysOverdue: 12,
      );
      expect(
        findings.firstWhere((f) => f.code == 'anc.missedVisit').message,
        'Missed ANC — gap of 12 days.',
      );
    });

    test('none of the above → routine visit N message', () {
      final findings = evaluateAncFindings(
        latest: {},
        previous: null,
        ancVisitCount: 2,
        hasKnownHypertension: false,
      );
      expect(findings, hasLength(1));
      expect(findings.first.message, 'Routine visit — no concerns flagged. Visit 3 on track.');
    });
  });
}
