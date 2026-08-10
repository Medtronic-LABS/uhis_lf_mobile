import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

import '../config/app_config.dart';
import 'browser_adapter_stub.dart'
    if (dart.library.html) 'browser_adapter_web.dart';

const String _authCookieName = 'AuthCookie';
const String _sessionCookieName = 'JSESSIONID';
const String _authRetryExtra = 'authRetry';

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
  // Fired only when authentication has failed for real (401 after a refresh
  // attempt). Never fired for 403 — that means "authenticated but not
  // permitted" and must not sign the user out.
  void Function()? onUnauthorized;
  // Awaited before every request except the login and token-validation
  // endpoints themselves — lets AuthRepository refresh a near-expiry Bearer
  // token before it's used, so most sessions never reach onUnauthorized.
  Future<void> Function()? onBeforeRequest;
  // One-shot refresh used by the 401 interceptor. Returns true when the
  // session was restored and the original request may be retried.
  Future<bool> Function()? onTokenRefresh;

  static Future<ApiClient> create() async {
    final cookieJar = CookieJar();
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
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
          onResponse: (response, handler) async {
            await client._onAuthResponse(response, handler);
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
            await client._onAuthResponse(response, handler);
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

  /// Shared 2xx / 401 handling for web and native interceptors.
  ///
  /// 403 is intentionally ignored here: it means the user is authenticated
  /// but not permitted for that resource, and must not force a sign-out.
  Future<void> _onAuthResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final authz = response.headers.value('authorization');
    if (authz != null && authz.isNotEmpty) {
      _authToken = authz;
    }
    final status = response.statusCode;
    final path = response.requestOptions.path;
    if (status != null && status >= 200 && status < 300) {
      onAuthenticatedActivity?.call();
      handler.next(response);
      return;
    }
    if (status == 401 &&
        !path.contains('/session') &&
        !path.contains('/authenticate')) {
      final alreadyRetried =
          response.requestOptions.extra[_authRetryExtra] == true;
      if (!alreadyRetried && onTokenRefresh != null) {
        debugPrint(
            '[ApiClient] 401 on $path — attempting token refresh before sign-out');
        final refreshed = await onTokenRefresh!();
        if (refreshed) {
          try {
            final opts = response.requestOptions;
            opts.extra[_authRetryExtra] = true;
            final token = _authToken;
            if (token != null && token.isNotEmpty) {
              opts.headers['Authorization'] = token;
            }
            final retry = await dio.fetch(opts);
            handler.resolve(retry);
            return;
          } catch (e) {
            debugPrint('[ApiClient] retry after refresh failed: $e');
          }
        }
      }
      debugPrint(
          '[ApiClient] 401 on $path — signaling onUnauthorized (session expired)');
      onUnauthorized?.call();
    } else if (status == 403) {
      debugPrint(
          '[ApiClient] 403 on $path — permission denied, session kept');
    }
    handler.next(response);
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
