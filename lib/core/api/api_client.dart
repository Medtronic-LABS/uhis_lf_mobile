import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

import '../config/app_config.dart';
import 'endpoints.dart';
import 'browser_adapter_stub.dart'
    if (dart.library.html) 'browser_adapter_web.dart';

const String _authCookieName = 'AuthCookie';
const String _sessionCookieName = 'JSESSIONID';

/// `RequestOptions.extra` key holding the 1-based attempt number, so a replayed
/// request knows how many attempts have already been spent.
const String _kAttemptKey = 'uhisAttempt';

/// Read-only POST endpoints that are safe to replay.
///
/// Writes are excluded deliberately: `offline-sync/create` has no server-side
/// uniqueness on `requestId` (`OfflineSync.requestId` is unconstrained and
/// `constructOfflineSync` → `saveAll` inserts without an existence check), so
/// replaying one can duplicate households, members and assessments. Most reads
/// in this API are POSTs, so method alone is not a safe test.
const Set<String> _retryableReadPaths = <String>{
  Endpoints.offlineSyncFetch,
  Endpoints.offlineSyncMemberAssessmentHistory,
  Endpoints.staticUserData,
  Endpoints.patientSearch,
};

/// True when [e] is a transient transport failure (or a 5xx) on a request that
/// is safe to replay. A 4xx never reaches here — `validateStatus` admits
/// anything below 500 as a normal response — and would not be worth retrying
/// anyway.
bool _isRetryable(DioException e) {
  final safeToReplay = e.requestOptions.method.toUpperCase() == 'GET' ||
      _retryableReadPaths.contains(e.requestOptions.path);
  if (!safeToReplay) return false;
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError =>
      true,
    DioExceptionType.badResponse => (e.response?.statusCode ?? 0) >= 500,
    _ => false,
  };
}

class ApiClient {
  ApiClient._(this.dio, this._cookieJar);

  static String get _baseUrl => AppConfig.apiBaseUrl;

  final Dio dio;
  final CookieJar _cookieJar;
  String? _tenantId;
  String? _organizationFhirId;
  DateTime? _authCookieExpiry;
  String? _cachedAuthCookie;
  String? _cachedJsession;
  // Bearer token returned by the mobile ('mob') auth flow in the `Authorization`
  // response header. Community roles (SK) authenticate this way instead of the
  // web AuthCookie; the token is replayed on every subsequent request.
  String? _authToken;
  void Function(String authCookie, DateTime expiry)? onAuthCookieRotated;
  // Fired on every successful (2xx) authenticated response — lets
  // AuthRepository extend the locally-persisted reentry-session TTL on real
  // backend activity, so an actively-used mobile session doesn't hit the
  // synthetic Bearer-token expiry wall while the SK is still working.
  void Function()? onAuthenticatedActivity;
  // Fired on a 401/403 from any authenticated endpoint (never the login
  // endpoint itself — a wrong password legitimately 401s there) — lets
  // AuthState detect a server-invalidated session proactively instead of
  // only via local TTL checks.
  void Function()? onUnauthorized;
  // Awaited before every request except the login and token-validation
  // endpoints themselves — lets AuthRepository refresh a near-expiry Bearer
  // token before it's used, so most sessions never reach onUnauthorized.
  Future<void> Function()? onBeforeRequest;
  // Fired just before a retry-safe request is replayed, with the request path,
  // the 1-based attempt about to start, and the configured maximum. Retrying is
  // otherwise invisible; the sync screen uses this to show progress rather than
  // appearing frozen for the whole retry budget.
  void Function(String path, int attempt, int maxAttempts)? onRetryAttempt;

