import 'dart:async';
import 'dart:collection';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../debug/console_log.dart';
import 'network_log_entry.dart';
import 'network_log_sink.dart';
import 'network_request_recorder.dart';

/// Buffers entries in memory and writes them in batches.
///
/// Flushes [flushDelay] after the first buffered entry, immediately for a
/// failed request (status >= 400 or an error), and whenever [flush] is called
/// (app pause, page open). [epoch] changes on every wipe so entries and
/// in-flight batches from before the wipe are never written.
class DbNetworkRequestRecorder
    implements NetworkRequestRecorder, WipeParticipant {
  DbNetworkRequestRecorder(
    NetworkLogSink sink, {
    Duration flushDelay = const Duration(seconds: 3),
    int maxBuffer = 500,
    Timer Function(Duration, void Function()) timerFactory = Timer.new,
  }) : _sink = sink,
       _flushDelay = flushDelay,
       _maxBuffer = maxBuffer,
       _timerFactory = timerFactory;

  final NetworkLogSink _sink;
  final Duration _flushDelay;
  final int _maxBuffer;
  final Timer Function(Duration, void Function()) _timerFactory;

  final Queue<NetworkLogEntry> _buffer = Queue();
  Timer? _timer;
  bool _urgentScheduled = false;
  int _epoch = 0;
  int _dropped = 0;

  @override
  int get epoch => _epoch;

  /// Entries lost to overflow or a failed write since startup.
  int get droppedCount => _dropped;

  @override
  void record(NetworkLogEntry e) {
    if (e.epoch != _epoch) return;
    _buffer.addLast(e);
    if (_buffer.length > _maxBuffer) {
      _buffer.removeFirst();
      _dropped++;
    }
    if ((e.statusCode ?? 0) >= 400 || e.errorType != null) {
      _scheduleUrgentFlush();
    } else {
      _timer ??= _timerFactory(_flushDelay, _onTimer);
    }
  }

  /// Writes everything buffered now. Only [DatabaseException] is absorbed
  /// (counted in [droppedCount]); other errors propagate to the caller.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return;
    final batch = List<NetworkLogEntry>.of(_buffer);
    _buffer.clear();
    final captured = _epoch;
    try {
      await _sink.insertBatch(batch, isCurrent: () => captured == _epoch);
    } on DatabaseException {
      if (captured == _epoch) _dropped += batch.length;
    }
  }

  /// Drops buffered entries and invalidates in-flight batches and entries.
  void clearBuffer() {
    _buffer.clear();
    _timer?.cancel();
    _timer = null;
    _epoch++;
  }

  @override
  void onWipeStarting() => clearBuffer();

  @override
  Future<void> onWipeInTransaction(Transaction tx) async {}

  void _scheduleUrgentFlush() {
    if (_urgentScheduled) return;
    _urgentScheduled = true;
    scheduleMicrotask(() {
      _urgentScheduled = false;
      _flushInBackground();
    });
  }

  void _onTimer() {
    _timer = null;
    _flushInBackground();
  }

  void _flushInBackground() {
    flush().catchError((Object e) {
      ConsoleLog.warn('[NetworkLog] background flush failed: ${e.runtimeType}');
    });
  }
}
