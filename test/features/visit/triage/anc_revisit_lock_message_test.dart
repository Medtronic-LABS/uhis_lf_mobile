import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/i18n/app_date_format.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/features/visit/triage/anc_revisit_lock_message.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppDateFormat.ensureInitialised();
  });

  setUp(() => AppLocale.current = AppLanguage.english);

  group('isAncRevisitTooSoon', () {
    test('high-risk: unlocked on the next calendar day (Spice parity)', () {
      final lastVisit = DateTime(2026, 9, 1, 21, 30);
      final now = DateTime(2026, 9, 2, 9, 0);

      expect(
        isAncRevisitTooSoon(
          lastVisitMs: lastVisit.millisecondsSinceEpoch,
          revisitDays: 1,
          now: now,
        ),
        isFalse,
        reason: 'Visit yesterday evening should not block this morning',
      );
    });

    test('high-risk: locked on the same calendar day', () {
      final lastVisit = DateTime(2026, 9, 1, 9, 0);
      final now = DateTime(2026, 9, 1, 21, 0);

      expect(
        isAncRevisitTooSoon(
          lastVisitMs: lastVisit.millisecondsSinceEpoch,
          revisitDays: 1,
          now: now,
        ),
        isTrue,
      );
    });

    test('normal: locked until 15 calendar days have passed', () {
      final lastVisit = DateTime(2026, 8, 14);
      final day14 = DateTime(2026, 8, 28);
      final day15 = DateTime(2026, 8, 29);

      expect(
        isAncRevisitTooSoon(
          lastVisitMs: lastVisit.millisecondsSinceEpoch,
          revisitDays: 15,
          now: day14,
        ),
        isTrue,
      );
      expect(
        isAncRevisitTooSoon(
          lastVisitMs: lastVisit.millisecondsSinceEpoch,
          revisitDays: 15,
          now: day15,
        ),
        isFalse,
      );
    });
  });

  group('computeAncRevisitLock', () {
    test('same-day ANC locks even when lastVisitMs is yesterday', () {
      final yesterday = DateTime(2026, 9, 1, 14, 0);
      final now = DateTime(2026, 9, 2, 10, 0);

      final lock = computeAncRevisitLock(
        lastVisitMs: yesterday.millisecondsSinceEpoch,
        highRisk: true,
        ancAssessmentToday: true,
        now: now,
      );

      expect(lock.tooSoon, isTrue);
      expect(lock.lastVisitMs, isNull);
      expect(lock.revisitDays, 1);
    });

    test('high-risk: unlocked on next calendar day without same-day ANC', () {
      final yesterday = DateTime(2026, 9, 1, 21, 30);
      final now = DateTime(2026, 9, 2, 9, 0);

      final lock = computeAncRevisitLock(
        lastVisitMs: yesterday.millisecondsSinceEpoch,
        highRisk: true,
        ancAssessmentToday: false,
        now: now,
      );

      expect(lock.tooSoon, isFalse);
    });

    test('same-day ANC locks when lastVisitMs is null', () {
      final now = DateTime(2026, 9, 2, 10, 0);

      final lock = computeAncRevisitLock(
        lastVisitMs: null,
        highRisk: false,
        ancAssessmentToday: true,
        now: now,
      );

      expect(lock.tooSoon, isTrue);
    });
  });

  group('ancRevisitLockMessage', () {
    test('high-risk uses 1-day interval wording', () {
      final msg = ancRevisitLockMessage(
        AncRevisitLockInput(
          lastVisitMs: DateTime(2026, 8, 14).millisecondsSinceEpoch,
          highRisk: true,
          revisitDays: 1,
        ),
      );

      expect(msg, contains('14 Aug 2026'));
      expect(msg, contains('revisit in 1 day'));
      expect(msg, isNot(contains('next due')));
    });

    test('normal uses interval days without next due date', () {
      final msg = ancRevisitLockMessage(
        AncRevisitLockInput(
          lastVisitMs: DateTime(2026, 8, 14).millisecondsSinceEpoch,
          highRisk: false,
          revisitDays: 15,
        ),
      );

      expect(msg, contains('14 Aug 2026'));
      expect(msg, contains('revisit in 15 days'));
      expect(msg, isNot(contains('next due')));
    });
  });
}
