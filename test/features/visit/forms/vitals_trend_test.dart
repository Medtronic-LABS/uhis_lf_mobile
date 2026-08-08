import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/vitals_trend.dart';

void main() {
  group('VitalsTrendAnalyzer', () {
    test('shows systolic when 3 readings rise by ≥5 each step', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 110, diastolic: 70, weight: 55.0),
          VisitVitals(systolic: 116, diastolic: 72, weight: 55.5),
        ],
        today: const VisitVitals(
          systolic: 122,
          diastolic: 74,
          weight: 56.0,
        ),
      );

      expect(result.show, isTrue);
      expect(result.columns.length, 3);
      expect(result.metrics.map((m) => m.metric), [VitalMetric.systolic]);
      expect(result.metrics.single.rising, isTrue);
    });

    test('hides numeric row when a step rises by less than 5', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 110),
          VisitVitals(systolic: 112), // +2
        ],
        today: const VisitVitals(systolic: 120), // +8
      );

      expect(result.show, isFalse);
      expect(result.metrics, isEmpty);
    });

    test('hides numeric row when a step dips', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 120),
          VisitVitals(systolic: 126),
        ],
        today: const VisitVitals(systolic: 124),
      );

      expect(result.show, isFalse);
    });

    test('shows weight when rising by ≥5 kg each step', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(weight: 55.0),
          VisitVitals(weight: 60.5),
        ],
        today: const VisitVitals(weight: 66.0),
      );

      expect(result.show, isTrue);
      expect(result.metrics.single.metric, VitalMetric.weight);
    });

    test('hides weight when gain is under 5 kg per step', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(weight: 60.0),
          VisitVitals(weight: 61.0),
        ],
        today: const VisitVitals(weight: 62.0),
      );

      expect(result.show, isFalse);
    });

    test('shows urine when 3 grades captured and at least one Present', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(urineProtein: 'Absent'),
          VisitVitals(urineProtein: 'Absent'),
        ],
        today: const VisitVitals(urineProtein: 'Present'),
      );

      expect(result.show, isTrue);
      expect(result.metrics.single.metric, VitalMetric.urineProtein);
    });

    test('hides urine when only Trace is positive (Present-only)', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(urineProtein: 'Absent'),
          VisitVitals(urineProtein: 'Trace'),
        ],
        today: const VisitVitals(urineProtein: 'Absent'),
      );

      expect(result.show, isFalse);
    });

    test('hides urine when a grade is missing among the 3 visits', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(urineProtein: 'Absent'),
          VisitVitals(urineProtein: 'Absent'),
        ],
        today: const VisitVitals(), // no urine today
      );

      expect(result.show, isFalse);
    });

    test('returns empty when fewer than 2 prior visits', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 110),
        ],
        today: const VisitVitals(systolic: 130),
      );

      expect(result.show, isFalse);
      expect(result.metrics, isEmpty);
      expect(result.columns, isEmpty);
    });

    test('omits params that fail while keeping qualifying ones', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(
            systolic: 118,
            diastolic: 78,
            weight: 60.0,
            urineProtein: 'Absent',
          ),
          VisitVitals(
            systolic: 124,
            diastolic: 80,
            weight: 61.0,
            urineProtein: 'Absent',
          ),
        ],
        today: const VisitVitals(
          systolic: 130,
          diastolic: 82,
          weight: 62.0,
          urineProtein: 'Present',
        ),
      );

      expect(result.show, isTrue);
      final kinds = result.metrics.map((m) => m.metric).toSet();
      expect(kinds, {
        VitalMetric.systolic, // +6, +6
        VitalMetric.urineProtein, // Present
      });
      expect(kinds.contains(VitalMetric.diastolic), isFalse); // +2, +2
      expect(kinds.contains(VitalMetric.weight), isFalse); // +1, +1
    });

    test('uses only the last two priors when more history exists', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 100), // ignored
          VisitVitals(systolic: 110),
          VisitVitals(systolic: 116),
        ],
        today: const VisitVitals(systolic: 122),
      );

      expect(result.columns.length, 3);
      expect(result.show, isTrue);
      expect(
        result.metrics.single.values,
        [110.0, 116.0, 122.0],
      );
    });

    test('derives days-ago sub-label from visit dates', () {
      final now = DateTime(2026, 7, 9);
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: [
          VisitVitals(
            date: now.subtract(const Duration(days: 56)),
            systolic: 110,
          ),
          VisitVitals(
            date: now.subtract(const Duration(days: 28)),
            systolic: 116,
          ),
        ],
        today: const VisitVitals(systolic: 122),
        todayDate: now,
      );
      expect(result.columns.first.daysAgo, 56);
      expect(result.columns[1].daysAgo, 28);
      expect(result.columns.last.isToday, isTrue);
    });
  });

  group('isUrineProteinPresent', () {
    test('Present aliases count; Trace and Absent do not', () {
      expect(isUrineProteinPresent('Present'), isTrue);
      expect(isUrineProteinPresent('positive'), isTrue);
      expect(isUrineProteinPresent('Trace'), isFalse);
      expect(isUrineProteinPresent('Absent'), isFalse);
      expect(isUrineProteinPresent(null), isFalse);
    });
  });
}
