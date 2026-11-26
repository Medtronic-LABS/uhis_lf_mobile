import 'network_log_entry.dart';

/// Receives one [NetworkLogEntry] per finished request. Implementations must
/// be synchronous and must never throw into the HTTP path.
abstract interface class NetworkRequestRecorder {
  /// Current wipe epoch; stamp it on entries when the request starts.
  int get epoch;

  void record(NetworkLogEntry e);
}

/// Recorder that discards everything (tests, and before the DB is ready).
class NoopNetworkRequestRecorder implements NetworkRequestRecorder {
  const NoopNetworkRequestRecorder();

  @override
  int get epoch => 0;

  @override
  void record(NetworkLogEntry e) {}
}
