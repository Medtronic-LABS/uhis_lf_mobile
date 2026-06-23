import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uhis_next/main.dart' as app;
import 'package:uhis_next/core/constants/app_strings.dart';

const _kTestPin = ['1', '2', '3', '4', '5', '6'];

/// Pause long enough for a human observer to see what just happened.
Future<void> _pause(WidgetTester tester, [int seconds = 2]) =>
    tester.pump(Duration(seconds: seconds));

Future<void> _enterPinDigits(WidgetTester tester) async {
  for (final digit in _kTestPin) {
    await tester.tap(find.text(digit).last);
    await tester.pump(const Duration(milliseconds: 500)); // visible per-digit
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

  group('login flow', () {
    testWidgets('01 — login screen renders all form elements', (tester) async {
      // Wait for the app to fully load.
      await tester.pumpAndSettle(const Duration(seconds: 15));
      await _pause(tester, 2); // pause so you can see the login screen

      expect(find.text(LoginStrings.usernameLabel), findsOneWidget);
      expect(find.text(LoginStrings.passwordLabel), findsOneWidget);
      expect(find.text(LoginStrings.signIn), findsAtLeastNWidgets(1));

      await _pause(tester, 2); // pause before next test
    });

    testWidgets(
        '02 — login + optional security screens + navigate past login',
        (tester) async {
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await _pause(tester, 2); // pause so you can see the login screen

      if (find.widgetWithText(TextFormField, LoginStrings.usernameLabel)
          .evaluate()
          .isEmpty) {
        expect(find.text(LoginStrings.signIn), findsNothing);
        return;
      }

      // ── 1. Type username ─────────────────────────────────────────────────
      await tester.tap(
          find.widgetWithText(TextFormField, LoginStrings.usernameLabel));
      await _pause(tester, 1);
      await tester.enterText(
        find.widgetWithText(TextFormField, LoginStrings.usernameLabel),
        'hyper_sk',
      );
      await _pause(tester, 2); // pause so you can read the typed username

      // ── 2. Type password ─────────────────────────────────────────────────
      await tester.tap(
          find.widgetWithText(TextFormField, LoginStrings.passwordLabel));
      await _pause(tester, 1);
      await tester.enterText(
        find.widgetWithText(TextFormField, LoginStrings.passwordLabel),
        'Spice123',
      );
      await _pause(tester, 2); // pause so you can see both fields filled

      // ── 3. Tap Sign in ───────────────────────────────────────────────────
      await tester.tap(find.text(LoginStrings.signIn));
      await _pause(tester, 2); // pause to show the tap happened
      await tester.pumpAndSettle(const Duration(seconds: 30));
      await _pause(tester, 3); // pause to see what screen appeared after login

      // ── 4. Optional: "Secure Your Account" onboarding ───────────────────
      if (find.text(OnboardingStrings.title).evaluate().isNotEmpty) {
        await _pause(tester, 3); // pause to read the screen
        await tester.tap(find.text(OnboardingStrings.skipButton));
        await tester.pumpAndSettle();
        await _pause(tester, 2);
        if (find.text(OnboardingStrings.skipAnywayButton).evaluate().isNotEmpty) {
          await _pause(tester, 2); // pause to read the confirm dialog
          await tester.tap(find.text(OnboardingStrings.skipAnywayButton));
          await tester.pumpAndSettle();
          await _pause(tester, 2);
        }
      }

      // ── 5. Optional: biometric offer dialog ──────────────────────────────
      if (find.text(DashboardStrings.notNow).evaluate().isNotEmpty) {
        await _pause(tester, 3); // pause to read the biometric dialog
        await tester.tap(find.text(DashboardStrings.notNow));
        await tester.pumpAndSettle();
        await _pause(tester, 2);
      }

      // ── 6. Optional: 6-digit PIN creation ────────────────────────────────
      if (find.text(PinStrings.createTitle(6)).evaluate().isNotEmpty) {
        await _pause(tester, 3); // pause to read the PIN create screen

        await _enterPinDigits(tester);
        await _pause(tester, 2); // pause to see all 6 dots filled

        await tester.pumpAndSettle(const Duration(seconds: 3));

        if (find.text(PinStrings.confirmTitle).evaluate().isNotEmpty) {
          await _pause(tester, 3); // pause to read the PIN confirm screen
          await _enterPinDigits(tester);
          await _pause(tester, 2); // pause to see the confirm dots filled
          await tester.pumpAndSettle(const Duration(seconds: 30));
          await _pause(tester, 3); // pause to see the navigation result
        }
      }

      // ── 7. Assert: login screen gone ─────────────────────────────────────
      await _pause(tester, 3); // final pause so you can see the end state
      expect(find.text(LoginStrings.signIn), findsNothing);
    });
  });
}
