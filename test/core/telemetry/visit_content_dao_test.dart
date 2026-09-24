library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/visit_content_dao.dart';
import 'package:uhis_next/core/telemetry/visit_content_entry.dart';

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

VisitContentEntry _entry({
  String id = 'vc1',
  String visitUuid = 'visit-1',
  String patientId = 'patient-1',
  String? transcript = 'hello world',
  int occurredAt = 1788940800000,
}) =>
    VisitContentEntry(
      id: id,
      visitUuid: visitUuid,
      patientId: patientId,
      transcript: transcript,
      transcriptCapturedAt: transcript == null ? null : occurredAt,
      occurredAt: occurredAt,
    );

void main() {
  late AppDatabase db;
  late VisitContentDao dao;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await _openInMemoryDb();
    dao = VisitContentDao(db);
  });

  tearDown(() async => db.close());

  test('upsert stores and reads back by visit uuid', () async {
    await dao.upsert(_entry());
    final row = await dao.byVisitUuid('visit-1');
    expect(row?.transcript, 'hello world');
    expect(row?.patientId, 'patient-1');
  });

  test('upsert replaces the same visit row', () async {
    await dao.upsert(_entry(transcript: 'first'));
    await dao.upsert(_entry(
      id: 'vc2',
      transcript: 'second',
      occurredAt: 1788940900000,
    ));
    expect((await dao.counts()).total, 1);
    expect((await dao.byVisitUuid('visit-1'))?.transcript, 'second');
  });

  test('pending returns oldest first', () async {
    await dao.upsert(_entry(id: 'a', visitUuid: 'v2', occurredAt: 2000));
    await dao.upsert(_entry(id: 'b', visitUuid: 'v1', occurredAt: 1000));

    expect((await dao.pending()).map((e) => e.id), ['b', 'a']);
  });

  test('markUploaded removes rows from pending', () async {
    await dao.upsert(_entry());
    await dao.markUploaded(['vc1']);

    expect((await dao.counts()).pending, 0);
    expect((await dao.counts()).total, 1);
  });

  test('api payload uses ISO instants', () {
    final json = _entry().toApiJson();
    expect(json['transcriptCapturedAt'], '2026-09-09T08:00:00.000Z');
    expect(json['visitUuid'], 'visit-1');
    expect(json['patientId'], 'patient-1');
  });
}
