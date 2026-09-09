/// Unit tests for [TelemetryService] and telemetry retention.
///
/// The behaviour that matters most here is the failure contract: telemetry
/// must never be able to break a visit. A dead database has to produce a
/// dropped metric, not a thrown exception on the submit path.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/telemetry_dao.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';
import 'package:uhis_next/core/telemetry/telemetry_service.dart';
import 'package:uhis_next/core/telemetry/telemetry_uploader.dart';

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
    service = TelemetryService(dao: dao, userIdResolver: () async => 4242);
  });

  tearDown(() async {
    await db.close();
  });

  Future<TelemetryEvent> onlyRow() async {
    final rows = await dao.inRange(DateTime(2020), DateTime(2100));
    expect(rows, hasLength(1));
    return rows.single;
  }

  group('recordVisitCompleted', () {
    test('writes the metric-1-to-4 payload and stamps identity', () async {
      await service.recordVisitCompleted(
        visitUuid: 'visit-1',
        programmes: const ['anc', 'ncd'],
        scribeUsed: true,
        aiCorrected: const ['weight'],
        aiAcceptedUnchanged: const ['systolic', 'diastolic'],
        manual: const ['hemoglobin'],
        empty: const ['fundalHeight'],
        libraryTotal: 33,
        renderedTotal: 24,
        extractableVisible: 18,
        durationMs: 412000,
      );

      final row = await onlyRow();
      expect(row.eventType, TelemetryEventType.visitCompleted);
      expect(row.visitUuid, 'visit-1');
      expect(row.skUserId, '4242');
      expect(row.payloadVersion, kTelemetryPayloadVersion);
      expect(row.uploadStatus, TelemetryUploadStatus.pending);

      final p = VisitCompletedPayload.fromJson(row.payload);
      expect(p.programmes, ['anc', 'ncd']);
      expect(p.scribeUsed, isTrue);
      expect(p.durationMs, 412000);
      expect(p.aiCorrected, ['weight']);
      expect(p.aiAcceptedUnchanged, ['systolic', 'diastolic']);
      expect(p.extractableVisible, 18);
    });

    test('aiFilled is derived, so it can never disagree with its parts', () async {
      await service.recordVisitCompleted(
        visitUuid: 'v',
        programmes: const ['ncd'],
        scribeUsed: true,
        aiCorrected: const ['weight'],
        aiAcceptedUnchanged: const ['systolic'],
        manual: const [],
        empty: const [],
        libraryTotal: 1,
        renderedTotal: 1,
        extractableVisible: 1,
      );

      final p = VisitCompletedPayload.fromJson((await onlyRow()).payload);
      expect(p.aiFilled, ['weight', 'systolic']);
      expect(p.aiFilled.length, p.aiCorrected.length + p.aiAcceptedUnchanged.length);
    });

    test('carries no patient, member or encounter identifier', () async {
      // The wipe exclusion is only defensible while this stays true.
      await service.recordVisitCompleted(
        visitUuid: 'v',
        programmes: const ['ncd'],
        scribeUsed: false,
        aiCorrected: const [],
        aiAcceptedUnchanged: const [],
        manual: const ['weight'],
        empty: const [],
        libraryTotal: 1,
        renderedTotal: 1,
        extractableVisible: 1,
      );

      final row = await onlyRow();
      final serialised = row.toDb().toString().toLowerCase();
      expect(serialised, isNot(contains('patient_id')));
      expect(serialised, isNot(contains('encounter')));
      expect(serialised, isNot(contains('member')));
    });

    test('a null user id is tolerated (not yet logged in / no cached id)', () async {
      final anon = TelemetryService(dao: dao, userIdResolver: () async => null);
      await anon.recordVisitCompleted(
        visitUuid: 'v',
        programmes: const ['ncd'],
        scribeUsed: false,
        aiCorrected: const [],
        aiAcceptedUnchanged: const [],
        manual: const [],
        empty: const [],
        libraryTotal: 0,
        renderedTotal: 0,
        extractableVisible: 0,
      );
      expect((await onlyRow()).skUserId, isNull);
    });
  });

  group('recordCounsellingShare', () {
    test('records channel and launch outcome', () async {
      await service.recordCounsellingShare(
        channel: TelemetryShareChannel.sms,
        hasMessage: true,
        launched: true,
      );

      final row = await onlyRow();
      expect(row.eventType, TelemetryEventType.counsellingShare);
      final p = CounsellingSharePayload.fromJson(row.payload);
      expect(p.channel, TelemetryShareChannel.sms);
      expect(p.launched, isTrue);
    });
  });

  group('failure contract', () {
    test('a dead database drops the metric instead of throwing', () async {
      // This is the property that keeps telemetry off the critical path: if
      // this ever throws, a submit with real clinical data could fail because
      // of a metric.
      await db.close();

      await expectLater(
        service.recordVisitCompleted(
          visitUuid: 'v',
          programmes: const ['ncd'],
          scribeUsed: true,
          aiCorrected: const [],
          aiAcceptedUnchanged: const ['systolic'],
          manual: const [],
          empty: const [],
          libraryTotal: 1,
          renderedTotal: 1,
          extractableVisible: 1,
        ),
        completes,
      );

      // Reopen so tearDown's close() is well-defined.
      db = await _openInMemoryDb();
    });

    test('a throwing user-id resolver also drops rather than propagates', () async {
      final broken = TelemetryService(
        dao: dao,
        userIdResolver: () async => throw StateError('no session'),
      );

      await expectLater(
        broken.recordCounsellingShare(
          channel: TelemetryShareChannel.sms,
          hasMessage: true,
          launched: true,
        ),
        completes,
      );
      expect((await dao.counts()).total, 0);
    });
  });

  group('retention', () {
    test('purgeUploaded is a no-op while nothing has been uploaded', () async {
      // Full upload behaviour lives in telemetry_uploader_test.dart; this
      // only pins that retention cannot touch an unsent row.
      await service.recordCounsellingShare(
        channel: TelemetryShareChannel.sms,
        hasMessage: true,
        launched: true,
      );

      expect(
        await dao.purgeUploadedOlderThan(kTelemetryRetention),
        0,
      );
      expect((await dao.counts()).total, 1);
    });

    test('retention default is a month', () {
      expect(kTelemetryRetention, const Duration(days: 30));
    });
  });

  test('newVisitUuid returns a distinct id each call', () {
    expect(service.newVisitUuid(), isNot(service.newVisitUuid()));
  });
}
