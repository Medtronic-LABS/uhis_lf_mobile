library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_dao.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_entry.dart';

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

TeleconsultConsentLogEntry _entry({
  String id = 'c1',
  String patientId = 'patient-1',
  String? visitId = 'visit-1',
  String decision = TeleconsultConsentDecision.agreed,
  String lng = 'en',
  int occurredAt = 1788940800000,
}) =>
    TeleconsultConsentLogEntry(
      id: id,
      patientId: patientId,
      visitId: visitId,
      decision: decision,
      lng: lng,
      occurredAt: occurredAt,
    );

void main() {
  late AppDatabase db;
  late TeleconsultConsentLogDao dao;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await _openInMemoryDb();
    dao = TeleconsultConsentLogDao(db);
  });

  tearDown(() async => db.close());

  test('upsert stores and reads back through pending()', () async {
    await dao.upsert(_entry());
    final rows = await dao.pending();
    expect(rows, hasLength(1));
    expect(rows.single.patientId, 'patient-1');
    expect(rows.single.decision, TeleconsultConsentDecision.agreed);
  });

  test('upsert with the same id replaces the row', () async {
    await dao.upsert(_entry(decision: TeleconsultConsentDecision.declined));
    await dao.upsert(_entry(decision: TeleconsultConsentDecision.agreed));

    expect((await dao.counts()).total, 1);
    expect((await dao.pending()).single.decision,
        TeleconsultConsentDecision.agreed);
  });

  test('pending returns oldest first', () async {
    await dao.upsert(_entry(id: 'a', occurredAt: 2000));
    await dao.upsert(_entry(id: 'b', occurredAt: 1000));

    expect((await dao.pending()).map((e) => e.id), ['b', 'a']);
  });

  test('markUploaded removes rows from pending', () async {
    await dao.upsert(_entry());
    await dao.markUploaded(['c1']);

    expect((await dao.counts()).pending, 0);
    expect((await dao.counts()).total, 1);
  });

  test('markUploaded with an empty id list is a no-op', () async {
    await dao.upsert(_entry());
    final updated = await dao.markUploaded(const []);

    expect(updated, 0);
    expect((await dao.counts()).pending, 1);
  });

  test('api payload uses ISO instants and camelCase keys', () {
    final json = _entry(
      visitId: 'visit-9',
      decision: TeleconsultConsentDecision.declined,
      lng: 'bn',
    ).toApiJson();

    expect(json['occurredAt'], '2026-09-09T08:00:00.000Z');
    expect(json['patientId'], 'patient-1');
    expect(json['visitId'], 'visit-9');
    expect(json['decision'], TeleconsultConsentDecision.declined);
    expect(json['lng'], 'bn');
  });
}
