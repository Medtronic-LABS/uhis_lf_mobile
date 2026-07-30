import 'package:flutter_test/flutter_test.dart';
import 'package:leapwell/core/clinical/briefing_rules/ncd_briefing_rules.dart';

void main() {
  group('evaluateNcdFindings', () {
    test('no history → empty', () {
      final findings = evaluateNcdFindings(
        latest: null,
        previous: null,
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(findings, isEmpty);
    });

    test('both BP and glucose above threshold → combined message only', () {
      final findings = evaluateNcdFindings(
        latest: {
          'bpLog': {'avgSystolic': 150, 'avgDiastolic': 95},
          'glucoseLog': {'glucoseValue': 12.0, 'glucoseType': 'rbs'},
        },
        previous: null,
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(findings.map((f) => f.code), contains('ncd.bpAndGlucoseCombined'));
      expect(findings.map((f) => f.code), isNot(contains('ncd.bpAlone')));
      expect(findings.map((f) => f.code), isNot(contains('ncd.glucoseAlone')));
    });

    test('BP alone above threshold → individual BP message', () {
      final findings = evaluateNcdFindings(
        latest: {
          'bpLog': {'avgSystolic': 150, 'avgDiastolic': 95},
        },
        previous: null,
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(findings.map((f) => f.code), contains('ncd.bpAlone'));
    });

    test('fasting glucose >= 7 alone → individual glucose message', () {
      final findings = evaluateNcdFindings(
        latest: {
          'glucoseLog': {'glucoseValue': 8.0, 'glucoseType': 'fbs'},
        },
        previous: null,
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(findings.map((f) => f.code), contains('ncd.glucoseAlone'));
    });

    test('random glucose >= 11.1 alone → individual glucose message', () {
      final findings = evaluateNcdFindings(
        latest: {
          'glucoseLog': {'glucoseValue': 11.5, 'glucoseType': 'rbs'},
        },
        previous: null,
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(findings.map((f) => f.code), contains('ncd.glucoseAlone'));
    });

    test('known HTN with normal reading still triggers bpAlone', () {
      final findings = evaluateNcdFindings(
        latest: {
          'bpLog': {'avgSystolic': 110, 'avgDiastolic': 70},
        },
        previous: null,
        hasKnownHypertension: true,
        hasKnownDiabetes: false,
      );
      expect(findings.map((f) => f.code), contains('ncd.bpAlone'));
    });

    test('medication adherence low (compliance No) → co-occurs with bpAlone', () {
      final findings = evaluateNcdFindings(
        latest: {
          'bpLog': {'avgSystolic': 150, 'avgDiastolic': 95},
          'symptomsLog': {'compliance': 'No'},
        },
        previous: null,
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(
        findings.map((f) => f.code).toSet(),
        containsAll(['ncd.bpAlone', 'ncd.lowAdherence']),
      );
    });

    test('BP trending down toward target (not currently high) → trending message', () {
      final findings = evaluateNcdFindings(
        latest: {
          'bpLog': {'avgSystolic': 128, 'avgDiastolic': 82},
        },
        previous: {
          'bpLog': {'avgSystolic': 138, 'avgDiastolic': 88},
        },
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(findings.map((f) => f.code), contains('ncd.trendingDown'));
    });

    test('all within target, no trend data → fallback message', () {
      final findings = evaluateNcdFindings(
        latest: {
          'bpLog': {'avgSystolic': 118, 'avgDiastolic': 75},
        },
        previous: null,
        hasKnownHypertension: false,
        hasKnownDiabetes: false,
      );
      expect(findings, hasLength(1));
      expect(findings.first.code, 'ncd.withinTarget');
    });
  });
}
