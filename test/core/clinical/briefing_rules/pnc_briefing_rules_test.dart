import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/briefing_rules/pnc_briefing_rules.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

void main() {
  // These assert English copy, so pin the language. AppLocale defaults to
  // Bangla (BD-first), and Bangla localizes digits — '12 days' becomes
  // '১২ days' — so an unpinned test is really asserting the default locale.
  setUp(() => AppLocale.current = AppLanguage.english);

  group('evaluatePncFindings', () {
    test('no history → empty', () {
      expect(evaluatePncFindings(latest: null, pncVisitCount: 0), isEmpty);
    });

    test('danger sign present (coded list) → per-sign message', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {
            // Spice option id for Heavy bleeding.
            'postpartumDangerSigns': ['1'],
          },
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.dangerSign'));
    });

    test('danger sign via boolean fallback field (older record, no coded list)', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {'convulsions': true},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.dangerSign'));
      expect(
        findings.firstWhere((f) => f.code == 'pnc.dangerSign').message,
        'Danger sign reported: Convulsions.',
      );
    });

    test('temp >= 102F → urgent temperature message', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {'temperature': 103.0},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.urgentTemperature'));
    });

    test('pulse > 90 → urgent pulse message', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {'pulse': '98'},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.urgentPulse'));
    });

    test('pulse < 60 → urgent pulse message', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {'pulse': '52'},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.urgentPulse'));
    });

    test('BP >= 140/90 → urgent BP message', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {'systolic': '145', 'diastolic': '70'},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.urgentBp'));
    });

    test('multiple abnormal vitals simultaneously all get named', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {
            'temperature': 103.0,
            'pulse': '98',
            'systolic': '145',
            'diastolic': '95',
          },
        },
        pncVisitCount: 1,
      );
      expect(
        findings.map((f) => f.code).toSet(),
        containsAll(['pnc.urgentTemperature', 'pnc.urgentPulse', 'pnc.urgentBp']),
      );
    });

    test('Hb < 8 → severe anemia message', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {'hemoglobin': 7.0},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.severeAnaemia'));
    });

    test('no contraception method >=42 days postpartum → counsel message', () {
      final findings = evaluatePncFindings(
        latest: {
          'daysSinceDelivery': 50,
          'postpartumContraception': {'familyPlanningMethods': 'none'},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.noContraception'));
    });

    test('Vitamin A not consumed within 56 days → supplement gap message', () {
      final findings = evaluatePncFindings(
        latest: {
          'daysSinceDelivery': 20,
          'maternalHealthAssessment': {'vitaminAConsumed': false},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.supplementGapVitaminA'));
    });

    test('IFA consumed < 30 → supplement gap message', () {
      final findings = evaluatePncFindings(
        latest: {
          'maternalHealthAssessment': {'ifaTabletsConsumed': 5},
        },
        pncVisitCount: 1,
      );
      expect(findings.map((f) => f.code), contains('pnc.supplementGapIfa'));
    });

    test('PNC visit overdue → gap-of-N-days message', () {
      final findings = evaluatePncFindings(
        latest: {},
        pncVisitCount: 1,
        overdueDaysOverdue: 7,
      );
      expect(
        findings.firstWhere((f) => f.code == 'pnc.overdueVisit').message,
        'PNC Visit 2 is overdue by 7 days.',
      );
    });

    test('none of the above → routine recovering-well message', () {
      final findings = evaluatePncFindings(latest: {}, pncVisitCount: 1);
      expect(findings, hasLength(1));
      expect(findings.first.message, 'Recovering well — no concerns at this PNC visit.');
    });
  });
}
