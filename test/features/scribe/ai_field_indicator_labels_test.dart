import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

void main() {
  // AppLocale.current is a global static flag (the app's context-free
  // localization seam — see app_locale.dart) shared across the whole test
  // process. AppLocale.current defaults to bangla, so set english explicitly
  // and restore it afterwards or it leaks into unrelated test files run in
  // the same suite.
  setUp(() {
    AppLocale.current = AppLanguage.english;
  });

  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

  group('ScribeBannerStrings confidence-level getters', () {
    test('confidenceHigh', () {
      expect(ScribeBannerStrings.confidenceHigh, 'High confidence');
    });

    test('confidenceMedium', () {
      expect(ScribeBannerStrings.confidenceMedium, 'Medium');
    });

    test('confidenceReviewNeeded', () {
      expect(ScribeBannerStrings.confidenceReviewNeeded, 'Review needed');
    });
  });

  group('ScribeBannerStrings status-chip getters', () {
    test('statusAccepted', () {
      expect(ScribeBannerStrings.statusAccepted, 'Accepted');
    });

    test('statusModified', () {
      expect(ScribeBannerStrings.statusModified, 'Modified');
    });
  });
}
