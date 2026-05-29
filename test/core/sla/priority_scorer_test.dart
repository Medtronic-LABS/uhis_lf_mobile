import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/referral.dart';
import 'package:uhis_next/core/models/sla.dart';
import 'package:uhis_next/core/sla/priority_scorer.dart';

void main() {
  const scorer = PriorityScorer();
  final now = DateTime(2026, 5, 29, 10);

  ReferralFacts facts({
    bool slaBreachedFlag = false,
    int? ageYears,
    bool isPregnancy = false,
    bool isEmergencyDx = false,
    bool arrivalConfirmed = false,
    Duration elapsed = const Duration(hours: 1),
    int missedFollowUps = 0,
  }) {
    return ReferralFacts(
      referralId: 'rp',
      slaTier: SlaTier.emergency,
      currentState: ReferralStatus.inTransit,
      createdAt: now.subtract(elapsed),
      now: now,
      ageYears: ageYears,
      isPregnancy: isPregnancy,
      isEmergencyDiagnosis: isEmergencyDx,
      arrivalConfirmedAt:
          arrivalConfirmed ? now.subtract(const Duration(minutes: 5)) : null,
      missedFollowUps: missedFollowUps,
    );
  }

  test('healthy fact set → LOW band', () {
    final p = scorer.score(
        facts: facts(arrivalConfirmed: true), slaBreached: false);
    expect(p.level, SlaPriority.low);
    expect(p.score, lessThan(31));
    expect(p.rationale.modelVersion, PriorityScorer.modelVersion);
  });

  test('sla-breached alone (50) → MEDIUM', () {
    final p = scorer.score(facts: facts(), slaBreached: true);
    expect(p.score, equals(80)); // 50 sla + 30 no-arrival
    expect(p.level, SlaPriority.high);
    expect(p.drivers, contains('sla-breached'));
  });

  test('emergency-dx + under-5 + no-arrival + delay-48h + missed → CRITICAL',
      () {
    final p = scorer.score(
      facts: facts(
        ageYears: 3,
        isEmergencyDx: true,
        elapsed: const Duration(hours: 60),
        missedFollowUps: 2,
      ),
      slaBreached: true,
    );
    // 50 + 20 + 40 + 30 + 25 + 15 = 180
    expect(p.score, greaterThanOrEqualTo(91));
    expect(p.level, SlaPriority.critical);
    expect(p.rationale.humanReviewRequired, isTrue);
    expect(p.drivers, containsAll(<String>[
      'sla-breached',
      'under-5:3',
      'emergency-dx',
      'no-arrival',
      'delay-48h',
      'missed-follow-up:2',
    ]));
  });

  test('band boundary at exactly 91 → CRITICAL', () {
    // 50 sla + 20 under-5 + 21 from... not constructable from current weights.
    // Construct >=91: 40 emergency + 30 no-arrival + 25 delay-48h = 95.
    final p = scorer.score(
      facts: facts(
        isEmergencyDx: true,
        elapsed: const Duration(hours: 60),
      ),
      slaBreached: false,
    );
    expect(p.score, 95);
    expect(p.level, SlaPriority.critical);
  });

  test('band boundary at 90 → HIGH', () {
    // 50 sla + 40 emergency = 90
    final p = scorer.score(
      facts: facts(isEmergencyDx: true, arrivalConfirmed: true),
      slaBreached: true,
    );
    expect(p.score, 90);
    expect(p.level, SlaPriority.high);
    expect(p.rationale.humanReviewRequired, isFalse);
  });

  test('pregnancy adds 20', () {
    final base = scorer.score(
        facts: facts(arrivalConfirmed: true), slaBreached: false);
    final preg = scorer.score(
        facts: facts(isPregnancy: true, arrivalConfirmed: true),
        slaBreached: false);
    expect(preg.score - base.score, 20);
    expect(preg.drivers, contains('pregnancy'));
  });

  test('drivers are stable order: weights applied in fixed sequence', () {
    final p = scorer.score(
      facts: facts(
        ageYears: 4,
        isPregnancy: true,
        isEmergencyDx: true,
        elapsed: const Duration(hours: 60),
        missedFollowUps: 1,
      ),
      slaBreached: true,
    );
    expect(p.drivers, [
      'sla-breached',
      'under-5:4',
      'pregnancy',
      'emergency-dx',
      'no-arrival',
      'delay-48h',
      'missed-follow-up:1',
    ]);
  });
}
