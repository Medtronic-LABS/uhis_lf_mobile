import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/net_log/native_network_event_source.dart';
import 'package:uhis_next/core/net_log/network_log_dao.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_repository.dart';
import 'package:uhis_next/core/net_log/network_request_recorder.dart';
import 'package:uhis_next/core/net_log/service_classifier.dart';

class FakeRecorder implements ManagedNetworkRequestRecorder {
  final List<String> calls;
  FakeRecorder(this.calls);
  @override
  int epoch = 0;
  @override
  int droppedCount = 0;
  List<NetworkLogEntry> buffer = [];
  NetworkLogDao? dao;

  @override
  void record(NetworkLogEntry e) => buffer.add(e);

  @override
  Future<void> flush() async {
    calls.add('flush');
    final d = dao;
    if (d != null && buffer.isNotEmpty) {
      await d.insertBatch(buffer, isCurrent: () => true);
    }
    buffer = [];
  }

  @override
  void clearBuffer() {
    calls.add('clearBuffer');
    buffer = [];
    epoch++;
  }
}

/// Records `dao.clear` into the shared call log and every merged batch.
class SpyDao extends NetworkLogDao {
  SpyDao(super.db, this.calls);
  final List<String> calls;
  final List<List<NetworkLogEntry>> merged = [];

  @override
  Future<int> mergeNative(
    List<NetworkLogEntry> entries, {
    int? cursorTo,
  }) {
    merged.add(entries);
    return super.mergeNative(entries, cursorTo: cursorTo);
  }

  @override
  Future<void> clear() {
    calls.add('dao.clear');
    return super.clear();
  }
}

class FakeSource implements NativeNetworkEventSource {
  FakeSource(this.handler);
  final Future<NativeNetworkEventsResult> Function(int afterId, int limit)
  handler;
  final List<int> afterIds = [];

  @override
  Future<NativeNetworkEventsResult> fetch({
    required int afterId,
    int limit = 200,
  }) {
    afterIds.add(afterId);
    return handler(afterId, limit);
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;

NetworkLogEntry _dart(int t, {String service = 'core'}) => NetworkLogEntry(
  startedAtMs: t,
  source: 'dart',
  service: service,
  method: 'GET',
  url: 'https://example.test/x/$t',
  statusCode: 200,
);

NetworkLogEntry _native(int id, {String url = 'https://example.test/n'}) =>
    NetworkLogEntry(
      startedAtMs: _now() + 1000,
      source: 'native',
      nativeId: id,
      service: '',
      method: 'GET',
      url: url,
      statusCode: 200,
    );

NativeNetworkEventsResult _ok(List<NetworkLogEntry> ev, [int? maxId]) =>
    NativeNetworkEventsResult(
      status: NativeNetworkStatus.ok,
      events: ev,
      maxId: maxId ?? (ev.isEmpty ? 0 : ev.last.nativeId!),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late SpyDao dao;
  late FakeRecorder recorder;
  late List<String> calls;

  setUp(() async {
    final raw = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.schemaVersion,
        onCreate: AppDatabase.createSchema,
      ),
    );
    db = AppDatabase.forTesting(raw);
    calls = [];
    dao = SpyDao(db, calls);
    recorder = FakeRecorder(calls)..dao = dao;
  });
  tearDown(() => db.close());

  NetworkLogRepository repo(NativeNetworkEventSource s) =>
      NetworkLogRepository(dao: dao, recorder: recorder, native: s);

  FakeSource unavailable() => FakeSource(
    (_, _) async => const NativeNetworkEventsResult(
      status: NativeNetworkStatus.unavailable,
    ),
  );

