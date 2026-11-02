import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/endpoints.dart';
import 'package:uhis_next/core/version/app_version_service.dart';

void main() {
  test('checkUrl uses gateway or direct mobile path', () {
    final url = AppVersionService.checkUrl();
    expect(
      url.endsWith(Endpoints.mobileAppVersionGateway) ||
          url.endsWith(Endpoints.mobileAppVersionDirect),
      isTrue,
    );
  });
}
