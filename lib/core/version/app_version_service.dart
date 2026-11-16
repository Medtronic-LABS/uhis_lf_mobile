import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';
import '../debug/console_log.dart';
import 'app_version_info.dart';

/// Outcome of a server-side app-version check. Sealed so callers must handle
/// every case (see `AuthRepository.login`).
sealed class AppVersionCheckResult {
  const AppVersionCheckResult();
}

/// The installed app satisfies the server's minimum and latest version.
class AppVersionUpToDate extends AppVersionCheckResult {
  const AppVersionUpToDate();
}

/// A newer version exists but the current one is still allowed (optional update).
class AppVersionUpdateAvailable extends AppVersionCheckResult {
  const AppVersionUpdateAvailable([this.latestVersionLabel = '']);
  final String latestVersionLabel;
}

/// The installed version is below the server's enforced minimum — the app is
/// blocked until the user updates. [minVersionLabel] is shown to the user.
class AppVersionUpdateRequired extends AppVersionCheckResult {
  const AppVersionUpdateRequired(this.minVersionLabel);
  final String minVersionLabel;
}

/// The version policy could not be fetched and none was cached.
class AppVersionCheckFailed extends AppVersionCheckResult {
  const AppVersionCheckFailed();
}

/// Version policy served by leapfrog-ai-service `POST /mobile/app-version`
/// (`app/api/mobile.py`). The server only reports min/latest build codes; the
/// comparison against the installed build happens here, in [evaluate].
@immutable
class AppVersionPolicy {
  const AppVersionPolicy({
    required this.minAppVersionCode,
    required this.minAppVersionLabel,
    required this.latestAppVersionCode,
    required this.latestAppVersionLabel,
    this.versionCheckExempt = false,
  });

  final int minAppVersionCode;
  final String minAppVersionLabel;
  final int latestAppVersionCode;
  final String latestAppVersionLabel;

  /// Server-side allowlist (`VERSION_CHECK_EXEMPT_USERS`) — e.g. QA accounts
  /// that must keep running an older build.
  final bool versionCheckExempt;

  /// Parses the endpoint body (or a cached copy). Returns null when the
  /// minimum code is missing — a policy we can't read must never lock anyone
  /// out.
  static AppVersionPolicy? fromJson(Object? json) {
    if (json is! Map) return null;
    final minCode = _asInt(json['minAppVersionCode']);
    if (minCode == null) return null;
    return AppVersionPolicy(
      minAppVersionCode: minCode,
      minAppVersionLabel: json['minAppVersionLabel']?.toString() ?? '',
      latestAppVersionCode: _asInt(json['latestAppVersionCode']) ?? minCode,
      latestAppVersionLabel: json['latestAppVersionLabel']?.toString() ?? '',
      versionCheckExempt: json['versionCheckExempt'] == true,
    );
  }

  Map<String, Object?> toJson() => {
        'minAppVersionCode': minAppVersionCode,
        'minAppVersionLabel': minAppVersionLabel,
        'latestAppVersionCode': latestAppVersionCode,
        'latestAppVersionLabel': latestAppVersionLabel,
        'versionCheckExempt': versionCheckExempt,
      };

  /// Decision for an installed build. An unknown build code (`<= 0`, i.e.
  /// package info failed to load) is treated as up to date rather than
  /// blocking the app on our own read failure.
  AppVersionCheckResult evaluate(int installedVersionCode) {
    if (versionCheckExempt || installedVersionCode <= 0) {
      return const AppVersionUpToDate();
    }
    if (installedVersionCode < minAppVersionCode) {
      return AppVersionUpdateRequired(minAppVersionLabel);
    }
    if (installedVersionCode < latestAppVersionCode) {
      return AppVersionUpdateAvailable(latestAppVersionLabel);
    }
    return const AppVersionUpToDate();
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}

/// Persists the last policy the server returned so the force-update gate
/// still holds on PIN/biometric unlock while offline.
abstract interface class AppVersionPolicyStore {
  Future<AppVersionPolicy?> read();
  Future<void> write(AppVersionPolicy policy);
}

class SecureAppVersionPolicyStore implements AppVersionPolicyStore {
  const SecureAppVersionPolicyStore([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);

  static const String _key = 'app_version_policy_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<AppVersionPolicy?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      return AppVersionPolicy.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('[AppVersion] cached policy unreadable: $e');
      return null;
    }
  }

  @override
  Future<void> write(AppVersionPolicy policy) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(policy.toJson()));
    } catch (e) {
      debugPrint('[AppVersion] could not cache policy: $e');
    }
  }
}

