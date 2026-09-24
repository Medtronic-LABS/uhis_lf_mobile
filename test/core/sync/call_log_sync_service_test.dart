import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/call_log_history_dao.dart';
import 'package:uhis_next/core/db/sync_meta_dao.dart';
import 'package:uhis_next/core/sync/call_log_sync_client.dart';
import 'package:uhis_next/core/sync/call_log_sync_service.dart';

/// Mirrors shukhee_sdk's own `_ScriptedAdapter` test convention -- one
/// scripted response per call, repeating the last if exhausted.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._responses);

  final List<Future<ResponseBody> Function(RequestOptions)> _responses;
  final List<RequestOptions> requests = [];
  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final index = callCount < _responses.length ? callCount : _responses.length - 1;
    callCount++;
    return _responses[index](options);
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(bytes, 200, headers: {
    'content-type': ['application/json; charset=utf-8'],
  });
}

Future<ResponseBody> Function(RequestOptions) _page(Map<String, dynamic> message) {
  return (_) async => _jsonResponse({'message': message});
}

Map<String, dynamic> _callLogChange({
  required String name,
  required int syncSeq,
  String status = 'completed',
  String? patient = 'patient-1',
  Map<String, dynamic>? clinicalData,
}) {
  return {
    'doctype': 'Call Logs',
    'name': name,
    'sync_seq': syncSeq,
    'deleted': false,
    'doc': {
      'name': name,
      'patient': patient,
      'encounter_id': 'encounter-1',
      'status': status,
      'appointment_status': 'Completed',
      'doctor_name': 'Dr. Farzana Kabir',
      'reason': 'Fever',
      if (clinicalData != null) 'clinical_data': jsonEncode(clinicalData),
      'creation': '2026-01-01 10:00:00.000000',
    },
  };
}

Map<String, dynamic> _patientChange({required String name, required int syncSeq}) {
  return {
    'doctype': 'Patient',
    'name': name,
    'sync_seq': syncSeq,
    'deleted': false,
    'doc': {'name': name, 'full_name': 'Some Patient'},
  };
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppDatabase, CallLogHistoryDao, SyncMetaDao)> openTestDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    final app = AppDatabase.forTesting(db);
    return (app, CallLogHistoryDao(app), SyncMetaDao(app));
  }

  (CallLogSyncClient, _ScriptedAdapter) buildClient(
    List<Future<ResponseBody> Function(RequestOptions)> responses,
  ) {
    final adapter = _ScriptedAdapter(responses);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
    final client = CallLogSyncClient(
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'test-token',
      dio: dio,
    );
    return (client, adapter);
  }

  group('CallLogSyncService.pull', () {
    test('a page mixing Patient and Call Logs rows persists only the completed Call Logs rows', () async {
      final (db, dao, syncMeta) = await openTestDb();
      addTearDown(db.close);

      final (client, _) = buildClient([
        _page({
          'contract_version': 1,
          'changes': [
            _patientChange(name: 'PT-1', syncSeq: 1),
            _callLogChange(name: 'CL-1', syncSeq: 2, clinicalData: {'chiefComplaints': ['Fever']}),
            _callLogChange(name: 'CL-2', syncSeq: 3, status: 'pending'),
          ],
          'next_cursor': 3,
          'has_more': false,
        }),
      ]);
      final service = CallLogSyncService(client: client, dao: dao, syncMeta: syncMeta);

      await service.pull();

      final rows = await dao.getForPatient('patient-1');
      // Only CL-1 persisted: PT-1 isn't a Call Logs row, CL-2 isn't completed.
      expect(rows.map((r) => r.id), ['CL-1']);
      expect(rows.single.clinicalDataJson, isNotNull);
      expect(jsonDecode(rows.single.clinicalDataJson!), {'chiefComplaints': ['Fever']});
    });

    test('cursor advances to next_cursor even on an all-non-Call-Logs page', () async {
      final (db, dao, syncMeta) = await openTestDb();
      addTearDown(db.close);

      final (client, _) = buildClient([
        _page({
          'contract_version': 1,
          'changes': [_patientChange(name: 'PT-1', syncSeq: 5)],
          'next_cursor': 5,
          'has_more': false,
        }),
      ]);
      final service = CallLogSyncService(client: client, dao: dao, syncMeta: syncMeta);

      await service.pull();

      expect((await syncMeta.read('callLogs'))!.cursor, 5);
    });

    test('pagination continues while has_more and stops when false', () async {
      final (db, dao, syncMeta) = await openTestDb();
      addTearDown(db.close);

      final (client, adapter) = buildClient([
        _page({
          'contract_version': 1,
          'changes': [_callLogChange(name: 'CL-1', syncSeq: 1)],
          'next_cursor': 1,
          'has_more': true,
        }),
        _page({
          'contract_version': 1,
          'changes': [_callLogChange(name: 'CL-2', syncSeq: 2)],
          'next_cursor': 2,
          'has_more': true,
        }),
        _page({
          'contract_version': 1,
          'changes': [_callLogChange(name: 'CL-3', syncSeq: 3)],
          'next_cursor': 3,
          'has_more': false,
        }),
      ]);
      final service = CallLogSyncService(client: client, dao: dao, syncMeta: syncMeta);

      await service.pull();

      expect(adapter.callCount, 3);
      final rows = await dao.getForPatient('patient-1');
      expect(rows.map((r) => r.id).toSet(), {'CL-1', 'CL-2', 'CL-3'});
      expect((await syncMeta.read('callLogs'))!.cursor, 3);
    });

    test('a second pull starts from the previously-stamped cursor, not from zero', () async {
      final (db, dao, syncMeta) = await openTestDb();
      addTearDown(db.close);
      await syncMeta.stampCursor('callLogs', 10);

      final (client, adapter) = buildClient([
        _page({
          'contract_version': 1,
          'changes': [_callLogChange(name: 'CL-1', syncSeq: 11)],
          'next_cursor': 11,
          'has_more': false,
        }),
      ]);
      final service = CallLogSyncService(client: client, dao: dao, syncMeta: syncMeta);

      await service.pull();

      final body = adapter.requests.single.data as Map<String, dynamic>;
      expect(body['cursor'], 10);
      expect((await syncMeta.read('callLogs'))!.cursor, 11);
    });
  });
}
