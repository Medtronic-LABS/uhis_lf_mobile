import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/follow_up_dao.dart';
import 'package:uhis_next/features/patient/followup_call_service.dart';

/// Verifies the device-side follow-up call/close lifecycle + push serializer.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, FollowUpDao, FollowUpCallService)> openDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    final dao = FollowUpDao(app);
    return (app, dao, FollowUpCallService(dao));
  }

  // A server-pulled follow-up (carries its backend id inside rawJson).
  FollowUpRow serverFollowUp(String id, {int? backendId = 42}) => FollowUpRow(
        id: id,
        patientId: 'p1',
        kind: FollowUpKind.medicalReview,
        dueAt: DateTime(2026, 7, 1).millisecondsSinceEpoch,
        attempts: 0,
        unsuccessfulAttempts: 0,
        type: 'REFERRED',
        referredSiteId: 'site-9',
        backendId: backendId,
        syncStatus: FollowUpSyncStatus.success,
        rawJson: jsonEncode({
          'id': backendId,
          'memberId': 'm1',
          'patientId': 'p1',
          'type': 'REFERRED',
        }),
      );

  group('logCall lifecycle', () {
    test('unsuccessful call increments attempts, marks NotSynced, stays open',
        () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);
      await dao.upsertMany([serverFollowUp('f1')]);

      final updated = await svc.logCall(
        followUpId: 'f1',
        status: FollowUpCallStatus.unsuccessful,
        reason: 'no answer',
      );

      expect(updated, isNotNull);
      expect(updated!.attempts, 1);
      expect(updated.unsuccessfulAttempts, 1);
      expect(updated.isCompleted, isFalse);
      expect(updated.syncStatus, FollowUpSyncStatus.notSynced);
      expect(await dao.callsFor('f1'), hasLength(1));
    });

    test('successful call increments attempts but not unsuccessful', () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);
      await dao.upsertMany([serverFollowUp('f1')]);

      final u = await svc.logCall(
        followUpId: 'f1',
        status: FollowUpCallStatus.successful,
      );
      expect(u!.attempts, 1);
      expect(u.unsuccessfulAttempts, 0);
    });

    test('wrong number closes the follow-up immediately', () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);
      await dao.upsertMany([serverFollowUp('f1')]);

      final u = await svc.logCall(
        followUpId: 'f1',
        status: FollowUpCallStatus.wrongNumber,
      );
      expect(u!.isCompleted, isTrue);
      expect(u.isLost, isTrue);
    });

    test('exhausting retry attempts auto-completes the ticket', () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);
      await dao.upsertMany([serverFollowUp('f1')]);

      FollowUpRow? u;
      for (var i = 0; i < 5; i++) {
        u = await svc.logCall(
          followUpId: 'f1',
          status: FollowUpCallStatus.unsuccessful,
          retryAttempts: 5,
        );
      }
      expect(u!.attempts, 5);
      expect(u.isCompleted, isTrue);
    });
  });

  group('pull protection', () {
    test('a server pull does not clobber a locally-edited (NotSynced) row',
        () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);
      await dao.upsertMany([serverFollowUp('f1')]);
      await svc.logCall(
          followUpId: 'f1', status: FollowUpCallStatus.unsuccessful);

      // Server re-sends the same follow-up with attempts reset to 0.
      await dao.upsertMany([serverFollowUp('f1')]);

      final row = await dao.byId('f1');
      expect(row!.attempts, 1, reason: 'local edit must survive the pull');
      expect(row.syncStatus, FollowUpSyncStatus.notSynced);
    });
  });

  group('push serializer', () {
    test('pending follow-ups serialize with calls, provenance, numeric ts',
        () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);
      await dao.upsertMany([serverFollowUp('f1')]);
      await svc.logCall(
        followUpId: 'f1',
        status: FollowUpCallStatus.unsuccessful,
        reason: 'busy',
      );

      final result = await svc.serializePendingForPush(
        provenance: {'modifiedDate': '2026-07-13T10:00:00Z'},
      );

      expect(result.ids, ['f1']);
      expect(result.wire, hasLength(1));
      final w = result.wire.first;
      expect(w['id'], 42, reason: 'server id preserved from rawJson → update');
      expect(w['memberId'], 'm1', reason: 'server routing fields survive');
      expect(w['attempts'], 1);
      expect(w['isCompleted'], isFalse);
      expect(w['updatedAt'], isA<int>());
      expect(w['provenance'], {'modifiedDate': '2026-07-13T10:00:00Z'});
      final details = w['followUpDetails'] as List;
      expect(details, hasLength(1));
      expect(details.first['status'], 'UNSUCCESSFUL');
    });

    test('markPushed flips rows to InProgress and stops re-pushing', () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);
      await dao.upsertMany([serverFollowUp('f1')]);
      await svc.logCall(
          followUpId: 'f1', status: FollowUpCallStatus.unsuccessful);

      expect(await dao.pendingPushCount(), 1);
      await svc.markPushed(['f1']);
      expect(await dao.pendingPushCount(), 0);
      expect((await dao.byId('f1'))!.syncStatus, FollowUpSyncStatus.inProgress);
    });
  });

  group('scheduleLocal (device-created follow-up)', () {
    test('creates a NotSynced, open follow-up that is push-eligible', () async {
      final (db, dao, svc) = await openDb();
      addTearDown(db.close);

      final id = await svc.scheduleLocal(
        patientId: 'p2',
        dueDate: DateTime(2026, 8, 1),
        reason: 'referral check',
      );
      final row = await dao.byId(id);
      expect(row, isNotNull);
      expect(row!.syncStatus, FollowUpSyncStatus.notSynced);
      expect(row.isCompleted, isFalse);
      expect(await dao.pendingPushCount(), 1);
    });
  });
}
