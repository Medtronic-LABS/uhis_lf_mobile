import 'dart:convert';

import '../db/referral_dao.dart';
import '../models/referral.dart';
import '../sla/sla_evaluator.dart';
import 'channel_registry.dart';
import 'notification_service.dart';

/// Coordinates repeat-cadence + persistence for SLA notifications.
///
/// Single source of truth for whether a (referralId, channel) pair is
/// "due" to fire again. Persists to `notification_log` via [ReferralDao]
/// so the rehydrate-on-boot path can restore pending alarms.
///
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md` §4.5 + §12.6.
class RepeatScheduler {
  RepeatScheduler({
    required ReferralDao dao,
    required NotificationService notifications,
    DateTime Function()? clock,
  })  : _dao = dao,
        _notifications = notifications,
        _clock = clock ?? DateTime.now;

  final ReferralDao _dao;
  final NotificationService _notifications;
  final DateTime Function() _clock;

  /// Maybe-fire a notification for the given referral on the given channel.
  ///
  /// Honours the [EscalationChain.minIntervalBetweenRepeats] floor by
  /// checking the latest `notification_log` row for the (referral, channel)
  /// pair. Returns `true` when a notification was actually dispatched.
  Future<bool> maybeFire({
    required String referralId,
    required String channelId,
    required String title,
    required String body,
    Map<String, Object?>? payload,
  }) async {
    final now = _clock();
    final last = await _dao.latestForReferral(referralId, channelId);
    final lastFiredAt = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(last.firedAt);
    if (lastFiredAt != null &&
        now.difference(lastFiredAt) < EscalationChain.minIntervalBetweenRepeats) {
      return false;
    }
    final id = _stableId(referralId, channelId);
    final payloadJson = payload == null ? null : jsonEncode(payload);
    await _notifications.show(
      id: id,
      channelId: channelId,
      title: title,
      body: body,
      payload: payloadJson,
    );
    final nextRepeatAt = _nextRepeatAt(channelId, now);
    await _dao.logNotification(NotificationLogRow(
      id: '$referralId:$channelId:${now.millisecondsSinceEpoch}',
      referralId: referralId,
      channel: channelId,
      firedAt: now.millisecondsSinceEpoch,
      nextRepeatAt: nextRepeatAt?.millisecondsSinceEpoch,
      payloadJson: payloadJson,
    ));
    return true;
  }

  /// Re-emit any repeat that was due while the device was off. Called once
  /// at app start (`main.dart` `initState`) — the
  /// `flutter_local_notifications` plugin handles native-side reboot of
  /// future-dated alarms via its own `ScheduledNotificationBootReceiver`,
  /// so this method only catches past-due repeats.
  Future<int> rehydrateOnBoot() async {
    final pending = await _dao.pendingRepeats();
    if (pending.isEmpty) return 0;
    int n = 0;
    for (final row in pending) {
      final payload = (row.payloadJson == null || row.payloadJson!.isEmpty)
          ? const <String, Object?>{}
          : jsonDecode(row.payloadJson!) as Map<String, Object?>;
      final title = payload['title']?.toString() ?? 'Referral reminder';
      final body =
          payload['body']?.toString() ?? 'You have a pending referral alert.';
      final fired = await maybeFire(
        referralId: row.referralId,
        channelId: row.channel,
        title: title,
        body: body,
        payload: payload,
      );
      if (fired) n++;
    }
    return n;
  }

  /// Stable, channel-namespaced notification ID. Bound to a 32-bit signed int
  /// per the Android Notification.id contract.
  int _stableId(String referralId, String channelId) {
    final h = '$channelId:$referralId'.hashCode;
    return h & 0x7fffffff;
  }

  DateTime? _nextRepeatAt(String channelId, DateTime now) {
    switch (channelId) {
      case NotificationChannels.critical:
        return now.add(EscalationChain.repeatIntervalCritical);
      case NotificationChannels.warning:
        return now.add(EscalationChain.repeatIntervalWarning);
      case NotificationChannels.completion:
        return null; // one-shot
      default:
        return null;
    }
  }
}
