import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uhis_next/core/net_log/db_network_request_recorder.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_sink.dart';
import 'package:uhis_next/core/net_log/network_request_recorder.dart';

class _FakeSink implements NetworkLogSink {
  final List<List<NetworkLogEntry>> batches = [];
  final List<bool Function()?> guards = [];
  Object? error;
  Completer<void>? gate;

  @override
  Future<void> insertBatch(
    List<NetworkLogEntry> entries, {
    bool Function()? isCurrent,
  }) async {
    batches.add(List.of(entries));
    guards.add(isCurrent);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    fired = true;
    callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}

NetworkLogEntry _e({
  int? status = 200,
  String? error,
  int epoch = 0,
  int at = 1,
}) => NetworkLogEntry(
  startedAtMs: at,
  source: 'dart',
  service: 'auth',
  method: 'GET',
  url: '/x',
  statusCode: status,
  errorType: error,
  epoch: epoch,
);

void main() {
  late _FakeSink sink;
  late List<_FakeTimer> timers;
  late DbNetworkRequestRecorder rec;

  setUp(() {
    sink = _FakeSink();
    timers = [];
    rec = DbNetworkRequestRecorder(
      sink,
      timerFactory: (d, cb) {
        final t = _FakeTimer(d, cb);
        timers.add(t);
        return t;
      },
    );
  });

  List<_FakeTimer> active() => timers.where((t) => t.isActive).toList();

  test('noop recorder has epoch 0 and ignores records', () {
    const r = NoopNetworkRequestRecorder();
    r.record(_e());
    expect(r.epoch, 0);
  });

  test(
    'no timer on a fresh recorder; one is armed for the first entry only',
    () {
      expect(timers, isEmpty);
      rec.record(_e());
      rec.record(_e(at: 2));
      expect(active(), hasLength(1));
      expect(active().single.duration, const Duration(seconds: 3));
    },
  );

  test(
    'timer firing flushes the buffer; no timer remains afterwards',
    () async {
      rec.record(_e());
      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      expect(sink.batches, hasLength(1));
      expect(active(), isEmpty);
    },
  );

  test('status >= 400 flushes immediately, one flush for a burst', () async {
    rec.record(_e(status: 500));
    rec.record(_e(status: 404, at: 2));
    rec.record(_e(status: null, error: 'timeout', at: 3));
    expect(sink.batches, isEmpty, reason: 'microtask-coalesced');
    await Future<void>.delayed(Duration.zero);
    expect(sink.batches, hasLength(1));
    expect(sink.batches.single, hasLength(3));
    expect(active(), isEmpty);
  });

  test('a 2xx entry does not flush immediately', () async {
    rec.record(_e());
    await Future<void>.delayed(Duration.zero);
    expect(sink.batches, isEmpty);
  });

  test('overflow drops the oldest and counts it', () async {
    for (var i = 0; i < 501; i++) {
      rec.record(_e(at: i));
    }
    expect(rec.droppedCount, 1);
    await rec.flush();
    expect(sink.batches.single, hasLength(500));
    expect(sink.batches.single.first.startedAtMs, 1);
  });

  test('DatabaseException adds the batch size to droppedCount', () async {
    sink.error = _DbEx();
    rec.record(_e());
    rec.record(_e(at: 2));
    await rec.flush();
    expect(rec.droppedCount, 2);
  });

  test('other exceptions propagate from flush but never from record', () async {
    sink.error = StateError('boom');
    rec.record(_e());
    await expectLater(rec.flush(), throwsStateError);
    expect(() => rec.record(_e(status: 500)), returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });

  test('clearBuffer empties, cancels the timer and bumps the epoch', () async {
    rec.record(_e());
    final before = rec.epoch;
    rec.clearBuffer();
    expect(rec.epoch, before + 1);
    expect(active(), isEmpty);
    await rec.flush();
    expect(sink.batches, isEmpty);
  });

  test('stale-epoch entries are dropped', () async {
    rec.clearBuffer();
    rec.record(_e(epoch: 0));
    expect(timers.where((t) => t.isActive), isEmpty);
    rec.record(_e(epoch: rec.epoch));
    await rec.flush();
    expect(sink.batches.single, hasLength(1));
  });

  test('a flush started before clearBuffer sees isCurrent == false', () async {
    sink.gate = Completer<void>();
    rec.record(_e());
    final f = rec.flush();
    expect(sink.guards.single!(), isTrue);
    rec.clearBuffer();
    expect(sink.guards.single!(), isFalse);
    sink.gate!.complete();
    await f;
    expect(rec.droppedCount, 0);
  });

  test(
    'entries recorded during an in-flight flush are written exactly once',
    () async {
      sink.gate = Completer<void>();
      rec.record(_e(at: 1));
      final first = rec.flush();
      rec.record(_e(at: 2));
      sink.gate!.complete();
      await first;
      await rec.flush();
      expect(sink.batches.map((b) => b.map((e) => e.startedAtMs).toList()), [
        [1],
        [2],
      ]);
      expect(rec.droppedCount, 0);
    },
  );

  test('a DatabaseException after a wipe is not counted as dropped', () async {
    sink.gate = Completer<void>();
    sink.error = _DbEx();
    rec.record(_e());
    final f = rec.flush();
    rec.clearBuffer();
    sink.gate!.complete();
    await f;
    expect(rec.droppedCount, 0);
  });

  test('a manual flush cancels the armed timer', () async {
    rec.record(_e());
    await rec.flush();
    expect(timers.single.cancelled, isTrue);
  });

  test('an urgent flush cancels the armed timer', () async {
    rec.record(_e());
    rec.record(_e(status: 500, at: 2));
    await Future<void>.delayed(Duration.zero);
    expect(sink.batches, hasLength(1));
    expect(timers.single.cancelled, isTrue);
  });

  test('onWipeStarting behaves like clearBuffer', () async {
    rec.record(_e());
    final before = rec.epoch;
    rec.onWipeStarting();
    expect(rec.epoch, before + 1);
    expect(active(), isEmpty);
    await rec.flush();
    expect(sink.batches, isEmpty);
  });

  test('record never throws for extreme entries', () {
    final huge = 'x' * 100000;
    expect(
      () => rec.record(
        NetworkLogEntry(
          startedAtMs: -1 << 62,
          source: huge,
          service: '',
          method: huge,
          url: huge,
          finalUrl: huge,
          statusCode: 1 << 62,
          durationMs: -1,
          attempt: -5,
          errorType: huge,
        ),
      ),
      returnsNormally,
    );
  });
}

class _DbEx implements DatabaseException {
  @override
  String toString() => 'db';
  @override
  bool isOpenFailedError() => false;
  @override
  bool isDatabaseClosedError() => false;
  @override
  bool isReadOnlyError() => false;
  @override
  bool isNoSuchTableError([String? table]) => false;
  @override
  bool isSyntaxError() => false;
  @override
  bool isUniqueConstraintError([String? field]) => false;
  @override
  bool isNotNullConstraintError([String? field]) => false;
  @override
  bool isDuplicateColumnError([String? field]) => false;
  @override
  Object? get result => null;
  @override
  int? getResultCode() => null;
}
