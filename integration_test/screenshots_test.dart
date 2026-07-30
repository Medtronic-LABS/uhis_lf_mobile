import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uhis_next/main.dart' as app;
import 'package:uhis_next/core/constants/app_strings.dart';

/// Captures Play Store listing screenshots from a real, logged-in run of the
/// app. Kept separate from the functional integration tests (login_test.dart,
/// household_enrollment_test.dart, patient_vitals_test.dart) since capturing
/// images is a different responsibility than asserting behavior.
///
/// Run via `scripts/capture_screenshots.sh`, not `flutter test` — screenshots
/// only reach the host filesystem through `test_driver/integration_test.dart`
/// driving this file with `flutter drive`.
const _kUsername = 'hyper_sk';
const _kPassword = 'Spice123';
const _kTestPin = ['1', '2', '3', '4'];
const _kPatientName = 'Saidul';

Future<void> _settle(WidgetTester tester, [int seconds = 5]) =>
    tester.pumpAndSettle(Duration(seconds: seconds));

Future<void> _enterPinDigits(WidgetTester tester) async {
  for (final digit in _kTestPin) {
    await tester.tap(find.text(digit).last);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Mirrors the login flow already proven out in patient_vitals_test.dart:
/// sign in, then dismiss whichever optional onboarding/biometric/PIN screens
/// appear (they depend on the account's prior session state).
Future<void> _login(WidgetTester tester) async {
  await _settle(tester, 10);

  await tester.enterText(
      find.widgetWithText(TextFormField, LoginStrings.usernameLabel),
      _kUsername);
  await tester.enterText(
      find.widgetWithText(TextFormField, LoginStrings.passwordLabel),
      _kPassword);
  await tester.tap(find.text(LoginStrings.signIn));
  await tester.pump(const Duration(seconds: 1));

  await _settle(tester, 120); // cold sync can take up to ~2 minutes

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

  if (find.text(PinStrings.createTitle(4)).evaluate().isNotEmpty) {
    await _enterPinDigits(tester);
    await _settle(tester, 5);
    if (find.text(PinStrings.confirmTitle).evaluate().isNotEmpty) {
      await _enterPinDigits(tester);
      await _settle(tester, 10);
    }
  }

  await _settle(tester);
  expect(find.text(LoginStrings.signIn), findsNothing);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ).deleteAll();
    app.main();
  });

  testWidgets('capture Play Store screenshots', (tester) async {
    await _login(tester);
    await tester.pump();
    await binding.takeScreenshot('01_dashboard_worklist');

    // ── Patient/household context screen ──────────────────────────────────
    expect(find.byType(SearchBar), findsOneWidget);
    await tester.tap(find.byType(SearchBar));
    await _settle(tester);

    final searchInput = find.byType(EditableText);
    expect(searchInput, findsAtLeastNWidgets(1));
    await tester.enterText(searchInput.first, _kPatientName);
    await tester.pump(const Duration(milliseconds: 500)); // debounce
    await _settle(tester, 5);

    final resultTile = find.textContaining(_kPatientName);
    expect(resultTile, findsAtLeastNWidgets(1));
    await tester.tap(resultTile.first);
    await _settle(tester, 5);
    await binding.takeScreenshot('02_patient_context');

    // ── Visit flow — Step 1 triage/symptom picker ───────────────────────────
    // Best-effort: reaching this (and especially the Step 3 AI Recommendation
    // screen further beyond it) depends on this synced test account having
    // patient/vitals data that lets `NewPatientVisitStrings.startVisitCta`
    // resolve to a single eligible service without extra taps. If the CTA
    // isn't present or a service picker blocks it, log and move on rather
    // than fail the whole capture run — treat those screens as manual
    // captures until a stable test-data fixture exists for them.
    try {
      final startVisit = find.text(NewPatientVisitStrings.startVisitCta);
      if (startVisit.evaluate().isEmpty) {
        throw StateError('Start Visit CTA not present on this account/state');
      }
      await tester.tap(startVisit.first);
      await _settle(tester, 5);

      if (find.text(NewPatientVisitStrings.selectServiceCta)
          .evaluate()
          .isNotEmpty) {
        throw StateError(
            'A service must be selected first — not automated here');
      }

      await _settle(tester, 3);
      await binding.takeScreenshot('03_visit_triage');
    } catch (e) {
      // ignore: avoid_print
      print('[screenshots] Step 1 triage screen not reached ($e) — '
          'capture this one manually from a QA build.');
    }
  });
}
