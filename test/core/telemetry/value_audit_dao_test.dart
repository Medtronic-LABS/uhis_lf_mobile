/// The PHI value-audit queue.
///
/// Mirrors telemetry_dao_test.dart, with one deliberate difference: there is no
/// purge test, because this table has no purge. The SK-handover wipe is its
/// device-side retention policy — asserted in
/// test/core/db/telemetry_wipe_exclusion_test.dart, which covers both sides of
/// the boundary.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/value_audit_dao.dart';
import 'package:uhis_next/core/telemetry/value_audit_entry.dart';

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

ValueAuditEntry _entry({
  String id = 'a1',
  String visitUuid = 'v-1',
  String fieldId = 'systolic',
  String? aiValue = '160',
  String? finalValue = '140',
  int occurredAt = 1788940800000,
}) =>
    ValueAuditEntry(
      id: id,
      visitUuid: visitUuid,
      fieldId: fieldId,
      aiValue: aiValue,
      finalValue: finalValue,
      occurredAt: occurredAt,
    );

void main() {
  late AppDatabase db;
  late ValueAuditDao dao;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await _openInMemoryDb();
    dao = ValueAuditDao(db);
  });

  tearDown(() async => db.close());

  test('stores a pair and reads it back verbatim', () async {
    await dao.insertAll([_entry(aiValue: '10.5', finalValue: 'Not done')]);

    final rows = await dao.pending();
    expect(rows.single.aiValue, '10.5');
    expect(rows.single.finalValue, 'Not done',
        reason: 'values are stored as the form held them, not parsed');
  });

  test('ignores a duplicate id rather than double-writing', () async {
    // The id is the server's dedup key too; a device retrying a batch must not
    // produce two rows for one edit.
    await dao.insertAll([_entry()]);
    await dao.insertAll([_entry()]);

    expect((await dao.counts()).total, 1);
  });

  test('writes a whole visit atomically', () async {
    // A visit writes every pair at submit; a partial write would leave the
    // audit trail half-recorded.
    await dao.insertAll([
      _entry(id: 'a1', fieldId: 'systolic'),
      _entry(id: 'a2', fieldId: 'diastolic'),
      _entry(id: 'a3', fieldId: 'temperature'),
    ]);

    expect((await dao.counts()).total, 3);
  });

  test('pending returns oldest first', () async {
    await dao.insertAll([
      _entry(id: 'newer', occurredAt: 2000),
      _entry(id: 'older', occurredAt: 1000),
    ]);

    expect((await dao.pending()).map((e) => e.id), ['older', 'newer']);
  });

  test('markUploaded takes rows out of pending without deleting them',
      () async {
    await dao.insertAll([_entry(id: 'a1'), _entry(id: 'a2')]);

    await dao.markUploaded(['a1']);

    final counts = await dao.counts();
    expect(counts.pending, 1);
    expect(counts.total, 2, reason: 'uploaded rows stay until the wipe');
    expect((await dao.pending()).single.id, 'a2');
  });

  test('a null value round-trips as null, not as an empty string', () async {
    // "AI proposed nothing" and "AI proposed empty" are different findings.
    await dao.insertAll([_entry(aiValue: null, finalValue: '140')]);

    expect((await dao.pending()).single.aiValue, isNull);
  });

  test('the api payload carries an ISO instant, not epoch millis', () async {
    final json = _entry().toApiJson();
    expect(json['occurredAt'], '2026-09-09T08:00:00.000Z');
    expect(json['aiValue'], '160');
    expect(json['finalValue'], '140');
    expect(json['visitUuid'], 'v-1');
  });
}
