/// Locks the English wording of the `ClinicalFindingStrings` getters wired
/// into the briefing-rules files in `lib/core/clinical/briefing_rules/` (Task
/// 12 of the localization plan) — asserts exact expected strings so a future
/// refactor of the getter or its call site cannot silently drift the
/// clinical copy shown to the SK.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';

void main() {
  // AppLocale.current is a global static flag shared across the whole test
  // process (see app_locale.dart, default bangla). Any case that relies on
  // the English fallback must set it explicitly and restore afterwards or it
  // leaks into unrelated test files run in the same suite.
  setUp(() {
    AppLocale.current = AppLanguage.english;
  });

  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

  group('ClinicalFindingStrings — English fallback', () {
    test('ancBpAboveSafeThreshold', () {
      expect(
        ClinicalFindingStrings.ancBpAboveSafeThreshold,
        'BP is above the safe threshold. Watch for pre-eclampsia.',
      );
    });

    test('ncdBpAboveNormal', () {
      expect(
        ClinicalFindingStrings.ncdBpAboveNormal,
        'BP is above normal. Requires review and follow-up.',
      );
    });

    test('pncSevereAnemia', () {
      expect(ClinicalFindingStrings.pncSevereAnemia, 'Severe anemia.');
    });

    test('childImmunizationOnSchedule', () {
      expect(
        ClinicalFindingStrings.childImmunizationOnSchedule,
        'Immunization on schedule, growth on track.',
      );
    });

    test('pregnancyOutcomeStillbirthOrNeonatalDeath', () {
      expect(
        ClinicalFindingStrings.pregnancyOutcomeStillbirthOrNeonatalDeath,
        'Stillbirth or neonatal death recorded.',
      );
    });
  });
}
