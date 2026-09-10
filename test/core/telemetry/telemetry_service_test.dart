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
    service = TelemetryService(
      dao: dao,
      userIdResolver: () async => 4242,
      tenantIdResolver: () async => 77,
    );
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

  test('stamps the capturing tenant so a cross-tenant upload still credits it',
      () async {
    // A shared device keeps its telemetry queue across a different-SK login
    // (the wipe exclusion), so the row must remember which tenant produced
    // it; the server stamps only the *uploading* session's tenant.
    await service.recordCounsellingShare(
      channel: TelemetryShareChannel.sms,
      surface: TelemetryShareSurface.counselling,
      hasMessage: true,
      launched: true,
    );
    final rows = await dao.pending();
    expect(rows.single.capturedTenantId, 77);
  });

  test('a missing tenant leaves the row null rather than guessing', () async {
    final noTenant = TelemetryService(
      dao: dao,
      userIdResolver: () async => 1,
      tenantIdResolver: () async => null,
    );
    await noTenant.recordCounsellingShare(
      channel: TelemetryShareChannel.sms,
      surface: TelemetryShareSurface.counselling,
      hasMessage: true,
      launched: true,
    );
    final rows = await dao.pending();
    expect(rows.single.capturedTenantId, isNull,
        reason: 'null degrades to the server crediting the uploading session');
  });

  group('payload v3 — scribe span, editing time, outcome', () {
    test('omits the new keys entirely when nothing was measured', () async {
      // Absence, not null and not zero: a reader tells "not measured" from
      // "measured as zero" by the key being missing, and v1/v2 rows have no
      // key either.
      await service.recordVisitCompleted(
        visitUuid: 'v1',
        programmes: const ['anc'],
        scribeUsed: false,
        aiCorrected: const [],
        aiAcceptedUnchanged: const [],
        manual: const ['systolic'],
        empty: const [],
        libraryTotal: 60,
        renderedTotal: 20,
        extractableVisible: 8,
      );
      final payload = (await dao.pending()).single.payload;
      for (final key in const [
        'scribeStartedAt',
        'scribeEndedAt',
        'manualEditingMs',
        'outcome',
        'failureReasons',
      ]) {
        expect(payload.containsKey(key), isFalse, reason: key);
      }
    });

    test('carries the span, editing time and outcome when measured',
        () async {
      await service.recordVisitCompleted(
        visitUuid: 'v2',
        programmes: const ['anc'],
        scribeUsed: true,
        aiCorrected: const ['systolic'],
        aiAcceptedUnchanged: const ['pulse'],
        manual: const [],
        empty: const [],
        libraryTotal: 60,
        renderedTotal: 20,
        extractableVisible: 8,
        scribeStartedAtMs: 1788940800000,
        scribeEndedAtMs: 1788941040000,
        manualEditingMs: 90000,
        outcome: 'partial',
        failureReasons: const {'validation_failed': 2},
      );
      final payload = (await dao.pending()).single.payload;
      expect(payload['scribeStartedAt'], 1788940800000);
      expect(payload['scribeEndedAt'], 1788941040000);
      expect(payload['manualEditingMs'], 90000);
      expect(payload['outcome'], 'partial');
      expect(payload['failureReasons'], {'validation_failed': 2});
    });

    test('the payload version is 3', () async {
      await service.recordCounsellingShare(
        channel: TelemetryShareChannel.sms,
        surface: TelemetryShareSurface.counselling,
        hasMessage: true,
        launched: true,
      );
      expect((await dao.pending()).single.payloadVersion, 3);
    });

    test('round-trips the new fields through fromJson', () {
      // The uploader sends toJson; a reader must get the same values back.
      const original = VisitCompletedPayload(
        programmes: ['ncd'],
        scribeUsed: true,
        aiFilled: ['systolic'],
        aiCorrected: ['systolic'],
        aiAcceptedUnchanged: [],
        manual: [],
        empty: [],
        libraryTotal: 60,
        renderedTotal: 20,
        extractableVisible: 8,
        scribeStartedAtMs: 1788940800000,
        scribeEndedAtMs: 1788941040000,
        manualEditingMs: 90000,
        outcome: 'success',
        failureReasons: {'sk_owned': 1},
      );
      final back = VisitCompletedPayload.fromJson(original.toJson());
      expect(back.scribeStartedAtMs, original.scribeStartedAtMs);
      expect(back.scribeEndedAtMs, original.scribeEndedAtMs);
      expect(back.manualEditingMs, original.manualEditingMs);
      expect(back.outcome, original.outcome);
      expect(back.failureReasons, original.failureReasons);
    });
  });
}
