import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/pregnancy_episode_dao.dart';
import 'package:uhis_next/core/db/pregnancy_snapshot_dao.dart';
import 'package:uhis_next/core/mission/mission_pregnancy_facts.dart';
import 'package:uhis_next/core/risk/pregnancy_cohort_rules.dart';
import 'package:uhis_next/core/risk/pregnancy_rmnch_menu_gating.dart';

void main() {
  final now = DateTime(2026, 10, 13);

  PregnancySnapshotRow snap({
    int? lmpDaysAgo,
    int? eddDaysFromNow,
    int? deliveryDaysAgo,
  }) {
    return PregnancySnapshotRow(
      patientId: 'p1',
      facts: PregnancyFacts.empty,
      lmpDate: lmpDaysAgo == null
          ? null
          : now.subtract(Duration(days: lmpDaysAgo)).millisecondsSinceEpoch,
      eddDate: eddDaysFromNow == null
          ? null
          : now.add(Duration(days: eddDaysFromNow)).millisecondsSinceEpoch,
      deliveryDateMillis: deliveryDaysAgo == null
          ? null
          : now.subtract(Duration(days: deliveryDaysAgo)).millisecondsSinceEpoch,
    );
  }

  PregnancyEpisodeRow openEpisode(PregnancySnapshotRow obstetric) {
    return PregnancyEpisodeRow(
      id: 'ep1',
      patientId: 'p1',
      startedAt: now.millisecondsSinceEpoch,
      obstetric: obstetric,
    );
  }

  group('episodeForMenus — Spice relevance filter', () {
    test('stale open episode (EDD years overdue) is ignored', () {
      final raw = openEpisode(snap(lmpDaysAgo: 990, eddDaysFromNow: -700));
      expect(PregnancyCohortRules.isRelevantForRmnchMenus(raw.obstetric, now: now),
          isFalse);
      expect(PregnancyRmnchMenuGating.episodeForMenus(raw, now: now), isNull);
    });

    test('active pregnancy within grace is kept', () {
      final raw = openEpisode(snap(lmpDaysAgo: 100, eddDaysFromNow: 30));
      expect(PregnancyRmnchMenuGating.episodeForMenus(raw, now: now), isNotNull);
    });
  });

  group('isAncEarlyLmpBlocked', () {
    test('true only under 6 weeks on active pregnancy', () {
      expect(
        PregnancyRmnchMenuGating.isAncEarlyLmpBlocked(
          snap(lmpDaysAgo: 30),
          now: now,
        ),
        isTrue,
      );
    });

    test('false when LMP is old (Sabita-like)', () {
      expect(
        PregnancyRmnchMenuGating.isAncEarlyLmpBlocked(
          snap(lmpDaysAgo: 990, eddDaysFromNow: -700),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('isPregnancyOutcomeLocked', () {
    test('unlocked when no relevant obstetric row', () {
      expect(
        PregnancyRmnchMenuGating.isPregnancyOutcomeLocked(null, now: now),
        isFalse,
      );
    });

    test('locked only in postnatal window on relevant row', () {
      expect(
        PregnancyRmnchMenuGating.isPregnancyOutcomeLocked(
          snap(lmpDaysAgo: 200, deliveryDaysAgo: 10),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
