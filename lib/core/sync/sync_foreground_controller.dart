import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_strings.dart';
import 'sync_activity.dart';
import 'sync_foreground_notifier.dart';
import 'sync_progress.dart';

/// Runs the Android `dataSync` foreground service for exactly as long as
/// something is syncing, and mirrors sync progress into its notification.
///
/// Owns no sync logic and is never awaited by a sync: if the service refuses to
/// start (Android 12+ blocks foreground-service starts from the background) or
/// the channel throws, the sync proceeds unchanged and simply loses its
/// notification. That degradation is deliberate — a missing notification must
/// never fail a data pull.
///
/// Lifecycle is driven off [SyncActivity.onActiveChanged], which fires only on
/// the "nothing syncing" ↔ "something syncing" edge, so a pull and a concurrent
/// assessment push produce one service start and one stop.
class SyncForegroundController {
  /// Takes the progress [Stream] rather than [OfflineSyncService] itself — the
  /// controller needs nothing else from it, and the narrow dependency keeps
  /// this testable without constructing the service's dozen DAOs.
  SyncForegroundController({
    required Stream<SyncProgress> progress,
    SyncForegroundNotifier notifier = const NoopSyncForegroundNotifier(),
  })  : _progress = progress,
        _notifier = notifier;

  final Stream<SyncProgress> _progress;
  final SyncForegroundNotifier _notifier;

  StreamSubscription<SyncProgress>? _progressSub;
  bool _serviceRunning = false;
  bool _sawError = false;

  /// Begins observing sync activity. Call once during app start-up.
  void attach() {
    SyncActivity.onActiveChanged = _onActiveChanged;
    _progressSub = _progress.listen(_onProgress);
  }

  Future<void> dispose() async {
    SyncActivity.onActiveChanged = null;
    await _progressSub?.cancel();
    _progressSub = null;
    if (_serviceRunning) await _stop();
  }

  void _onActiveChanged(bool active) {
    if (active) {
      unawaited(_start());
    } else {
      unawaited(_stop());
    }
  }

  Future<void> _start() async {
    if (_serviceRunning) return;
    _sawError = false;
    final started = await _guard(
      'start',
      () => _notifier.start(
        channelName: SyncStrings.notificationChannelName,
        title: SyncStrings.notificationTitle,
        text: SyncStrings.notificationStarting,
      ),
    );
    // Track what actually happened, not what we asked for: if Android refused
    // the start — or the channel threw — there is no service to update or stop.
    _serviceRunning = started ?? false;
    if (!_serviceRunning) {
      debugPrint('[SyncForeground] running without foreground service');
    }
  }

  Future<void> _stop() async {
    if (!_serviceRunning) return;
    _serviceRunning = false;
    await _guard('stop', _notifier.stop);
    if (_sawError) {
      await _guard(
        'showFailure',
        () => _notifier.showFailure(
          title: SyncStrings.notificationFailedTitle,
          text: _lastError ?? SyncStrings.syncFailed,
        ),
      );
    }
  }

  /// Runs a notifier call and swallows anything it throws.
  ///
  /// This is the boundary the class contract rests on: the notification is an
  /// aid, and no failure to draw one may surface as an unhandled async error or
  /// interrupt the sync it is reporting on. Returns null when the call failed.
  Future<T?> _guard<T>(String label, Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('[SyncForeground] $label failed: $e');
      return null;
    }
  }

  String? _lastError;

  void _onProgress(SyncProgress progress) {
    if (progress.hasError) {
      _sawError = true;
      _lastError = progress.error;
      return;
    }
    if (!_serviceRunning) return;
    unawaited(
      _guard(
        'update',
        () => _notifier.update(
          text: _notificationText(progress),
          done: progress.itemsDone,
          total: progress.itemsTotal,
        ),
      ),
    );
  }

  /// "households 240 / 1200" while counts are known, otherwise the step label
  /// alone. Copy comes from [SyncStrings]; nothing user-facing is built here.
  String _notificationText(SyncProgress progress) {
    final label = progress.entityName.isNotEmpty
        ? progress.entityName
        : progress.currentStep.label;
    if (progress.itemsTotal > 0) {
      return SyncStrings.notificationProgress(
        label,
        progress.itemsDone,
        progress.itemsTotal,
      );
    }
    return label;
  }
}
