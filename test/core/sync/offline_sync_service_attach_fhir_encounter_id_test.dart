/// Unit tests for [OfflineSyncService]'s `_attachPendingFhirEncounterIds` step
/// (exercised via the `@visibleForTesting` `attachPendingFhirEncounterIdsForTest`
/// entry point) -- the piece that durably attaches a visit's server-assigned
/// FHIR Encounter id onto a local Shukhee Call Logs row once the visit's own
/// assessment-history sync learns it, so the call/prescription link survives
/// a full local data wipe or a new device. See `EncounterDao.findPendingDraftId`
/// and `docs/soft_logout_sync_dedup_plan.md`-adjacent context for the
/// surrounding assessment-history persist step this is normally reached from.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/assessment_dao.dart';
import 'package:uhis_next/core/db/call_log_history_dao.dart';
import 'package:uhis_next/core/db/follow_up_dao.dart';
import 'package:uhis_next/core/db/immunisation_dao.dart';
import 'package:uhis_next/core/db/patient_dao.dart';
import 'package:uhis_next/core/db/patient_programmes_dao.dart';
import 'package:uhis_next/core/db/sync_meta_dao.dart';
import 'package:uhis_next/core/sync/offline_sync_service.dart';
import 'package:uhis_next/core/sync/shukhee_encounter_attach_service.dart';
import 'package:uhis_next/core/sync/shukhee_encounter_link_client.dart';

/// Mirrors call_log_sync_service_test.dart's own `_ScriptedAdapter` convention.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._attached);

  final bool Function(Map<String, dynamic> body) _attached;
  final List<Map<String, dynamic>> requestBodies = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.data as Map<String, dynamic>;
    requestBodies.add(body);
    final ok = _attached(body);
    final bytes = utf8.encode(jsonEncode({
      'message': {'attached': ok}
    }));
    return ResponseBody.fromBytes(bytes, 200, headers: {
      'content-type': ['application/json; charset=utf-8'],
    });
  }
}

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
  late CallLogHistoryDao callLogHistory;

  setUp(() async {
    db = await _openInMemoryDb();
    callLogHistory = CallLogHistoryDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  CallLogHistoryRow makeRow({required String id, required String encounterId}) {
    return CallLogHistoryRow(
      id: id,
      syncSeq: 1,
      encounterId: encounterId,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      rawJson: '{}',
    );
  }

  Future<OfflineSyncService> buildSync({
    required bool Function(Map<String, dynamic> body) attachResult,
  }) async {
    final adapter = _ScriptedAdapter(attachResult);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
    final linkClient = ShukheeEncounterLinkClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'test-token',
      dio: dio,
    );
    final encounterAttach = ShukheeEncounterAttachService(
      callLogHistory: callLogHistory,
      linkClient: linkClient,
    );
    final api = await ApiClient.create();
    return OfflineSyncService(
      api: api,
      auth: AuthRepository(api),
      db: db,
      patients: PatientDao(db),
      programmes: PatientProgrammesDao(db),
      followUps: FollowUpDao(db),
      immunisations: ImmunisationDao(db),
      assessments: AssessmentDao(db),
      syncMeta: SyncMetaDao(db),
      encounterAttach: encounterAttach,
    );
  }

  test(
      'attaches the resolved FHIR id to a pending Call Logs row for the '
      'same client-minted visit id, and stamps it locally', () async {
    await callLogHistory
        .upsertMany([makeRow(id: 'CL-1', encounterId: 'client-uuid-1')]);
    final sync = await buildSync(attachResult: (_) => true);

    await sync.attachPendingFhirEncounterIdsForTest(
      {'client-uuid-1': 'fhir-enc-1'},
    );

    expect(await callLogHistory.getPendingFhirAttach(), isEmpty);
    final row = await callLogHistory.getById('CL-1');
    expect(row!.fhirEncounterId, 'fhir-enc-1');
  });

  test('leaves the local row unstamped when the backend attach fails, so the '
      'next sync pass retries it', () async {
    await callLogHistory
        .upsertMany([makeRow(id: 'CL-1', encounterId: 'client-uuid-1')]);
    final sync = await buildSync(attachResult: (_) => false);

    await sync.attachPendingFhirEncounterIdsForTest(
      {'client-uuid-1': 'fhir-enc-1'},
    );

    final row = await callLogHistory.getById('CL-1');
    expect(row!.fhirEncounterId, isNull);
    expect(await callLogHistory.getPendingFhirAttach(), hasLength(1));
  });

  test('does not call the backend for a Call Logs row whose visit id was not '
      'reconciled on this sync pass', () async {
    await callLogHistory
        .upsertMany([makeRow(id: 'CL-1', encounterId: 'client-uuid-1')]);
    var calls = 0;
    final sync = await buildSync(attachResult: (_) {
      calls++;
      return true;
    });

    await sync.attachPendingFhirEncounterIdsForTest(
      {'some-other-visit-id': 'fhir-enc-9'},
    );

    expect(calls, 0);
    final row = await callLogHistory.getById('CL-1');
    expect(row!.fhirEncounterId, isNull);
  });

  test('is a no-op when no Call Logs rows are pending attach', () async {
    final sync = await buildSync(attachResult: (_) => true);

    await sync.attachPendingFhirEncounterIdsForTest({'client-uuid-1': 'fhir-enc-1'});
    // Nothing thrown, nothing to assert beyond "didn't crash" -- no row
    // existed to begin with.
  });

  test('an already-attached row is skipped (not re-sent to the backend)', () async {
    await callLogHistory.upsertMany([
      CallLogHistoryRow(
        id: 'CL-1',
        syncSeq: 1,
        encounterId: 'client-uuid-1',
        fhirEncounterId: 'fhir-enc-1',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        rawJson: '{}',
      ),
    ]);
    var calls = 0;
    final sync = await buildSync(attachResult: (_) {
      calls++;
      return true;
    });

    await sync.attachPendingFhirEncounterIdsForTest({'client-uuid-1': 'fhir-enc-1'});

    expect(calls, 0);
  });
}
