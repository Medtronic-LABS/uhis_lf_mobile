library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_dao.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_entry.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_service.dart';

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

void main() {
  late AppDatabase db;
  late TeleconsultConsentLogDao dao;
  late TeleconsultConsentLogService service;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await _openInMemoryDb();
    dao = TeleconsultConsentLogDao(db);
    service = TeleconsultConsentLogService(
      dao: dao,
      userIdResolver: () async => 373,
      tenantIdResolver: () async => 12,
    );
  });

  tearDown(() async => db.close());

  test('record stores an Agreed decision with resolved identity', () async {
    await service.record(
      patientId: 'patient-1',
      visitId: 'visit-1',
      agreed: true,
      lng: 'en',
      consentVersion: '2',
      patientDob: '1990-01-01',
    );

    final row = (await dao.pending()).single;
    expect(row.patientId, 'patient-1');
    expect(row.visitId, 'visit-1');
    expect(row.decision, TeleconsultConsentDecision.agreed);
    expect(row.lng, 'en');
    expect(row.consentVersion, '2');
    expect(row.patientDob, '1990-01-01');
    expect(row.skUserId, '373');
    expect(row.capturedTenantId, 12);
    expect(row.uploadStatus, TeleconsultConsentLogUploadStatus.pending);
  });

  test('record stores a Declined decision', () async {
    await service.record(
      patientId: 'patient-2',
      agreed: false,
      lng: 'bn',
    );

    final row = (await dao.pending()).single;
    expect(row.decision, TeleconsultConsentDecision.declined);
    expect(row.visitId, isNull);
    expect(row.consentVersion, isNull);
    expect(row.patientDob, isNull);
  });

  test('a dead database drops the record instead of throwing', () async {
    // This is the property that keeps the log off the Agree/Decline
    // navigation critical path.
    await db.close();

    await expectLater(
      service.record(patientId: 'patient-1', agreed: true, lng: 'en'),
      completes,
    );

    // Reopen so tearDown's close() is well-defined.
    db = await _openInMemoryDb();
  });

  test('a throwing user-id resolver also drops rather than propagates',
      () async {
    final broken = TeleconsultConsentLogService(
      dao: dao,
      userIdResolver: () async => throw StateError('no session'),
    );

    await expectLater(
      broken.record(patientId: 'patient-1', agreed: true, lng: 'en'),
      completes,
    );
    expect((await dao.counts()).total, 0);
  });

  test('a missing tenant leaves the row null rather than guessing', () async {
    final noTenant = TeleconsultConsentLogService(
      dao: dao,
      userIdResolver: () async => 1,
      tenantIdResolver: () async => null,
    );
    await noTenant.record(patientId: 'patient-1', agreed: true, lng: 'en');

    expect((await dao.pending()).single.capturedTenantId, isNull);
  });
}
