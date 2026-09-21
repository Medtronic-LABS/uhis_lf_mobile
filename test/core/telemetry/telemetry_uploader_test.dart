/// Unit tests for [TelemetryUploader].
///
/// The property that matters most: **a row is only marked uploaded when the
/// server confirms it.** Marking optimistically would let
/// [TelemetryDao.purgeUploadedOlderThan] delete data that never left the
/// device — and until the dashboard is live this table is the only copy.
///
/// HTTP is faked at Dio's [HttpClientAdapter] seam, so no server and no extra
/// test dependency.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/telemetry/telemetry_dao.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';
import 'package:uhis_next/core/telemetry/telemetry_uploader.dart';

/// Returns a canned response for every request, recording what was sent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Object? body;
  final List<Map<String, dynamic>> sent = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    if (data is Map<String, dynamic>) sent.add(data);
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
  late TelemetryDao dao;
  late ApiClient api;

  setUp(() async {
    db = await _openInMemoryDb();
    dao = TelemetryDao(db);
    api = await ApiClient.create();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
      await dao.insert(TelemetryEvent(
        id: 'e$i',
        eventType: TelemetryEventType.visitCompleted,
        occurredAt: DateTime.utc(2026, 9, 4, 10, i).millisecondsSinceEpoch,
        visitUuid: 'visit-$i',
        skUserId: 'sk-1',
        appVersion: '1.0.6',
        appBuild: 6,
        payloadVersion: kTelemetryPayloadVersion,
        payload: const {'scribeUsed': true},
      ));
    }
  }

  TelemetryUploader uploaderWith(_FakeAdapter adapter) {
    api.dio.httpClientAdapter = adapter;
    return TelemetryUploader(dao, api);
  }

  group('successful upload', () {
    test('marks exactly the ids the server accepted', () async {
      await seed(3);
      final adapter = _FakeAdapter(statusCode: 200, body: {
        'received': 3,
        'inserted': 3,
        'duplicates': 0,
        'acceptedIds': ['e0', 'e1', 'e2'],
      });

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 3);
      expect(await dao.pending(), isEmpty);
      expect((await dao.counts()).total, 3);
    });

    test('a partial acceptedIds leaves the rest pending', () async {
      // The server is the authority on what landed; anything it didn't
      // confirm must be retried, not assumed delivered.
      await seed(3);
      final adapter = _FakeAdapter(statusCode: 200, body: {
        'received': 3,
        'inserted': 2,
        'duplicates': 0,
        'acceptedIds': ['e0', 'e1'],
      });

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 2);
      expect((await dao.pending()).map((e) => e.id), ['e2']);
    });

    test('duplicates still count as accepted so the client stops resending',
        () async {
      await seed(2);
      final adapter = _FakeAdapter(statusCode: 200, body: {
        'received': 2,
        'inserted': 0,
        'duplicates': 2,
        'acceptedIds': ['e0', 'e1'],
      });

      await uploaderWith(adapter).uploadPending();

      expect(await dao.pending(), isEmpty);
    });

    test('sends the wire shape the server expects', () async {
      await seed(1);
      final adapter = _FakeAdapter(statusCode: 200, body: {
        'received': 1, 'inserted': 1, 'duplicates': 0, 'acceptedIds': ['e0'],
      });

      await uploaderWith(adapter).uploadPending();

      final events = adapter.sent.single['events'] as List;
      final event = events.single as Map<String, dynamic>;
      expect(event['id'], 'e0');
      expect(event['eventType'], TelemetryEventType.visitCompleted);
      expect(event['payloadVersion'], kTelemetryPayloadVersion);
      // occurredAt goes as an ISO-8601 UTC instant, not epoch millis.
      expect(event['occurredAt'], '2026-09-04T10:00:00.000Z');
      // Identity is the server's to assign — never sent.
      expect(event.containsKey('tenantId'), isFalse);
      expect(event.containsKey('tenant_id'), isFalse);
    });
  });

  group('failure never loses data', () {
    test('a 500 leaves every row pending', () async {
      await seed(2);
      final adapter = _FakeAdapter(statusCode: 500, body: {'detail': 'boom'});

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 0);
      expect((await dao.pending()), hasLength(2));
    });

    test('a 401 leaves every row pending and does not throw', () async {
      await seed(2);
      final adapter = _FakeAdapter(statusCode: 401, body: {'detail': 'nope'});

      await expectLater(uploaderWith(adapter).uploadPending(), completes);
      expect((await dao.pending()), hasLength(2));
    });

    test('a 200 with no acceptedIds marks nothing', () async {
      // Without a confirmation list we cannot know what landed. Marking the
      // batch anyway would let retention delete unsent rows.
      await seed(2);
      final adapter = _FakeAdapter(statusCode: 200, body: {'ok': true});

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 0);
      expect((await dao.pending()), hasLength(2));
    });

    test('a non-JSON-object body marks nothing', () async {
      await seed(1);
      final adapter = _FakeAdapter(statusCode: 200, body: ['unexpected']);

      expect(await uploaderWith(adapter).uploadPending(), 0);
      expect((await dao.pending()), hasLength(1));
    });
  });

  test('an empty queue makes no request at all', () async {
    final adapter = _FakeAdapter(statusCode: 200, body: {'acceptedIds': []});

    expect(await uploaderWith(adapter).uploadPending(), 0);
    expect(adapter.sent, isEmpty);
  });

  test('purgeUploaded only removes rows past the retention window', () async {
    await seed(1);
    await dao.markUploaded(['e0'], at: DateTime(2026, 1, 1));

    final removed = await uploaderWith(
      _FakeAdapter(statusCode: 200, body: const {}),
    ).purgeUploaded();

    expect(removed, 1);
    expect((await dao.counts()).total, 0);
  });
}
