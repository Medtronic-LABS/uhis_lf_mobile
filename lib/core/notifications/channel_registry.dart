import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification channel IDs used by the Referral SLA Engine. Pinned as
/// constants so [RepeatScheduler], [NotificationService], and the
/// Android channel registration all read from one place.
///
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §4.5 + §12.6.
abstract final class NotificationChannels {
  NotificationChannels._();

  static const String critical = 'referral_critical';
  static const String warning = 'referral_warning';
  static const String completion = 'referral_completion';
}

/// Stable per-channel display config. The strings live in `app_strings.dart`
/// `ReferralStrings.channel*` — but those are picked up at registration time
/// (English-only for the device-OS channel name, since the Android settings
/// screen shows the channel name in the system language). Bangla labels for
/// the actual notification *body* are formatted at dispatch time, not here.
class ChannelRegistry {
  ChannelRegistry(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  /// Register all three channels idempotently. Safe to re-invoke on every
  /// app start — same ID with same config is a no-op.
  Future<void> registerAll() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return; // iOS path lands later; see spec §10 OQ #6.
    await android.createNotificationChannel(_critical());
    await android.createNotificationChannel(_warning());
    await android.createNotificationChannel(_completion());
  }

  AndroidNotificationChannel _critical() => const AndroidNotificationChannel(
        NotificationChannels.critical,
        'Critical referrals',
        description: 'SLA breaches and emergency referral alerts.',
        importance: Importance.max,
        enableVibration: true,
      );

  AndroidNotificationChannel _warning() => const AndroidNotificationChannel(
        NotificationChannels.warning,
        'Referral warnings',
        description: 'SLA approaching breach; clinical review pending.',
        importance: Importance.high,
        enableVibration: true,
      );

  AndroidNotificationChannel _completion() =>
      const AndroidNotificationChannel(
        NotificationChannels.completion,
        'Referral completions',
        description: 'Treatment completed, discharged, follow-up scheduled.',
        importance: Importance.defaultImportance,
        enableVibration: false,
      );
}
