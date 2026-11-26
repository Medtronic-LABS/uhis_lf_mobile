import '../config/app_config.dart';
import '../debug/console_log.dart';
import 'native_network_event_source.dart';
import 'network_log_dao.dart';
import 'network_log_entry.dart';
import 'network_request_recorder.dart';
import 'service_classifier.dart';
import 'url_sanitizer.dart';

/// One screenful of the network log plus the header data around it.
class NetworkLogPage {
  const NetworkLogPage({
    required this.rows,
    required this.counts,
    required this.nativeStatus,
    required this.droppedCount,
    required this.hasMore,
  });

  final List<NetworkLogEntry> rows;
  final Map<String, int> counts;
  final NativeNetworkStatus nativeStatus;
  final int droppedCount;
  final bool hasMore;
}

/// Merges Dart-recorded and native SDK requests and serves the log page.
class NetworkLogRepository {
  NetworkLogRepository({
    required NetworkLogDao dao,
    required ManagedNetworkRequestRecorder recorder,
    required NativeNetworkEventSource native,
    ServiceClassifier? classifier,
  }) : _dao = dao,
       _recorder = recorder,
       _native = native,
       _classifier = classifier;

  static const int pageSize = 200;
  static const int maxNativeCalls = 3;

  final NetworkLogDao _dao;
  final ManagedNetworkRequestRecorder _recorder;
  final NativeNetworkEventSource _native;
  final ServiceClassifier? _classifier;

  /// Native status of the last pull; later pages reuse it.
  NativeNetworkStatus _nativeStatus = NativeNetworkStatus.unavailable;

  /// Loads one page. The first page (offset 0) flushes the recorder and pulls
  /// native events; later pages only read the table, so rows arriving between
  /// pages cannot shift the offset.
  Future<NetworkLogPage> load({String? service, int offset = 0}) async {
    if (offset == 0) {
      await _recorder.flush();
      _nativeStatus = await _pullNative();
    }
    final nativeStatus = _nativeStatus;
    // One extra row tells us whether anything lies beyond this page.
    final fetched = await _dao.page(
      limit: pageSize + 1,
      offset: offset,
      service: service,
    );
    final counts = await _dao.countsByService();
    return NetworkLogPage(
      rows: fetched.take(pageSize).toList(),
      counts: counts,
      nativeStatus: nativeStatus,
      droppedCount: _recorder.droppedCount,
      hasMore: fetched.length > pageSize,
    );
  }

  Future<List<NetworkLogEntry>> copyRows({String? service}) =>
      _dao.newest(pageSize, service: service);

  /// Buffer first: otherwise queued rows would be flushed back after Clear.
  Future<void> clear() async {
    _recorder.clearBuffer();
    await _dao.clear();
  }

  Future<NativeNetworkStatus> _pullNative() async {
    final epoch = _recorder.epoch;
    final classifier =
        _classifier ?? ServiceClassifier(AppConfig.configuredEndpoints);
    var cursor = (await _dao.nativeState()).cursor;
    var status = NativeNetworkStatus.unavailable;
    for (var call = 0; call < maxNativeCalls; call++) {
      final result = await _fetch(cursor);
      status = result.status;
      if (status != NativeNetworkStatus.ok) break;
      // A store reset on the SDK side: restart from the beginning.
      if (result.maxId < cursor) {
        if (_recorder.epoch != epoch) break;
        await _dao.mergeNative(const [], cursorTo: 0);
        cursor = 0;
        continue;
      }
      if (result.events.isNotEmpty) {
        // A wipe during the pull: a stale cursor could skip new SDK events.
        if (_recorder.epoch != epoch) break;
        final batch = [for (final e in result.events) _normalise(e, classifier)];
        final last = result.events
            .map((e) => e.nativeId ?? 0)
            .reduce((a, b) => a > b ? a : b);
        await _dao.mergeNative(batch, cursorTo: last);
        cursor = last;
      }
      if (result.events.length < pageSize) break;
    }
    return status;
  }

  Future<NativeNetworkEventsResult> _fetch(int afterId) async {
    try {
      return await _native.fetch(afterId: afterId, limit: pageSize);
    } on Exception catch (e) {
      ConsoleLog.warn('[NetworkLog] native fetch failed: ${e.runtimeType}');
      return const NativeNetworkEventsResult(status: NativeNetworkStatus.failed);
    }
  }

  NetworkLogEntry _normalise(NetworkLogEntry e, ServiceClassifier c) {
    final url = UrlSanitizer.sanitize(e.url);
    return NetworkLogEntry(
      startedAtMs: e.startedAtMs,
      source: 'native',
      nativeId: e.nativeId,
      service: c.classify(url),
      method: e.method,
      url: url,
      finalUrl: e.finalUrl,
      statusCode: e.statusCode,
      durationMs: e.durationMs,
      timing: 'headers',
      attempt: e.attempt,
      errorType: e.errorType,
    );
  }
}
