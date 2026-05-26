import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';

String hashPassword(String plaintext) {
  final hmac = Hmac(sha512, utf8.encode(AppConfig.passwordHashKey));
  return hmac.convert(utf8.encode(plaintext)).toString();
}

class AuthRepository {
  AuthRepository(this._api) : _storage = const FlutterSecureStorage() {
    _api.onAuthCookieRotated = (cookie, expiry) async {
      if (await isBiometricEnabled()) {
        await _storage.write(key: _kBioAuthCookie, value: cookie);
        await _storage.write(
          key: _kBioAuthCookieExpiry,
          value: expiry.toIso8601String(),
        );
        final cookies = await _api.exportAuthCookies();
        if (cookies.jsession != null) {
          await _storage.write(key: _kBioJSession, value: cookies.jsession);
        }
      }
    };
  }

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  static const _kTenantId = 'tenantId';
  static const _kUsername = 'lastUsername';
  static const _kBioEnabled = 'biometric_enabled';
  static const _kBioJSession = 'bio_jsessionid';
  static const _kBioAuthCookie = 'bio_authcookie';
  static const _kBioAuthCookieExpiry = 'bio_authcookie_expiry';
  static const _kBioTenant = 'bio_tenant_id';
  static const _kBioUsername = 'bio_last_username';
  static const _kBioOfferedOnce = 'bio_offered_once';

  Future<String?> currentTenantId() async {
    final cached = _api.tenantId;
    if (cached != null && cached.isNotEmpty) return cached;
    final stored = await _storage.read(key: _kTenantId);
    if (stored != null) _api.setTenantId(stored);
    return stored;
  }

  Future<String?> lastUsername() => _storage.read(key: _kUsername);

  Future<void> login(String username, String password) async {
    final form = FormData.fromMap({
      'username': username,
      'password': hashPassword(password),
    });
    final resp = await _api.dio.post(
      Endpoints.login,
      data: form,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
      ),
    );
    if (resp.statusCode != 200 && resp.statusCode != 302) {
      throw AuthException('Invalid credentials');
    }
    await _storage.write(key: _kUsername, value: username);
    await _loadProfile();
    if (await isBiometricEnabled()) {
      try {
        await enableBiometric();
      } catch (_) {}
    }
  }

  Future<void> _loadProfile() async {
    final resp = await _api.dio.post(Endpoints.profile);
    if (resp.statusCode != 200) {
      throw AuthException('Failed to load profile (${resp.statusCode})');
    }
    final data = resp.data;
    final entity = (data is Map) ? data['entity'] : null;
    final tenant = (entity is Map) ? entity['tenantId'] : null;
    if (tenant == null) {
      throw AuthException('Profile missing tenantId');
    }
    final tenantStr = tenant.toString();
    _api.setTenantId(tenantStr);
    await _storage.write(key: _kTenantId, value: tenantStr);
  }

  Future<void> logout() async {
    try {
      await _api.dio.get(Endpoints.logout);
    } catch (_) {}
    await _api.clearSession();
    await _storage.delete(key: _kTenantId);
    await _clearBiometricSession();
  }

  Future<void> _clearBiometricSession() async {
    await _storage.delete(key: _kBioJSession);
    await _storage.delete(key: _kBioAuthCookie);
    await _storage.delete(key: _kBioAuthCookieExpiry);
    await _storage.delete(key: _kBioTenant);
  }

  Future<void> handleSessionExpired() async {
    await _api.clearSession();
    await _storage.delete(key: _kTenantId);
    await _clearBiometricSession();
  }

  Future<bool> wasBiometricOffered() async =>
      (await _storage.read(key: _kBioOfferedOnce)) == 'true';

  Future<void> markBiometricOffered() async {
    await _storage.write(key: _kBioOfferedOnce, value: 'true');
  }

  Future<bool> isBiometricEnabled() async {
    final v = await _storage.read(key: _kBioEnabled);
    return v == 'true';
  }

  Future<String?> biometricLastUsername() =>
      _storage.read(key: _kBioUsername);

  Future<void> enableBiometric() async {
    final cookies = await _api.exportAuthCookies();
    if (cookies.authCookie == null || cookies.jsession == null) {
      throw AuthException('No active session to enrol');
    }
    final expiry = _api.authCookieExpiry ??
        DateTime.now()
            .add(Duration(seconds: AppConfig.authCookieTtlSeconds));
    final tenant = _api.tenantId;
    final username = await lastUsername();
    await _storage.write(key: _kBioJSession, value: cookies.jsession);
    await _storage.write(key: _kBioAuthCookie, value: cookies.authCookie);
    await _storage.write(
        key: _kBioAuthCookieExpiry, value: expiry.toIso8601String());
    if (tenant != null) {
      await _storage.write(key: _kBioTenant, value: tenant);
    }
    if (username != null) {
      await _storage.write(key: _kBioUsername, value: username);
    }
    await _storage.write(key: _kBioEnabled, value: 'true');
  }

  Future<void> disableBiometric() async {
    await _storage.delete(key: _kBioEnabled);
    await _storage.delete(key: _kBioJSession);
    await _storage.delete(key: _kBioAuthCookie);
    await _storage.delete(key: _kBioAuthCookieExpiry);
    await _storage.delete(key: _kBioTenant);
    await _storage.delete(key: _kBioUsername);
  }

  Future<bool> restoreBiometricSession() async {
    final enabled = await isBiometricEnabled();
    if (!enabled) return false;
    final expiryStr = await _storage.read(key: _kBioAuthCookieExpiry);
    if (expiryStr == null) {
      await _clearBiometricSession();
      return false;
    }
    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      await _clearBiometricSession();
      return false;
    }
    final js = await _storage.read(key: _kBioJSession);
    final ac = await _storage.read(key: _kBioAuthCookie);
    final tenant = await _storage.read(key: _kBioTenant);
    if (js == null || ac == null || tenant == null) {
      await _clearBiometricSession();
      return false;
    }
    await _api.importAuthCookies(
      jsession: js,
      authCookie: ac,
      authCookieExpiry: expiry,
    );
    _api.setTenantId(tenant);
    await _storage.write(key: _kTenantId, value: tenant);
    return true;
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
