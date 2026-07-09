import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/vitals_trend.dart';

void main() {
  group('VitalsTrendAnalyzer', () {
    test('shows card when systolic BP climbs across visits', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 120, diastolic: 78, weight: 65.0, urineProtein: 'Absent'),
          VisitVitals(systolic: 126, diastolic: 82, weight: 66.5, urineProtein: 'Absent'),
        ],
        today: const VisitVitals(
          systolic: 132,
          diastolic: 86,
          weight: 67.3,
          urineProtein: 'Trace',
        ),
      );

      expect(result.show, isTrue);
      expect(result.columns.length, 3); // V1, V2, Today
      final systolic =
          result.metrics.firstWhere((m) => m.metric == VitalMetric.systolic);
      expect(systolic.rising, isTrue);
      final urine = result.metrics
          .firstWhere((m) => m.metric == VitalMetric.urineProtein);
      expect(urine.rising, isTrue); // Absent(0) → Absent(0) → Trace(1)
    });

    test('hides card when BP is flat or falling even if weight rises', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 120, diastolic: 80, weight: 60.0),
          VisitVitals(systolic: 118, diastolic: 78, weight: 62.0),
        ],
        today: const VisitVitals(systolic: 116, diastolic: 76, weight: 64.0),
      );

      expect(result.show, isFalse);
    });

    test('returns empty when there are no prior visits', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [],
        today: const VisitVitals(systolic: 140, diastolic: 90),
      );

      expect(result.show, isFalse);
      expect(result.metrics, isEmpty);
    });

    test('a single dip breaks the rising trend', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 120),
          VisitVitals(systolic: 130),
        ],
        today: const VisitVitals(systolic: 125),
      );
      // 120 → 130 → 125 dips at the last step, so not "rising".
      expect(result.show, isFalse);
    });

    test('caps the table to two prior visits plus today', () {
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: const [
          VisitVitals(systolic: 110),
          VisitVitals(systolic: 115),
          VisitVitals(systolic: 120),
          VisitVitals(systolic: 125),
        ],
        today: const VisitVitals(systolic: 130),
      );
      expect(result.columns.length, 3);
      expect(result.show, isTrue);
    });

    test('derives days-ago sub-label from visit dates', () {
      final now = DateTime(2026, 7, 9);
      final result = VitalsTrendAnalyzer.analyze(
        priorVisits: [
          VisitVitals(date: now.subtract(const Duration(days: 56)), systolic: 120),
          VisitVitals(date: now.subtract(const Duration(days: 28)), systolic: 126),
        ],
        today: const VisitVitals(systolic: 132),
        todayDate: now,
      );
      expect(result.columns.first.daysAgo, 56);
      expect(result.columns[1].daysAgo, 28);
      expect(result.columns.last.isToday, isTrue);
    });
  });
}
