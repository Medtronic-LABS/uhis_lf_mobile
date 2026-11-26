import 'network_log_entry.dart';

/// The write side of the network log that the recorder depends on.
abstract interface class NetworkLogSink {
  /// Persists [entries]; writes nothing when [isCurrent] returns false.
  Future<void> insertBatch(
    List<NetworkLogEntry> entries, {
    bool Function()? isCurrent,
  });
}
