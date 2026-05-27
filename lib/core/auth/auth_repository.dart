import 'dart:convert';
import 'dart:math';

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

/// Salted HMAC-SHA512 of the fallback PIN. The PIN is never stored in
/// plaintext — only this hash + its random per-device [salt] are persisted.
String hashPin(String pin, String salt) {
  final hmac = Hmac(sha512, utf8.encode('${AppConfig.passwordHashKey}$salt'));
  return hmac.convert(utf8.encode(pin)).toString();
}

String _newPinSalt() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return base64Url.encode(bytes);
}

class AuthRepository {
  AuthRepository(this._api) : _storage = const FlutterSecureStorage() {
    _api.onAuthCookieRotated = (cookie, expiry) async {
      if (await isReentryEnabled()) {
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
  static const _kPinEnabled = 'pin_enabled';
  static const _kPinHash = 'pin_hash';
  static const _kPinSalt = 'pin_salt';
  static const _kPinAttempts = 'pin_failed_attempts';
  static const _kFirstName = 'firstName';
  static const _kLastName = 'lastName';
  static const _kArea = 'operationalArea';
  static const _kWard = 'ward';
  static const _kUpazila = 'upazila';
  static const _kSkId = 'skId';
  static const _kNidOrPhone = 'nidOrPhone';
  static const _kHouseholdCountCache = 'householdCountCache';

  Future<String?> currentTenantId() async {
    final cached = _api.tenantId;
    if (cached != null && cached.isNotEmpty) return cached;
    final stored = await _storage.read(key: _kTenantId);
    if (stored != null) _api.setTenantId(stored);
    return stored;
  }

  Future<String?> lastUsername() => _storage.read(key: _kUsername);

  Future<String?> firstName() => _storage.read(key: _kFirstName);

  Future<UserProfileSummary> userProfileSummary() async {
    return UserProfileSummary(
      firstName: await _storage.read(key: _kFirstName),
      lastName: await _storage.read(key: _kLastName),
      skId: await _storage.read(key: _kSkId),
      nidOrPhone: await _storage.read(key: _kNidOrPhone),
      ward: await _storage.read(key: _kWard),
      upazila: await _storage.read(key: _kUpazila),
      area: await _storage.read(key: _kArea),
      householdCount: int.tryParse(
          await _storage.read(key: _kHouseholdCountCache) ?? ''),
    );
  }

  Future<void> cacheHouseholdCount(int count) =>
      _storage.write(key: _kHouseholdCountCache, value: '$count');

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
    if (await isReentryEnabled()) {
      // Best-effort: refresh the persisted re-entry session (biometric or PIN)
      // after a fresh login. A failure here must not block sign-in.
      try {
        await _persistReentrySession();
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

    final entityMap = entity as Map;
    Future<void> writeOrDelete(String key, String? v) async {
      if (v != null && v.isNotEmpty) {
        await _storage.write(key: key, value: v);
      } else {
        await _storage.delete(key: key);
      }
    }

    final firstName = (entityMap['firstName'] as String?)?.trim();
    await writeOrDelete(_kFirstName, firstName);
    final lastName = (entityMap['lastName'] as String?)?.trim();
    await writeOrDelete(_kLastName, lastName);

    final idVal = entityMap['id']?.toString();
    final fhirId = (entityMap['fhirId'] as String?)?.trim();
    final regionCode =
        (entityMap['country'] is Map ? entityMap['country']['regionCode'] : null)
                ?.toString() ??
            'BD';
    String? skId;
    if (idVal != null && idVal.isNotEmpty) {
      final year = DateTime.now().year;
      final padded = idVal.padLeft(3, '0');
      skId = 'SK-$regionCode-$year-$padded';
    } else if (fhirId != null && fhirId.isNotEmpty) {
      skId = 'SK-$regionCode-$fhirId';
    }
    await writeOrDelete(_kSkId, skId);

    final phone = (entityMap['phoneNumber'] as String?)?.trim();
    final nidExtracted = _extractNid(entityMap);
    await writeOrDelete(_kNidOrPhone, nidExtracted ?? phone);

    String? area;
    final orgs = entityMap['organizations'];
    if (orgs is List && orgs.isNotEmpty) {
      final first = orgs.first;
      if (first is Map) {
        final name = (first['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) area = name;
      }
    }
    await writeOrDelete(_kArea, area);

    String? ward;
    final villages = entityMap['villages'];
    if (villages is List && villages.isNotEmpty) {
      final first = villages.first;
      if (first is Map) {
        final name = (first['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) ward = name;
      }
    }
    await writeOrDelete(_kWard, ward);
    final upazila = _deriveUpazila(area, entityMap);
    await writeOrDelete(_kUpazila, upazila);
  }

  static String? _extractNid(Map entity) {
    for (final k in const ['nid', 'nationalId', 'idCode', 'identifier']) {
      final v = entity[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final ids = entity['identifiers'];
    if (ids is List) {
      for (final entry in ids) {
        if (entry is Map) {
          final v = entry['value'];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }
    }
    return null;
  }

  static String? _deriveUpazila(String? area, Map entity) {
    if (area != null && area.isNotEmpty) {
      const tail = ['Community Clinic', 'Health Facility', 'Clinic', 'Centre', 'Center'];
      var t = area;
      for (final suffix in tail) {
        if (t.endsWith(suffix)) {
          t = t.substring(0, t.length - suffix.length).trim();
          break;
        }
      }
      if (t.isNotEmpty && t != area) return t;
    }
    final country = entity['country'];
    if (country is Map) {
      final display = country['displayValues'];
      if (display is Map) {
        final chief = display['chiefdom'];
        if (chief is Map) {
          final label = chief['s'];
          if (label is String && label.isNotEmpty) return label;
        }
      }
    }
    return null;
  }

  Future<void> logout() async {
    // Best-effort server-side logout; local re-entry is fully cleared so a
    // logged-out device has no silent re-entry (biometric or PIN).
    try {
      await _api.dio.get(Endpoints.logout);
    } catch (_) {}
    await _api.clearSession();
    await _storage.delete(key: _kTenantId);
    await _clearReentrySession();
    await _storage.delete(key: _kBioEnabled);
    await _storage.delete(key: _kBioUsername);
    await clearPin();
  }

  /// Clears the shared persisted re-entry session (cookies + tenant) used by
  /// BOTH biometric and PIN unlock, but KEEPS the enabled flags + PIN hash so
  /// they re-bind on the next password login (used for expiry + password
  /// fallback). Full teardown of preferences happens only in [logout].
  Future<void> _clearReentrySession() async {
    await _storage.delete(key: _kBioJSession);
    await _storage.delete(key: _kBioAuthCookie);
    await _storage.delete(key: _kBioAuthCookieExpiry);
    await _storage.delete(key: _kBioTenant);
  }

  Future<void> handleSessionExpired() async {
    await _api.clearSession();
    await _storage.delete(key: _kTenantId);
    await _clearReentrySession();
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

  /// Persists the shared re-entry session (cookies + tenant + username) from
  /// the currently-active session. Shared by biometric and PIN enrolment so
  /// either method can later restore the same session.
  Future<void> _persistReentrySession() async {
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
  }

  Future<void> enableBiometric() async {
    await _persistReentrySession();
    await _storage.write(key: _kBioEnabled, value: 'true');
  }

  /// Disables biometric. The shared re-entry session is cleared only if a PIN
  /// is not still relying on it.
  Future<void> disableBiometric() async {
    await _storage.delete(key: _kBioEnabled);
    if (!await isPinSet()) {
      await _clearReentrySession();
      await _storage.delete(key: _kBioUsername);
    }
  }

  // ── Fallback PIN ──────────────────────────────────────────────────────────

  Future<bool> isReentryEnabled() async =>
      (await isBiometricEnabled()) || (await isPinSet());

  Future<bool> isPinSet() async =>
      (await _storage.read(key: _kPinEnabled)) == 'true';

  /// Stores a salted hash of [pin] and persists the shared re-entry session so
  /// the PIN can later restore it (mirrors [enableBiometric]).
  Future<void> setPin(String pin) async {
    final salt = _newPinSalt();
    await _storage.write(key: _kPinSalt, value: salt);
    await _storage.write(key: _kPinHash, value: hashPin(pin, salt));
    await _storage.write(key: _kPinAttempts, value: '0');
    await _storage.write(key: _kPinEnabled, value: 'true');
    await _persistReentrySession();
  }

  /// Verifies [pin] against the stored salted hash. On success resets the
  /// failed-attempt counter; on failure increments it.
  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _kPinSalt);
    final stored = await _storage.read(key: _kPinHash);
    if (salt == null || stored == null) return false;
    final ok = hashPin(pin, salt) == stored;
    if (ok) {
      await _storage.write(key: _kPinAttempts, value: '0');
    } else {
      final n = await pinFailedAttempts();
      await _storage.write(key: _kPinAttempts, value: '${n + 1}');
    }
    return ok;
  }

  Future<int> pinFailedAttempts() async =>
      int.tryParse(await _storage.read(key: _kPinAttempts) ?? '0') ?? 0;

  Future<void> clearPin() async {
    await _storage.delete(key: _kPinEnabled);
    await _storage.delete(key: _kPinHash);
    await _storage.delete(key: _kPinSalt);
    await _storage.delete(key: _kPinAttempts);
  }

  /// Disables the PIN. The shared re-entry session is cleared only if biometric
  /// is not still relying on it.
  Future<void> disablePinReentry() async {
    await clearPin();
    if (!await isBiometricEnabled()) {
      await _clearReentrySession();
      await _storage.delete(key: _kBioUsername);
    }
  }

  Future<bool> restorePersistedSession() async {
    final enabled = await isReentryEnabled();
    if (!enabled) return false;
    final expiryStr = await _storage.read(key: _kBioAuthCookieExpiry);
    if (expiryStr == null) {
      await _clearReentrySession();
      return false;
    }
    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      await _clearReentrySession();
      return false;
    }
    final js = await _storage.read(key: _kBioJSession);
    final ac = await _storage.read(key: _kBioAuthCookie);
    final tenant = await _storage.read(key: _kBioTenant);
    if (js == null || ac == null || tenant == null) {
      await _clearReentrySession();
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

class UserProfileSummary {
  const UserProfileSummary({
    this.firstName,
    this.lastName,
    this.skId,
    this.nidOrPhone,
    this.ward,
    this.upazila,
    this.area,
    this.householdCount,
  });

  final String? firstName;
  final String? lastName;
  final String? skId;
  final String? nidOrPhone;
  final String? ward;
  final String? upazila;
  final String? area;
  final int? householdCount;

  bool get hasAnyDetail =>
      [skId, nidOrPhone, ward, upazila, area].any((s) => s != null && s.isNotEmpty);
}
