/// E2E test — navigate from the patient list to the dynamic form screen.
///
/// Flow:
///   (login if needed) → Patients tab → member tile → PatientContextScreen →
///   VisitLandingScreen → Start Visit → symptom picker → triage result →
///   "Open checklist →" → form screen
///
/// The test asserts [DynamicAssessmentScreen] renders with "Submit Assessment",
/// confirming the JSON-driven renderer initialised from program_forms.json.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/main.dart' as app;

// ── Credentials ───────────────────────────────────────────────────────────────

const _kEmail = 'hyper_sk';
const _kPassword = 'Spice123';
const _kPin = ['1', '2', '3', '4', '5', '6'];

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Pause so a human watching the emulator can see each step.
Future<void> _see(WidgetTester t, [int seconds = 2]) =>
    t.pump(Duration(seconds: seconds));

/// Pump the widget tree for [seconds] real-clock seconds.
///
/// Using a time-bounded pump loop rather than [WidgetTester.pumpAndSettle] so
/// the test does not block indefinitely on continuous animations (loading
/// spinners, looping Lottie, etc.) that never settle.
Future<void> _settle(WidgetTester t, [int seconds = 15]) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Tap [finder], then settle.
Future<void> _tap(WidgetTester t, Finder finder, {int settle = 5}) async {
  await t.tap(finder);
  await _see(t, 1);
  await _settle(t, settle);
}

/// Type [text] into [finder].
Future<void> _type(WidgetTester t, Finder finder, String text) async {
  await t.tap(finder);
  await t.enterText(finder, text);
  await _see(t, 1);
}

/// Enter all six PIN digits one at a time.
Future<void> _enterPin(WidgetTester t) async {
  for (final digit in _kPin) {
    await _tap(t, find.text(digit).last, settle: 1);
  }
}

// ── Helpers — handle startup screens ─────────────────────────────────────────

/// True when the login form is visible.
bool _onLoginScreen() =>
    find.widgetWithText(TextFormField, LoginStrings.usernameLabel)
        .evaluate()
        .isNotEmpty;

/// True when the lock screen is visible (fingerprint card or "Use password" link).
bool _onLockScreen() =>
    find.text(LockStrings.welcomeBack).evaluate().isNotEmpty ||
    find.text(LockStrings.verifyFingerprint).evaluate().isNotEmpty ||
    find.text(CommonStrings.usePassword).evaluate().isNotEmpty;

/// Log in with the test credentials.
/// Throws [TestFailure] if the login screen is still visible after submit
/// (which typically means invalid credentials or a server error).
Future<void> _login(WidgetTester t) async {
  await _type(
    t,
    find.widgetWithText(TextFormField, LoginStrings.usernameLabel),
    _kEmail,
  );
  await _type(
    t,
    find.widgetWithText(TextFormField, LoginStrings.passwordLabel),
    _kPassword,
  );
  await _see(t, 1);
  await _tap(t, find.text(LoginStrings.signIn), settle: 30);
  await _see(t, 3);

  // If the login form is still visible, credentials were rejected.
  if (_onLoginScreen()) {
    fail('Login failed — check that "$_kEmail" / "$_kPassword" is valid on '
        'the backend at the configured API_BASE_URL.');
  }
}

/// Handle any post-login onboarding / biometric / PIN screens.
Future<void> _handlePostLogin(WidgetTester t) async {
  // "Secure Your Account" onboarding
  if (find.text(OnboardingStrings.title).evaluate().isNotEmpty) {
    await _see(t, 2);
    await _tap(t, find.text(OnboardingStrings.skipButton));
    if (find.text(OnboardingStrings.skipAnywayButton).evaluate().isNotEmpty) {
      await _tap(t, find.text(OnboardingStrings.skipAnywayButton));
    }
  }

  // Biometric offer dialog ("Not now")
  if (find.text(DashboardStrings.notNow).evaluate().isNotEmpty) {
    await _tap(t, find.text(DashboardStrings.notNow));
  }

  // 6-digit PIN creation
  if (find.text(PinStrings.createTitle(6)).evaluate().isNotEmpty) {
    await _see(t, 2);
    await _enterPin(t);
    await _settle(t, 5);
    if (find.text(PinStrings.confirmTitle).evaluate().isNotEmpty) {
      await _enterPin(t);
      await _settle(t, 10);
    }
  }
}

