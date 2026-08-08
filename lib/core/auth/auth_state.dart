import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../config/app_config.dart';
import '../constants/app_strings.dart';
import '../debug/console_log.dart';
import '../errors/domain_exceptions.dart';
import 'auth_repository.dart';
import 'biometric_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthState(this._repo, this._biometric, {Future<void> Function()? onWipeLocalData})
      : _onWipeLocalData = onWipeLocalData {
    // Server-side session invalidation (401/403 from any authenticated call).
    // Try to recover it silently from stored credentials before disturbing the
    // SK — see [_recoverSessionSilently].
    _repo.onUnauthorized = () {
      debugPrint('[AuthState] onUnauthorized fired (server 401/403) — attempting silent recovery');
      unawaited(_recoverSessionSilently());
    };
  }

  final AuthRepository _repo;
  final BiometricService _biometric;
  // Truncates the local SQLCipher DB — set from main.dart to
  // AppDatabase.wipeAllData(). Intentionally NOT called any more: sign-out is
  // soft (see [logout] Step 3 for the full rationale and the safety condition).
  // Kept wired so restoring the wipe is a one-line change rather than
  // re-threading a dependency through main.dart.
  // ignore: unused_field
  final Future<void> Function()? _onWipeLocalData;
  // Additional in-memory caches to clear on logout (e.g.
  // MissionDashboardRepository.clearCache) — registered post-construction via
  // [registerLogoutHook] since some repositories are wired up in main.dart
  // after AuthState already exists. Without this, a repository's cached
  // snapshot from the previous session would still be visible to the next
  // user who logs in on the same device, even though the DB itself is wiped.
  final List<void Function()> _logoutHooks = [];

  /// Registers a callback to run during [logout], after the local DB wipe.
  /// Use this for any in-memory cache that would otherwise outlive a signed-
  /// out session and leak into the next user's login.
  void registerLogoutHook(void Function() hook) {
    _logoutHooks.add(hook);
  }

  // Best-effort flushes to run BEFORE the local DB wipe — e.g. pushing any
  // still-`pending` assessment writes so they reach the backend before
  // their local row is truncated. Without this, a write made shortly
  // before logout (or while offline) can be silently lost forever: gone
  // locally, never received by the backend, so nothing can restore it on
  // the next login. Same registration pattern as [registerLogoutHook].
  final List<Future<void> Function()> _preWipeHooks = [];

  /// Registers a callback to run during [logout], before the local DB wipe.
  /// Use this to flush any pending offline-sync writes. Each hook is
  /// expected to bound its own duration (e.g. via `.timeout(...)`) — a slow
  /// or offline hook must not be able to hang logout.
  void registerPreWipeHook(Future<void> Function() hook) {
    _preWipeHooks.add(hook);
  }
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
      // Offline path: verify stored hash (Spice Android parity).
      // Allows CHWs to authenticate for days/weeks without connectivity.
      final offline = await isDeviceOffline();
      debugPrint('[AuthState] login: offline=$offline user=$username');
      if (offline) {
        final hashOk = await _repo.verifyOfflinePassword(username, password);
        debugPrint('[AuthState] login: offline password match=$hashOk');
        if (hashOk) {
          final graceOk = await _repo.restoreTokensIgnoringExpiry();
          _username = username;
          _sameUserRelogin = true;
          _biometricEnabled = await _repo.isBiometricEnabled();
          _pinEnabled = await _repo.isPinSet();
          _onboardingComplete = await _repo.isOnboardingComplete();
          _status = AuthStatus.signedIn;
          _locked = false;
          debugPrint('[AuthState] login: offline password verified${graceOk ? ', session restored' : ', no prior session'}');
          return true;
        }
        // Fall through to online login. The offline probe can false-positive
        // (e.g. google.com DNS blocked while spice backend is reachable), and
        // logout clears the offline password hash — so a hard fail here would
        // strand the user with no network attempt.
        debugPrint(
            '[AuthState] login: no offline credentials — trying online login');
      }
      // Online path: normal network login.
      // Must run BEFORE _repo.login(), which overwrites the cached username.
      _sameUserRelogin = await _repo.isReturningUser(username);
      debugPrint(
          '[AuthState] login: online path sameUserRelogin=$_sameUserRelogin');
      await _repo.login(username, password);
      _username = username;
      _biometricEnabled = await _repo.isBiometricEnabled();
      _pinEnabled = await _repo.isPinSet();
      _onboardingComplete = await _repo.isOnboardingComplete();
      _status = AuthStatus.signedIn;
      _locked = false;
      debugPrint('[AuthState] login: online success');
      return true;
    } catch (e) {
      debugPrint('[AuthState] login: failed — $e');
      _error = NetworkErrorMapper.friendly(e);
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
      debugPrint('[AuthState] biometricUnlock: restored=$restored');
      if (!restored) {
        final offline = await isDeviceOffline();
        debugPrint('[AuthState] biometricUnlock: restore failed, offline=$offline');
        if (offline) {
          // Offline grace: biometric identity verified, device in hand, but
          // no network to reach the server. Restore stored token as-is — the
          // server will reject with 401 on the next online call, which fires
          // handleSessionExpired() and forces a re-login at that point.
          final graceOk = await _repo.restoreTokensIgnoringExpiry();
          debugPrint('[AuthState] biometricUnlock: graceOk=$graceOk');
          if (graceOk) {
            _username = await _repo.biometricLastUsername() ?? _username;
            _onboardingComplete = await _repo.isOnboardingComplete();
            _status = AuthStatus.signedIn;
            _locked = false;
            debugPrint('[AuthState] biometricUnlock: offline grace — local expiry bypassed');
            return true;
          }
        }
        await _repo.clearExpiredReentrySession();
        return _failExpiredRestore();
      }
      _username = await _repo.biometricLastUsername() ?? _username;
      _onboardingComplete = await _repo.isOnboardingComplete();
      _status = AuthStatus.signedIn;
      _locked = false;
      return true;
    } catch (e) {
      _error = NetworkErrorMapper.friendly(e);
      return false;
    } finally {
      _busy = false;
      // Defer notification to avoid build scope conflicts when GoRouter
      // redirects during the current build phase.
      _scheduleNotify();
    }
  }

  /// Whether the device currently has no usable network interface.
  /// Used by unlock / logout flows that need an offline-grace path.
  Future<bool> isDeviceOffline() async {
    // Prefer connectivity_plus (same as SyncConnectivityService). A google.com
    // DNS probe false-positives offline in markets where Google is blocked or
    // filtered, which previously blocked online login entirely after logout
    // cleared the offline password hash.
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
      final hasInterface =
          results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) return true;
      return false;
    } catch (_) {
      // Fall back to a short reachability probe against our own API host.
      try {
        final host = Uri.parse(AppConfig.apiBaseUrl).host;
        if (host.isEmpty) return true;
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3));
        return result.isEmpty || result[0].rawAddress.isEmpty;
      } catch (_) {
        return true;
      }
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
      if (!restored) {
        if (await isDeviceOffline()) {
          final graceOk = await _repo.restoreTokensIgnoringExpiry();
          if (graceOk) {
            _username = await _repo.biometricLastUsername() ?? _username;
            _onboardingComplete = await _repo.isOnboardingComplete();
            _status = AuthStatus.signedIn;
            _locked = false;
            debugPrint('[AuthState] pinUnlock: offline grace — local expiry bypassed');
            return true;
          }
        }
        await _repo.clearExpiredReentrySession();
        return _failExpiredRestore();
      }
      _username = await _repo.biometricLastUsername() ?? _username;
      _onboardingComplete = await _repo.isOnboardingComplete();
      _status = AuthStatus.signedIn;
      _locked = false;
      return true;
    } catch (e) {
      _error = NetworkErrorMapper.friendly(e);
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

  /// Max consecutive silent re-login attempts before falling back to the
  /// password prompt. Stops a permanently-rejected credential from hammering
  /// the server once per request, forever.
  static const _maxSilentReloginAttempts = 3;

  /// In-flight silent re-login, so N concurrent 401s produce ONE login call.
  Future<void>? _silentRelogin;
  int _silentReloginFailures = 0;

  /// Recovers a server-expired session without disturbing the SK.
  ///
  /// The credential the login endpoint accepts is already on the device (see
  /// [AuthRepository.loginWithStoredCredentials]), so an expired session can be
  /// re-established in the background. Outcomes:
  ///
  /// - success        → token restored, the SK sees nothing
  /// - server refusal → real credential failure; fall through to the password
  ///                    prompt via [handleSessionExpired]
  /// - network error  → stay signed in and offline-capable; retry on the next
  ///                    authenticated request
  ///
  /// An explicit logout is never undone here — that is what the stored
  /// explicit-logout flag guards.
  Future<void> _recoverSessionSilently() {
    // Single-flight: a burst of parallel requests all 401 at once.
    return _silentRelogin ??= _runSilentRecovery().whenComplete(() {
      _silentRelogin = null;
    });
  }

  Future<void> _runSilentRecovery() async {
    if (_status == AuthStatus.signedOut) return;

    if (await _repo.wasExplicitLogout()) {
      debugPrint('[AuthState] silent recovery skipped — last sign-out was explicit');
      await handleSessionExpired();
      return;
    }

    if (_silentReloginFailures >= _maxSilentReloginAttempts) {
      debugPrint(
          '[AuthState] silent recovery exhausted ($_silentReloginFailures attempts) — prompting');
      await handleSessionExpired();
      return;
    }

    try {
      await _repo.loginWithStoredCredentials();
      _silentReloginFailures = 0;
      debugPrint('[AuthState] silent recovery succeeded — session restored');
    } on AuthException catch (e) {
      // Server refused the stored credential: password changed server-side or
      // the account was disabled. Only a real password entry can fix this.
      _silentReloginFailures++;
      debugPrint('[AuthState] silent recovery refused by server ($e) — prompting');
      await handleSessionExpired();
    } on DioException catch (e) {
      // Offline or transport failure — NOT a credential problem. Signing out
      // here would strand an SK mid-visit with no way back in until they have
      // signal, so stay signed in and retry on the next request.
      debugPrint('[AuthState] silent recovery deferred (network: ${e.type}) — staying signed in');
    } on SocketException catch (e) {
      debugPrint('[AuthState] silent recovery deferred (socket: $e) — staying signed in');
    }
  }

  Future<void> handleSessionExpired() async {
    if (_status == AuthStatus.signedOut) {
      debugPrint('[AuthState] handleSessionExpired() called but already signedOut — no-op');
      return;
    }
    debugPrint('[AuthState] handleSessionExpired() — signing out, username preserved for relogin lock');
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

  /// Soft sign-out: flush, end the server session, clear in-memory caches.
  ///
  /// The local database is deliberately **not** wiped and the username is
  /// deliberately **kept** — see the wipe block below and
  /// [AuthRepository.logout] for why, and for what has to stay true elsewhere
  /// in the app for that to remain safe.
  Future<void> logout() async {
    // Flush BEFORE ending the session. The push needs the Bearer token that
    // _repo.logout() is about to clear; run in the other order and every
    // pending assessment 401s and is marked `failed`, a state AutomaticSync
    // never retries.
    ConsoleLog.step(
        '🔐 [AuthState] logout() Step 1/4 — flushing ${_preWipeHooks.length} pending sync(s)...');
    for (final hook in _preWipeHooks) {
      try {
        await hook();
      } catch (e) {
        ConsoleLog.warn('[AuthState] pre-logout flush hook failed: $e');
        // Non-fatal — sign-out must complete regardless of whether a flush
        // succeeded. Anything unflushed stays on disk (see Step 3) and will
        // push on the next login.
      }
    }
    ConsoleLog.step('🔐 [AuthState] logout() Step 2/4 — ending server session...');
    await _repo.logout();
    // Step 3 — local data is intentionally retained.
    //
    // Sign-out no longer truncates the database. Anything not flushed above
    // (offline, slow network) survives and syncs after the next login instead
    // of being destroyed. Clearing local data is Android Settings → Clear Data.
    //
    // SAFETY: this is only sound while a device stays bound to one SK. That
    // binding is the locked username field in LoginScreen
    // (`enabled: cachedUsername == null`), fed by the username
    // AuthRepository.logout() now preserves. Do NOT add a "switch user" or
    // "change username" affordance, and do not re-enable that field — a second
    // SK signing in here would inherit the first SK's households, patients and
    // clinical records. _onWipeLocalData stays wired so restoring the wipe is a
    // one-line change if that binding is ever broken.
    ConsoleLog.step(
        '🔐 [AuthState] logout() Step 3/4 — retaining local database (soft logout).');
    ConsoleLog.step(
        '🔐 [AuthState] logout() Step 4/4 — clearing ${_logoutHooks.length} in-memory cache(s)...');
    for (final hook in _logoutHooks) {
      try {
        hook();
      } catch (e) {
        ConsoleLog.warn('[AuthState] logout cache-clear hook failed: $e');
        // Non-fatal — sign-out must complete regardless.
      }
    }
    _status = AuthStatus.signedOut;
    _locked = false;
    _biometricEnabled = false;
    _pinEnabled = false;
    // _username is deliberately NOT cleared — LoginScreen reads this field to
    // prefill and lock the username, which is what keeps the device bound to
    // this SK across a soft logout.
    ConsoleLog.success('✅ [AuthState] logout() — signed out, local data retained.');
    // Defer to avoid build scope conflicts
    _scheduleNotify();
  }
}
