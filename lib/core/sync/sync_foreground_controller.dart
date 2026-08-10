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
    Duration startDelay = const Duration(seconds: 2),
  })  : _progress = progress,
        _notifier = notifier,
        _startDelay = startDelay;

  final Stream<SyncProgress> _progress;
  final SyncForegroundNotifier _notifier;

  /// How long a sync must still be running before the service is started.
  ///
  /// Most syncs are no-ops — a connectivity-triggered pass with nothing pending
  /// finished in **176 ms** on a Pixel 10a. Starting a foreground service for
  /// those flickers a notification and, worse, races `stopSelf` against
  /// `startForeground`, which Android logs as "Bringing down service while
  /// still waiting for start foreground" and can escalate to
  /// ForegroundServiceDidNotStartInTimeException on a slower handset.
  ///
  /// The trade-off is that the first [_startDelay] of a sync runs unprotected.
  /// That is safe in practice: syncs begin while the app is in the foreground,
  /// and the screen timeout this feature exists for is 30 s.
  final Duration _startDelay;

  StreamSubscription<SyncProgress>? _progressSub;
  Timer? _startTimer;

  /// Non-null while a start is in flight. A stop must await it — see
  /// [_stopAfterAnyPendingStart].
  Future<void>? _startInFlight;

  bool _serviceRunning = false;
  bool _sawError = false;

  /// Last progress seen, replayed once the service is actually up. Without
  /// this, every event arriving during the start window is dropped as
  /// "not running" and the notification never shows counts at all.
  SyncProgress? _latestProgress;

  /// Begins observing sync activity. Call once during app start-up.
  void attach() {
    SyncActivity.onActiveChanged = _onActiveChanged;
    _progressSub = _progress.listen(_onProgress);
  }

  Future<void> dispose() async {
    SyncActivity.onActiveChanged = null;
    _startTimer?.cancel();
    _startTimer = null;
    await _progressSub?.cancel();
    _progressSub = null;
    await _stopAfterAnyPendingStart();
  }

  void _onActiveChanged(bool active) {
    _startTimer?.cancel();
    _startTimer = null;
    if (active) {
      _startTimer = Timer(_startDelay, _beginStart);
    } else {
      unawaited(_stopAfterAnyPendingStart());
    }
  }

  void _beginStart() {
    _startTimer = null;
    if (_serviceRunning || _startInFlight != null) return;
    final pending = _runStart();
    _startInFlight = pending;
    unawaited(pending.whenComplete(() => _startInFlight = null));
  }

  /// Stops only after any in-flight start has settled.
  ///
  /// Issuing `stopSelf` while `startForegroundService` is still resolving is
  /// exactly the state Android complains about, and leaves a window where the
  /// 5-second startForeground deadline can fire against a service nobody
  /// intends to keep.
  Future<void> _stopAfterAnyPendingStart() async {
    final pending = _startInFlight;
    if (pending != null) await pending;
    await _stop();
  }

  Future<void> _runStart() async {
    if (_serviceRunning) return;
    _sawError = false;
    debugPrint('[SyncForeground] starting service');
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
      return;
    }
    // Replay whatever arrived while the channel round-trip was in flight,
    // otherwise the notification sits on its "starting" text for the rest of
    // the sync.
    final buffered = _latestProgress;
    if (buffered != null) await _pushProgress(buffered);
  }

  Future<void> _stop() async {
    _latestProgress = null;
    if (!_serviceRunning) return;
    _serviceRunning = false;
    debugPrint('[SyncForeground] stopping service');
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
    // Buffer unconditionally: events arriving during the start delay or the
    // channel round-trip are replayed by [_runStart] once the service is up.
    _latestProgress = progress;
    if (!_serviceRunning) return;
    unawaited(_pushProgress(progress));
  }

  Future<void> _pushProgress(SyncProgress progress) => _guard(
        'update',
        () => _notifier.update(
          text: _notificationText(progress),
          done: progress.itemsDone,
          total: progress.itemsTotal,
        ),
      );

  /// "households 240 / 1200" while counts are known, otherwise the step label
  /// alone. Copy comes from [SyncStrings]; nothing user-facing is built here.
  String _notificationText(SyncProgress progress) {
    if (progress.isRetrying) {
      return SyncStrings.retryingAttempt(
        progress.retryAttempt!,
        progress.retryMaxAttempts!,
      );
    }
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
