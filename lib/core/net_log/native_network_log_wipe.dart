import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../services/micro_coaching_service.dart';

/// Clears the native SDK's request events when the app database is wiped for a
/// user switch, so the next user never sees the previous user's native rows.
class NativeNetworkLogWipe implements WipeParticipant {
  const NativeNetworkLogWipe({
    Future<bool> Function() clear = MicroCoachingService.clearNetworkEvents,
  }) : _clear = clear;

  final Future<bool> Function() _clear;

  /// Fired without waiting: the call never throws, and holding the wipe
  /// transaction open on a platform call would block the database.
  @override
  void onWipeStarting() => unawaited(_clear());

  @override
  Future<void> onWipeInTransaction(Transaction tx) async {}
}
