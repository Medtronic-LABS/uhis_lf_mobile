import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'biometric_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthState(this._repo, this._biometric);

  final AuthRepository _repo;
  final BiometricService _biometric;
  AuthStatus _status = AuthStatus.unknown;
  String? _username;
  String? _error;
  bool _busy = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _locked = false;

  AuthStatus get status => _status;
  String? get username => _username;
  String? get error => _error;
  bool get busy => _busy;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  bool get locked => _locked;

  Future<void> bootstrap() async {
    final t = await _repo.currentTenantId();
    _username = await _repo.lastUsername();
    _biometricEnabled = await _repo.isBiometricEnabled();
    _biometricAvailable = await _biometric.isAvailable();
    if (_biometricEnabled) {
      _status = AuthStatus.signedOut;
      _locked = true;
    } else if (t != null && t.isNotEmpty) {
      _status = AuthStatus.signedIn;
      _locked = false;
    } else {
      _status = AuthStatus.signedOut;
      _locked = false;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _repo.login(username, password);
      _username = username;
      _biometricEnabled = await _repo.isBiometricEnabled();
      _status = AuthStatus.signedIn;
      _locked = false;
      return true;
    } catch (e) {
      _error = e.toString();
      _status = AuthStatus.signedOut;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> biometricUnlock() async {
    if (!_biometricEnabled) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _biometric.authenticate(
        reason: 'Unlock UHIS Next',
      );
      if (!ok) return false;
      final restored = await _repo.restoreBiometricSession();
      if (!restored) {
        _error = 'Saved session expired — sign in again';
        _status = AuthStatus.signedOut;
        _locked = false;
        return false;
      }
      _username = await _repo.biometricLastUsername() ?? _username;
      _status = AuthStatus.signedIn;
      _locked = false;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> enrolBiometric() async {
    await _repo.enableBiometric();
    _biometricEnabled = true;
    notifyListeners();
  }

  Future<void> disableBiometric() async {
    await _repo.disableBiometric();
    _biometricEnabled = false;
    notifyListeners();
  }

  Future<void> markBiometricOffered() async {
    await _repo.markBiometricOffered();
  }

  Future<bool> wasBiometricOffered() => _repo.wasBiometricOffered();

  Future<UserProfileSummary> userProfileSummary() => _repo.userProfileSummary();

  /// Background-lock entry — must be synchronous to avoid task-switcher leak.
  void lock() {
    if (_status != AuthStatus.signedIn) return;
    if (!_biometricEnabled) return;
    if (_locked) return;
    _locked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> handleSessionExpired() async {
    if (_status == AuthStatus.signedOut) return;
    await _repo.handleSessionExpired();
    _status = AuthStatus.signedOut;
    _locked = false;
    _error = 'Session expired';
    notifyListeners();
  }

  Future<void> logout() async {
    await _repo.logout();
    _status = AuthStatus.signedOut;
    _locked = false;
    notifyListeners();
  }
}
