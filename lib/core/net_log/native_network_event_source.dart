import 'network_log_entry.dart';

enum NativeNetworkStatus { ok, unavailable, notInitialized, failed }

/// Outcome of one pull from the native SDK request log.
class NativeNetworkEventsResult {
  const NativeNetworkEventsResult({
    required this.status,
    this.events = const [],
    this.maxId = 0,
  });

  final NativeNetworkStatus status;

  /// Events with an empty `service`; the repository classifies them.
  final List<NetworkLogEntry> events;

  /// Highest event id in the SDK store, used to detect a store reset.
  final int maxId;
}

/// Reads request events recorded by the native micro-coaching SDK.
abstract interface class NativeNetworkEventSource {
  Future<NativeNetworkEventsResult> fetch({
    required int afterId,
    int limit = 200,
  });
}

/// Source used until a platform implementation exists.
class UnavailableNativeNetworkEventSource implements NativeNetworkEventSource {
  const UnavailableNativeNetworkEventSource();

  @override
  Future<NativeNetworkEventsResult> fetch({
    required int afterId,
    int limit = 200,
  }) async => const NativeNetworkEventsResult(
    status: NativeNetworkStatus.unavailable,
  );
}
