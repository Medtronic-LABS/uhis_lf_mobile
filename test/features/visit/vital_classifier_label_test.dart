import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/features/visit/vital_classifier.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('VitalClassification.label routes through AppStrings', () {
    AppLocale.current = AppLanguage.english;
    expect(VitalClassification.normal.label, 'Normal');
    expect(VitalClassification.low.label, 'Low');
    expect(VitalClassification.high.label, 'High');
    expect(VitalClassification.critical.label, 'Critical');
  });
}
