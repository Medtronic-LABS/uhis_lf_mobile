import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'channel_registry.dart';

/// Thin wrapper around `flutter_local_notifications` for the Referral SLA
/// engine. Three responsibilities:
///
/// - Bootstrap the plugin on app start (`initialize()` + `registerAll()`).
/// - Request notification permission (Android 13+, optional on older).
/// - Show or schedule a notification on a known [NotificationChannels] id.
///
/// Repeat cadence + `notification_log` persistence live in
/// [RepeatScheduler], not here — this class is intentionally a thin shim so
/// it stays unit-testable with a fake plugin.
///
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §4.5 + §12.6.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;

  FlutterLocalNotificationsPlugin get plugin => _plugin;

  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    await ChannelRegistry(_plugin).registerAll();
    _initialized = true;
  }

  /// Request notification permission. On Android 13+ requests
  /// POST_NOTIFICATIONS at runtime. On iOS requests alert/badge/sound
  /// via UNUserNotificationCenter. Returns `true` if granted.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return true;
  }

  /// One-shot immediate show. Caller supplies a stable [id] so duplicates
  /// re-render rather than stacking.
  Future<void> show({
    required int id,
    required String channelId,
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    await _plugin.show(
      id,
      title,
      body,
      _detailsFor(channelId),
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  NotificationDetails _detailsFor(String channelId) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _androidChannelName(channelId),
        channelDescription: _androidChannelDescription(channelId),
        importance: _importanceFor(channelId),
        priority: _priorityFor(channelId),
        category: AndroidNotificationCategory.reminder,
      ),
    );
  }

  String _androidChannelName(String channelId) {
    switch (channelId) {
      case NotificationChannels.critical:
        return 'Critical referrals';
      case NotificationChannels.warning:
        return 'Referral warnings';
      case NotificationChannels.completion:
        return 'Referral completions';
      default:
        return channelId;
    }
  }

  String _androidChannelDescription(String channelId) {
    switch (channelId) {
      case NotificationChannels.critical:
        return 'SLA breaches and emergency referral alerts.';
      case NotificationChannels.warning:
        return 'SLA approaching breach; clinical review pending.';
      case NotificationChannels.completion:
        return 'Treatment completed, discharged, follow-up scheduled.';
      default:
        return '';
    }
  }

  Importance _importanceFor(String channelId) {
    switch (channelId) {
      case NotificationChannels.critical:
        return Importance.max;
      case NotificationChannels.warning:
        return Importance.high;
      default:
        return Importance.defaultImportance;
    }
  }

  Priority _priorityFor(String channelId) {
    switch (channelId) {
      case NotificationChannels.critical:
        return Priority.max;
      case NotificationChannels.warning:
        return Priority.high;
      default:
        return Priority.defaultPriority;
    }
  }
}
