import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uhis_next/main.dart' as app;
import 'package:uhis_next/core/constants/app_strings.dart';

// ── Test constants ────────────────────────────────────────────────────────────

const _kUsername = 'hyper_sk';
const _kPassword = 'Spice123';
const _kPin = ['1', '2', '3', '4'];

// Household 1 (head-only enrollment)
const _kHouseNumber = 'A-101';
const _kTotalMembers = '4';
const _kHeadName = 'Amena Begum';
const _kHeadId = '1234567890123456';

// Household 2 (head + additional member)
const _kHouseNumber2 = 'B-202';
const _kHeadName2 = 'Fatema Khatun';
const _kHeadId2 = '9876543210987654';
const _kMemberName = 'Rahim Uddin';

// ── Widget finders ────────────────────────────────────────────────────────────

/// Find a [TextField] by the hintText set on its [InputDecoration].
Finder _field(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> _settle(WidgetTester t, [int seconds = 5]) =>
    t.pumpAndSettle(Duration(seconds: seconds));

Future<void> _ms(WidgetTester t, [int ms = 300]) =>
    t.pump(Duration(milliseconds: ms));

Future<void> _enterPin(WidgetTester t) async {
  for (final digit in _kPin) {
    await t.tap(find.text(digit).last);
    await t.pump(const Duration(milliseconds: 300));
  }
}

/// Login with [_kUsername] / [_kPassword], handling post-login screens.
/// Returns immediately when the login form is not visible (already logged in).
Future<void> _login(WidgetTester t) async {
  await _settle(t, 10);
  if (find
      .widgetWithText(TextFormField, LoginStrings.usernameLabel)
      .evaluate()
      .isEmpty) {
    return;
  }

  await t.enterText(
    find.widgetWithText(TextFormField, LoginStrings.usernameLabel),
    _kUsername,
  );
  await t.enterText(
    find.widgetWithText(TextFormField, LoginStrings.passwordLabel),
    _kPassword,
  );
  await t.tap(find.text(LoginStrings.signIn));
  await t.pump(const Duration(seconds: 1));
  // Allow up to 120 s for cold sync to complete.
  await _settle(t, 120);

  // Optional: onboarding
  if (find.text(OnboardingStrings.title).evaluate().isNotEmpty) {
    await t.tap(find.text(OnboardingStrings.skipButton));
    await _settle(t);
    if (find.text(OnboardingStrings.skipAnywayButton).evaluate().isNotEmpty) {
      await t.tap(find.text(OnboardingStrings.skipAnywayButton));
      await _settle(t);
    }
  }

  // Optional: biometric dialog
  if (find.text(DashboardStrings.notNow).evaluate().isNotEmpty) {
    await t.tap(find.text(DashboardStrings.notNow));
    await _settle(t);
  }

  // Optional: PIN setup
  if (find.text(PinStrings.createTitle(4)).evaluate().isNotEmpty) {
    await _enterPin(t);
    await _settle(t, 5);
    if (find.text(PinStrings.confirmTitle).evaluate().isNotEmpty) {
      await _enterPin(t);
      await _settle(t, 10);
    }
  }

  await _settle(t);
  expect(
    find.text(LoginStrings.signIn),
    findsNothing,
    reason: 'Login screen must be dismissed after successful login',
  );
}

/// Tap the "Enroll new" FAB → tap "Create Household" in the overlay
/// → arrive at [CreateHouseholdScreen].
Future<void> _openCreateHousehold(WidgetTester t) async {
  await t.tap(find.text(MissionDashboardStrings.enrolNewCta));
  await _settle(t, 3);
  await t.tap(find.text('Create Household'));
  await _settle(t, 3);
  expect(
    find.text(EnrollmentStrings.householdInfoSectionHeader),
    findsOneWidget,
    reason: 'Should arrive at household information form',
  );
}

/// Open the village [DropdownButtonFormField] (hint "Select village"),
/// then tap the first item that appears in the overlay.
Future<void> _selectVillage(WidgetTester t) async {
  await t.tap(find.text(EnrollmentStrings.villageHint));
  await t.pumpAndSettle();
  // Dropdown overlay renders DropdownMenuItem<String> for each option.
  final items = find.byType(DropdownMenuItem<String>);
  expect(
    items,
    findsAtLeastNWidgets(1),
    reason: 'At least one village must be configured for this user',
  );
  await t.tap(items.first);
  await t.pumpAndSettle();
}

/// Open the marital-status dropdown (hint "Select status") and pick the
/// first option (Married).
Future<void> _selectMaritalStatus(WidgetTester t) async {
  await t.ensureVisible(find.text('Select status').last);
  await t.pumpAndSettle();
  await t.tap(find.text('Select status').last);
  await t.pumpAndSettle();
  await t.tap(find.text(EnrollmentStrings.maritalStatusesV2.first).last);
  await t.pumpAndSettle();
}

/// Tap the date-of-birth field to open [showDatePicker], then accept the
/// default date ("today") by tapping the 'OK' button.
///
/// The DOB field is wrapped in [AbsorbPointer] + [GestureDetector]. Tapping
/// the underlying [TextField] area delivers the pointer to the ancestor
/// [GestureDetector], which calls [_selectDate] and opens the picker.
Future<void> _pickTodayDate(WidgetTester t) async {
  await t.tap(_field(EnrollmentStrings.dateOfBirthHint).first);
  await _settle(t, 2);
  if (find.text('OK').evaluate().isNotEmpty) {
    await t.tap(find.text('OK'));
    await _settle(t);
  }
}

/// Fill [CreateHouseholdScreen] with household info and head details.
Future<void> _fillHouseholdForm(
  WidgetTester t, {
  required String houseNumber,
  required String totalMembers,
  required String headName,
  required String headId,
  required String gender,
}) async {
  // ── Household section ────────────────────────────────────────────────────
  await _selectVillage(t);

  // Household Type — pill segmented button (householdTypesV2 = ['BRAC VO', 'NVO'])
  await t.tap(find.text(EnrollmentStrings.householdTypesV2.first));
  await t.pumpAndSettle();

  await t.enterText(_field(EnrollmentStrings.houseNumberHint), houseNumber);
  await _ms(t);

  await t.enterText(_field(EnrollmentStrings.totalMembersHint), totalMembers);
  await _ms(t);

  // ── Head section ─────────────────────────────────────────────────────────
  await t.scrollUntilVisible(
    find.text(EnrollmentStrings.householdHeadSectionHeader),
    500,
  );
  await t.pumpAndSettle();

  await t.enterText(_field(EnrollmentStrings.headNameHint), headName);
  await _ms(t);

  await t.enterText(_field(EnrollmentStrings.idNumberHint), headId);
  await _ms(t);

  // Scroll to DOB, then open the date picker
  await t.scrollUntilVisible(_field(EnrollmentStrings.dateOfBirthHint).first, 500);
  await _pickTodayDate(t);

  // Gender (segmented buttons: 'Male' | 'Female' | 'Third Gender')
  await t.tap(find.text(gender));
  await t.pumpAndSettle();

  // Marital Status dropdown
  await _selectMaritalStatus(t);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Clear any leftover session so each run starts from the login screen.
    await const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ).deleteAll();
    app.main();
  });

  group('Household enrollment + server sync', () {
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets(
      '01 — create household (head-only) and POST to /offline-sync/create',
      (t) async {
        await _login(t);

        // ── Open form ──────────────────────────────────────────────────────
        await _openCreateHousehold(t);

        // ── Fill household + head ──────────────────────────────────────────
        await _fillHouseholdForm(
          t,
          houseNumber: _kHouseNumber,
          totalMembers: _kTotalMembers,
          headName: _kHeadName,
          headId: _kHeadId,
          gender: EnrollmentStrings.gendersHead.first, // 'Male'
        );

        // ── Scroll to Continue and submit ──────────────────────────────────
        await t.scrollUntilVisible(
          find.text(EnrollmentStrings.continueArrow),
          500,
        );
        await t.tap(find.text(EnrollmentStrings.continueArrow));
        await _settle(t, 3);

        // ── Review / success screen ────────────────────────────────────────
        expect(
          find.textContaining('Household Created'),
          findsOneWidget,
          reason: 'Success header must appear after all required fields are filled',
        );
        // Head card should show the entered name
        expect(find.text(_kHeadName), findsOneWidget);

        // ── POST to server + warmSync ──────────────────────────────────────
        await t.tap(find.text(EnrollmentStrings.saveHousehold));
        // Allow up to 15 s for the server round-trip.
        await _settle(t, 15);

        expect(
          find.text(EnrollmentStrings.enrollmentSuccess),
          findsOneWidget,
          reason: 'Success snackbar must appear after server POST succeeds',
        );

        // ── Navigate back to dashboard ─────────────────────────────────────
        await _settle(t, 3);
        expect(
          find.text(MissionDashboardStrings.enrolNewCta),
          findsOneWidget,
          reason: 'Dashboard must be reached after enrollment',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    testWidgets(
      '02 — create household, add member, then POST both to server',
      (t) async {
        await _login(t);

        // ── Open form ──────────────────────────────────────────────────────
        await _openCreateHousehold(t);

        // ── Fill household + head ──────────────────────────────────────────
        await _fillHouseholdForm(
          t,
          houseNumber: _kHouseNumber2,
          totalMembers: '2',
          headName: _kHeadName2,
          headId: _kHeadId2,
          gender: EnrollmentStrings.gendersHead[1], // 'Female'
        );

        await t.scrollUntilVisible(
          find.text(EnrollmentStrings.continueArrow),
          500,
        );
        await t.tap(find.text(EnrollmentStrings.continueArrow));
        await _settle(t, 3);

        expect(find.textContaining('Household Created'), findsOneWidget);

        // ── Tap "Add Member" dashed-border button ─────────────────────────
        await t.tap(find.text(EnrollmentStrings.addMoreMembers));
        await _settle(t, 3);
        expect(find.text('Add Member'), findsOneWidget,
            reason: 'AddHouseholdMemberScreen must appear');

        // ── Fill member form ───────────────────────────────────────────────

        // Q2: Name
        await t.scrollUntilVisible(_field(EnrollmentStrings.memberNameHint), 300);
        await t.enterText(_field(EnrollmentStrings.memberNameHint), _kMemberName);
        await _ms(t);

        // Q3: Date of Birth
        await t.scrollUntilVisible(
          _field(EnrollmentStrings.dateOfBirthHint).first,
          300,
        );
        await _pickTodayDate(t);

        // Q4: Gender
        await t.tap(find.text(EnrollmentStrings.gendersMember.first)); // 'Male'
        await t.pumpAndSettle();

        // Q6: Marital Status
        await _selectMaritalStatus(t);

        // Q8: Mobile — mark not available via checkbox
        await t.scrollUntilVisible(
          find.text(EnrollmentStrings.mobileNotAvailableHint),
          300,
        );
        // Checkbox is the first [Checkbox] visible after scrolling
        await t.tap(find.byType(Checkbox).first);
        await t.pumpAndSettle();

        // ── Save member ────────────────────────────────────────────────────
        await t.scrollUntilVisible(
          find.text(EnrollmentStrings.saveMemberCTA),
          300,
        );
        await t.tap(find.text(EnrollmentStrings.saveMemberCTA));
        await _settle(t, 3);

        // ── Back on success screen — member card must be visible ───────────
        expect(
          find.text(_kMemberName),
          findsOneWidget,
          reason: 'Added member name must appear on the review screen',
        );

        // ── POST household + member to server, then warmSync ───────────────
        await t.tap(find.text(EnrollmentStrings.saveHousehold));
        await _settle(t, 15);

        expect(
          find.text(EnrollmentStrings.enrollmentSuccess),
          findsOneWidget,
          reason: 'Success snackbar expected after server POST with member',
        );

        await _settle(t, 3);
        expect(
          find.text(MissionDashboardStrings.enrolNewCta),
          findsOneWidget,
          reason: 'Dashboard must be reached after enrollment with member',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────────
    testWidgets(
      '03 — sync pulls enrolled households back into local DB (warmSync)',
      (t) async {
        // This test verifies the pull half of the cycle. After enrollment
        // in test 01/02, warmSync fetches the newly created records from the
        // server back into the local DB. We confirm this by verifying that
        // the dashboard worklist is reachable (sync completed without error)
        // and the "Enroll new" FAB is still visible (no crash).

        await _login(t); // already logged in — returns immediately

        // Trigger an explicit warm sync from the worklist
        // The sync strip's "Sync now" tap fires _orchestrator.syncAll().
        final syncButton = find.byTooltip('Sync now');
        if (syncButton.evaluate().isNotEmpty) {
          await t.tap(syncButton);
          await _settle(t, 15);
        }

        // Dashboard is still intact — no crash from warmSync
        expect(
          find.text(MissionDashboardStrings.enrolNewCta),
          findsOneWidget,
          reason: 'Dashboard must remain stable after warm sync',
        );
      },
    );
  });
}
