import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../config/app_config.dart';
import '../constants/app_strings.dart';
import 'auth_repository.dart';
import 'biometric_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthState(this._repo, this._biometric, {Future<void> Function()? onWipeLocalData})
      : _onWipeLocalData = onWipeLocalData;

  final AuthRepository _repo;
  final BiometricService _biometric;
  // Truncates the local SQLCipher DB on logout — set from main.dart to
  // AppDatabase.wipeAllData(). Optional (and non-fatal if it throws) so
  // AuthState keeps no direct data-layer dependency.
  final Future<void> Function()? _onWipeLocalData;
  AuthStatus _status = AuthStatus.unknown;
  String? _username;
  String? _error;
  bool _busy = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _pinEnabled = false;
  bool _locked = false;
  bool _onboardingComplete = false;
  bool _notifyScheduled = false;
  bool _splashReady = false;
  bool _sameUserRelogin = false;

  AuthStatus get status => _status;
  bool get splashReady => _splashReady;

  void setSplashReady() {
    _splashReady = true;
    _scheduleNotify();
  }

  /// Schedule notifyListeners for the next frame to avoid build scope conflicts
  /// when GoRouter's refreshListenable triggers during an existing build.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
  String? get username => _username;
  String? get error => _error;
  bool get busy => _busy;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  bool get pinEnabled => _pinEnabled;
  bool get onboardingComplete => _onboardingComplete;

  /// True when the just-completed [login] was the same SK re-authenticating
  /// (e.g. after a forced session-expiry sign-out) rather than a first-time
  /// setup or a different SK signing into a shared device. Read by the sync
  /// screen to decide whether the post-login resync may skip the wipe.
  bool get sameUserRelogin => _sameUserRelogin;

  /// Any local re-entry method enrolled (biometric OR PIN). Drives lock /
  /// barrier / router gating that must not be biometric-specific.
  bool get reentryEnabled => _biometricEnabled || _pinEnabled;
  bool get locked => _locked;

  Future<void> bootstrap() async {
    _username = await _repo.lastUsername();
    _biometricEnabled = await _repo.isBiometricEnabled();
    _pinEnabled = await _repo.isPinSet();
    _biometricAvailable = await _biometric.isAvailable();
    _onboardingComplete = await _repo.isOnboardingComplete();
    if (reentryEnabled) {
      // Biometric or PIN is set — session cookies are securely persisted.
      // User must unlock via /lock before accessing the app.
      _status = AuthStatus.signedOut;
      _locked = true;
    } else {
      // No reentry method set. Session cookies are NOT persisted across app
      // restarts, so the user must re-login even if they were logged in before.
      // A cached tenantId just remembers their last tenant, not a valid session.
      _status = AuthStatus.signedOut;
      _locked = false;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _busy = true;
    _error = null;
    _scheduleNotify();
    try {
      // Must run BEFORE _repo.login(), which overwrites the cached username.
      _sameUserRelogin = await _repo.isReturningUser(username);
      await _repo.login(username, password);
      _username = username;
      _biometricEnabled = await _repo.isBiometricEnabled();
      _pinEnabled = await _repo.isPinSet();
      _onboardingComplete = await _repo.isOnboardingComplete();
      _status = AuthStatus.signedIn;
      _locked = false;
      return true;
    } catch (e) {
      _error = e.toString();
      _status = AuthStatus.signedOut;
      return false;
    } finally {
      _busy = false;
      // Defer notification to avoid build scope conflicts when GoRouter
      // redirects during the current build phase.
      _scheduleNotify();
    }
  }

  Future<bool> biometricUnlock() async {
    if (!_biometricEnabled) return false;
    _busy = true;
    _error = null;
    _scheduleNotify();
    try {
      final ok = await _biometric.authenticate(
        reason: AppConfig.biometricReason,
      );
      if (!ok) return false;
      final restored = await _repo.restorePersistedSession();
      if (!restored) return _failExpiredRestore();
      _username = await _repo.biometricLastUsername() ?? _username;
      _onboardingComplete = await _repo.isOnboardingComplete();
      _status = AuthStatus.signedIn;
      _locked = false;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _busy = false;
      // Defer notification to avoid build scope conflicts when GoRouter
      // redirects during the current build phase.
      _scheduleNotify();
    }
  }

  /// Shared failure path for [biometricUnlock]/[pinUnlock] when the
  /// persisted reentry session has genuinely expired. Clears
  /// `biometricEnabled`/`pinEnabled` (matching [handleSessionExpired]) so
  /// `reentryEnabled` becomes false and the router's `redirect` — which
  /// re-evaluates on every `notifyListeners()` via `GoRouter(refreshListenable:
  /// auth)` — sends the user to `/login` instead of leaving them stuck on a
  /// "verification failed" retry loop.
  bool _failExpiredRestore() {
    _error = AuthStrings.savedSessionExpired;
    _status = AuthStatus.signedOut;
    _locked = false;
    _biometricEnabled = false;
    _pinEnabled = false;
    return false;
  }

  Future<void> enrolBiometric() async {
    await _repo.enableBiometric();
    _biometricEnabled = true;
    // Defer to avoid build scope conflicts when GoRouter redirects
    _scheduleNotify();
  }

  Future<void> disableBiometric() async {
    await _repo.disableBiometric();
    _biometricEnabled = false;
    // Defer to avoid build scope conflicts when GoRouter redirects
    _scheduleNotify();
  }

  // ── Fallback PIN ──────────────────────────────────────────────────────────

  /// Enrol the fallback PIN (also persists the shared re-entry session).
  Future<void> enrolPin(String pin) async {
    await _repo.setPin(pin);
    _pinEnabled = true;
    // Defer to avoid build scope conflicts when GoRouter redirects
    _scheduleNotify();
  }

  Future<void> disablePin() async {
    await _repo.disablePinReentry();
    _pinEnabled = false;
    // Defer to avoid build scope conflicts when GoRouter redirects
    _scheduleNotify();
  }

  Future<int> pinAttemptsRemaining() async {
    final left = AppConfig.pinMaxAttempts - await _repo.pinFailedAttempts();
    return left < 0 ? 0 : left;
  }

  Future<bool> isPinLockedOut() async => (await pinAttemptsRemaining()) <= 0;

  /// Unlock with the fallback PIN: verify it, then restore the shared re-entry
  /// session (the same one biometric uses). Returns true on success.
  Future<bool> pinUnlock(String pin) async {
    if (!_pinEnabled) return false;
    _busy = true;
    _error = null;
    _scheduleNotify();
    try {
      final ok = await _repo.verifyPin(pin);
      if (!ok) {
        final left = await pinAttemptsRemaining();
        _error = left <= 0
            ? PinStrings.tooManyAttempts
            : '${PinStrings.wrong} · ${PinStrings.attemptsRemaining(left)}';
        return false;
      }
      final restored = await _repo.restorePersistedSession();
      if (!restored) return _failExpiredRestore();
      _username = await _repo.biometricLastUsername() ?? _username;
      _onboardingComplete = await _repo.isOnboardingComplete();
      _status = AuthStatus.signedIn;
      _locked = false;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _busy = false;
      // Defer notification to avoid build scope conflicts when GoRouter
      // redirects during the current build phase.
      _scheduleNotify();
    }
  }

  Future<void> markBiometricOffered() async {
    await _repo.markBiometricOffered();
  }

  Future<bool> wasBiometricOffered() => _repo.wasBiometricOffered();

  Future<bool> isOnboardingComplete() => _repo.isOnboardingComplete();

  Future<void> markOnboardingComplete() async {
    await _repo.markOnboardingComplete();
    _onboardingComplete = true;
    // Defer notification to avoid build scope conflicts when GoRouter
    // redirects during the current build phase.
    _scheduleNotify();
  }

  Future<UserProfileSummary> userProfileSummary() => _repo.userProfileSummary();

  /// Background-lock entry — must be synchronous to avoid task-switcher leak.
  void lock() {
    if (_status != AuthStatus.signedIn) return;
    if (!reentryEnabled) return;
    if (_locked) return;
    _locked = true;
    // Defer to avoid build scope conflicts
    _scheduleNotify();
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    // Defer to avoid build scope conflicts
    _scheduleNotify();
  }

  /// User chose "Use password" from the lock barrier or `/lock` screen.
  /// Drops the active session locally (server cookies considered abandoned),
  /// clears the lock flag, and forces signedOut so the user can land on
  /// `/login?from=lock`. Biometric preference is preserved — successful
  /// password login will silently re-enrol the new session.
  Future<void> requestPasswordFallback() async {
    await _repo.handleSessionExpired();
    _status = AuthStatus.signedOut;
    _locked = false;
    // Defer to avoid build scope conflicts
    _scheduleNotify();
  }

  Future<void> handleSessionExpired() async {
    if (_status == AuthStatus.signedOut) return;
    await _repo.handleSessionExpired();
    _status = AuthStatus.signedOut;
    _locked = false;
    _biometricEnabled = false;
    _pinEnabled = false;
    _error = AuthStrings.sessionExpired;
    // Defer to avoid build scope conflicts
    _scheduleNotify();
  }

  void clearError() {
    _error = null;
  }

  Future<void> logout() async {
    await _repo.logout();
    if (_onWipeLocalData != null) {
      try {
        await _onWipeLocalData();
      } catch (e) {
        debugPrint('[AuthState] local data wipe failed during logout: $e');
        // Non-fatal — sign-out must complete regardless; next login re-wipes.
      }
    }
    _status = AuthStatus.signedOut;
    _locked = false;
    _biometricEnabled = false;
    _pinEnabled = false;
    // Defer to avoid build scope conflicts
    _scheduleNotify();
  }
}
