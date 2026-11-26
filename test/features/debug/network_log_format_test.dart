import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/theme/app_theme.dart';
import 'package:uhis_next/core/net_log/url_sanitizer.dart';
import 'package:uhis_next/features/debug/network_log_format.dart';

NetworkLogEntry _entry(int? status) => NetworkLogEntry(
  startedAtMs: 1,
  source: 'dart',
  service: 'core',
  method: 'GET',
  url: 'https://example.test/a',
  statusCode: status,
);

void main() {
  group('statusColor', () {
    final expected = <int?, Object>{
      200: AppColors.rangeNormal,
      301: AppColors.infoAccentDark,
      404: AppColors.rangeElevated,
      503: AppColors.rangeCritical,
      null: AppColors.rangeCrisis,
    };
    expected.forEach((code, color) {
      test('$code maps to its bucket colour', () {
        expect(NetworkLogFormat.statusColor(_entry(code)), color);
      });
    });

    test('the five buckets use five distinct colours', () {
      final colors = expected.keys
          .map((c) => NetworkLogFormat.statusColor(_entry(c)))
          .toSet();
      expect(colors, hasLength(5));
    });
  });

  group('endpointUrl', () {
    test('drops userinfo, query and fragment but keeps host and port', () {
      expect(
        NetworkLogFormat.endpointUrl(
          'https://user:pw@api.example.test:8443/x?token=abc#f',
        ),
        'https://api.example.test:8443/x',
      );
    });

    test('leaves a plain base url unchanged', () {
      expect(
        NetworkLogFormat.endpointUrl('https://gw.example.test/admin-api'),
        'https://gw.example.test/admin-api',
      );
    });

    test('an unparsable value is shown as a fixed marker', () {
      expect(
        NetworkLogFormat.endpointUrl('https://exa mple:port/x'),
        UrlSanitizer.unparsable,
      );
    });
  });
}
