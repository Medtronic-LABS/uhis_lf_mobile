import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/call_log_history_dao.dart';
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

  CallLogHistoryRow makeRow({required String id, String? encounterId}) {
    return CallLogHistoryRow(
      id: id,
      syncSeq: 1,
      encounterId: encounterId,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      rawJson: '{}',
    );
  }

  ShukheeEncounterAttachService buildService({
    required bool Function(Map<String, dynamic> body) attachResult,
  }) {
    final adapter = _ScriptedAdapter(attachResult);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
    final linkClient = ShukheeEncounterLinkClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'test-token',
      dio: dio,
    );
    return ShukheeEncounterAttachService(
      callLogHistory: callLogHistory,
      linkClient: linkClient,
    );
  }

  group('attachForVisit', () {
    test('attaches and stamps locally when a matching pending row exists', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      final service = buildService(attachResult: (_) => true);

      await service.attachForVisit('uuid-1', 'fhir-enc-1');

      final row = await callLogHistory.getById('CL-1');
      expect(row!.fhirEncounterId, 'fhir-enc-1');
    });

    test('no-ops when no row matches the visit id', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      var calls = 0;
      final service = buildService(attachResult: (_) {
        calls++;
        return true;
      });

      await service.attachForVisit('uuid-does-not-exist', 'fhir-enc-1');

      expect(calls, 0);
    });

    test('no-ops (does not re-call the backend) when already attached', () async {
      await callLogHistory.upsertMany([
        CallLogHistoryRow(
          id: 'CL-1',
          syncSeq: 1,
          encounterId: 'uuid-1',
          fhirEncounterId: 'fhir-enc-1',
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          rawJson: '{}',
        ),
      ]);
      var calls = 0;
      final service = buildService(attachResult: (_) {
        calls++;
        return true;
      });

      await service.attachForVisit('uuid-1', 'fhir-enc-1');

      expect(calls, 0);
    });

    test('leaves the row unstamped when the backend attach fails', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      final service = buildService(attachResult: (_) => false);

      await service.attachForVisit('uuid-1', 'fhir-enc-1');

      final row = await callLogHistory.getById('CL-1');
      expect(row!.fhirEncounterId, isNull);
    });
  });

  group('attachAll', () {
    test('attaches every pending row whose encounter_id is in the map', () async {
      await callLogHistory.upsertMany([
        makeRow(id: 'CL-1', encounterId: 'uuid-1'),
        makeRow(id: 'CL-2', encounterId: 'uuid-2'),
        makeRow(id: 'CL-3', encounterId: 'uuid-unmapped'),
      ]);
      final service = buildService(attachResult: (_) => true);

      await service.attachAll({'uuid-1': 'fhir-1', 'uuid-2': 'fhir-2'});

      expect((await callLogHistory.getById('CL-1'))!.fhirEncounterId, 'fhir-1');
      expect((await callLogHistory.getById('CL-2'))!.fhirEncounterId, 'fhir-2');
      expect((await callLogHistory.getById('CL-3'))!.fhirEncounterId, isNull);
    });

    test('is a no-op for an empty map', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      var calls = 0;
      final service = buildService(attachResult: (_) {
        calls++;
        return true;
      });

      await service.attachAll(const {});

      expect(calls, 0);
    });
  });

  group('attachFromOtherDetails', () {
    test('attaches when otherDetails carries a matching encounterId', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      final service = buildService(attachResult: (_) => true);

      await service.attachFromOtherDetails(
        jsonEncode({'encounterId': 'uuid-1', 'isReferred': false}),
        'fhir-enc-1',
      );

      expect((await callLogHistory.getById('CL-1'))!.fhirEncounterId, 'fhir-enc-1');
    });

    test('no-ops when otherDetails is null', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      var calls = 0;
      final service = buildService(attachResult: (_) {
        calls++;
        return true;
      });

      await service.attachFromOtherDetails(null, 'fhir-enc-1');

      expect(calls, 0);
    });

    test('no-ops when otherDetails has no encounterId key', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      var calls = 0;
      final service = buildService(attachResult: (_) {
        calls++;
        return true;
      });

      await service.attachFromOtherDetails(jsonEncode({'isReferred': false}), 'fhir-enc-1');

      expect(calls, 0);
    });

    test('no-ops (never throws) when otherDetails is malformed JSON', () async {
      await callLogHistory.upsertMany([makeRow(id: 'CL-1', encounterId: 'uuid-1')]);
      var calls = 0;
      final service = buildService(attachResult: (_) {
        calls++;
        return true;
      });

      await service.attachFromOtherDetails('{not valid json', 'fhir-enc-1');

      expect(calls, 0);
    });
  });
}
