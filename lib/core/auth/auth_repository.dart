import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';

/// Hash password using HmacSHA512 keyed by [AppConfig.passwordHashKey],
/// matching the Spice Android EncryptionUtil.getSecurePassword() implementation.
/// Dev endpoint uses empty SALT (UHIS_DEV_SALT_KEY=).
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
        // Also refresh the auth token if available (mobile flow)
        final authToken = _api.exportAuthToken();
        if (authToken != null && authToken.isNotEmpty) {
          await _storage.write(key: _kBioAuthToken, value: authToken);
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
  static const _kBioAuthToken = 'bio_auth_token'; // Bearer token for mobile auth
  static const _kBioTenant = 'bio_tenant_id';
  static const _kBioUsername = 'bio_last_username';
  static const _kBioOfferedOnce = 'bio_offered_once';
  static const _kPinEnabled = 'pin_enabled';
  static const _kPinHash = 'pin_hash';
  static const _kPinSalt = 'pin_salt';
  static const _kPinAttempts = 'pin_failed_attempts';
  static const _kOnboardingComplete = 'onboarding_complete';
  static const _kFirstName = 'firstName';
  static const _kLastName = 'lastName';
  static const _kArea = 'operationalArea';
  static const _kWard = 'ward';
  static const _kUpazila = 'upazila';
  static const _kSkId = 'skId';
  static const _kNidOrPhone = 'nidOrPhone';
  static const _kHouseholdCountCache = 'householdCountCache';
  static const _kVillageIds = 'villageIds';
  static const _kSubVillageIds = 'subVillageIds';
  static const _kUserId = 'userId';
  static const _kDeviceId = 'deviceId';

  Future<String?> currentTenantId() async {
    final cached = _api.tenantId;
    if (cached != null && cached.isNotEmpty) return cached;
    final stored = await _storage.read(key: _kTenantId);
    if (stored != null) _api.setTenantId(stored);
    return stored;
  }

  Future<String?> lastUsername() => _storage.read(key: _kUsername);

  Future<String?> firstName() => _storage.read(key: _kFirstName);

  /// Returns the numeric user ID stored from the profile response.
  Future<int?> userId() async {
    final stored = await _storage.read(key: _kUserId);
    return stored != null ? int.tryParse(stored) : null;
  }

  /// Returns a stable device ID, generating one on first access.
  Future<String> deviceId() async {
    var stored = await _storage.read(key: _kDeviceId);
    if (stored == null || stored.isEmpty) {
      stored = const Uuid().v4();
      await _storage.write(key: _kDeviceId, value: stored);
    }
    return stored;
  }

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
    // Clear any stale tenant/auth state before fresh login
    _api.setTenantId(null);
    await _api.clearSession();
    
    final hashedPwd = hashPassword(password);
    // ignore: avoid_print
    print('[Auth] Login attempt: user=$username, hash=${hashedPwd.substring(0, 16)}...');
    
    // Backend expects multipart/form-data (matching Android's MultipartBody.FORM)
    final formData = FormData.fromMap({
      'username': username,
      'password': hashedPwd,
    });
    
    final resp = await _api.dio.post(
      Endpoints.login,
      data: formData,
    );
    // ignore: avoid_print
    print('[Auth] Login response: ${resp.statusCode}');
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
    // Store numeric user ID for sync requests
    await writeOrDelete(_kUserId, idVal);
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
    final villageIdList = <int>[];
    if (villages is List && villages.isNotEmpty) {
      final first = villages.first;
      if (first is Map) {
        final name = (first['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) ward = name;
      }
      // Extract all village IDs (union IDs) from the profile
      for (final v in villages) {
        if (v is Map) {
          final id = v['id'];
          if (id is int) villageIdList.add(id);
          if (id is num) villageIdList.add(id.toInt());
        }
      }
    }
    await writeOrDelete(_kWard, ward);
    // Store village IDs as comma-separated string
    if (villageIdList.isNotEmpty) {
      await _storage.write(key: _kVillageIds, value: villageIdList.join(','));
    } else {
      await _storage.delete(key: _kVillageIds);
    }
    final upazila = _deriveUpazila(area, entityMap);
    await writeOrDelete(_kUpazila, upazila);

    // Fetch and cache sub-village IDs for all villages
    // Extract user ID for fallback SS-based sub-village fetch
    final userId = entityMap['id'];
    final userIdInt = (userId is int) ? userId : (userId is num ? userId.toInt() : null);
    await _fetchAndCacheSubVillages(villageIdList, skId: userIdInt);
  }

  /// Fetches sub-villages for each village (union) ID and caches the sub-village IDs.
  /// If no village IDs provided, falls back to fetching via Shasthya Shebika endpoint.
  Future<void> _fetchAndCacheSubVillages(List<int> villageIds, {int? skId}) async {
    // Deduplicate village IDs
    final uniqueVillageIds = villageIds.toSet();
    final subVillageIdSet = <int>{};
    for (final villageId in uniqueVillageIds) {
      try {
        final resp = await _api.dio.get(Endpoints.subVillagesByVillage(villageId));
        if (resp.statusCode == 200) {
          final data = resp.data;
          // Response format: { "entity": [ { "id": 18, ... }, ... ] }
          final entity = (data is Map) ? data['entity'] : data;
          if (entity is List) {
            for (final sv in entity) {
              if (sv is Map) {
                final id = sv['id'];
                if (id is int) subVillageIdSet.add(id);
                if (id is num) subVillageIdSet.add(id.toInt());
              }
            }
          }
        }
      } catch (e) {
        // Log but continue - sub-village fetch is best-effort
        // ignore: avoid_print
        print('[AuthRepository] Failed to fetch sub-villages for village $villageId: $e');
      }
    }
    // If no sub-villages found via villages, try fetching from Shasthya Shebika endpoint
    if (subVillageIdSet.isEmpty && skId != null) {
      // ignore: avoid_print
      print('[AuthRepository] No villages in profile, fetching sub-villages via SS endpoint for SK $skId');
      try {
        final ssResp = await _api.dio.post(
          Endpoints.shasthyaShebikasBySkId,
          data: [skId], // API expects plain array of SK IDs
          options: Options(contentType: 'application/json'),
        );
        // ignore: avoid_print
        print('[AuthRepository] SS endpoint response: ${ssResp.statusCode}');
        if (ssResp.statusCode == 200) {
          final ssData = ssResp.data;
          // Response: { "success": true, "data": { "87": [ { "subVillages": [...] }, ... ] } }
          final dataMap = (ssData is Map) ? ssData['data'] : null;
          // ignore: avoid_print
          print('[AuthRepository] SS data keys: ${dataMap?.keys}');
          if (dataMap is Map) {
            for (final ssListEntry in dataMap.values) {
              if (ssListEntry is List) {
                for (final ss in ssListEntry) {
                  if (ss is Map) {
                    final svList = ss['subVillages'];
                    if (svList is List) {
                      for (final sv in svList) {
                        if (sv is Map) {
                          final svId = sv['id'];
                          if (svId is int) subVillageIdSet.add(svId);
                          if (svId is num) subVillageIdSet.add(svId.toInt());
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[AuthRepository] Failed to fetch sub-villages via SS endpoint: $e');
      }
    }

    final subVillageIds = subVillageIdSet.toList();
    // ignore: avoid_print
    print('[AuthRepository] Cached sub-village IDs: $subVillageIds');
    if (subVillageIds.isNotEmpty) {
      await _storage.write(key: _kSubVillageIds, value: subVillageIds.join(','));
    } else {
      await _storage.delete(key: _kSubVillageIds);
    }
  }

  /// Returns the cached sub-village IDs for the logged-in user.
  /// In dev mode, prefers the DEV_SUB_VILLAGE_IDS config if set.
  Future<List<int>> subVillageIds() async {
    // Dev mode: prefer config override
    final devIds = AppConfig.devSubVillageIdList;
    if (devIds.isNotEmpty) {
      // ignore: avoid_print
      print('[AuthRepository] Using dev sub-village IDs: $devIds');
      return devIds;
    }
    
    final stored = await _storage.read(key: _kSubVillageIds);
    if (stored == null || stored.isEmpty) return const [];
    return stored
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
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

  /// Clears the shared persisted re-entry session (cookies + token + tenant)
  /// used by BOTH biometric and PIN unlock, but KEEPS the enabled flags + PIN
  /// hash so they re-bind on the next password login (used for expiry +
  /// password fallback). Full teardown of preferences happens only in [logout].
  Future<void> _clearReentrySession() async {
    await _storage.delete(key: _kBioJSession);
    await _storage.delete(key: _kBioAuthCookie);
    await _storage.delete(key: _kBioAuthCookieExpiry);
    await _storage.delete(key: _kBioAuthToken);
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

  Future<bool> isOnboardingComplete() async =>
      (await _storage.read(key: _kOnboardingComplete)) == 'true';

  Future<void> markOnboardingComplete() async {
    await _storage.write(key: _kOnboardingComplete, value: 'true');
  }

  Future<bool> isBiometricEnabled() async {
    final v = await _storage.read(key: _kBioEnabled);
    return v == 'true';
  }

  Future<String?> biometricLastUsername() =>
      _storage.read(key: _kBioUsername);

  /// Persists the shared re-entry session (cookies/token + tenant + username)
  /// from the currently-active session. Shared by biometric and PIN enrolment
  /// so either method can later restore the same session.
  ///
  /// Mobile uses Bearer tokens; web uses cookies. We persist whichever is
  /// available.
  Future<void> _persistReentrySession() async {
    final cookies = await _api.exportAuthCookies();
    final authToken = _api.exportAuthToken();

    // Mobile uses Bearer token, web uses cookies
    final hasCookies =
        cookies.authCookie != null && cookies.jsession != null;
    final hasToken = authToken != null && authToken.isNotEmpty;

    if (!hasCookies && !hasToken) {
      throw AuthException('No active session to enrol');
    }

    final expiry = _api.authCookieExpiry ??
        DateTime.now().add(Duration(seconds: AppConfig.authCookieTtlSeconds));
    final tenant = _api.tenantId;
    final username = await lastUsername();

    // Persist cookies if available (web flow)
    if (hasCookies) {
      await _storage.write(key: _kBioJSession, value: cookies.jsession);
      await _storage.write(key: _kBioAuthCookie, value: cookies.authCookie);
    }

    // Persist auth token if available (mobile flow)
    if (hasToken) {
      await _storage.write(key: _kBioAuthToken, value: authToken);
    }

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
    final authToken = await _storage.read(key: _kBioAuthToken);
    final tenant = await _storage.read(key: _kBioTenant);

    // Mobile uses Bearer token, web uses cookies
    final hasCookies = js != null && ac != null;
    final hasToken = authToken != null && authToken.isNotEmpty;

    if (!hasCookies && !hasToken) {
      await _clearReentrySession();
      return false;
    }
    if (tenant == null) {
      await _clearReentrySession();
      return false;
    }

    // Restore cookies if available (web flow)
    if (hasCookies) {
      await _api.importAuthCookies(
        jsession: js,
        authCookie: ac,
        authCookieExpiry: expiry,
      );
    }

    // Restore auth token if available (mobile flow)
    if (hasToken) {
      _api.importAuthToken(authToken);
    }

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
