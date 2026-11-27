/// Single owner of the Play in-app-update lifecycle.
///
/// Responsibilities (one each, per the Engineering Design Standards):
/// - one `installUpdateListener` subscription, disposed deterministically;
/// - one throttled Play availability check per resume, shared by "is a
///   flexible update downloaded?" and "is an immediate update interrupted?";
/// - interrupted-immediate-update recovery that is **never** throttled;
/// - the safe-point rule for restarting into a downloaded update;
/// - answering the required-update question ([RequiredUpdateResolver]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_update/in_app_update.dart';

import '../debug/console_log.dart';
import '../errors/domain_exceptions.dart';
import 'app_version_service.dart';
import 'play_update_client.dart';
import 'required_update_guard.dart';

/// Result of trying to start an update.
sealed class AppUpdateOutcome {
  const AppUpdateOutcome();
}

/// Immediate update finished (or Play completed an already-downloaded one).
class AppUpdateInstalled extends AppUpdateOutcome {
  const AppUpdateInstalled();
}

/// Flexible download started; completion arrives via the install listener.
class AppUpdateDownloading extends AppUpdateOutcome {
  const AppUpdateDownloading();
}

class AppUpdateCancelled extends AppUpdateOutcome {
  const AppUpdateCancelled();
}

/// Play has nothing it can run for this install right now.
class AppUpdateUnavailable extends AppUpdateOutcome {
  const AppUpdateUnavailable([this.code]);
  final String? code;
}

class AppUpdateFailed extends AppUpdateOutcome {
  const AppUpdateFailed([this.code]);
  final String? code;
}

/// Diagnostics sink for update lifecycle events. Carries no user identifiers.
abstract interface class AppUpdateLog {
  void event(String name, [Map<String, Object?> data = const {}]);
}

class ConsoleAppUpdateLog implements AppUpdateLog {
  const ConsoleAppUpdateLog();

  @override
  void event(String name, [Map<String, Object?> data = const {}]) =>
      ConsoleLog.step('[AppUpdate] $name $data');
}

/// Remembers that an immediate update was started, so recovery after a kill
/// does not depend on a throttled or racing Play query.
abstract interface class ImmediateUpdateFlagStore {
  Future<bool> isSet();
  Future<void> set(bool value);
}

class SecureImmediateUpdateFlagStore implements ImmediateUpdateFlagStore {
  const SecureImmediateUpdateFlagStore([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);

  static const String _key = 'app_update_immediate_started_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> isSet() async {
    try {
      return await _storage.read(key: _key) == '1';
    } on PlatformException catch (e) {
      debugPrint('[AppUpdate] flag unreadable: $e');
      return false;
    }
  }

  @override
  Future<void> set(bool value) async {
    try {
      if (value) {
        await _storage.write(key: _key, value: '1');
      } else {
        await _storage.delete(key: _key);
      }
    } on PlatformException catch (e) {
      debugPrint('[AppUpdate] flag not persisted: $e');
    }
  }
}

