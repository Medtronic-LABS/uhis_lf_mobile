import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the Android `dataSync` foreground service that keeps the process
/// alive while an offline sync runs.
///
/// An interface rather than a concrete class so callers depend on the contract:
/// tests and web get [NoopSyncForegroundNotifier], Android gets
/// [MethodChannelSyncForegroundNotifier]. Carries no business logic — all copy
/// is passed in already localized from `app_strings.dart`.
abstract class SyncForegroundNotifier {
  /// Starts the foreground service. Returns false when Android refused the
  /// start (API 31+ forbids starting one from the background), in which case
  /// the sync must continue without it rather than fail.
  Future<bool> start({
    required String channelName,
    required String title,
    required String text,
  });

  /// Updates the ongoing notification. [total] of 0 renders an indeterminate
  /// spinner, which is honest about work of unknown length.
  Future<void> update({required String text, int done = 0, int total = 0});

  /// Tears down the service and its ongoing notification.
  Future<void> stop();

  /// Posts a dismissible failure notice after [stop], so a sync that failed
  /// while the SK was elsewhere leaves a trace.
  Future<void> showFailure({required String title, required String text});
}

/// No-op implementation for web, tests, and any platform without the service.
class NoopSyncForegroundNotifier implements SyncForegroundNotifier {
  const NoopSyncForegroundNotifier();

  @override
  Future<bool> start({
    required String channelName,
    required String title,
    required String text,
  }) async =>
      false;

  @override
  Future<void> update({required String text, int done = 0, int total = 0}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> showFailure({required String title, required String text}) async {}
}

/// Android implementation over `com.medtroniclabs.uhis_next/sync_foreground`.
///
/// Every call swallows [PlatformException] and [MissingPluginException] after
/// logging: the notification is an aid, and failing to draw it must never fail
/// a sync.
class MethodChannelSyncForegroundNotifier implements SyncForegroundNotifier {
  const MethodChannelSyncForegroundNotifier();

  static const _channel =
      MethodChannel('com.medtroniclabs.uhis_next/sync_foreground');

  @override
  Future<bool> start({
    required String channelName,
    required String title,
    required String text,
  }) async {
    try {
      final started = await _channel.invokeMethod<bool>('start', {
        'channelName': channelName,
        'title': title,
        'text': text,
        'done': 0,
        'total': 0,
      });
      if (started != true) {
        debugPrint('[SyncForeground] start refused — continuing without service');
      }
      return started ?? false;
    } on PlatformException catch (e) {
      debugPrint('[SyncForeground] start failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> update({
    required String text,
    int done = 0,
    int total = 0,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'title': '',
        'text': text,
        'done': done,
        'total': total,
      });
    } on PlatformException catch (e) {
      debugPrint('[SyncForeground] update failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      // Platform without the plugin — nothing to update.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      debugPrint('[SyncForeground] stop failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      // Nothing was started.
    }
  }

  @override
  Future<void> showFailure({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod<void>('showFailure', {
        'title': title,
        'text': text,
      });
    } on PlatformException catch (e) {
      debugPrint('[SyncForeground] showFailure failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      // Nothing to show.
    }
  }
}
