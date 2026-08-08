import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/briefing_rules/child_immunization_briefing_rules.dart';
import 'package:uhis_next/features/visit/immunisation/epi_schedule_engine.dart';

VaccineEntry _entry({
  required String code,
  required DateTime scheduledDate,
  required VaccineStatus status,
}) =>
    VaccineEntry(
      code: code,
      display: code,
      wireName: code,
      category: 'test',
      description: '',
      route: '',
      cardGroup: 1,
      scheduledDate: scheduledDate,
      status: status,
    );

void main() {
  final today = DateTime(2026, 1, 15);

  group('evaluateChildImmunizationFindings', () {
    test('any dose overdue → overdue count + names message', () {
      final milestones = [
        VaccineMilestone(
          label: '6 Weeks',
          scheduledDate: today.subtract(const Duration(days: 10)),
          offsetType: 'week',
          offsetValue: 6,
          vaccines: [
            _entry(
              code: 'BCG',
              scheduledDate: today.subtract(const Duration(days: 10)),
              status: VaccineStatus.dueNow,
            ),
          ],
        ),
      ];
      final findings = evaluateChildImmunizationFindings(
        milestones: milestones,
        today: today,
      );
      expect(findings, hasLength(1));
      expect(findings.first.code, 'childImmunization.overdue');
      expect(findings.first.message, contains('1 dose(s) overdue'));
      expect(findings.first.message, contains('BCG'));
    });

    test('weight gain slowed (latest <= previous) → flagged', () {
      final findings = evaluateChildImmunizationFindings(
        milestones: const [],
        latestWeightKg: 6.0,
        previousWeightKg: 6.2,
        today: today,
      );
      expect(findings.map((f) => f.code), contains('childImmunization.weightGainSlowed'));
    });

    test('weight gain positive → not flagged', () {
      final findings = evaluateChildImmunizationFindings(
        milestones: const [],
        latestWeightKg: 6.5,
        previousWeightKg: 6.2,
        today: today,
      );
      expect(findings.map((f) => f.code), isNot(contains('childImmunization.weightGainSlowed')));
    });

    test('dose due within next 7 days (not yet overdue) → due-soon message', () {
      final milestones = [
        VaccineMilestone(
          label: '9 Months',
          scheduledDate: today.add(const Duration(days: 5)),
          offsetType: 'month',
          offsetValue: 9,
          vaccines: [
            _entry(
              code: 'Measles',
              scheduledDate: today.add(const Duration(days: 5)),
              status: VaccineStatus.upcoming,
            ),
          ],
        ),
      ];
      final findings = evaluateChildImmunizationFindings(
        milestones: milestones,
        today: today,
      );
      expect(findings, hasLength(1));
      expect(findings.first.code, 'childImmunization.dueSoon');
      expect(findings.first.message, 'Measles due soon — plan for next visit.');
    });

    test('upcoming but more than 7 days away → not due-soon', () {
      final milestones = [
        VaccineMilestone(
          label: '9 Months',
          scheduledDate: today.add(const Duration(days: 20)),
          offsetType: 'month',
          offsetValue: 9,
          vaccines: [
            _entry(
              code: 'Measles',
              scheduledDate: today.add(const Duration(days: 20)),
              status: VaccineStatus.upcoming,
            ),
          ],
        ),
      ];
      final findings = evaluateChildImmunizationFindings(
        milestones: milestones,
        today: today,
      );
      expect(findings.map((f) => f.code), isNot(contains('childImmunization.dueSoon')));
    });

    test('fully on schedule, growth on track → fallback message', () {
      final milestones = [
        VaccineMilestone(
          label: '6 Weeks',
          scheduledDate: today.subtract(const Duration(days: 10)),
          offsetType: 'week',
          offsetValue: 6,
          vaccines: [
            _entry(
              code: 'BCG',
              scheduledDate: today.subtract(const Duration(days: 10)),
              status: VaccineStatus.completed,
            ),
          ],
        ),
      ];
      final findings = evaluateChildImmunizationFindings(
        milestones: milestones,
        latestWeightKg: 6.5,
        previousWeightKg: 6.2,
        today: today,
      );
      expect(findings, hasLength(1));
      expect(findings.first.code, 'childImmunization.onSchedule');
    });
  });
}