  group('NetworkLogRepository.load', () {
    for (final status in NativeNetworkStatus.values.where(
      (s) => s != NativeNetworkStatus.ok,
    )) {
      test('status $status keeps Dart rows and is exposed', () async {
        await dao.insertBatch([_dart(1), _dart(2)]);
        final page = await repo(
          FakeSource((_, _) async => NativeNetworkEventsResult(status: status)),
        ).load();
        expect(page.nativeStatus, status);
        expect(page.rows, hasLength(2));
        expect(page.counts, {'core': 2});
      });
    }

    test('flushes the recorder first', () async {
      recorder.record(_dart(5));
      final page = await repo(unavailable()).load();
      expect(calls.first, 'flush');
      expect(page.rows, hasLength(1));
    });

    test('stores a raw presigned native url sanitised and classified', () async {
      final raw =
          'https://user:pw@bucket.example.test/file.mp3?X-Amz-Signature=abc&t=1';
      final page = await repo(
        FakeSource((_, _) async => _ok([_native(1, url: raw)])),
      ).load();
      final row = page.rows.single;
      expect(row.source, 'native');
      expect(row.timing, 'headers');
      expect(row.url, isNot(contains('?')));
      expect(row.url, isNot(contains('pw')));
      expect(row.url, isNot(contains('Signature')));
      expect(row.service, isNotEmpty);
    });

    test('cursor advances and the next load asks from it', () async {
      final src = FakeSource((after, _) async {
        return after == 0 ? _ok([_native(4), _native(7)]) : _ok(const [], 7);
      });
      final r = repo(src);
      await r.load();
      expect(src.afterIds, [0]);
      src.afterIds.clear();
      await r.load();
      expect(src.afterIds.first, 7);
      expect((await dao.nativeState()).cursor, 7);
    });

    test('an oversized batch is capped and the cursor stops at the 200th id', () async {
      final src = FakeSource((after, _) async {
        if (after == 0) {
          return NativeNetworkEventsResult(
            status: NativeNetworkStatus.ok,
            events: [for (var i = 1; i <= 5000; i++) _native(i)],
            maxId: 5000,
          );
        }
        return _ok(const [], 5000);
      });
      final r = repo(src);
      await r.load();
      expect(dao.merged.first, hasLength(200));
      expect((await dao.nativeState()).cursor, 200);
      await r.load();
      expect(src.afterIds.last, 200);
    });

    test('a fully malformed batch advances the cursor past it', () async {
      final src = FakeSource((after, _) async {
        if (after == 0) {
          return const NativeNetworkEventsResult(
            status: NativeNetworkStatus.ok,
            maxId: 400,
            lastRawId: 200,
            rawCount: 200,
          );
        }
        return _ok(const [], 400);
      });
      final r = repo(src);
      await r.load();
      expect((await dao.nativeState()).cursor, 200);
      expect(src.afterIds, [0, 200]);
    });

    test('mixed good and bad rows advance to the highest raw id', () async {
      final src = FakeSource(
        (_, _) async => NativeNetworkEventsResult(
          status: NativeNetworkStatus.ok,
          events: [_native(3)],
          maxId: 9,
          lastRawId: 9,
          rawCount: 4,
        ),
      );
      await repo(src).load();
      expect((await dao.nativeState()).cursor, 9);
      expect(src.afterIds, [0]);
    });

    test('cursor resets to 0 when maxId < cursor', () async {
      await dao.mergeNative(const [], cursorTo: 50);
      final src = FakeSource((after, _) async {
        return after == 50 ? _ok(const [], 3) : _ok([_native(2)]);
      });
      await repo(src).load();
      expect(src.afterIds, [50, 0]);
      expect((await dao.nativeState()).cursor, 2);
    });

    test('makes at most 3 calls of 200 per load', () async {
      var next = 1;
      final src = FakeSource((after, limit) async {
        expect(limit, 200);
        return _ok([for (var i = 0; i < 200; i++) _native(next++)]);
      });
      await repo(src).load();
      expect(src.afterIds, [0, 200, 400]);
      expect((await dao.nativeState()).cursor, 600);
    });

    test('epoch change mid-pull skips merge and cursor update', () async {
      await dao.mergeNative(const [], cursorTo: 9);
      final src = FakeSource((_, _) async {
        recorder.epoch++;
        return _ok([_native(20)]);
      });
      final page = await repo(src).load();
      expect(page.rows, isEmpty);
      expect((await dao.nativeState()).cursor, 9);
      final native = await db.db.query(
        AppDatabase.tableNetworkLog,
        where: "source = 'native'",
      );
      expect(native, isEmpty);
    });

    test('a throwing source yields failed and does not crash', () async {
      await dao.insertBatch([_dart(1)]);
      final page = await repo(
        FakeSource((_, _) async => throw const FormatException('x')),
      ).load();
      expect(page.nativeStatus, NativeNetworkStatus.failed);
      expect(page.rows, hasLength(1));
    });

    test('hands the DAO a sanitised url and the exact service', () async {
      final classifier = ServiceClassifier(const [
        ConfiguredEndpoint(
          service: 'micro-coaching',
          url: 'https://coach.example.test/sdk',
          rule: 'test',
        ),
      ]);
      final r = NetworkLogRepository(
        dao: dao,
        recorder: recorder,
        native: FakeSource(
          (_, _) async => _ok([
            _native(
              1,
              url: 'https://u:pw@coach.example.test/sdk/v1/e?X-Amz-Signature=abc',
            ),
          ]),
        ),
        classifier: classifier,
      );
      await r.load();
      final e = dao.merged.single.single;
      expect(e.url, isNot(contains('?')));
      expect(e.url, isNot(contains('pw')));
      expect(e.url, isNot(contains('Signature')));
      expect(e.service, 'micro-coaching');
      expect(e.source, 'native');
      expect(e.timing, 'headers');
    });

    test('reset with an empty result stores cursor 0', () async {
      await dao.mergeNative(const [], cursorTo: 50);
      final src = FakeSource((_, _) async => _ok(const [], 0));
      await repo(src).load();
      expect(src.afterIds.first, 50);
      expect((await dao.nativeState()).cursor, 0);
    });

    test('epoch change before the reset path leaves the cursor', () async {
      await dao.mergeNative(const [], cursorTo: 50);
      final src = FakeSource((_, _) async {
        recorder.epoch++;
        return _ok(const [], 0);
      });
      await repo(src).load();
      expect(src.afterIds, [50]);
      expect((await dao.nativeState()).cursor, 50);
    });

    test('an Error from the source propagates', () async {
      final src = FakeSource((_, _) async => throw StateError('bug'));
      expect(repo(src).load(), throwsA(isA<StateError>()));
    });

    test('later pages do not flush or pull native rows', () async {
      await dao.insertBatch([for (var i = 1; i <= 250; i++) _dart(i)]);
      final src = FakeSource((_, _) async => _ok([_native(9)]));
      final r = repo(src);
      final first = await r.load();
      expect(src.afterIds, [0]);
      calls.clear();
      final second = await r.load(offset: first.rows.length);
      expect(src.afterIds, [0]);
      expect(calls, isEmpty);
      final ids = {...first.rows, ...second.rows};
      expect(ids.length, first.rows.length + second.rows.length);
      expect(second.nativeStatus, first.nativeStatus);
    });

    test('hasMore reflects rows beyond the page and offset pages on', () async {
      await dao.insertBatch([for (var i = 1; i <= 201; i++) _dart(i)]);
      final r = repo(unavailable());
      final first = await r.load();
      expect(first.rows, hasLength(200));
      expect(first.hasMore, isTrue);
      final second = await r.load(offset: 200);
      expect(second.rows, hasLength(1));
      expect(second.hasMore, isFalse);
    });

    test('exposes the recorder dropped count', () async {
      recorder.droppedCount = 4;
      expect((await repo(unavailable()).load()).droppedCount, 4);
    });
  });

  group('NetworkLogRepository other', () {
    test('copyRows caps at 200 and honours the filter', () async {
      await dao.insertBatch([
        for (var i = 1; i <= 250; i++) _dart(i),
        for (var i = 1; i <= 3; i++) _dart(i, service: 'auth-service'),
      ]);
      final r = repo(unavailable());
      expect(await r.copyRows(), hasLength(200));
      final f = await r.copyRows(service: 'auth-service');
      expect(f, hasLength(3));
      expect(f.every((e) => e.service == 'auth-service'), isTrue);
    });

    test('clear drops the buffer before the table and rows stay gone', () async {
      recorder.record(_dart(1));
      await dao.insertBatch([_dart(2)]);
      calls.clear();
      await repo(unavailable()).clear();
      expect(calls, ['clearBuffer', 'dao.clear']);
      final page = await repo(unavailable()).load();
      expect(page.rows, isEmpty);
    });
  });
}
