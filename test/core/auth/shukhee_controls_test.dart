import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/auth/user_hierarchy_service.dart';

void main() {
  group('ShukheeControls.fromJson', () {
    test('parses teleconsultEnabled true', () {
      expect(ShukheeControls.fromJson({'teleconsultEnabled': true}).teleconsultEnabled, isTrue);
    });

    test('parses teleconsultEnabled false', () {
      expect(ShukheeControls.fromJson({'teleconsultEnabled': false}).teleconsultEnabled, isFalse);
    });

    test('defaults to false when the key is missing', () {
      expect(ShukheeControls.fromJson(const {}).teleconsultEnabled, isFalse);
    });

    test('defaults to false when the value is the wrong type', () {
      expect(ShukheeControls.fromJson({'teleconsultEnabled': 'true'}).teleconsultEnabled, isFalse);
    });
  });

  group('isTeleconsultVisible', () {
    test('visible only when both the build flag and backend flag are true', () {
      expect(isTeleconsultVisible(buildFlag: true, backendFlag: true), isTrue);
      expect(isTeleconsultVisible(buildFlag: true, backendFlag: false), isFalse);
      expect(isTeleconsultVisible(buildFlag: false, backendFlag: true), isFalse);
      expect(isTeleconsultVisible(buildFlag: false, backendFlag: false), isFalse);
    });
  });
}
