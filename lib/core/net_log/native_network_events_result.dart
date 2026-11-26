import 'network_log_entry.dart';

enum NativeNetworkStatus { ok, unavailable, notInitialized, failed }

/// Outcome of one pull from the native SDK request log.
class NativeNetworkEventsResult {
  const NativeNetworkEventsResult({
    required this.status,
    this.events = const [],
    this.maxId = 0,
    this.lastRawId,
    this.rawCount,
  });

  final NativeNetworkStatus status;

  /// Events with an empty `service`; the repository classifies them.
  final List<NetworkLogEntry> events;

  /// Highest event id in the SDK store, used to detect a store reset.
  final int maxId;

  /// Highest valid `id` among every raw row examined, including skipped
  /// malformed ones, so the cursor can move past rows that never parse.
  /// Null when the source does not report it.
  final int? lastRawId;

  /// Number of raw rows examined (parsed plus skipped). Null means
  /// [events] is the whole batch.
  final int? rawCount;
}
