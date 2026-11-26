import 'network_log_entry.dart';

/// Receives one [NetworkLogEntry] per finished request. Implementations must
/// be synchronous and must never throw into the HTTP path.
abstract interface class NetworkRequestRecorder {
  /// Current wipe epoch; stamp it on entries when the request starts.
  int get epoch;

  void record(NetworkLogEntry e);
}

/// A recorder the network log page can drain and reset: write out buffered
/// entries, drop them on Clear, and report how many were lost.
abstract interface class ManagedNetworkRequestRecorder
    implements NetworkRequestRecorder {
  Future<void> flush();

  /// Like [flush] but never throws, for fire-and-forget callers (app pause,
  /// background timers) where an error would otherwise be unhandled.
  Future<void> flushQuietly();

  /// Drops buffered entries and bumps [epoch].
  void clearBuffer();

  /// Entries lost to overflow or a failed write since startup.
  int get droppedCount;
}

/// Recorder that discards everything (tests, and before the DB is ready).
class NoopNetworkRequestRecorder implements ManagedNetworkRequestRecorder {
  const NoopNetworkRequestRecorder();

  @override
  Future<void> flush() async {}

  @override
  Future<void> flushQuietly() async {}

  @override
  void clearBuffer() {}

  @override
  int get droppedCount => 0;

  @override
  int get epoch => 0;

  @override
  void record(NetworkLogEntry e) {}
}
