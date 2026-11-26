import '../services/micro_coaching_service.dart';
import 'native_network_events_result.dart';

export 'native_network_events_result.dart';

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

/// Reads the native micro-coaching SDK request log over its method channel.
class MicroCoachingNetworkEventSource implements NativeNetworkEventSource {
  const MicroCoachingNetworkEventSource({
    Future<NativeNetworkEventsResult> Function({
      required int afterId,
      int limit,
    })? fetcher,
  }) : _fetcher = fetcher ?? MicroCoachingService.getNetworkEvents;

  final Future<NativeNetworkEventsResult> Function({
    required int afterId,
    int limit,
  }) _fetcher;

  @override
  Future<NativeNetworkEventsResult> fetch({
    required int afterId,
    int limit = 200,
  }) => _fetcher(afterId: afterId, limit: limit);
}
