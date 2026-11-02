/// Builds the app's one real [ShukheeClient], wired to this app's own
/// authenticated session ([ApiClient]) -- shared by `TeleconsultScreen` (a
/// live booking/call) and `TeleconsultCallDetailScreen` (a historical call's
/// read-only document download), so the "strip the Bearer prefix" auth
/// plumbing and debug-only request logging exist in exactly one place.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/debug/console_log.dart';
import '../../core/i18n/app_locale.dart';

ShukheeClient buildShukheeClient(BuildContext context) {
  final apiClient = context.read<ApiClient>();
  final config = ShukheeConfig(
    baseUrl: AppConfig.shukheeApiBaseUrl,
    // ApiClient.exportAuthToken() returns the full "Bearer <token>" string
    // verbatim (its own request interceptor uses it as-is, with no scheme
    // prepended -- see api_client.dart's onRequest handlers) -- but
    // shukhee_sdk's authTokenProvider contract expects just the raw token
    // and prepends "Bearer " itself. Strip it here so the two don't stack
    // into "Bearer Bearer <token>", which the real auth-service rejects
    // with 400 (confirmed live against the sandbox this session).
    authTokenProvider: () async {
      final raw = apiClient.exportAuthToken();
      if (raw == null) return null;
      const prefix = 'Bearer ';
      return raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
    },
    // The backend's real (Phase 2) auth validation needs this to call the
    // legacy platform's own /authenticate endpoint -- see shukhee_sdk's
    // ShukheeConfig.tenantIdProvider doc for why.
    tenantIdProvider: () async => apiClient.tenantId,
    // Sent as `_lang` -- Frappe's own request bootstrap
    // (`HTTPRequest.set_lang`) reads `form_dict._lang` ahead of anything
    // else, so every `frappe.throw(_("..."))` error this app's Shukhee
    // calls can raise comes back in whichever language the app is
    // currently showing. See shukhee_sdk's ShukheeConfig.languageCodeProvider
    // doc for the full mechanism.
    languageCodeProvider: () async => AppLocale.isBangla ? 'bn' : 'en',
  );
  return ShukheeClient(
    config,
    // Debug-only: shukhee_sdk builds its own internal Dio with no logging
    // (it has no dependency on this app's ConsoleLog/[ShukheeDebug]
    // convention), so every Shukhee HTTP call is otherwise invisible on
    // device. Injecting our own Dio here (same BaseOptions the SDK would
    // have built itself) makes every call visible via `adb logcat` without
    // touching the shared SDK package.
    dio: kDebugMode ? _buildDebugDio(config) : null,
  );
}

/// Debug-only Dio, mirroring the BaseOptions shukhee_sdk would have built
/// internally, plus a request/response/error logging interceptor -- see
/// [buildShukheeClient]. `[ShukheeDebug]` tag, visible via `adb logcat`.
Dio _buildDebugDio(ShukheeConfig config) {
  final dio = Dio(BaseOptions(
    baseUrl: config.baseUrl,
    connectTimeout: config.connectTimeout,
    receiveTimeout: config.receiveTimeout,
  ));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final data = options.data;
        String bodyDesc;
        if (data is FormData) {
          final fields = {for (final f in data.fields) f.key: f.value};
          final files = {
            for (final f in data.files) f.key: '${f.value.filename} (${f.value.length}b)',
          };
          bodyDesc = 'fields=$fields'
              '${files.isNotEmpty ? ' files=$files' : ''}';
        } else {
          bodyDesc = data?.toString() ?? '(none)';
        }
        ConsoleLog.banner(
          '[ShukheeDebug] --> ${options.method} ${options.path}\n'
          'headers: ${options.headers}\n'
          'body: $bodyDesc',
        );
        handler.next(options);
      },
      onResponse: (response, handler) {
        ConsoleLog.success(
          '[ShukheeDebug] <-- ${response.statusCode} ${response.requestOptions.path}',
        );
        ConsoleLog.json('[ShukheeDebug] response body', response.data);
        handler.next(response);
      },
      onError: (e, handler) {
        ConsoleLog.warn(
          '[ShukheeDebug] <-- ERROR ${e.response?.statusCode} ${e.requestOptions.path}: '
          '${e.response?.data ?? e.message}',
        );
        handler.next(e);
      },
    ),
  );
  return dio;
}
