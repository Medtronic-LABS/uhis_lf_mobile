import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/net_log/native_network_event_source.dart';
import '../../core/net_log/network_log_entry.dart';
import '../../core/net_log/network_log_repository.dart';
import '../../core/net_log/service_classifier.dart';

/// State holder for the network log page; widgets only read and call it.
///
/// A [load] requested while another load is running is coalesced into one
/// re-run after it finishes (so a filter change is never lost); [loadMore]
/// while loading is ignored.
class NetworkLogController extends ChangeNotifier {
  NetworkLogController(
    this._repo, {
    List<ConfiguredEndpoint>? endpoints,
  }) : _endpoints = endpoints;

  final NetworkLogRepository _repo;
  final List<ConfiguredEndpoint>? _endpoints;

  String? service;
  List<NetworkLogEntry> rows = const [];
  Map<String, int> counts = const {};
  NativeNetworkStatus nativeStatus = NativeNetworkStatus.unavailable;
  int droppedCount = 0;
  bool loading = false;
  bool hasMore = false;
  bool _disposed = false;
  bool _reloadQueued = false;

  List<ConfiguredEndpoint> get endpoints =>
      _endpoints ?? AppConfig.configuredEndpoints;

  void setService(String? s) {
    if (s == service) return;
    service = s;
    load();
  }

  Future<void> load() {
    if (loading) {
      _reloadQueued = true;
      return Future.value();
    }
    return _run(() => _repo.load(service: service), append: false);
  }

  Future<void> refresh() => load();

  Future<void> loadMore() {
    if (!hasMore) return Future.value();
    return _run(
      () => _repo.load(service: service, offset: rows.length),
      append: true,
    );
  }

  Future<void> clear() async {
    await _repo.clear();
    rows = const [];
    counts = const {};
    hasMore = false;
    _notify();
    await load();
  }

  Future<List<NetworkLogEntry>> rowsForCopy() =>
      _repo.copyRows(service: service);

  Future<void> _run(
    Future<NetworkLogPage> Function() read, {
    required bool append,
  }) async {
    if (loading || _disposed) return;
    loading = true;
    _notify();
    try {
      final page = await read();
      rows = append ? [...rows, ...page.rows] : page.rows;
      counts = page.counts;
      nativeStatus = page.nativeStatus;
      droppedCount = page.droppedCount;
      hasMore = page.hasMore;
    } finally {
      loading = false;
      _notify();
    }
    if (_reloadQueued && !_disposed) {
      _reloadQueued = false;
      await load();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
