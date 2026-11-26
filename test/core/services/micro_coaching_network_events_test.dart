import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/net_log/native_network_event_source.dart';
import 'package:uhis_next/core/services/micro_coaching_service.dart';

const _channel = MethodChannel('com.medtroniclabs.uhis_next/micro_coaching');

Map<String, Object?> _row(int id, {Object? statusCode = 200, Object? errorType}) => {
  'id': id,
  'started_at_ms': 1000 + id,
  'method': 'GET',
  'url': 'https://example.test/api/$id',
  'status_code': statusCode,
  'duration_ms': 12,
  'error_type': errorType,
};

Map<String, Object?> _ok(List<Object?> events, {int maxId = 3, Object? extra}) => {
  'status': 'ok',
  'sdk_event_version': 1,
  'events': events,
  'max_id': maxId,
  'future_key': ?extra,
};

void _handle(Future<Object?> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<NativeNetworkEventsResult> pull({int afterId = 0, int limit = 200}) =>
      MicroCoachingService.getNetworkEvents(afterId: afterId, limit: limit);

  test('unregistered channel is unavailable', () async {
    expect((await pull()).status, NativeNetworkStatus.unavailable);
  });

  test('PlatformException is failed', () async {
    _handle((_) async => throw PlatformException(code: 'x', message: 'secret'));
    expect((await pull()).status, NativeNetworkStatus.failed);
  });

  test('MissingPluginException is unavailable', () async {
    _handle((_) async => throw MissingPluginException());
    expect((await pull()).status, NativeNetworkStatus.unavailable);
  });

  test('notInitialized ignores events and keeps max_id', () async {
    _handle((_) async => {..._ok([_row(1)], maxId: 9), 'status': 'notInitialized'});
    final r = await pull();
    expect(r.status, NativeNetworkStatus.notInitialized);
    expect(r.events, isEmpty);
    expect(r.maxId, 9);
  });

  test('sdk_event_version 2 is unavailable', () async {
    _handle((_) async => {..._ok([]), 'sdk_event_version': 2});
    expect((await pull()).status, NativeNetworkStatus.unavailable);
  });

  test('non-map response is failed', () async {
    _handle((_) async => 'nope');
    expect((await pull()).status, NativeNetworkStatus.failed);
  });

  test('envelope with wrongly typed field is failed', () async {
    _handle((_) async => {..._ok([]), 'max_id': 'x'});
    expect((await pull()).status, NativeNetworkStatus.failed);
  });

  test('unknown status string is failed', () async {
    _handle((_) async => {..._ok([]), 'status': 'weird'});
    expect((await pull()).status, NativeNetworkStatus.failed);
  });

  test('good payload maps to native entries', () async {
    _handle((_) async => _ok([
      _row(1),
      _row(2, statusCode: 500),
      _row(3, statusCode: null, errorType: 'Timeout'),
    ]));
    final r = await pull();
    expect(r.status, NativeNetworkStatus.ok);
    expect(r.maxId, 3);
    expect(r.events, hasLength(3));
    final e = r.events[0];
    expect(e.source, 'native');
    expect(e.timing, 'headers');
    expect(e.attempt, 1);
    expect(e.nativeId, 1);
    expect(e.service, '');
    expect(e.startedAtMs, 1001);
    expect(e.method, 'GET');
    expect(e.url, 'https://example.test/api/1');
    expect(e.statusCode, 200);
    expect(e.durationMs, 12);
    expect(e.errorType, isNull);
    expect(r.events[2].statusCode, isNull);
    expect(r.events[2].errorType, 'Timeout');
  });

  test('malformed row is skipped, others kept', () async {
    _handle((_) async => _ok([
      _row(1),
      {..._row(2), 'url': 5},
      {'id': 'x'},
      'junk',
      _row(4),
    ], maxId: 4));
    final r = await pull();
    expect(r.status, NativeNetworkStatus.ok);
    expect(r.events.map((e) => e.nativeId), [1, 4]);
  });

  test('non-android platform makes no call', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var called = false;
    _handle((_) async {
      called = true;
      return _ok([]);
    });
    expect((await pull()).status, NativeNetworkStatus.unavailable);
    expect(called, isFalse);
  });

  test('request arguments are exact and limit is clamped', () async {
    final seen = <MethodCall>[];
    _handle((c) async {
      seen.add(c);
      return _ok([]);
    });
    await pull(afterId: 5, limit: 200);
    await pull(afterId: 0, limit: 9999);
    await pull(afterId: 0, limit: 0);
    expect(seen.first.method, 'getNetworkEvents');
    expect(seen[0].arguments, {'afterId': 5, 'limit': 200, 'contract_version': 1});
    expect(seen[1].arguments['limit'], 500);
    expect(seen[2].arguments['limit'], 1);
  });

  test('unknown extra response keys are ignored', () async {
    _handle((_) async => _ok([_row(1)], maxId: 1, extra: {'a': 1}));
    expect((await pull()).status, NativeNetworkStatus.ok);
  });

  test('never-completing handler times out as failed', () async {
    _handle((_) => Completer<Object?>().future);
    final r = await MicroCoachingService.getNetworkEvents(
      afterId: 0,
      timeout: const Duration(milliseconds: 50),
    );
    expect(r.status, NativeNetworkStatus.failed);
  });

  test('events beyond the requested limit are not read', () async {
    _handle((_) async => _ok([for (var i = 1; i <= 5000; i++) _row(i)], maxId: 5000));
    final r = await pull(limit: 200);
    expect(r.events, hasLength(200));
    expect(r.rawCount, 200);
    expect(r.lastRawId, 200);
  });

  test('lastRawId and rawCount include skipped rows', () async {
    _handle((_) async => _ok([
      _row(1),
      {..._row(9), 'url': 5},
      {'id': 'x'},
    ], maxId: 9));
    final r = await pull();
    expect(r.events, hasLength(1));
    expect(r.rawCount, 3);
    expect(r.lastRawId, 9);
  });

  test('negative afterId is clamped to 0', () async {
    Object? args;
    _handle((c) async {
      args = c.arguments;
      return _ok([]);
    });
    await pull(afterId: -4);
    expect((args! as Map)['afterId'], 0);
  });

  test('version is checked before the rest of the envelope', () async {
    _handle((_) async => {'sdk_event_version': 2, 'status': 7});
    expect((await pull()).status, NativeNetworkStatus.unavailable);
  });

  final badEnvelopes = <String, Map<String, Object?>>{
    'events not a list': {..._ok([]), 'events': 'x'},
    'status not a string': {..._ok([]), 'status': 1},
    'version missing': {'status': 'ok', 'events': [], 'max_id': 0},
    'events missing': {'status': 'ok', 'sdk_event_version': 1, 'max_id': 1},
  };
  badEnvelopes.forEach((name, payload) {
    test('envelope $name is failed', () async {
      _handle((_) async => payload);
      expect((await pull()).status, NativeNetworkStatus.failed);
    });
  });

  final nonOneVersions = <String, Object?>{
    'double': 1.0,
    'string': '1',
    'null': null,
    'zero': 0,
  };
  nonOneVersions.forEach((name, version) {
    test('sdk_event_version $name is unavailable', () async {
      _handle((_) async => {..._ok([]), 'sdk_event_version': version});
      expect((await pull()).status, NativeNetworkStatus.unavailable);
    });
  });

  final badRows = <String, Map<String, Object?>>{
    'wrong-typed status_code': {..._row(1), 'status_code': '200'},
    'wrong-typed error_type': {..._row(1), 'error_type': 5},
    'negative id': {..._row(1), 'id': -1},
    'status_code 99': {..._row(1), 'status_code': 99},
    'status_code 600': {..._row(1), 'status_code': 600},
    'negative duration': {..._row(1), 'duration_ms': -1},
  };
  badRows.forEach((name, row) {
    test('row with $name is skipped', () async {
      _handle((_) async => _ok([row, _row(2)], maxId: 2));
      final r = await pull();
      expect(r.status, NativeNetworkStatus.ok);
      expect(r.events.map((e) => e.nativeId), [2]);
    });
  });

  test('MicroCoachingNetworkEventSource delegates to the fetcher', () async {
    int? gotAfter;
    int? gotLimit;
    final source = MicroCoachingNetworkEventSource(
      fetcher: ({required int afterId, int limit = 200}) async {
        gotAfter = afterId;
        gotLimit = limit;
        return const NativeNetworkEventsResult(
          status: NativeNetworkStatus.ok,
          maxId: 7,
        );
      },
    );
    final r = await source.fetch(afterId: 4, limit: 50);
    expect(gotAfter, 4);
    expect(gotLimit, 50);
    expect(r.maxId, 7);
  });

  group('clearNetworkEvents', () {
    test('true when the SDK confirms', () async {
      _handle((c) async => c.method == 'clearNetworkEvents' ? null : throw MissingPluginException());
      expect(await MicroCoachingService.clearNetworkEvents(), isTrue);
    });
    test('false when the channel is unregistered', () async {
      expect(await MicroCoachingService.clearNetworkEvents(), isFalse);
    });
    test('false on an unexpected exception type, never throws', () async {
      _handle((_) async => throw StateError('secret'));
      expect(await MicroCoachingService.clearNetworkEvents(), isFalse);
    });
    test('false on PlatformException, never throws', () async {
      _handle((_) async => throw PlatformException(code: 'x', message: 'secret'));
      expect(await MicroCoachingService.clearNetworkEvents(), isFalse);
    });
  });
}
