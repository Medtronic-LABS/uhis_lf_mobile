/// Seam over Google Play's in-app update API.
///
/// Everything above this file (controller, guard, dialogs) depends on
/// [PlayUpdateClient] and [PlayUpdateSnapshot], never on the `in_app_update`
/// plugin, so it is unit-testable without a device and a plugin upgrade
/// touches one place.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:in_app_update/in_app_update.dart';

import '../errors/domain_exceptions.dart';

/// What Play reported for this install at one point in time.
@immutable
class PlayUpdateSnapshot {
  const PlayUpdateSnapshot({
    required this.availability,
    required this.immediateAllowed,
    required this.flexibleAllowed,
    required this.installStatus,
    this.availableVersionCode,
  });

  final UpdateAvailability availability;
  final bool immediateAllowed;
  final bool flexibleAllowed;
  final InstallStatus installStatus;

  /// Version code Play would install. Null when Play does not report it —
  /// callers treat that as "unverified", not "unavailable".
  final int? availableVersionCode;

  bool get updateOffered => availability == UpdateAvailability.updateAvailable;

  bool get immediateInProgress =>
      availability == UpdateAvailability.developerTriggeredUpdateInProgress;

  bool get flexibleDownloaded => installStatus == InstallStatus.downloaded;
}

abstract interface class PlayUpdateClient {
  /// Throws [PlayUpdateUnavailableException] when Play cannot answer.
  Future<PlayUpdateSnapshot> check();

  Future<AppUpdateResult> performImmediate();

  Future<AppUpdateResult> startFlexible();

  Future<void> completeFlexible();

  /// Broadcast of flexible-update install status changes.
  Stream<InstallStatus> get installStatus;
}

class InAppUpdatePlayClient implements PlayUpdateClient {
  const InAppUpdatePlayClient();

  @override
  Future<PlayUpdateSnapshot> check() => _guard(() async {
        final info = await InAppUpdate.checkForUpdate();
        return PlayUpdateSnapshot(
          availability: info.updateAvailability,
          immediateAllowed: info.immediateUpdateAllowed,
          flexibleAllowed: info.flexibleUpdateAllowed,
          installStatus: info.installStatus,
          availableVersionCode: info.availableVersionCode,
        );
      });

  @override
  Future<AppUpdateResult> performImmediate() =>
      _guard(InAppUpdate.performImmediateUpdate);

  @override
  Future<AppUpdateResult> startFlexible() =>
      _guard(InAppUpdate.startFlexibleUpdate);

  @override
  Future<void> completeFlexible() => _guard(InAppUpdate.completeFlexibleUpdate);

  @override
  Stream<InstallStatus> get installStatus => InAppUpdate.installUpdateListener;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw PlayUpdateUnavailableException(code: e.code, message: e.message);
    }
  }
}