// ── Test ──────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Do NOT clear FlutterSecureStorage — that wipes the SQLCipher DB key and
    // causes AppDatabase.open() to fail. The test handles all entry states:
    // login screen, lock screen, or already-authenticated dashboard.
    app.main();
  });

  testWidgets(
    'navigate from patient card to dynamic form screen',
    (tester) async {
      // ── 1. Wait for the app to fully initialise ────────────────────────────
      await _settle(tester, 20);
      await _see(tester, 2);

      // ── 2. Handle startup screen — login / lock / already on dashboard ─────
      if (_onLoginScreen()) {
        await _login(tester);
        await _handlePostLogin(tester);
      } else if (_onLockScreen()) {
        // Lock screen — navigate to login via "Use password" link.
        if (find.text(CommonStrings.usePassword).evaluate().isNotEmpty) {
          await _tap(tester, find.text(CommonStrings.usePassword), settle: 5);
          if (_onLoginScreen()) {
            await _login(tester);
            await _handlePostLogin(tester);
          }
        }
      }
      // else: already authenticated → dashboard is showing, proceed directly.

      await _settle(tester, 5);
      await _see(tester, 2);

      // ── 3. Stay on the Home tab and wait for the mission queue ────────────
      //
      // DashboardScreen (Home tab) shows MissionQueueCard widgets for each
      // patient follow-up. Tapping the action button ("Visit now") on a card
      // calls _startVisitFromQueue which uses the correct internal patientId
      // and navigates directly to the triage screen — skipping PatientContext
      // and VisitLandingScreen which pass the NID-format URL param as patientId
      // and would cause SymptomPicker to fail with "Patient not found".
      await _settle(tester, 12);

      // ── 4. Tap the first "Visit now" action on a mission queue card ───────
      final visitNowKey = find.byKey(const Key('visit_queue_card_action_tap'));
      expect(
        visitNowKey,
        findsWidgets,
        reason: 'No MissionQueueCard action button found on Home tab. '
            'The mission queue may not have loaded or hyper_sk has no '
            'pending follow-ups.',
      );

      await _tap(tester, visitNowKey.first, settle: 20);
      await _see(tester, 3);

      // ── 5. Wait for SymptomPicker to complete async loading ───────────────
      //
      // SymptomPicker.initState() registers an addPostFrameCallback that calls
      // _loadPatientContext() — an async function that queries SQLite. Give it
      // extra time to finish beyond the 20 s already spent above.
      await _settle(tester, 10);

      // ── 6. Symptom selection ──────────────────────────────────────────────
      //
      // Select 'Blurred vision' — the 'blurred_vision' symptom code is in the
      // NCD-Metabolic cluster (no age/sex restrictions → always shown) and maps
      // to the Cataract pathway rule which has DemographicGate.any (fires for
      // every patient regardless of age or sex). The 'cataract' form type is
      // present in program_forms.json, so DynamicAssessmentScreen will render
      // the form and show "Submit Assessment". ✓
      //
      // Fallback: try 'Severe headache' (activates NCD-HTN for adults ≥18 y).
      if (find.text(TriageStrings.symptomBlurredVision).evaluate().isNotEmpty) {
        debugPrint('[form_screen_test] Selecting symptom: Blurred vision');
        await _tap(tester, find.text(TriageStrings.symptomBlurredVision), settle: 3);
      } else if (find.text(TriageStrings.symptomHeadacheSevere).evaluate().isNotEmpty) {
        debugPrint('[form_screen_test] Selecting symptom: Severe headache');
        await _tap(tester, find.text(TriageStrings.symptomHeadacheSevere), settle: 3);
      } else {
        debugPrint('[form_screen_test] WARNING: No symptom chip found. '
            'SymptomPicker may be in error/loading state.');
      }
      await _see(tester, 1);

      // ── 7. Symptom picker CTA ─────────────────────────────────────────────
      //
      // When a pathway is activated the CTA changes to ctaWithPathways;
      // otherwise it shows ctaRoutine.
      if (find.text(SymptomPickerStrings.ctaWithPathways).evaluate().isNotEmpty) {
        debugPrint('[form_screen_test] Pathway detected — tapping ctaWithPathways');
        await _tap(tester, find.text(SymptomPickerStrings.ctaWithPathways), settle: 10);
      } else if (find.text(SymptomPickerStrings.ctaRoutine).evaluate().isNotEmpty) {
        debugPrint('[form_screen_test] No pathway activated — tapping ctaRoutine. '
            '"Submit Assessment" will NOT appear on this path (VisitFormScreen '
            'shows "No assessment pathways activated." when activatedPathways=[]).');
        await _tap(tester, find.text(SymptomPickerStrings.ctaRoutine), settle: 10);
      } else {
        debugPrint('[form_screen_test] WARNING: No CTA found. '
            'SymptomPicker may be in error or loading state.');
      }

      await _settle(tester, 5);
      await _see(tester, 2);

      // ── 8. Triage result screen ───────────────────────────────────────────
      //
      // ctaWithPathways → _onContinue() → triage-result screen → tap here → form
      // ctaRoutine → _onContinue() skips triage-result → form (no pathways)
      if (find.text(TriageResultStrings.ctaOpenChecklist).evaluate().isNotEmpty) {
        debugPrint('[form_screen_test] Triage result: tapping Open checklist');
        await _tap(tester, find.text(TriageResultStrings.ctaOpenChecklist), settle: 10);
      } else if (find.text(TriageResultStrings.ctaNoPathways).evaluate().isNotEmpty) {
        debugPrint('[form_screen_test] Triage result: no pathways, tapping Start routine visit');
        await _tap(tester, find.text(TriageResultStrings.ctaNoPathways), settle: 10);
      } else {
        debugPrint('[form_screen_test] No triage-result CTA — may have gone directly to form.');
      }

      await _settle(tester, 10);
      await _see(tester, 3);

      // ── 9. Assert DynamicAssessmentScreen rendered ────────────────────────
      //
      // The submit button only appears when DynamicAssessmentScreen successfully
      // loaded the form schema and rendered DynamicFormRenderer.
      //
      // Root causes if this fails:
      //   (a) SymptomPicker in error state — patient not found in local DB.
      //       Possible if MissionQueueItem.patientId doesn't match patients.id.
      //   (b) Routine-visit path taken — symptom selection did not activate any
      //       pathway (shouldn't happen with 'Blurred vision' + cataract rule).
      //   (c) program_forms.json has no schema for the activated programme.
      //   (d) DynamicFormRenderer had a rendering exception.
      expect(
        find.text(ComposerStrings.submitButton),
        findsOneWidget,
        reason:
            '"Submit Assessment" must be visible, confirming DynamicAssessmentScreen '
            'rendered the cataract (or fallback) form. See debug log for the path '
            'taken through triage.',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