  static Future<ApiClient> create() async {
    final cookieJar = CookieJar();
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout:
            const Duration(seconds: AppConfig.apiConnectTimeoutSeconds),
        receiveTimeout:
            const Duration(seconds: AppConfig.apiReceiveTimeoutSeconds),
        headers: {'client': AppConfig.apiClient},
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final client = ApiClient._(dio, cookieJar);
    // Android ≤ 7.1 (API ≤ 25) ships a root-CA store that predates ISRG Root X1
    // (Let's Encrypt's post-2021 chain). TLS handshakes to the dev backend fail
    // with CERTIFICATE_VERIFY_FAILED on those devices. In debug builds we bypass
    // the check so engineers can test on older hardware; release builds always
    // enforce full certificate verification.
    if (!kIsWeb && kDebugMode) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () =>
          HttpClient()
            ..badCertificateCallback = (cert, host, port) {
              debugPrint('ApiClient [debug]: bypassing cert check for $host:$port');
              return true;
            };
    }
    // Registered first so a refreshed token (if onBeforeRequest triggers one)
    // is what the cookie/token-header interceptor below attaches. Skips the
    // login endpoint (no token exists yet pre-login) and the token-validation
    // endpoint itself (would otherwise recurse — that request would trigger
    // onBeforeRequest again, which would call it again, forever).
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final skip = options.path.contains('/session') ||
              options.path.contains('/authenticate');
          if (!skip) await client.onBeforeRequest?.call();
          handler.next(options);
        },
      ),
    );
    if (kIsWeb) {
      configureWebCredentials(dio);
      // On web the browser manages cookies via withCredentials.  The Bearer
      // token in the Authorization response header is NOT forwarded by XHR
      // automatically — capture it on login and replay it on every subsequent
      // request (mirrors the native interceptor below).
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final token = client._authToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = token;
            }
            handler.next(options);
          },
          onResponse: (response, handler) {
            final authz = response.headers.value('authorization');
            if (authz != null && authz.isNotEmpty) {
              client._authToken = authz;
            }
            final status = response.statusCode;
            if (status != null && status >= 200 && status < 300) {
              client.onAuthenticatedActivity?.call();
            } else if ((status == 401 || status == 403) &&
                !response.requestOptions.path.contains('/session')) {
              debugPrint('[ApiClient] $status on ${response.requestOptions.path} — signaling onUnauthorized');
              client.onUnauthorized?.call();
            }
            handler.next(response);
          },
        ),
      );
    } else {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final cookies = await cookieJar.loadForRequest(options.uri);
            if (cookies.isNotEmpty) {
              options.headers['Cookie'] =
                  cookies.map((c) => '${c.name}=${c.value}').join('; ');
            }
            final token = client._authToken;
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = token;
            }
            handler.next(options);
          },
          onResponse: (response, handler) async {
            final authz = response.headers.value('authorization');
            if (authz != null && authz.isNotEmpty) {
              client._authToken = authz;
            }
            final raw = response.headers.map['set-cookie'];
            if (raw != null && raw.isNotEmpty) {
              final stored = <Cookie>[];
              for (final entry in raw) {
                for (final line
                    in entry.split(RegExp(r'\r?\n')).map((s) => s.trim())) {
                  if (line.isEmpty) continue;
                  try {
                    final parsed = Cookie.fromSetCookieValue(line);
                    final maxAge = parsed.maxAge;
                    final c = parsed
                      ..secure = false
                      ..domain = null
                      ..path = '/';
                    stored.add(c);
                    if (c.name == _authCookieName) {
                      client._cachedAuthCookie = c.value;
                      final ttl = (maxAge != null && maxAge > 0)
                          ? Duration(seconds: maxAge)
                          : Duration(seconds: AppConfig.authCookieTtlSeconds);
                      final expiry = DateTime.now().add(ttl);
                      client._authCookieExpiry = expiry;
                      client.onAuthCookieRotated?.call(c.value, expiry);
                    }
                    if (c.name == _sessionCookieName) {
                      client._cachedJsession = c.value;
                    }
                  } catch (e) {
                    debugPrint('[api_client] malformed Set-Cookie, skipping: $e');
                  }
                }
              }
              if (stored.isNotEmpty) {
                await cookieJar.saveFromResponse(
                  response.requestOptions.uri,
                  stored,
                );
              }
            }
            final status = response.statusCode;
            if (status != null && status >= 200 && status < 300) {
              client.onAuthenticatedActivity?.call();
            } else if ((status == 401 || status == 403) &&
                !response.requestOptions.path.contains('/session')) {
              debugPrint('[ApiClient] $status on ${response.requestOptions.path} — signaling onUnauthorized');
              client.onUnauthorized?.call();
            }
            handler.next(response);
          },
        ),
      );
    }
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Skip auth-scoped headers for the login endpoint — auth-service
          // determines tenant + org from credentials and rejects extras.
          final isLogin = options.path.contains('/session');
          if (!isLogin) {
            final t = client._tenantId;
            if (t != null && t.isNotEmpty) {
              options.headers['tenantId'] = t;
            }
            final org = client._organizationFhirId;
            if (org != null && org.isNotEmpty) {
              options.headers['organizationId'] = org;
            }
            options.headers['App-Version'] = AppConfig.appVersionName;
            options.headers['App-Version-Code'] =
                AppConfig.appVersionCode.toString();
          }
          handler.next(options);
        },
      ),
    );
    // Retry must sit before LogInterceptor so a retried attempt is logged as
    // its own request/response pair rather than folded into the first.
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          final attempt = (e.requestOptions.extra[_kAttemptKey] as int?) ?? 1;
          if (!_isRetryable(e) || attempt >= AppConfig.apiMaxAttempts) {
            handler.next(e);
            return;
          }
          final next = attempt + 1;
          debugPrint('[ApiClient] retry $next/${AppConfig.apiMaxAttempts} '
              '${e.requestOptions.path} after ${e.type.name}');
          client.onRetryAttempt
              ?.call(e.requestOptions.path, next, AppConfig.apiMaxAttempts);
          await Future<void>.delayed(
              const Duration(seconds: AppConfig.apiRetryDelaySeconds));
          // Carry the attempt counter on the replayed request so the nested
          // onError for that attempt stops at apiMaxAttempts overall.
          final options = e.requestOptions
            ..extra[_kAttemptKey] = next;
          try {
            handler.resolve(await dio.fetch<dynamic>(options));
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    );
    return client;
  }

  void setTenantId(String? id) {
    _tenantId = id;
  }

  String? get tenantId => _tenantId;

  /// FHIR ID of the organization the logged-in user belongs to. Replayed in
  /// the `organizationId` header on every authed request (matches the Spice
  /// Android reference interceptor at `AppInterceptor` in `di/AppModule.kt`).
  void setOrganizationFhirId(String? id) {
    _organizationFhirId = id;
  }

  String? get organizationFhirId => _organizationFhirId;

  /// `tenantId` coerced to a number when it is numeric, else the raw string.
  /// The spice/user services expect a numeric `tenantId` in JSON bodies; this
  /// is the single source for that coercion (was duplicated across repos).
  Object? get tenantIdAsNum {
    final t = _tenantId;
    if (t == null) return null;
    return int.tryParse(t) ?? t;
  }

  DateTime? get authCookieExpiry => _authCookieExpiry;

  /// Returns true if currently authenticated via Bearer token (mobile flow).
  bool get hasAuthToken => _authToken != null && _authToken!.isNotEmpty;

  /// True when the client can authenticate API calls (Bearer token and/or
  /// auth cookie). Offline password login can mark the user signed-in without
  /// restoring credentials — callers that hit the network must check this.
  bool get hasSessionCredentials {
    if (hasAuthToken) return true;
    final cookie = _cachedAuthCookie;
    return cookie != null && cookie.isNotEmpty;
  }

  /// Export the Bearer token used for mobile auth.
  String? exportAuthToken() => _authToken;

  /// Import a previously persisted Bearer token.
  void importAuthToken(String? token) {
    _authToken = token;
  }

  Future<({String? jsession, String? authCookie})> exportAuthCookies() async {
    if (kIsWeb) return (jsession: null, authCookie: null);
    // Return cached values captured when cookies were received.
    // This bypasses cookie jar path-matching issues.
    return (jsession: _cachedJsession, authCookie: _cachedAuthCookie);
  }

  Future<void> importAuthCookies({
    required String? jsession,
    required String? authCookie,
    DateTime? authCookieExpiry,
  }) async {
    // Cache values for exportAuthCookies
    _cachedJsession = jsession;
    _cachedAuthCookie = authCookie;
    _authCookieExpiry = authCookieExpiry;
    if (kIsWeb) return;
    final uri = Uri.parse(_baseUrl);
    final cookies = <Cookie>[];
    if (jsession != null && jsession.isNotEmpty) {
      cookies.add(Cookie(_sessionCookieName, jsession)
        ..path = '/'
        ..httpOnly = true
        ..secure = false
        ..domain = null);
    }
    if (authCookie != null && authCookie.isNotEmpty) {
      cookies.add(Cookie(_authCookieName, authCookie)
        ..path = '/'
        ..httpOnly = true
        ..secure = false
        ..domain = null);
    }
    if (cookies.isNotEmpty) {
      await _cookieJar.saveFromResponse(uri, cookies);
    }
  }

  Future<void> clearSession() async {
    _tenantId = null;
    _organizationFhirId = null;
    _authCookieExpiry = null;
    _cachedAuthCookie = null;
    _cachedJsession = null;
    _authToken = null;
    await _cookieJar.deleteAll();
  }
}
