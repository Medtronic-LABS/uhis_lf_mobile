/// Unit tests for [TelemetryDao] — the persistence half of the AI Scribe /
/// counselling telemetry feature.
///
/// The date-range and purge behaviours are the load-bearing ones: the whole
/// point of the feature is generating a report for a chosen range, and the
/// retention rule has to be able to drop old uploaded rows without ever
/// touching one that hasn't reached the server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/telemetry_dao.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';

Future<AppDatabase> _openInMemoryDb() async {
  final rawDb = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppDatabase.schemaVersion,
      onCreate: AppDatabase.createSchema,
    ),
  );
  return AppDatabase.forTesting(rawDb);
}

TelemetryEvent _event({
  required String id,
  required DateTime occurredAt,
  String eventType = TelemetryEventType.visitCompleted,
  String? skUserId = 'sk-1',
  Map<String, dynamic>? payload,
  String uploadStatus = TelemetryUploadStatus.pending,
  int? uploadedAt,
}) =>
    TelemetryEvent(
      id: id,
      eventType: eventType,
      occurredAt: occurredAt.millisecondsSinceEpoch,
      visitUuid: 'visit-$id',
      skUserId: skUserId,
      appVersion: '1.0.6',
      appBuild: 6,
      payloadVersion: kTelemetryPayloadVersion,
      payload: payload ?? const {'scribeUsed': true},
      uploadStatus: uploadStatus,
      uploadedAt: uploadedAt,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late TelemetryDao dao;

  setUp(() async {
    db = await _openInMemoryDb();
    dao = TelemetryDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('insert / round-trip', () {
    test('every field survives a write-read cycle', () async {
      final at = DateTime(2026, 9, 4, 10, 30);
      await dao.insert(_event(
        id: 'e1',
        occurredAt: at,
        payload: {
          'programmes': ['anc', 'ncd'],
          'scribeUsed': true,
          'fields': {
            'aiFilled': ['systolic', 'weight']
          },
        },
      ));

      final rows = await dao.inRange(at, at);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.id, 'e1');
      expect(row.eventType, TelemetryEventType.visitCompleted);
      expect(row.occurredAt, at.millisecondsSinceEpoch);
      expect(row.visitUuid, 'visit-e1');
      expect(row.skUserId, 'sk-1');
      expect(row.appVersion, '1.0.6');
      expect(row.appBuild, 6);
      expect(row.payloadVersion, kTelemetryPayloadVersion);
      expect(row.uploadStatus, TelemetryUploadStatus.pending);
      expect(row.uploadedAt, isNull);
      // Payload is stored as JSON text — confirm structure, not just presence.
      expect(row.payload['programmes'], ['anc', 'ncd']);
      expect((row.payload['fields'] as Map)['aiFilled'], ['systolic', 'weight']);
    });

    test('re-inserting the same id is a no-op, not a crash', () async {
      // id doubles as the server dedup key, so a duplicate emit must be safe.
      final at = DateTime(2026, 9, 4);
      await dao.insert(_event(id: 'dup', occurredAt: at));
      await dao.insert(_event(id: 'dup', occurredAt: at));

      expect((await dao.counts()).total, 1);
    });

    test('an unparseable payload still yields a countable row', () async {
      await db.db.insert(AppDatabase.tableTelemetryEvents, {
        'id': 'bad',
        'event_type': TelemetryEventType.visitCompleted,
        'occurred_at': DateTime(2026, 9, 4).millisecondsSinceEpoch,
        'app_version': '1.0.6',
        'app_build': 6,
        'payload_version': 1,
        'payload': 'not-json{',
      });

      final rows = await dao.inRange(DateTime(2026, 9, 4), DateTime(2026, 9, 4));
      expect(rows, hasLength(1));
      expect(rows.single.payload, isEmpty);
    });
  });

  group('inRange — whole-day inclusive at both ends', () {
    setUp(() async {
      await dao.insert(_event(id: 'before', occurredAt: DateTime(2026, 8, 31, 23, 59)));
      await dao.insert(_event(id: 'first-midnight', occurredAt: DateTime(2026, 9, 1, 0, 0)));
      await dao.insert(_event(id: 'middle', occurredAt: DateTime(2026, 9, 4, 12, 0)));
      await dao.insert(_event(id: 'last-late', occurredAt: DateTime(2026, 9, 7, 23, 59, 59)));
      await dao.insert(_event(id: 'after', occurredAt: DateTime(2026, 9, 8, 0, 0)));
    });

    test('includes the whole of the first and last day', () async {
      final rows = await dao.inRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7));

      expect(
        rows.map((e) => e.id),
        containsAll(['first-midnight', 'middle', 'last-late']),
      );
      // A naive `<= to` would cut the final day off at midnight and silently
      // under-report it — this is the assertion that guards that.
      expect(rows.map((e) => e.id), isNot(contains('before')));
      expect(rows.map((e) => e.id), isNot(contains('after')));
      expect(rows, hasLength(3));
    });

    test('a single-day range returns that day only', () async {
      final rows = await dao.inRange(DateTime(2026, 9, 4), DateTime(2026, 9, 4));
      expect(rows.map((e) => e.id), ['middle']);
    });

    test('the time component of the caller\'s dates is ignored', () async {
      // The picker hands over whatever time it happened to construct with.
      final rows = await dao.inRange(
        DateTime(2026, 9, 7, 18, 45),
        DateTime(2026, 9, 7, 6, 15),
      );
      expect(rows.map((e) => e.id), ['last-late']);
    });

    test('newest first', () async {
      final rows = await dao.inRange(DateTime(2026, 8, 1), DateTime(2026, 9, 30));
      expect(rows.first.id, 'after');
      expect(rows.last.id, 'before');
    });
  });

  group('pending / markUploaded', () {
    test('pending returns only unsent rows, oldest first', () async {
      await dao.insert(_event(id: 'p2', occurredAt: DateTime(2026, 9, 5)));
      await dao.insert(_event(id: 'p1', occurredAt: DateTime(2026, 9, 4)));
      await dao.insert(_event(
        id: 'done',
        occurredAt: DateTime(2026, 9, 3),
        uploadStatus: TelemetryUploadStatus.uploaded,
        uploadedAt: DateTime(2026, 9, 3).millisecondsSinceEpoch,
      ));

      final pending = await dao.pending();
      expect(pending.map((e) => e.id), ['p1', 'p2']);
    });

    test('markUploaded stamps status and time', () async {
      await dao.insert(_event(id: 'p1', occurredAt: DateTime(2026, 9, 4)));
      final at = DateTime(2026, 9, 6, 8, 0);

      final updated = await dao.markUploaded(['p1'], at: at);

      expect(updated, 1);
      final row = (await dao.inRange(DateTime(2026, 9, 4), DateTime(2026, 9, 4))).single;
      expect(row.uploadStatus, TelemetryUploadStatus.uploaded);
      expect(row.uploadedAt, at.millisecondsSinceEpoch);
      expect(await dao.pending(), isEmpty);
    });

    test('markUploaded with no ids touches nothing', () async {
      await dao.insert(_event(id: 'p1', occurredAt: DateTime(2026, 9, 4)));
      expect(await dao.markUploaded(const []), 0);
      expect(await dao.pending(), hasLength(1));
    });
  });

  group('purgeUploadedOlderThan — retention', () {
    test('drops uploaded rows past the window, keeps recent ones', () async {
      final now = DateTime(2026, 10, 1);
      await dao.insert(_event(
        id: 'old-uploaded',
        occurredAt: DateTime(2026, 8, 1),
        uploadStatus: TelemetryUploadStatus.uploaded,
        uploadedAt: DateTime(2026, 8, 1).millisecondsSinceEpoch,
      ));
      await dao.insert(_event(
        id: 'recent-uploaded',
        occurredAt: DateTime(2026, 9, 25),
        uploadStatus: TelemetryUploadStatus.uploaded,
        uploadedAt: DateTime(2026, 9, 25).millisecondsSinceEpoch,
      ));

      final removed =
          await dao.purgeUploadedOlderThan(const Duration(days: 30), now: now);

      expect(removed, 1);
      expect((await dao.counts()).total, 1);
      final left = await dao.inRange(DateTime(2026, 8, 1), DateTime(2026, 10, 1));
      expect(left.map((e) => e.id), ['recent-uploaded']);
    });

    test('NEVER drops a pending row, however old', () async {
      // Until the upload path exists this table is the only copy of the data,
      // so age alone must never be grounds for deletion.
      await dao.insert(_event(id: 'ancient-pending', occurredAt: DateTime(2025, 1, 1)));

      final removed = await dao.purgeUploadedOlderThan(
        const Duration(days: 30),
        now: DateTime(2026, 10, 1),
      );

      expect(removed, 0);
      expect((await dao.counts()).pending, 1);
    });

    test('an uploaded row with no timestamp is left alone', () async {
      await dao.insert(_event(
        id: 'no-stamp',
        occurredAt: DateTime(2025, 1, 1),
        uploadStatus: TelemetryUploadStatus.uploaded,
      ));

      expect(
        await dao.purgeUploadedOlderThan(const Duration(days: 30),
            now: DateTime(2026, 10, 1)),
        0,
      );
    });
  });

  test('counts reports total and pending separately', () async {
    await dao.insert(_event(id: 'a', occurredAt: DateTime(2026, 9, 1)));
    await dao.insert(_event(
      id: 'b',
      occurredAt: DateTime(2026, 9, 2),
      uploadStatus: TelemetryUploadStatus.uploaded,
      uploadedAt: DateTime(2026, 9, 2).millisecondsSinceEpoch,
    ));

    final counts = await dao.counts();
    expect(counts.total, 2);
    expect(counts.pending, 1);
  });
}
