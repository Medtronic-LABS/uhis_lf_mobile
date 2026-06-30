import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uhis_next/main.dart' as app;
import 'package:uhis_next/core/constants/app_strings.dart';

const _kTestPin = ['1', '2', '3', '4', '5', '6'];
const _kPatientName = 'Saidul';

Future<void> _settle(WidgetTester tester, [int seconds = 5]) =>
    tester.pumpAndSettle(Duration(seconds: seconds));

Future<void> _enterPinDigits(WidgetTester tester) async {
  for (final digit in _kTestPin) {
    await tester.tap(find.text(digit).last);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ).deleteAll();
    app.main();
  });

  testWidgets(
    'login → sync → search patient from dashboard → verify vitals',
    (tester) async {
      // ── 0. App load ──────────────────────────────────────────────────────
      await _settle(tester, 10);

      // ── 1. Login ─────────────────────────────────────────────────────────
      expect(find.widgetWithText(TextFormField, LoginStrings.usernameLabel),
          findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, LoginStrings.usernameLabel),
          'hyper_sk');
      await tester.enterText(
          find.widgetWithText(TextFormField, LoginStrings.passwordLabel),
          'Spice123');
      await tester.tap(find.text(LoginStrings.signIn));
      await tester.pump(const Duration(seconds: 1));

      // ── 2. Post-login: sync (up to 120 s) + optional screens ────────────
      await _settle(tester, 120);

      if (find.text(OnboardingStrings.title).evaluate().isNotEmpty) {
        await tester.tap(find.text(OnboardingStrings.skipButton));
        await _settle(tester);
        if (find.text(OnboardingStrings.skipAnywayButton).evaluate().isNotEmpty) {
          await tester.tap(find.text(OnboardingStrings.skipAnywayButton));
          await _settle(tester);
        }
      }

      if (find.text(DashboardStrings.notNow).evaluate().isNotEmpty) {
        await tester.tap(find.text(DashboardStrings.notNow));
        await _settle(tester);
      }

      if (find.text(PinStrings.createTitle(6)).evaluate().isNotEmpty) {
        await _enterPinDigits(tester);
        await _settle(tester, 5);
        if (find.text(PinStrings.confirmTitle).evaluate().isNotEmpty) {
          await _enterPinDigits(tester);
          await _settle(tester, 10);
        }
      }

      await _settle(tester);
      expect(find.text(LoginStrings.signIn), findsNothing);

      // ── 3. Tap search bar (SearchAnchor.bar on Dashboard) ───────────────
      expect(find.byType(SearchBar), findsOneWidget);
      await tester.tap(find.byType(SearchBar));
      await _settle(tester);

      // ── 4. Type patient name in overlay ─────────────────────────────────
      final searchInput = find.byType(EditableText);
      expect(searchInput, findsAtLeastNWidgets(1));
      await tester.enterText(searchInput.first, _kPatientName);
      await tester.pump(const Duration(milliseconds: 500)); // debounce
      await _settle(tester, 5);

      // ── 5. Tap first result ──────────────────────────────────────────────
      final resultTile = find.textContaining(_kPatientName);
      expect(resultTile, findsAtLeastNWidgets(1));
      await tester.tap(resultTile.first);
      await _settle(tester, 5);

      // ── 6. Assert vitals section ─────────────────────────────────────────
      expect(find.text('Recent Vitals'), findsOneWidget,
          reason: 'Recent Vitals section header must appear on patient page');

      // ── 7. Assert at least one vital row ────────────────────────────────
      const vitalLabels = [
        'Blood Pressure', 'SpO₂', 'Respiratory Rate',
        'Blood Glucose', 'Weight', 'Temperature', 'BMI',
      ];
      final present =
          vitalLabels.where((l) => find.text(l).evaluate().isNotEmpty).toList();
      expect(present, isNotEmpty,
          reason: 'At least one vital row must render; checked: $vitalLabels');
    },
  );
}