class AppUpdateController extends ChangeNotifier
    implements RequiredUpdateResolver {
  AppUpdateController(
    this._play, {
    required bool supported,
    ImmediateUpdateFlagStore flagStore = const SecureImmediateUpdateFlagStore(),
    AppUpdateLog log = const ConsoleAppUpdateLog(),
    DateTime Function()? now,
    this.checkThrottle = const Duration(minutes: 2),
  })  : _supported = supported,
        _flag = flagStore,
        _log = log,
        _now = now ?? DateTime.now;

  final PlayUpdateClient _play;
  final bool _supported;
  final ImmediateUpdateFlagStore _flag;
  final AppUpdateLog _log;
  final DateTime Function() _now;

  /// Minimum gap between availability checks (not applied to recovery).
  final Duration checkThrottle;

  bool Function() _isSafePoint = () => false;
  StreamSubscription<InstallStatus>? _sub;
  DateTime? _lastCheck;
  bool _restartReady = false;
  bool _requiredDeferred = false;
  bool _warnedThisSession = false;

  /// A flexible update is downloaded and waiting for the user to restart.
  bool get restartReady => _restartReady;

  /// Whether Play updates are attempted at all (Android, non-sideload flavor).
  bool get supported => _supported;

  /// The router tells us whether the user is somewhere a restart is harmless
  /// (the home dashboard — never a visit or form).
  void bindSafePoint(bool Function() probe) => _isSafePoint = probe;

  /// Call on cold start and on every resume.
  Future<void> refresh() async {
    if (!_supported) return;
    _ensureListening();
    final recovering = await _flag.isSet();
    if (!recovering && _throttled()) return;
    final snapshot = await _checkOrNull();
    if (snapshot == null) return;
    _lastCheck = _now();
    if (snapshot.immediateInProgress) {
      await _runImmediate();
      return;
    }
    if (recovering) await _flag.set(false);
    _setRestartReady(snapshot.flexibleDownloaded);
  }

  @override
  Future<RequiredUpdateDecision> resolve(AppVersionUpdateRequired required) async {
    final snapshot = _supported ? await _checkOrNull() : null;
    final decision = decideRequiredUpdate(
      play: snapshot,
      minVersionCode: required.minVersionCode,
      graceExpired: required.graceExpired,
    );
    _log.event('required_update', {
      'decision': decision.name,
      'play': snapshot == null ? 'unavailable' : 'answered',
      'offered': snapshot?.availableVersionCode,
      'min': required.minVersionCode,
    });
    if (decision == RequiredUpdateDecision.warnStranded) {
      _log.event('update_stranded', {'min': required.minVersionCode});
    }
    return decision;
  }

  /// One-shot deferral so the mandatory gate never restarts the app mid-visit.
  /// Returns true the first time it is asked away from a safe point.
  bool deferRequiredOnce() {
    if (_isSafePoint() || _requiredDeferred) return false;
    _requiredDeferred = true;
    _log.event('required_deferred');
    return true;
  }

  /// Whether the dismissible warning has not yet been shown this session.
  bool takeWarningSlot() {
    if (_warnedThisSession) return false;
    return _warnedThisSession = true;
  }

  /// Required path: finish a downloaded flexible update, else run immediate.
  Future<AppUpdateOutcome> startRequiredUpdate() async {
    final (:snapshot, :code) = await _check();
    if (snapshot == null) return AppUpdateUnavailable(code);
    if (snapshot.flexibleDownloaded) return _completeFlexible();
    if (snapshot.immediateInProgress) return _runImmediate();
    if (!snapshot.updateOffered || !snapshot.immediateAllowed) {
      return const AppUpdateUnavailable();
    }
    return _runImmediate();
  }

  /// Optional path: flexible when allowed, else immediate when allowed.
  Future<AppUpdateOutcome> startOptionalUpdate() async {
    final (:snapshot, :code) = await _check();
    if (snapshot == null) return AppUpdateUnavailable(code);
    if (snapshot.flexibleDownloaded) {
      _setRestartReady(true);
      return const AppUpdateDownloading();
    }
    if (!snapshot.updateOffered) return const AppUpdateUnavailable();
    _ensureListening();
    if (snapshot.flexibleAllowed) return _startFlexible();
    if (snapshot.immediateAllowed) return _runImmediate();
    return const AppUpdateUnavailable();
  }

  /// Restart into a downloaded update — only at a safe point.
  Future<bool> completeRestartIfSafe() async {
    if (!_restartReady || !_isSafePoint()) return false;
    final outcome = await _completeFlexible();
    return outcome is AppUpdateInstalled;
  }

  // ── internals ──────────────────────────────────────────────────────────────

  bool _throttled() {
    final last = _lastCheck;
    return last != null && _now().difference(last) < checkThrottle;
  }

  Future<PlayUpdateSnapshot?> _checkOrNull() async =>
      (await _check()).snapshot;

  /// Play's answer, or the error code explaining why there is none.
  Future<({PlayUpdateSnapshot? snapshot, String? code})> _check() async {
    try {
      return (snapshot: await _play.check(), code: null);
    } on PlayUpdateUnavailableException catch (e) {
      _log.event('check_unavailable', {'code': e.code});
      return (snapshot: null, code: e.code);
    }
  }

  void _ensureListening() {
    _sub ??= _play.installStatus.listen(
      _onStatus,
      onError: (Object e) => _log.event('listener_error', {'error': '$e'}),
    );
  }

  void _onStatus(InstallStatus status) {
    _log.event('install_status', {'status': status.name});
    switch (status) {
      case InstallStatus.downloaded:
        _setRestartReady(true);
      case InstallStatus.installed:
      case InstallStatus.failed:
      case InstallStatus.canceled:
        _setRestartReady(false);
      case InstallStatus.unknown:
      case InstallStatus.pending:
      case InstallStatus.downloading:
      case InstallStatus.installing:
        break;
    }
  }

  void _setRestartReady(bool value) {
    if (_restartReady == value) return;
    _restartReady = value;
    notifyListeners();
  }

  Future<AppUpdateOutcome> _runImmediate() async {
    await _flag.set(true);
    try {
      final result = await _play.performImmediate();
      return _mapResult(result, clearFlagOnDone: true);
    } on PlayUpdateUnavailableException catch (e) {
      await _flag.set(false);
      return AppUpdateUnavailable(e.code);
    }
  }

  Future<AppUpdateOutcome> _startFlexible() async {
    try {
      final result = await _play.startFlexible();
      final outcome = _mapResult(result);
      return outcome is AppUpdateInstalled ? const AppUpdateDownloading() : outcome;
    } on PlayUpdateUnavailableException catch (e) {
      return AppUpdateUnavailable(e.code);
    }
  }

  Future<AppUpdateOutcome> _completeFlexible() async {
    try {
      await _play.completeFlexible();
      return const AppUpdateInstalled();
    } on PlayUpdateUnavailableException catch (e) {
      return AppUpdateFailed(e.code);
    }
  }

  AppUpdateOutcome _mapResult(AppUpdateResult result,
      {bool clearFlagOnDone = false}) {
    if (clearFlagOnDone && result != AppUpdateResult.success) {
      unawaited(_flag.set(false));
    }
    _log.event('update_result', {'result': result.name});
    return switch (result) {
      AppUpdateResult.success => const AppUpdateInstalled(),
      AppUpdateResult.userDeniedUpdate => const AppUpdateCancelled(),
      AppUpdateResult.inAppUpdateFailed => const AppUpdateFailed(),
    };
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
