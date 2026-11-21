/// The one-row-per-visit telemetry event end to end: [TelemetryService]
/// saving a [VisitTelemetryRecorder] through [TelemetryDao.upsert] into a real
/// (in-memory) `telemetry_events` table, and the upload guard that keeps a
/// save made mid-upload from being marked uploaded unsent.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/telemetry_dao.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';
import 'package:uhis_next/core/telemetry/telemetry_service.dart';
import 'package:uhis_next/core/telemetry/visit_telemetry_recorder.dart';

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
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late TelemetryDao dao;
  late TelemetryService service;

  setUp(() async {
    db = await _openInMemoryDb();
    dao = TelemetryDao(db);
    service = TelemetryService(
      dao: dao,
      userIdResolver: () async => 4242,
      tenantIdResolver: () async => 77,
    );
  });

  tearDown(() async => db.close());

  Future<List<TelemetryEvent>> visitRows() async =>
      (await dao.inRange(DateTime(2020), DateTime(2100)))
          .where((e) => e.eventType == TelemetryEventType.visit)
          .toList();

  test('startVisit writes an in-progress row keyed by the visit uuid',
      () async {
    final r = service.startVisit('enc-1');
    await service.saveVisit(null); // drain the queue
    final rows = await visitRows();

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.id, r.visitUuid);
    expect(row.visitUuid, r.visitUuid);
    expect(row.occurredAt, r.visitStartTime);
    expect(row.skUserId, '4242');
    expect(row.capturedTenantId, 77);
    expect(row.payload['status'], VisitTelemetryStatus.inProgress);
    expect(row.uploadStatus, TelemetryUploadStatus.pending);
  });

  test('every save replaces the same row', () async {
    final r = service.startVisit('enc-1');
    r.enterStep(1);
    r.enterStep(2);
    await service.saveVisit(r);
    r.enterStep(3);
    r.complete();
    await service.saveVisit(r);

    final rows = await visitRows();
    expect(rows, hasLength(1));
    expect(rows.single.payload['status'], VisitTelemetryStatus.completed);
    expect(rows.single.payload['lastStep'], 3);
  });

  test('reopening the visit flow is a new visit with a new uuid', () async {
    final first = service.startVisit('enc-1');
    expect(service.ensureVisitUuid('enc-1'), first.visitUuid);
    final second = service.startVisit('enc-1');

    expect(second.visitUuid, isNot(first.visitUuid));
    expect(service.ensureVisitUuid('enc-1'), second.visitUuid,
        reason: 'visit-content / value-audit must join the new row');
    expect(service.visitRecorderFor('enc-1'), same(second));
    await service.saveVisit(null);
    expect(await visitRows(), hasLength(2));
  });

  test('visit_completed and share taps feed the open visit row', () async {
    final r = service.startVisit('enc-1');
    r.enterStep(1);
    r.enterStep(2);
    await service.recordVisitCompleted(
      visitUuid: service.ensureVisitUuid('enc-1'),
      programmes: const ['anc'],
      scribeUsed: true,
      aiCorrected: const ['systolic'],
      aiAcceptedUnchanged: const ['diastolic'],
      manual: const ['weight'],
      empty: const [],
      libraryTotal: 42,
      renderedTotal: 28,
      extractableVisible: 12,
      durationMs: 373000,
    );
    r.enterStep(3);
    await service.recordCounsellingShare(
      channel: TelemetryShareChannel.whatsapp,
      surface: TelemetryShareSurface.visitFlow,
      hasMessage: true,
      launched: true,
      visitUuid: r.visitUuid,
    );
    r.complete();
    await service.saveVisit(r);

    final row = (await visitRows()).single;
    final completed = (await dao.inRange(DateTime(2020), DateTime(2100)))
        .firstWhere((e) => e.eventType == TelemetryEventType.visitCompleted);
    for (final key in completed.payload.keys) {
      expect(row.payload[key], completed.payload[key], reason: key);
    }
    final shares = (row.payload['step3'] as Map)['communicationShares'] as List;
    expect(shares.single['surface'], TelemetryShareSurface.visitFlow);
  });

  test('a saved EPI dose detected by scan reaches the visit row', () async {
    final r = service.startVisit('enc-1');
    r.enterStep(1);
    r.enterStep(2);
    await service.recordEpiVaccinationUpdate(
      vaccineKey: 'BCG',
      changeType: 'confirmed',
      ocrDetected: true,
      hadScanPrefill: true,
      dateChangedFromPrefill: false,
      updateDurationMs: 4000,
      ocrAssisted: true,
      visitUuid: r.visitUuid,
    );
    await service.recordEpiVaccinationUpdate(
      vaccineKey: 'OPV_0',
      changeType: 'wrongly_marked',
      ocrDetected: true,
      hadScanPrefill: false,
      dateChangedFromPrefill: false,
      updateDurationMs: 4000,
      ocrAssisted: true,
      visitUuid: r.visitUuid,
    );
    r.enterStep(3);
    await service.saveVisit(r);

    final row = (await visitRows()).single;
    expect(row.payload['scanUsed'], isTrue);
    expect((row.payload['fields'] as Map)['scanFilled'], ['BCG']);
  });

  test('a re-save after upload is queued for upload again', () async {
    final r = service.startVisit('enc-1');
    await service.saveVisit(null);
    await dao.markUploaded([r.visitUuid]);
    expect((await dao.pending()), isEmpty);

    r.enterStep(1);
    r.enterStep(2);
    await service.saveVisit(r);
    expect((await dao.pending()).single.id, r.visitUuid);
  });

  test('a save made while the batch was in flight stays pending', () async {
    final r = service.startVisit('enc-1');
    await service.saveVisit(null);
    final sent = (await dao.pending()).single;

    r.enterStep(1);
    r.enterStep(2);
    await service.saveVisit(r); // lands during the upload

    await dao.markUploaded(
      [sent.id],
      sentPayloads: {sent.id: jsonEncode(sent.payload)},
    );
    final pending = await dao.pending();
    expect(pending.single.payload['lastStep'], 2);

    await dao.markUploaded(
      [pending.single.id],
      sentPayloads: {pending.single.id: jsonEncode(pending.single.payload)},
    );
    expect(await dao.pending(), isEmpty);
  });
}
