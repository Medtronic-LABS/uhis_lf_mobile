import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/theme/app_theme.dart';

Future<BuildContext> _pumpWithTheme(WidgetTester tester, ThemeData theme) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Builder(builder: (context) {
      capturedContext = context;
      return const SizedBox.shrink();
    }),
  ));
  return capturedContext;
}

void main() {
  group('AppTheme extensions resolve', () {
    testWidgets('every ThemeExtension is present on AppTheme.light', (tester) async {
      final context = await _pumpWithTheme(tester, AppTheme.light);
      expect(Theme.of(context).extension<LeapfrogColors>(), isNotNull);
      expect(Theme.of(context).extension<ProgrammeColors>(), isNotNull);
      expect(Theme.of(context).extension<UrgencyTheme>(), isNotNull);
      expect(Theme.of(context).extension<AiColors>(), isNotNull);
      expect(Theme.of(context).extension<OnDarkColors>(), isNotNull);
      expect(Theme.of(context).extension<PartnerColors>(), isNotNull);
      expect(Theme.of(context).extension<MotionTheme>(), isNotNull);
    });

    testWidgets('every ThemeExtension is present on AppTheme.dark', (tester) async {
      final context = await _pumpWithTheme(tester, AppTheme.dark);
      expect(Theme.of(context).extension<LeapfrogColors>(), isNotNull);
      expect(Theme.of(context).extension<ProgrammeColors>(), isNotNull);
      expect(Theme.of(context).extension<UrgencyTheme>(), isNotNull);
      expect(Theme.of(context).extension<AiColors>(), isNotNull);
      expect(Theme.of(context).extension<OnDarkColors>(), isNotNull);
      expect(Theme.of(context).extension<PartnerColors>(), isNotNull);
      expect(Theme.of(context).extension<MotionTheme>(), isNotNull);
    });
  });

  group('ProgrammeColors.of(Programme.epi) — child-programme blocker fix', () {
    test('light: epi resolves to the dedicated child color, not the ncd fallback', () {
      final resolved = ProgrammeColors.light.of(Programme.epi);
      expect(resolved, ProgrammeColors.light.child);
      expect(resolved, isNot(ProgrammeColors.light.ncd));
    });

    test('dark: epi resolves to the dedicated child color, not the ncd fallback', () {
      final resolved = ProgrammeColors.dark.of(Programme.epi);
      expect(resolved, ProgrammeColors.dark.child);
      expect(resolved, isNot(ProgrammeColors.dark.ncd));
    });

    test('containerOf(Programme.epi) mirrors of()', () {
      expect(ProgrammeColors.light.containerOf(Programme.epi),
          ProgrammeColors.light.childContainer);
    });

    test('an unmapped programme still falls back to ncd (documented default)', () {
      expect(ProgrammeColors.light.of(Programme.unknown), ProgrammeColors.light.ncd);
    });
  });

  group('LeapfrogColors deprecated aliases still resolve (regression guard)', () {
    test('light instance keeps aiPurple/aiPurpleDark/whatsapp/sukhee* non-null', () {
      const tokens = LeapfrogColors.light;
      // ignore: deprecated_member_use_from_same_package
      expect(tokens.aiPurple, AppColors.aiPurple);
      // ignore: deprecated_member_use_from_same_package
      expect(tokens.aiPurpleDark, AppColors.aiPurpleDark);
      // ignore: deprecated_member_use_from_same_package
      expect(tokens.whatsapp, AppColors.whatsapp);
      // ignore: deprecated_member_use_from_same_package
      expect(tokens.sukheeGradientStart, AppColors.sukheeStart);
      // ignore: deprecated_member_use_from_same_package
      expect(tokens.sukheeGradientEnd, AppColors.sukheeEnd);
    });
  });
}
