/// Unit tests for [TeleconsultConsentLogUploader].
///
/// The property that matters most: **a row is only marked uploaded when the
/// server confirms it.** HTTP is faked at Dio's [HttpClientAdapter] seam, so
/// no server and no extra test dependency -- same approach as
/// `telemetry_uploader_test.dart`.
///
/// `record_consent_decision` is a single-record endpoint (see
/// `TeleconsultConsentLogEntry.toApiJson`'s doc comment) -- one POST per
/// pending row, response wrapped in Frappe's `{"message": {...}}` envelope,
/// unlike the batch `{"entries": [...]}` / `{"acceptedIds": [...]}` shape the
/// other telemetry uploaders use.
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

/// Returns a response per request, indexed by call order -- lets a test
/// script "first call succeeds, second fails" since each pending row now
/// gets its own independent request rather than one shared batch response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._responses);

  /// Convenience for "every request gets this same response".
  _FakeAdapter.always(int statusCode, Object? body)
      : this([(statusCode, body)]);

  final List<(int statusCode, Object? body)> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = requests.length;
    requests.add(options);
    final (statusCode, body) =
        index < _responses.length ? _responses[index] : _responses.last;
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
        consentVersion: '2',
        versionId: 'VER-2',
        patientDob: '2000-01-01',
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
    test('marks every row the server confirms', () async {
      await seed(3);
      final adapter = _FakeAdapter.always(200, {
        'message': {'logged': true},
      });

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 3);
      expect(await dao.pending(), isEmpty);
      expect((await dao.counts()).total, 3);
      expect(adapter.requests, hasLength(3));
    });

    test('stops at the first failure, leaving the rest pending', () async {
      await seed(3);
      // First row's request succeeds; the second (and everything after it)
      // fails -- the loop must stop there rather than skip ahead.
      final adapter = _FakeAdapter([
        (200, {'message': {'logged': true}}),
        (500, {'detail': 'boom'}),
      ]);

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 1);
      expect((await dao.pending()).map((e) => e.id), ['c1', 'c2']);
    });

    test('sends the single-record snake_case wire shape the server expects',
        () async {
      await seed(1);
      final adapter = _FakeAdapter.always(200, {
        'message': {'logged': true},
      });

      await uploaderWith(adapter).uploadPending();

      final sentBody =
          adapter.requests.single.data as Map<String, dynamic>;
      // Flat single-record body -- no {"entries": [...]} wrapper, no `id`/
      // `sk_user_id`/`captured_tenant_id`/`occurred_at` (those are local-only
      // bookkeeping or server-resolved, not part of the wire contract).
      expect(sentBody, {
        'patient_id': 'patient-0',
        'visit_id': 'visit-0',
        'decision': TeleconsultConsentDecision.agreed,
        'lng': 'en',
        'consent_version': '2',
        'version_id': 'VER-2',
        'patient_dob': '2000-01-01',
      });
    });
  });

  group('failure never loses data', () {
    test('a 404 (endpoint not built yet) leaves every row pending', () async {
      await seed(2);
      final adapter = _FakeAdapter.always(404, {'detail': 'not found'});

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 0);
      expect((await dao.pending()), hasLength(2));
    });

    test('a 500 leaves every row pending and does not throw', () async {
      await seed(2);
      final adapter = _FakeAdapter.always(500, {'detail': 'boom'});

      await expectLater(uploaderWith(adapter).uploadPending(), completes);
      expect((await dao.pending()), hasLength(2));
    });

    test('a 200 with no "logged" flag marks nothing', () async {
      await seed(2);
      final adapter = _FakeAdapter.always(200, {'message': {'ok': true}});

      final sent = await uploaderWith(adapter).uploadPending();

      expect(sent, 0);
      expect((await dao.pending()), hasLength(2));
    });
  });

  test('an empty queue makes no request at all', () async {
    final adapter = _FakeAdapter.always(200, {'message': {'logged': true}});

    expect(await uploaderWith(adapter).uploadPending(), 0);
    expect(adapter.requests, isEmpty);
  });
}
