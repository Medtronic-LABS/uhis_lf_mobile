import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/referral.dart';
import 'package:uhis_next/core/models/sla.dart';
import 'package:uhis_next/core/sla/sla_evaluator.dart';

void main() {
  const evaluator = SlaEvaluator();

  ReferralFacts facts({
    String id = 'r1',
    SlaTier tier = SlaTier.emergency,
    ReferralStatus state = ReferralStatus.acknowledged,
    Duration ago = const Duration(hours: 1),
    DateTime? arrival,
    DateTime? treatment,
    int? ageYears,
    bool isEmergencyDx = true,
  }) {
    final now = DateTime(2026, 5, 29, 10, 0, 0);
    return ReferralFacts(
      referralId: id,
      slaTier: tier,
      currentState: state,
      createdAt: now.subtract(ago),
      now: now,
      ageYears: ageYears,
      isEmergencyDiagnosis: isEmergencyDx,
      arrivalConfirmedAt: arrival,
      treatmentStartedAt: treatment,
    );
  }

  group('SlaEvaluator — emergency tier', () {
    test('inside arrival window, before warning band → no breach, no warning',
        () {
      final a = evaluator.evaluate(facts(
        ago: const Duration(minutes: 30),
        state: ReferralStatus.acknowledged,
      ));
      expect(a.state, ReferralStatus.acknowledged);
      expect(a.isBreached, isFalse);
      expect(a.warningArrival, isFalse);
    });

    test('arrival window past breach (>3h) → breachedArrival', () {
      final a = evaluator.evaluate(facts(
        ago: const Duration(hours: 4),
        state: ReferralStatus.inTransit,
      ));
      expect(a.state, ReferralStatus.breachedArrival);
      expect(a.isBreached, isTrue);
      expect(a.breachedSince, isNotNull);
    });

    test('within last 25% of arrival window → warningArrival', () {
      // 3h window, evaluate at 2h35m elapsed (25 minutes remaining =
      // ~14% of window → within warning band of 25%).
      final a = evaluator.evaluate(facts(
        ago: const Duration(hours: 2, minutes: 35),
        state: ReferralStatus.inTransit,
      ));
      expect(a.isBreached, isFalse);
      expect(a.warningArrival, isTrue);
    });

    test('arrival confirmed mid-window → arrived', () {
      final now = DateTime(2026, 5, 29, 10);
      final f = ReferralFacts(
        referralId: 'r-arr',
        slaTier: SlaTier.emergency,
        currentState: ReferralStatus.inTransit,
        createdAt: now.subtract(const Duration(minutes: 90)),
        now: now,
        isEmergencyDiagnosis: true,
        arrivalConfirmedAt: now.subtract(const Duration(minutes: 5)),
      );
      final a = evaluator.evaluate(f);
      expect(a.state, ReferralStatus.arrived);
      expect(a.isBreached, isFalse);
    });

    test(
        'arrived but treatment-window expired → breachedArrival (composite)',
        () {
      final now = DateTime(2026, 5, 29, 10);
      final f = ReferralFacts(
        referralId: 'r-tx',
        slaTier: SlaTier.emergency,
        currentState: ReferralStatus.arrived,
        createdAt: now.subtract(const Duration(hours: 2)),
        now: now,
        isEmergencyDiagnosis: true,
        arrivalConfirmedAt: now.subtract(const Duration(hours: 2)),
      );
      final a = evaluator.evaluate(f);
      expect(a.state, ReferralStatus.breachedArrival);
      expect(a.isBreached, isTrue);
    });

    test('treatment started after arrival → treatmentStarted', () {
      final now = DateTime(2026, 5, 29, 10);
      final f = ReferralFacts(
        referralId: 'r-tx2',
        slaTier: SlaTier.emergency,
        currentState: ReferralStatus.arrived,
        createdAt: now.subtract(const Duration(hours: 2)),
        now: now,
        isEmergencyDiagnosis: true,
        arrivalConfirmedAt: now.subtract(const Duration(minutes: 30)),
        treatmentStartedAt: now.subtract(const Duration(minutes: 5)),
      );
      final a = evaluator.evaluate(f);
      expect(a.state, ReferralStatus.treatmentStarted);
    });
  });

  group('SlaEvaluator — urgent tier', () {
    test('elapsed 25h on inTransit → breach', () {
      final a = evaluator.evaluate(facts(
        tier: SlaTier.urgent,
        ago: const Duration(hours: 25),
        state: ReferralStatus.inTransit,
      ));
      expect(a.state, ReferralStatus.breachedArrival);
      expect(a.isBreached, isTrue);
    });

    test('elapsed 12h with arrival confirmed → arrived, no breach', () {
      final now = DateTime(2026, 5, 29, 10);
      final f = ReferralFacts(
        referralId: 'r-u',
        slaTier: SlaTier.urgent,
        currentState: ReferralStatus.inTransit,
        createdAt: now.subtract(const Duration(hours: 12)),
        now: now,
        arrivalConfirmedAt: now.subtract(const Duration(hours: 6)),
      );
      final a = evaluator.evaluate(f);
      expect(a.state, ReferralStatus.arrived);
      expect(a.isBreached, isFalse);
    });
  });

  group('SlaEvaluator — routine tier', () {
    test('elapsed 4 days on inTransit → no breach yet (window is 7d)', () {
      final a = evaluator.evaluate(facts(
        tier: SlaTier.routine,
        ago: const Duration(days: 4),
        state: ReferralStatus.inTransit,
        isEmergencyDx: false,
      ));
      expect(a.isBreached, isFalse);
    });

    test('elapsed 8 days on inTransit → breach', () {
      final a = evaluator.evaluate(facts(
        tier: SlaTier.routine,
        ago: const Duration(days: 8),
        state: ReferralStatus.inTransit,
        isEmergencyDx: false,
      ));
      expect(a.isBreached, isTrue);
    });
  });

  group('SlaEvaluator — terminal states are no-ops', () {
    for (final s in [
      ReferralStatus.closedRecovered,
      ReferralStatus.closedDeceased,
      ReferralStatus.duplicate,
      ReferralStatus.refused,
      ReferralStatus.targetUnreachable,
      ReferralStatus.transportDeclined,
      ReferralStatus.diverted,
    ]) {
      test('${s.wireTag} stays put', () {
        final a = evaluator.evaluate(facts(
          state: s,
          ago: const Duration(days: 30),
        ));
        expect(a.state, s);
      });
    }
  });

  group('EscalationChain.levelFor', () {
    test('emergency 0 min → SK', () {
      expect(
          EscalationChain.levelFor(SlaTier.emergency, Duration.zero),
          EscalationLevel.sk);
    });
    test('emergency 1 h → Supervisor', () {
      expect(
          EscalationChain.levelFor(SlaTier.emergency, const Duration(hours: 1)),
          EscalationLevel.supervisor);
    });
    test('emergency 4 h → Facility', () {
      expect(
          EscalationChain.levelFor(SlaTier.emergency, const Duration(hours: 4)),
          EscalationLevel.facility);
    });
    test('emergency 10 h → District', () {
      expect(
          EscalationChain.levelFor(
              SlaTier.emergency, const Duration(hours: 10)),
          EscalationLevel.district);
    });
    test('routine 3 days → Supervisor', () {
      expect(
          EscalationChain.levelFor(SlaTier.routine, const Duration(days: 3)),
          EscalationLevel.supervisor);
    });
  });
}
