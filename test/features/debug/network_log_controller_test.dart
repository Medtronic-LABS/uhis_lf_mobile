import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/net_log/native_network_event_source.dart';
import 'package:uhis_next/core/net_log/network_log_dao.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_repository.dart';
import 'package:uhis_next/core/net_log/network_request_recorder.dart';
import 'package:uhis_next/core/net_log/service_classifier.dart';
import 'package:uhis_next/features/debug/network_log_controller.dart';

NetworkLogEntry _e(int t, String service) => NetworkLogEntry(
  startedAtMs: t,
  source: 'dart',
  service: service,
  method: 'GET',
  url: 'https://example.test/x/$t',
  statusCode: 200,
);

class CountingRepo extends NetworkLogRepository {
  CountingRepo(NetworkLogDao dao)
    : super(
        dao: dao,
        recorder: const NoopNetworkRequestRecorder(),
        native: const UnavailableNativeNetworkEventSource(),
      );
  int loads = 0;
  Completer<void>? gate;
  Object? failWith;

  @override
  Future<NetworkLogPage> load({String? service, int offset = 0}) async {
    loads++;
    final g = gate;
    if (g != null) await g.future;
    final f = failWith;
    if (f != null) {
      failWith = null;
      throw f;
    }
    return super.load(service: service, offset: offset);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late NetworkLogDao dao;
  late CountingRepo repo;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    db = AppDatabase.forTesting(raw);
    dao = NetworkLogDao(db);
    repo = CountingRepo(dao);
  });
  tearDown(() => db.close());

  test('load populates state', () async {
    await dao.insertBatch([_e(1, 'core'), _e(2, 'auth-service')]);
    final c = NetworkLogController(repo);
    await c.load();
    expect(c.rows, hasLength(2));
    expect(c.counts, {'core': 1, 'auth-service': 1});
    expect(c.nativeStatus, NativeNetworkStatus.unavailable);
    expect(c.loading, isFalse);
    c.dispose();
  });

  test('loadMore appends the next page, refresh replaces', () async {
    await dao.insertBatch([for (var i = 1; i <= 250; i++) _e(i, 'core')]);
    final c = NetworkLogController(repo);
    await c.load();
    expect(c.rows, hasLength(200));
    expect(c.hasMore, isTrue);
    await c.loadMore();
    expect(c.rows, hasLength(250));
    expect(c.hasMore, isFalse);
    await c.refresh();
    expect(c.rows, hasLength(200));
    c.dispose();
  });

  test('setService reloads from offset 0', () async {
    await dao.insertBatch([_e(1, 'core'), _e(2, 'auth-service')]);
    final c = NetworkLogController(repo);
    await c.load();
    c.setService('auth-service');
    await pumpEventQueue();
    expect(c.service, 'auth-service');
    expect(c.rows.map((r) => r.service), ['auth-service']);
    c.dispose();
  });

  test('concurrent loads coalesce into one re-run', () async {
    final c = NetworkLogController(repo);
    repo.gate = Completer<void>();
    final a = c.load();
    final b = c.load();
    final d = c.load();
    repo.gate!.complete();
    await Future.wait([a, b, d]);
    await pumpEventQueue();
    expect(repo.loads, 2);
    c.dispose();
  });

  test('a load during a load returns the queued re-run future', () async {
    final c = NetworkLogController(repo);
    final gate = Completer<void>();
    repo.gate = gate;
    final first = c.load();
    var refreshed = false;
    final second = c.refresh().then((_) => refreshed = true);
    repo.gate = null;
    gate.complete();
    await first;
    expect(refreshed, isFalse);
    await second;
    expect(repo.loads, 2);
    expect(refreshed, isTrue);
    c.dispose();
  });

  test('a throwing load keeps state and queues no spurious reload', () async {
    await dao.insertBatch([_e(1, 'core')]);
    final c = NetworkLogController(repo);
    await c.load();
    repo.failWith = Exception('boom');
    await c.load();
    expect(c.rows, hasLength(1));
    expect(c.loading, isFalse);
    final before = repo.loads;
    await pumpEventQueue();
    expect(repo.loads, before);
    await c.load();
    expect(repo.loads, before + 1);
    c.dispose();
  });

  test('setService with a failing reload leaves no unhandled error', () async {
    await dao.insertBatch([_e(1, 'core')]);
    final c = NetworkLogController(repo);
    await c.load();
    repo.failWith = Exception('boom');
    c.setService('core');
    await pumpEventQueue();
    expect(c.rows, hasLength(1));
    c.dispose();
  });

  test('loadMore reads the next page without a native pull', () async {
    await dao.insertBatch([for (var i = 1; i <= 250; i++) _e(i, 'core')]);
    final c = NetworkLogController(repo);
    await c.load();
    await c.loadMore();
    final ids = c.rows.map((r) => r.startedAtMs).toSet();
    expect(ids.length, 250);
    c.dispose();
  });

  test('no notifyListeners after dispose', () async {
    final c = NetworkLogController(repo);
    repo.gate = Completer<void>();
    final f = c.load();
    c.dispose();
    repo.gate!.complete();
    await f;
  });

  test('clear empties rows and rowsForCopy honours the filter', () async {
    await dao.insertBatch([_e(1, 'core'), _e(2, 'auth-service')]);
    final c = NetworkLogController(repo);
    c.service = 'core';
    expect(await c.rowsForCopy(), hasLength(1));
    await c.clear();
    expect(c.rows, isEmpty);
    c.dispose();
  });

  test('endpoints are injectable', () {
    const ep = ConfiguredEndpoint(service: 's', url: 'u', rule: 'r');
    final c = NetworkLogController(repo, endpoints: const [ep]);
    expect(c.endpoints, [ep]);
    c.dispose();
  });
}
