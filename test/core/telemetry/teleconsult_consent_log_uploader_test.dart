/// Unit tests for [TeleconsultConsentLogUploader].
///
/// The property that matters most: **a row is only marked uploaded when the
/// server confirms it.** HTTP is faked at Dio's [HttpClientAdapter] seam, so
/// no server and no extra test dependency -- same approach as
/// `telemetry_uploader_test.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_dao.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_entry.dart';
import 'package:uhis_next/core/telemetry/teleconsult_consent_log_uploader.dart';

/// Returns a canned response for every request, recording what was sent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Object? body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late TeleconsultConsentLogDao dao;
  late ApiClient api;

  setUp(() async {
    db = await _openInMemoryDb();
    dao = TeleconsultConsentLogDao(db);
    api = await ApiClient.create();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
      await dao.upsert(TeleconsultConsentLogEntry(
        id: 'c$i',
        patientId: 'patient-$i',
        visitId: 'visit-$i',
        decision: TeleconsultConsentDecision.agreed,
        lng: 'en',
        occurredAt: DateTime.utc(2026, 9, 4, 10, i).millisecondsSinceEpoch,
      ));
    }
  }

  TeleconsultConsentLogUploader uploaderWith(_FakeAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://shukhee.example.test'))
      ..httpClientAdapter = adapter;
    return TeleconsultConsentLogUploader(dao, api, dio: dio);
  }

  group('successful upload', () {
    test('marks exactly the ids the server accepted', () async {
      await seed(3);
      final adapter = _FakeAdapter(statusCode: 200, body: {
        'acceptedIds': ['c0', 'c1', 'c2'],
      });

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 3);
      expect(await dao.pending(), isEmpty);
      expect((await dao.counts()).total, 3);
    });

    test('a partial acceptedIds leaves the rest pending', () async {
      await seed(3);
      final adapter = _FakeAdapter(statusCode: 200, body: {
        'acceptedIds': ['c0', 'c1'],
      });

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 2);
      expect((await dao.pending()).map((e) => e.id), ['c2']);
    });

    test('sends the wire shape the server expects', () async {
      await seed(1);
      final adapter = _FakeAdapter(statusCode: 200, body: {
        'acceptedIds': ['c0'],
      });

      await uploaderWith(adapter).uploadPending();

      final adapterUsed = adapter;
      final sentBody = adapterUsed.requests.single.data as Map<String, dynamic>;
      final entries = sentBody['entries'] as List;
      final entry = entries.single as Map<String, dynamic>;
      expect(entry['id'], 'c0');
      expect(entry['patientId'], 'patient-0');
      expect(entry['decision'], TeleconsultConsentDecision.agreed);
      // occurredAt goes as an ISO-8601 UTC instant, not epoch millis.
      expect(entry['occurredAt'], '2026-09-04T10:00:00.000Z');
    });
  });

  group('failure never loses data', () {
    test('a 404 (endpoint not built yet) leaves every row pending', () async {
      await seed(2);
      final adapter = _FakeAdapter(statusCode: 404, body: {'detail': 'not found'});

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 0);
      expect((await dao.pending()), hasLength(2));
    });

    test('a 500 leaves every row pending and does not throw', () async {
      await seed(2);
      final adapter = _FakeAdapter(statusCode: 500, body: {'detail': 'boom'});

      await expectLater(uploaderWith(adapter).uploadPending(), completes);
      expect((await dao.pending()), hasLength(2));
    });

    test('a 200 with no acceptedIds marks nothing', () async {
      await seed(2);
      final adapter = _FakeAdapter(statusCode: 200, body: {'ok': true});

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 0);
      expect((await dao.pending()), hasLength(2));
    });
  });

  test('an empty queue makes no request at all', () async {
    final adapter = _FakeAdapter(statusCode: 200, body: {'acceptedIds': []});

    expect(await uploaderWith(adapter).uploadPending(), 0);
    expect(adapter.requests, isEmpty);
  });
}
