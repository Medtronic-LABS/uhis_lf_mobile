import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/referral_dao.dart';
import 'package:uhis_next/core/models/referral.dart';
import 'package:uhis_next/core/models/sla.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, ReferralDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, ReferralDao(app));
  }

  group('ReferralDao round-trip', () {
    test('upsert + byId + dashboard order', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      final now = DateTime(2026, 5, 29, 10).millisecondsSinceEpoch;
      final critical = Referral(
        id: 'r1',
        patientId: 'p1',
        slaTier: SlaTier.emergency,
        state: ReferralStatus.inTransit,
        createdAt: now - const Duration(hours: 4).inMilliseconds,
        updatedAt: now,
        priorityScore: 145,
        priorityLevel: SlaPriority.critical.wireTag,
        priorityDrivers: const ['sla-breached', 'emergency-dx'],
        breachedSince: now - const Duration(minutes: 30).inMilliseconds,
      );
      final low = Referral(
        id: 'r2',
        patientId: 'p2',
        slaTier: SlaTier.routine,
        state: ReferralStatus.acknowledged,
        createdAt: now - const Duration(hours: 1).inMilliseconds,
        updatedAt: now,
        priorityScore: 20,
        priorityLevel: SlaPriority.low.wireTag,
      );
      await dao.upsertMany([low, critical]);

      final byId = await dao.byId('r1');
      expect(byId, isNotNull);
      expect(byId!.priorityScore, 145);
      expect(byId.priorityDrivers, ['sla-breached', 'emergency-dx']);

      final dash = await dao.queryDashboard();
      expect(dash.first.id, 'r1');
      expect(dash[1].id, 'r2');

      expect(await dao.countByLevel(SlaPriority.critical), 1);
      expect(await dao.countActive(), 2);
    });

    test('appendStatusEvent + eventsForReferral preserve order', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      final t0 = DateTime(2026, 5, 29, 10).millisecondsSinceEpoch;
      await dao.appendStatusEvent(ReferralStatusEventRow(
          id: 'e1',
          referralId: 'r1',
          toState: ReferralStatus.created,
          occurredAt: t0));
      await dao.appendStatusEvent(ReferralStatusEventRow(
          id: 'e2',
          referralId: 'r1',
          fromState: ReferralStatus.created,
          toState: ReferralStatus.acknowledged,
          occurredAt: t0 + 60000));
      final events = await dao.eventsForReferral('r1');
      expect(events, hasLength(2));
      expect(events.first.toState, ReferralStatus.created);
      expect(events.last.toState, ReferralStatus.acknowledged);
    });

    test('notification log pending repeats query', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);

      final now = DateTime(2026, 5, 29, 10).millisecondsSinceEpoch;
      await dao.logNotification(NotificationLogRow(
          id: 'n1',
          referralId: 'r1',
          channel: 'referral_critical',
          firedAt: now - 1000,
          nextRepeatAt: now - 500));
      await dao.logNotification(NotificationLogRow(
          id: 'n2',
          referralId: 'r1',
          channel: 'referral_critical',
          firedAt: now - 100,
          nextRepeatAt: now + 60_000));
      final pending = await dao.pendingRepeats(olderThanMs: now);
      expect(pending, hasLength(1));
      expect(pending.first.id, 'n1');
    });

    test('queryDashboard with filter + includeClosed flag', () async {
      final (db, dao) = await openTestDb();
      addTearDown(db.close);
      final now = DateTime(2026, 5, 29, 10).millisecondsSinceEpoch;
      await dao.upsertMany([
        Referral(
          id: 'open',
          patientId: 'p1',
          slaTier: SlaTier.urgent,
          state: ReferralStatus.inTransit,
          createdAt: now,
          updatedAt: now,
          priorityScore: 70,
          priorityLevel: SlaPriority.high.wireTag,
        ),
        Referral(
          id: 'closed',
          patientId: 'p2',
          slaTier: SlaTier.emergency,
          state: ReferralStatus.closedRecovered,
          createdAt: now,
          updatedAt: now,
          priorityScore: 95,
          priorityLevel: SlaPriority.critical.wireTag,
        ),
      ]);
      final activeOnly = await dao.queryDashboard();
      expect(activeOnly, hasLength(1));
      expect(activeOnly.first.id, 'open');
      final all = await dao.queryDashboard(includeClosed: true);
      expect(all, hasLength(2));
      final highFilter =
          await dao.queryDashboard(levelFilter: SlaPriority.high);
      expect(highFilter.single.id, 'open');
    });
  });
}
