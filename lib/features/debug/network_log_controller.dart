import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/debug/console_log.dart';
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
  Future<void>? _inFlight;
  Future<void>? _queued;

  List<ConfiguredEndpoint> get endpoints =>
      _endpoints ?? AppConfig.configuredEndpoints;

  void setService(String? s) {
    if (s == service) return;
    service = s;
    unawaited(load());
  }

  /// Starts a load, or queues one re-run behind the load in flight. Every
  /// caller during that load gets the same queued future, which completes
  /// after the re-run.
  Future<void> load() {
    if (_disposed) return Future.value();
    final running = _inFlight;
    if (running == null) return _start(() => _repo.load(service: service));
    return _queued ??= running.then(
      (_) => _startQueued(),
      onError: (Object _) => _startQueued(),
    );
  }

  Future<void> _startQueued() {
    _queued = null;
    return load();
  }

  Future<void> refresh() => load();

  Future<void> loadMore() {
    if (!hasMore) return Future.value();
    if (loading) return Future.value();
    return _start(
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

  Future<void> _start(
    Future<NetworkLogPage> Function() read, {
    bool append = false,
  }) {
    final run = _run(read, append: append);
    _inFlight = run;
    return run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    });
  }

  /// A failed read keeps the last good state and is logged by type only.
  Future<void> _run(
    Future<NetworkLogPage> Function() read, {
    required bool append,
  }) async {
    loading = true;
    _notify();
    try {
      final page = await read();
      rows = append ? [...rows, ...page.rows] : page.rows;
      counts = page.counts;
      nativeStatus = page.nativeStatus;
      droppedCount = page.droppedCount;
      hasMore = page.hasMore;
    } on Exception catch (e) {
      ConsoleLog.warn('[NetworkLog] load failed: ${e.runtimeType}');
    } finally {
      loading = false;
      _notify();
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