/// Checks the running app version against the backend's minimum/latest.
///
/// Flow (LEAP-144):
/// - [check] fetches the policy, caches it, and evaluates it. If the fetch
///   fails it falls back to the cached policy, so a device that has ever seen
///   a minimum version keeps enforcing it offline.
/// - [cachedResult] evaluates the cached policy only — used on unlock so the
///   gate never waits on the network.
/// - With neither a fresh nor a cached policy the result is
///   [AppVersionCheckFailed]; callers let the user through (fail-open) so an
///   unreachable AI service can't lock health workers out of the app.
class AppVersionService {
  AppVersionService(
    this._api, {
    AppVersionPolicyStore store = const SecureAppVersionPolicyStore(),
    Future<AppVersionPolicy?> Function()? fetchPolicy,
    int Function()? installedVersionCode,
    Duration timeout = const Duration(seconds: 10),
  })  : _store = store,
        _fetchOverride = fetchPolicy,
        _installedVersionCode =
            installedVersionCode ?? (() => AppVersionInfo.current.versionCode),
        _timeout = timeout;

  final ApiClient _api;
  final AppVersionPolicyStore _store;
  final Future<AppVersionPolicy?> Function()? _fetchOverride;
  final int Function() _installedVersionCode;
  final Duration _timeout;

  static bool _optionalUpdatePending = false;
  static bool _optionalPromptShown = false;
  static String _optionalUpdateLabel = '';

  /// Whether a one-time optional-update prompt should be shown this session.
  static bool get needsOptionalPrompt =>
      _optionalUpdatePending && !_optionalPromptShown;

  /// Latest version label for the optional prompt.
  static String get optionalUpdateLabel => _optionalUpdateLabel;

  /// Records that the optional prompt was shown, so it appears once per session.
  static void markOptionalPromptShown() => _optionalPromptShown = true;

  /// Clears per-session prompt state on logout. The cached policy is kept on
  /// purpose — the force-update gate must survive a logout.
  static void invalidateSessionCache() {
    _optionalUpdatePending = false;
    _optionalPromptShown = false;
    _optionalUpdateLabel = '';
  }

  /// Full URL of the policy endpoint: direct to the AI service when
  /// `AI_SERVICE_URL` is set, otherwise through the nginx gateway.
  static String checkUrl() {
    final direct = AppConfig.aiServiceBaseUrl;
    if (direct.isNotEmpty) {
      return _join(direct, Endpoints.mobileAppVersionDirect);
    }
    return _join(AppConfig.apiBaseUrl, Endpoints.mobileAppVersionGateway);
  }

  static String _join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b$path';
  }

  /// Fetches, caches and evaluates the policy; falls back to the cache.
  Future<AppVersionCheckResult> check() async {
    final fresh = await _fetchSafely();
    if (fresh != null) await _store.write(fresh);
    final policy = fresh ?? await _store.read();
    if (policy == null) {
      debugPrint('[AppVersion] no policy available (fetch failed, none cached)');
      return const AppVersionCheckFailed();
    }
    return _record(policy.evaluate(_installedVersionCode()));
  }

  /// Evaluates the last cached policy without touching the network.
  Future<AppVersionCheckResult> cachedResult() async {
    final policy = await _store.read();
    if (policy == null) return const AppVersionUpToDate();
    return policy.evaluate(_installedVersionCode());
  }

  AppVersionCheckResult _record(AppVersionCheckResult result) {
    if (result is AppVersionUpdateAvailable) {
      _optionalUpdatePending = true;
      _optionalUpdateLabel = result.latestVersionLabel;
    } else {
      _optionalUpdatePending = false;
    }
    debugPrint('[AppVersion] installed=${_installedVersionCode()} → '
        '${result.runtimeType}');
    return result;
  }

  Future<AppVersionPolicy?> _fetchSafely() async {
    try {
      final fetch = _fetchOverride ?? _fetchFromServer;
      return await fetch().timeout(_timeout);
    } catch (e) {
      ConsoleLog.warn('[AppVersion] policy fetch failed: $e');
      return null;
    }
  }

  Future<AppVersionPolicy?> _fetchFromServer() async {
    final version = AppVersionInfo.current;
    final headers = <String, Object>{
      'App-Version': version.versionName,
      'App-Version-Code': version.versionCode.toString(),
    };
    final Dio dio;
    final String path;
    if (AppConfig.aiServiceBaseUrl.isNotEmpty) {
      dio = Dio(BaseOptions(
        baseUrl: AppConfig.aiServiceBaseUrl,
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
      ));
      _api.attachAiServiceAuth(dio);
      path = Endpoints.mobileAppVersionDirect;
    } else {
      dio = _api.dio;
      path = Endpoints.mobileAppVersionGateway;
    }
    ConsoleLog.banner('[PayloadDebug] app-version ${checkUrl()} $headers');
    final res = await dio.post<dynamic>(
      path,
      options: Options(headers: headers, receiveTimeout: _timeout),
    );
    ConsoleLog.step('[PayloadDebug] app-version → ${res.statusCode}');
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) return null;
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;
    return AppVersionPolicy.fromJson(data);
  }
}
