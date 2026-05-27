import 'dart:io' show Cookie;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/app_config.dart';
import 'browser_adapter_stub.dart'
    if (dart.library.html) 'browser_adapter_web.dart';

const String _authCookieName = 'AuthCookie';
const String _sessionCookieName = 'JSESSIONID';

class ApiClient {
  ApiClient._(this.dio, this._cookieJar);

  static String get _baseUrl => AppConfig.apiBaseUrl;

  final Dio dio;
  final CookieJar _cookieJar;
  String? _tenantId;
  DateTime? _authCookieExpiry;
  String? _cachedAuthCookie;
  String? _cachedJsession;
  void Function(String authCookie, DateTime expiry)? onAuthCookieRotated;

  static Future<ApiClient> create() async {
    final cookieJar = CookieJar();
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'client': AppConfig.apiClient},
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final client = ApiClient._(dio, cookieJar);
    if (kIsWeb) {
      configureWebCredentials(dio);
    } else {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final cookies = await cookieJar.loadForRequest(options.uri);
            if (cookies.isNotEmpty) {
              options.headers['Cookie'] =
                  cookies.map((c) => '${c.name}=${c.value}').join('; ');
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
                  } catch (_) {}
                }
              }
              if (stored.isNotEmpty) {
                await cookieJar.saveFromResponse(
                  response.requestOptions.uri,
                  stored,
                );
              }
            }
            handler.next(response);
          },
        ),
      );
    }
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final t = client._tenantId;
          if (t != null && t.isNotEmpty) {
            options.headers['tenantId'] = t;
          }
          handler.next(options);
        },
      ),
    );
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: false,
        responseHeader: true,
        responseBody: false,
        error: true,
      ),
    );
    return client;
  }

  void setTenantId(String? id) {
    _tenantId = id;
  }

  String? get tenantId => _tenantId;

  /// `tenantId` coerced to a number when it is numeric, else the raw string.
  /// The spice/user services expect a numeric `tenantId` in JSON bodies; this
  /// is the single source for that coercion (was duplicated across repos).
  Object? get tenantIdAsNum {
    final t = _tenantId;
    if (t == null) return null;
    return int.tryParse(t) ?? t;
  }

  DateTime? get authCookieExpiry => _authCookieExpiry;

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
    _authCookieExpiry = null;
    _cachedAuthCookie = null;
    _cachedJsession = null;
    await _cookieJar.deleteAll();
  }
}
