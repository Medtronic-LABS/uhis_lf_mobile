# App-Wide Translation & Localization-Seam Gap Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every remaining Bangla-localization gap and localization-seam structural bug across the whole `uhis_lf_mobile` app that two prior translation-fixing rounds this session did not cover, plus delete confirmed-dead code discovered along the way.

**Architecture:** This app centralizes all user-facing copy behind one seam: `getTranslatedString(String code, String fallback, {Map<String,String>? params})` in `lib/core/constants/app_strings.dart`, which looks `code` up in `assets/translations/strings.json` for the live locale and falls back to the English `fallback` argument when the code is absent. Every fix in this plan either (a) routes a raw literal through a new or existing `static String get`/method on the screen's `abstract final class XxxStrings`, (b) converts a `static const String`/`List<String>` holding user-facing text into a `static String get`/method (Dart's const-expression rule forbids a `const` field from calling a function), or (c) deletes confirmed-dead code. Seven parallel research passes (household/patient/search/settings, auth-adjacent screens, worklist/referral/training/misc features, scribe/realtime_asr/shared widgets, dashboard, visit remainder, and a structural re-audit of `app_strings.dart` + core services) produced the exhaustive findings this plan is built from.

**Tech Stack:** Flutter/Dart, `lib/core/constants/app_strings.dart` localization seam, `assets/translations/strings.json`.

## Global Constraints

- No hardcoded user-facing strings in any widget/service — every literal routes through an `AppStrings` getter (per `../../CLAUDE.md` Engineering Design Standards, Localization).
- A `static const String`/`List<String>` can never hold user-facing text, because Dart forbids `const` initializers from calling functions like `getTranslatedString` — convert to `static String get` / `static List<String> get`.
- Every new getter's English fallback text must be **byte-identical** to the literal it replaces — zero behavior change in English; Bangla only activates once `strings.json` has the entry.
- Do **not** add `strings.json` entries for brand-new getters created purely by relocating existing English literals in this plan (Tasks 1–13) — matches the established "missing key = pending translator" convention from the prior two rounds. The **one exception** is Task 14, which explicitly authors Bangla for a distinct, older category of pre-existing gaps per the user's standing instruction this session ("add Bangla for all of it now").
- Reuse an existing `...Strings` class in the same file whenever one is already used there; only introduce a new class if a file genuinely has none.
- No dead code — confirmed-dead getters/fields (Task 11) get deleted, not migrated.
- Preserve established Bangla vocabulary already in `strings.json`: রেফারেল/রেফার (referral/refer), রক্তচাপ (blood pressure), রক্তে গ্লুকোজ/শর্করা (blood glucose/sugar), রক্তাল্পতা (anemia), গর্ভাবস্থা (pregnancy), প্রসবপূর্ব/প্রসবোত্তর (antenatal/postnatal), টিকা/টিকাদান (vaccine/immunization), যক্ষ্মা (TB), জরুরি (urgent).
- `{paramName}` is the placeholder convention for interpolated values in `strings.json` entries — never Dart's `$paramName`/`${...}` syntax, which only belongs in the Dart-side `fallback` argument.

---

### Task 1: Systemic auth/network error localization + auth-adjacent screen literals

**Files:**
- Modify: `lib/core/errors/domain_exceptions.dart:104,106,108,122,124,125,126,130`
- Modify: `lib/core/auth/auth_repository.dart:236,275,603`
- Modify: `lib/features/lock/lock_screen.dart:632`
- Modify: `lib/features/login/login_screen.dart:349-351`
- Modify: `lib/features/pin/pin_unlock_screen.dart:66`
- Modify: `lib/features/training/training_screen.dart:52`
- Modify: `lib/core/constants/app_strings.dart` (add a new `NetworkErrorStrings` class; add 3 getters to `AuthStrings`; add 1 getter each to `LockStrings`, `LoginStrings`, `PinStrings`, `TrainingStrings`)
- Test: `test/core/errors/network_error_mapper_test.dart` (new)

**Interfaces:**
- Produces: `NetworkErrorStrings.connectionTimedOut`, `.requestCancelled`, `.noInternet`, `.accessDenied`, `.notFound`, `.serverBusy`, `.serverError`, `.somethingWentWrong` — all `static String get`.
- Produces: `AuthStrings.invalidCredentials`, `.tenantIdMissing`, `.noActiveSessionToEnrol` — all `static String get`.

`NetworkErrorMapper` (in `domain_exceptions.dart`) is the single choke point for every network/auth failure shown in login, lock, PIN, scribe, and assistant screens — its own doc comment already claims messages are "mapped to localized messages via `AppStrings`," but every method returns a raw English literal. This is the highest-blast-radius fix in this plan.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/errors/network_error_mapper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/errors/domain_exceptions.dart';

void main() {
  group('NetworkErrorMapper localization', () {
    tearDown(() => AppLocale.current = AppLanguage.english);

    test('connection timeout message is routed through AppStrings, not hardcoded', () {
      AppLocale.current = AppLanguage.english;
      final englishMsg = NetworkErrorMapper.friendly(
        DioExceptionType.connectionTimeout as Object,
      );
      expect(englishMsg, isNotEmpty);
      // The message must come from a getter, not a raw literal — verified by
      // confirming the same call under a Bangla locale can differ once a
      // strings.json entry exists (it currently doesn't, so both equal the
      // English fallback — this assertion only proves the code PATH is a
      // getter call, checked via the source-level Task 1 refactor, not by
      // behavior alone).
      AppLocale.current = AppLanguage.bangla;
      final banglaMsg = NetworkErrorMapper.friendly(
        DioExceptionType.connectionTimeout as Object,
      );
      expect(banglaMsg, isNotEmpty);
    });
  });
}
```

Run: `flutter test test/core/errors/network_error_mapper_test.dart -v`
Expected: This test passes trivially even before the fix (both branches return the same English string) — its real value is Step 4's manual confirmation that the source now calls `getTranslatedString`. Since `NetworkErrorMapper`'s exact exception-classification API isn't fully known from outside the file, don't over-invest in this test — treat it as a smoke test, and rely on the source-level diff + `flutter analyze` + the full suite diff (Task 15) as the real verification for this task, consistent with how localization-seam fixes were verified in this session's prior two rounds.

- [ ] **Step 2: Read the current file and confirm the exact exception-classification signature**

Run: `grep -n "static String friendly\|static String _fromDio\|static String _fromStatusCode\|static String _generic" lib/core/errors/domain_exceptions.dart`

Use the exact method signatures found to keep Step 3's diff minimal — do not change the classification logic, only the returned strings.

- [ ] **Step 3: Add `NetworkErrorStrings` and `AuthStrings` getters, then wire them in**

In `lib/core/constants/app_strings.dart`, add a new class (place it near `AuthStrings`):

```dart
abstract final class NetworkErrorStrings {
  NetworkErrorStrings._();
  static String get connectionTimedOut => getTranslatedString(
      'NetworkError.connectionTimedOut', 'Connection timed out. Check your signal and try again.');
  static String get requestCancelled => getTranslatedString(
      'NetworkError.requestCancelled', 'Request was cancelled. Please try again.');
  static String get noInternet => getTranslatedString(
      'NetworkError.noInternet', 'No internet connection. Check your signal and try again.');
  static String get accessDenied => getTranslatedString(
      'NetworkError.accessDenied', 'Access denied. Please log out and log back in.');
  static String get notFound => getTranslatedString(
      'NetworkError.notFound', 'The requested data was not found.');
  static String get serverBusy => getTranslatedString(
      'NetworkError.serverBusy', 'Server is busy. Please try again in a moment.');
  static String get serverError => getTranslatedString(
      'NetworkError.serverError', 'Server error. Please try again in a moment.');
  static String get somethingWentWrong => getTranslatedString(
      'NetworkError.somethingWentWrong', 'Something went wrong. Please try again.');
}
```

Add to the existing `AuthStrings` class:

```dart
static String get invalidCredentials => getTranslatedString('Auth.invalidCredentials', 'Invalid credentials');
static String get tenantIdMissing => getTranslatedString('Auth.tenantIdMissing', 'Login response missing tenantId');
static String get noActiveSessionToEnrol => getTranslatedString('Auth.noActiveSessionToEnrol', 'No active session to enrol');
```

In `lib/core/errors/domain_exceptions.dart`, add the import `import 'package:uhis_lf_mobile/core/constants/app_strings.dart';` and replace each raw literal at lines 104, 106, 108, 122, 124, 125, 126, 130 with its matching `NetworkErrorStrings.*` getter (e.g. line 104's `'Connection timed out. Check your signal and try again.'` becomes `NetworkErrorStrings.connectionTimedOut`).

In `lib/core/auth/auth_repository.dart`, add the same import and replace:
- Line 236: `'Invalid credentials'` → `AuthStrings.invalidCredentials`
- Line 275: `'Login response missing tenantId'` → `AuthStrings.tenantIdMissing`
- Line 603: `'No active session to enrol'` → `AuthStrings.noActiveSessionToEnrol`

- [ ] **Step 4: Fix the three remaining auth-adjacent screen literals**

`lib/features/lock/lock_screen.dart:632` — add `LockStrings.fingerprintSemanticLabel` (`getTranslatedString('Lock.fingerprintSemanticLabel', 'Authenticate with fingerprint')`) and replace the raw `Semantics(label: 'Authenticate with fingerprint', ...)` literal with it.

`lib/features/login/login_screen.dart:349-351` — add two getters to `LoginStrings`: `showPasswordTooltip` (`'Show password'`) and `hidePasswordTooltip` (`'Hide password'`), then change:
```dart
tooltip: _obscurePassword
    ? LoginStrings.showPasswordTooltip
    : LoginStrings.hidePasswordTooltip,
```

`lib/features/pin/pin_unlock_screen.dart:66` — add `PinStrings.backTooltip` (`getTranslatedString('Pin.backTooltip', 'Back')`) and replace `tooltip: 'Back'` with it.

`lib/features/training/training_screen.dart:52` — this screen already uses `CommonStrings.retry` correctly for its retry button, but line 52 (`Text(_error!, textAlign: TextAlign.center)`) renders the raw `e.toString()` exception message directly instead of a translated generic error. Add `TrainingStrings.loadFailedGeneric` (`getTranslatedString('Training.loadFailedGeneric', 'Something went wrong loading this content.')` — check first whether `TrainingStrings` already has a suitable generic error getter from the earlier round; reuse it if so) and change line 52 to render that getter instead of `_error!` (the raw exception can still be logged via `ConsoleLog`, just not shown to the user).

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/core/errors/domain_exceptions.dart lib/core/auth/auth_repository.dart lib/features/lock/lock_screen.dart lib/features/login/login_screen.dart lib/features/pin/pin_unlock_screen.dart lib/features/training/training_screen.dart lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/core/errors/network_error_mapper_test.dart -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/errors/domain_exceptions.dart lib/core/auth/auth_repository.dart lib/features/lock/lock_screen.dart lib/features/login/login_screen.dart lib/features/pin/pin_unlock_screen.dart lib/features/training/training_screen.dart lib/core/constants/app_strings.dart test/core/errors/network_error_mapper_test.dart
git commit -m "fix(i18n): route NetworkErrorMapper and auth-adjacent screen literals through AppStrings"
```

---

### Task 2: Household detail + patient enrollment screens, and the duplicated month-name-array bug

**Files:**
- Modify: `lib/features/household/household_detail_screen.dart:789`
- Modify: `lib/features/patient/enroll/programme_enroll_screen.dart:71,407-409,516,566`
- Modify: `lib/features/patient/patient_actions_row.dart:102,128`
- Modify: `lib/features/patient/enroll/pregnancy_registration_sheet.dart:382-397`
- Modify: `lib/core/widgets/gestational_age_card.dart:28-34`
- Modify: `lib/features/dashboard/widgets/follow_ups_due_widget.dart:199-209`
- Modify: `lib/core/constants/app_strings.dart` (add `HouseholdDetailStrings.addMember`; add getters to `EnrollStrings`, `PatientContextStrings`; add a new shared `DateFormatStrings` class)
- Test: `test/core/constants/date_format_strings_test.dart` (new)

**Interfaces:**
- Produces: `DateFormatStrings.monthAbbrev(int month)` — `static String` taking a 1-indexed month number, returning the localized 3-letter abbreviation. Consumed by Task 2's three call sites AND available for any future date-formatting need — this is the DRY fix for a month-name array that was independently duplicated in three files.

The month-abbreviation array (`'Jan'`, `'Feb'`, … `'Dec'`) is hardcoded identically in THREE places (`pregnancy_registration_sheet.dart`, `gestational_age_card.dart`, `follow_ups_due_widget.dart`) — a DRY violation as well as a translation gap. Fix it once, centrally.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/constants/date_format_strings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('monthAbbrev returns the English 3-letter abbreviation for each month', () {
    AppLocale.current = AppLanguage.english;
    const expected = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    for (var m = 1; m <= 12; m++) {
      expect(DateFormatStrings.monthAbbrev(m), expected[m - 1]);
    }
  });

  test('monthAbbrev falls back to English when no Bangla translation is present yet', () {
    AppLocale.current = AppLanguage.bangla;
    expect(DateFormatStrings.monthAbbrev(1), 'Jan');
  });
}
```

Run: `flutter test test/core/constants/date_format_strings_test.dart -v`
Expected: FAIL with "Undefined name 'DateFormatStrings'"

- [ ] **Step 2: Add the shared `DateFormatStrings` class**

In `lib/core/constants/app_strings.dart`:

```dart
abstract final class DateFormatStrings {
  DateFormatStrings._();

  static const _codes = [
    'DateFormat.monthJan', 'DateFormat.monthFeb', 'DateFormat.monthMar',
    'DateFormat.monthApr', 'DateFormat.monthMay', 'DateFormat.monthJun',
    'DateFormat.monthJul', 'DateFormat.monthAug', 'DateFormat.monthSep',
    'DateFormat.monthOct', 'DateFormat.monthNov', 'DateFormat.monthDec',
  ];
  static const _fallbacks = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// [month] is 1-indexed (1 = January).
  static String monthAbbrev(int month) =>
      getTranslatedString(_codes[month - 1], _fallbacks[month - 1]);
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `flutter test test/core/constants/date_format_strings_test.dart -v`
Expected: PASS

- [ ] **Step 4: Wire the three call sites to `DateFormatStrings.monthAbbrev`**

`lib/features/patient/enroll/pregnancy_registration_sheet.dart:382-397` — replace the `_monthName(int m)` function body's array indexing with `DateFormatStrings.monthAbbrev(m)`.

`lib/core/widgets/gestational_age_card.dart:28-34` — delete the `static const _months = [...]` list; in `_fmt()` (line 33-34), replace the indexed literal lookup with `DateFormatStrings.monthAbbrev(date.month)`.

`lib/features/dashboard/widgets/follow_ups_due_widget.dart:199-209` — same transform in `_formatDate`. Note lines 208-209 in the same method also have two raw literals in the *fallback* branches of an otherwise-localized function: `'${-daysUntil} days ago'` and `'Yesterday'`. Add two getters to `MissionDashboardStrings` — `daysAgo(int n)` (`getTranslatedString('MissionDashboard.daysAgo', '{n} days ago', params: {'n': '$n'})`) and `yesterday` (`getTranslatedString('MissionDashboard.yesterday', 'Yesterday')`) — and use them in place of the raw literals, consistent with the other branches in the same method (`.today`, `.tomorrow`, `.daysAway(daysUntil)`) that already call `MissionDashboardStrings`.

- [ ] **Step 5: Fix the remaining literals in this task's other files**

`lib/features/household/household_detail_screen.dart:789` — add `HouseholdDetailStrings.addMember` (`getTranslatedString('HouseholdDetail.addMember', 'Add Member')`) and replace `label: 'Add Member',`.

`lib/features/patient/enroll/programme_enroll_screen.dart`:
- Line 71: replace `parts.add('Age $_age');` with `parts.add(EnrollStrings.ageChip(_age));` — add `EnrollStrings.ageChip(int age) => getTranslatedString('Enroll.ageChip', 'Age {age}', params: {'age': '$age'});`.
- Lines 407-409 and 516: these ternaries exist because `EnrollStrings.pregnantWomanBengali` and the `*Bengali` sibling fields are `static const String` (can't call `getTranslatedString`). Convert `EnrollStrings.pregnantWomanBengali`, `.ancBengali`, `.pncBengali`, `.ncdBengali`, `.imciBengali`, `.epiBengali` from `static const String` to `static String get`, each still returning its current hardcoded Bangla text via a direct `getTranslatedString('Enroll.xxxBengali', '<existing Bangla text>')` call (this is a structural fix, not a new translation — the Bangla text already exists, it just needs to reach the seam). Once converted, the `AppLocale.isBangla ? X : Y` ternaries at both call sites can stay as-is (both branches are now proper getters) — **do not** delete the ternary itself, since this screen intentionally shows the dual-language tile pattern (same as `LockStrings`'s wordmark), it just needed both sides to be seam-routed.
- Line 566: add `EnrollStrings.selectedCount(int n)` (`getTranslatedString('Enroll.selectedCount', '{n} selected', params: {'n': '$n'})`) and replace `Text('$selectedCount selected', ...)`.

`lib/features/patient/patient_actions_row.dart`:
- Line 102: add `PatientContextStrings.startVisitFailed` (`getTranslatedString('PatientContext.startVisitFailed', 'Failed to start visit')`) and replace `controller.error ?? 'Failed to start visit'`.
- Line 128: add `PatientContextStrings.startingEllipsis` (`getTranslatedString('PatientContext.startingEllipsis', 'Starting...')`) and replace the `'Starting...'` branch of the ternary.

- [ ] **Step 6: Verify**

Run: `flutter analyze lib/features/household/household_detail_screen.dart lib/features/patient/enroll/programme_enroll_screen.dart lib/features/patient/patient_actions_row.dart lib/features/patient/enroll/pregnancy_registration_sheet.dart lib/core/widgets/gestational_age_card.dart lib/features/dashboard/widgets/follow_ups_due_widget.dart lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/core/constants/date_format_strings_test.dart -v`
Expected: PASS (all tests).

- [ ] **Step 7: Commit**

```bash
git add lib/features/household/household_detail_screen.dart lib/features/patient/enroll/ lib/features/patient/patient_actions_row.dart lib/core/widgets/gestational_age_card.dart lib/features/dashboard/widgets/follow_ups_due_widget.dart lib/core/constants/app_strings.dart test/core/constants/date_format_strings_test.dart
git commit -m "fix(i18n): consolidate month-name duplication and fix household/enrollment literals"
```

---

### Task 3: Localize `referral_narrative.dart`

**Files:**
- Modify: `lib/features/patient/referral_narrative.dart` (entire file — no `app_strings.dart` import currently exists)
- Modify: `lib/core/constants/app_strings.dart` (extend the existing `ReferralStrings` class, `lib/core/constants/app_strings.dart:987`)
- Test: `test/features/patient/referral_narrative_test.dart` (new, or extend if one already exists — check first)

**Interfaces:**
- Produces: `ReferralStrings.shortReasonBloodGlucoseElevated`, `.shortReasonAbnormalPulse`, `.shortReasonHighBp`, `.shortReasonLowHbAnemia`, `.shortReasonDangerSign`, `.shortReasonElevatedTemp`, `.shortReasonLowWeight`, `.shortReasonLowAdherence`, `.shortReasonNoFpMethod`, `.shortReasonSupplementGap`, `.shortReasonVisitOverdue`, `.shortReasonClinicalSymptoms` — all `static String get`, consumed by `shortReasonLabel()`.
- Produces: narrative-sentence getters/methods on `ReferralStrings` consumed by `buildReferralNarrative()` (see Step 3).

This whole file is a genuine gap: it never imports `app_strings.dart`, so every clinical narrative sentence it builds is permanently English. It's consumed by `patient_context_screen.dart` (already fixed for its OWN literals in an earlier round, but this file's output flows through it untouched).

- [ ] **Step 1: Check for an existing test file**

Run: `find test -iname "*referral_narrative*"`
If a test file exists, read it fully and extend it in Step 2 below instead of creating a new one — do not create a duplicate test file.

- [ ] **Step 2: Write the failing test**

```dart
// test/features/patient/referral_narrative_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/features/patient/referral_narrative.dart';

void main() {
  group('shortReasonLabel routes through ReferralStrings', () {
    test('returns the same English text as before for a known code', () {
      // Use whatever finding-code constant this file's shortReasonLabel()
      // already switches on for "High BP" (read the file first — do not
      // guess the exact parameter type/signature; match what's there).
      expect(shortReasonLabel('highBp'), 'High BP');
    });
  });
}
```

Run: `flutter test test/features/patient/referral_narrative_test.dart -v`
Expected: This should currently PASS (the literal is already `'High BP'`) — the point of this test is to lock the byte-identical English text in place BEFORE the refactor, so Step 4's verification catches any accidental wording drift. Read `referral_narrative.dart` first to get `shortReasonLabel`'s real signature (parameter name/type) and adjust this test to match exactly — do not invent a signature.

- [ ] **Step 3: Add `ReferralStrings` getters and rewrite `referral_narrative.dart`**

In `lib/core/constants/app_strings.dart`, extend `ReferralStrings` (existing class at line 987) with one getter per literal found in `shortReasonLabel()` (lines 48,49,53,59,61,63,66,69,74,80,83,85) and one getter/method per sentence in `buildReferralNarrative()` (lines 128-130,141,143-144,147,158-159,161,171-173,175,187,189,199-200,202,212,214,220,225,230,235,240-241,253). For each, the pattern is identical to every other fix in this plan:

```dart
static String get shortReasonBloodGlucoseElevated =>
    getTranslatedString('Referral.shortReasonBloodGlucoseElevated', 'Blood glucose elevated');
static String get shortReasonAbnormalPulse =>
    getTranslatedString('Referral.shortReasonAbnormalPulse', 'Abnormal pulse');
// ... one per remaining shortReasonLabel() literal, same shape
```

For narrative sentences that interpolate a value (e.g. `'Danger sign reported: $dSign.'`), use `params`:

```dart
static String dangerSignReported(String dSign) => getTranslatedString(
    'Referral.dangerSignReported', 'Danger sign reported: {dSign}.', params: {'dSign': dSign});
static String get dangerSignReportedGeneric => getTranslatedString(
    'Referral.dangerSignReportedGeneric', 'Danger sign reported — urgent attention required.');
```

In `referral_narrative.dart`, add `import 'package:uhis_lf_mobile/core/constants/app_strings.dart';` and replace every literal listed above with its matching `ReferralStrings` getter/method call, preserving the exact existing branching logic (only the returned string changes, not the conditions).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/patient/referral_narrative_test.dart -v`
Expected: PASS — proves the English output is unchanged after the refactor.

- [ ] **Step 5: Full-file verify**

Run: `flutter analyze lib/features/patient/referral_narrative.dart lib/core/constants/app_strings.dart`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/patient/referral_narrative.dart lib/core/constants/app_strings.dart test/features/patient/referral_narrative_test.dart
git commit -m "fix(i18n): route referral_narrative.dart through ReferralStrings"
```

---

### Task 4: Worklist, referral, and mission-service fallback/notification literals

**Files:**
- Modify: `lib/features/worklist/worklist_repository.dart:106`
- Modify: `lib/features/referral/referral_repository.dart:425-436,438-442,477,514`
- Modify: `lib/core/mission/mission_dashboard_service.dart:371-373,471,483,491,621-622,631,669,705-746`
- Modify: `lib/core/mission/programme_reason.dart:40,45`
- Modify: `lib/core/constants/app_strings.dart` (add getters to `WorklistStrings`, `ReferralStrings`, `MissionDashboardStrings`)
- Test: `test/core/mission/mission_dashboard_service_driver_insight_test.dart` (new)

**Interfaces:**
- Produces: `WorklistStrings.unnamedPatient` — `static String get`.
- Produces: `MissionDashboardStrings.driverInsight(String tag, {String? days})` — mirrors the already-fixed `driverLabel(tag)` sibling; same switch keys (`'sla-breached'`, `'child-under-5'`, `'pregnancy'`, `'overdue'`, `'referral'`, `'follow-up'`, etc.).

`referral_repository.dart` currently hardcodes near-duplicate notification copy even though `ReferralStrings.notifCriticalTitle`/`.notifWarningTitle`/`.notifCompletionTitle`/`.notifCriticalBody`/`.notifWarningBody`/`.notifCompletionBody` already exist and are unused by this file — reuse them instead of adding new ones. `mission_dashboard_service.dart`'s `_driverToInsight()` (lines 705-746) is an un-fixed twin of the `driverLabel` switch bug already fixed once this session for a sibling getter — same pattern, different method.

- [ ] **Step 1: Write the failing test for the `driverInsight` twin-bug fix**

```dart
// test/core/mission/mission_dashboard_service_driver_insight_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('driverInsight returns the existing English sentence for a known tag', () {
    AppLocale.current = AppLanguage.english;
    expect(
      MissionDashboardStrings.driverInsight('sla-breached'),
      'SLA breached — immediate action required.',
    );
  });

  test('driverInsight falls back gracefully for an unknown tag', () {
    AppLocale.current = AppLanguage.english;
    expect(MissionDashboardStrings.driverInsight('unknown-tag'), isNotEmpty);
  });
}
```

Run: `flutter test test/core/mission/mission_dashboard_service_driver_insight_test.dart -v`
Expected: FAIL with "The method 'driverInsight' isn't defined"

- [ ] **Step 2: Read `_driverToInsight()` in full to get the exact tag→sentence mapping**

Run: `grep -n "_driverToInsight\|_buildAiInsight" -A 40 lib/core/mission/mission_dashboard_service.dart | head -80`

Use the exact tags and sentences found (the task description lists them from research, but confirm exact wording/branching against the live file before writing the getter, since research summaries can compress detail).

- [ ] **Step 3: Add `MissionDashboardStrings.driverInsight` and wire it in**

Add to `MissionDashboardStrings` in `app_strings.dart`, mirroring the existing `driverLabel(tag)` getter's structure exactly (same switch keys, same fallback-default shape) — one `getTranslatedString('MissionDashboard.driverInsight.<tag>', '<exact sentence>')` call per case, using `params: {'days': '$days'}` for the one interpolated case (`'Overdue by $days days.'`).

In `mission_dashboard_service.dart`, replace the body of `_driverToInsight()` (or `_buildAiInsight`, whichever is the actual method per Step 2) to call `MissionDashboardStrings.driverInsight(key, days: ...)` instead of returning raw literals.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/mission/mission_dashboard_service_driver_insight_test.dart -v`
Expected: PASS

- [ ] **Step 5: Fix the remaining literals in this task**

`lib/features/worklist/worklist_repository.dart:106` — add `WorklistStrings.unnamedPatient` (`getTranslatedString('Worklist.unnamedPatient', '(Unnamed patient)')`), import `app_strings.dart` in this file, replace `p.name ?? '(Unnamed patient)'`.

`lib/features/referral/referral_repository.dart`:
- Lines 425-436 (`_titleFor`) — replace the 4 raw literals with `ReferralStrings.notifCriticalTitle`/`.notifWarningTitle`/`.notifCompletionTitle`, and for the `default` case add one new getter `ReferralStrings.notifGenericTitle` (`'Referral update'`) since no existing getter covers it.
- Lines 438-442 (`_bodyFor`) — add `ReferralStrings.notifDefaultBody` (`'Open referral needs your attention.'`) for the empty-drivers fallback.
- Line 477 — add `ReferralStrings.escalatedToLevel(int level)` (`getTranslatedString('Referral.escalatedToLevel', 'Escalated to level {level}', params: {'level': '$level'})`), replace `reason ?? 'Escalated to level $newLevel'`.
- Line 514 — add `ReferralStrings.bulkClosedBy(String actor)` (`getTranslatedString('Referral.bulkClosedBy', 'Bulk closed by {actor}', params: {'actor': actor})`), replace `reason ?? 'Bulk closed by $actor'`.

`lib/core/mission/mission_dashboard_service.dart`:
- Lines 371-373 — add `MissionDashboardStrings.memberFallback` (`'Member'`) and `.checkUpFallback` (`'Check-up'`), replace `member.role ?? 'Member'` and the `'Check-up'` branch.
- Line 621-622 — add `MissionDashboardStrings.patientIdShort(String id)` / `.patientIdFull(String id)` (or reuse one param'd getter with a pre-truncated string, matching whichever form the existing code already computes), replace both fallback branches.
- Line 631 — add `MissionDashboardStrings.referralFallback` (`'Referral'`), replace `referral.diagnosisLabel ?? 'Referral'`.
- Line 669 — add `MissionDashboardStrings.followUpDueFallback` (`'Follow-up due'`), replace `followUp.reason ?? 'Follow-up due'`.
- Lines 471,483,491 (`_buildRiskFactors`) — add `MissionDashboardStrings.riskReferralOverdue(int days)`, `.riskPatientsWaiting(int n)`, `.riskMissedFollowUps(int n)`, each with a `{n}`/`{days}` param, replace the three `factors.add(...)` raw-literal calls.

`lib/core/mission/programme_reason.dart:40,45` — add `MissionDashboardStrings.dueSuffix` (`getTranslatedString('MissionDashboard.dueSuffix', 'due')`), replace both trailing `'due'`/`'Due'` literals (note the capitalization difference at line 45 — check whether that's meaningful title-case or an inconsistency; if the latter, standardize both to use the same getter and let the call site decide casing via `.toUpperCase()`/similar if needed, don't silently change visible casing without checking the two render contexts first).

- [ ] **Step 6: Verify**

Run: `flutter analyze lib/features/worklist/worklist_repository.dart lib/features/referral/referral_repository.dart lib/core/mission/mission_dashboard_service.dart lib/core/mission/programme_reason.dart lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/core/mission/ -v`
Expected: All pass, including the new test and any pre-existing `mission_dashboard_service_tier_test.dart` (note: that file has one pre-existing, unrelated failing test in the baseline — confirm your change doesn't add a NEW failure, per Task 15's baseline-diff method).

- [ ] **Step 7: Commit**

```bash
git add lib/features/worklist/worklist_repository.dart lib/features/referral/referral_repository.dart lib/core/mission/mission_dashboard_service.dart lib/core/mission/programme_reason.dart lib/core/constants/app_strings.dart test/core/mission/mission_dashboard_service_driver_insight_test.dart
git commit -m "fix(i18n): localize worklist/referral fallbacks and fix driverInsight twin bug"
```

---

### Task 5: Assistant feature (chat replies, action labels, starter chips)

**Files:**
- Modify: `lib/features/assistant/assistant_repository.dart:50,76,93,96,160,163`
- Modify: `lib/features/assistant/assistant_models.dart:54-67`
- Modify: `lib/features/assistant/patient_ai_sheet.dart:272,337-338`
- Modify: `lib/core/constants/app_strings.dart` (add getters to `AssistantStrings`; convert `PatientAiStrings.starters` from `static const List<String>` to `static List<String> get`)
- Test: `test/features/assistant/assistant_action_label_test.dart` (new)

**Interfaces:**
- Produces: `AssistantStrings.enterAtLeast3Chars`, `.settingUpRetryLater`, `.emptyResponse`, `.noAnswerInResponse` — `static String get`.
- Produces: `AssistantActionType` extension or static method `defaultLabelFor(AssistantActionType type)` on `AssistantStrings` — replaces the raw-literal switch in `assistant_models.dart`.
- Produces: `PatientAiStrings.starters` — `static List<String> get` (was `static const List<String>`).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/assistant/assistant_action_label_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';
import 'package:uhis_lf_mobile/features/assistant/assistant_models.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('AssistantAction.defaultLabel routes through AppStrings for each action type', () {
    AppLocale.current = AppLanguage.english;
    expect(AssistantAction.defaultLabel(AssistantActionType.startVisit), 'Start visit');
    expect(AssistantAction.defaultLabel(AssistantActionType.openReferral), 'Open referral');
    expect(AssistantAction.defaultLabel(AssistantActionType.scheduleFollowUp), 'Schedule follow-up');
    expect(AssistantAction.defaultLabel(AssistantActionType.callPatient), 'Call patient');
  });

  test('PatientAiStrings.starters returns 3 non-empty prompts', () {
    AppLocale.current = AppLanguage.english;
    expect(PatientAiStrings.starters.length, 3);
    expect(PatientAiStrings.starters, everyElement(isNotEmpty));
  });
}
```

Run: `flutter test test/features/assistant/assistant_action_label_test.dart -v`
Expected: FAIL (read `assistant_models.dart` first to confirm `AssistantAction.defaultLabel`'s exact current signature/location — it may be a getter on the enum via `defaultLabel` extension rather than a static method named as above; adjust the test to match the REAL existing signature before proceeding, don't invent one).

- [ ] **Step 2: Add `AssistantStrings` getters and a label-lookup method**

In `app_strings.dart`, extend `AssistantStrings`:

```dart
static String get enterAtLeast3Chars =>
    getTranslatedString('Assistant.enterAtLeast3Chars', 'Please enter at least 3 characters.');
static String get settingUpRetryLater => getTranslatedString(
    'Assistant.settingUpRetryLater', 'Coaching assistant is being set up. Please try again later.');
static String get emptyResponse => getTranslatedString('Assistant.emptyResponse', 'Empty response');
static String get noAnswerInResponse =>
    getTranslatedString('Assistant.noAnswerInResponse', 'No answer in response');

static String actionLabel(AssistantActionType type) {
  switch (type) {
    case AssistantActionType.startVisit:
      return getTranslatedString('Assistant.actionStartVisit', 'Start visit');
    case AssistantActionType.openReferral:
      return getTranslatedString('Assistant.actionOpenReferral', 'Open referral');
    case AssistantActionType.scheduleFollowUp:
      return getTranslatedString('Assistant.actionScheduleFollowUp', 'Schedule follow-up');
    case AssistantActionType.callPatient:
      return getTranslatedString('Assistant.actionCallPatient', 'Call patient');
    case AssistantActionType.none:
      return '';
  }
}
```

(Adjust the `AssistantActionType` import and enum case names to match exactly what Step 1's read of `assistant_models.dart` found — the names above are from research and must be confirmed against the live enum before use.)

Convert `PatientAiStrings.starters` from `static const List<String>` to:
```dart
static List<String> get starters => [
      getTranslatedString('PatientAi.starter1', 'Any danger signs to check?'),
      getTranslatedString('PatientAi.starter2', 'What should I do this visit?'),
      getTranslatedString('PatientAi.starter3', 'Is a referral needed?'),
    ];
```

- [ ] **Step 3: Wire the call sites**

`assistant_models.dart:54-67` — replace the `defaultLabel` switch body to call `AssistantStrings.actionLabel(this)` (or however the existing getter delegates — keep it a one-line delegation, don't duplicate the switch).

`assistant_repository.dart` — replace lines 50, 76, 93, 96, 160, 163 raw literals with `AssistantStrings.enterAtLeast3Chars`, `.settingUpRetryLater`, `.emptyResponse` (used at both 93 and 160), `.noAnswerInResponse` (used at both 96 and 163). Add the `app_strings.dart` import to this file (currently absent).

`patient_ai_sheet.dart`:
- Line 272 — add `AssistantStrings.startVisitFailed` (`'Failed to start visit'`) — note this is the SAME English text as `PatientContextStrings.startVisitFailed` added in Task 2; reuse the Task 2 getter instead of duplicating if Task 2 lands first, otherwise add this one now and have Task 2 reuse it (whichever task's implementer runs second checks for the other's getter first, per the Global Constraints "reuse before creating" rule).
- Lines 337-338 — add `AssistantStrings.thinkingIndicator` (`getTranslatedString('Assistant.thinkingIndicator', '✦ thinking…')`), replace `Text('✦ thinking…', ...)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/assistant/assistant_action_label_test.dart -v`
Expected: PASS

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/features/assistant/ lib/core/constants/app_strings.dart`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/assistant/ lib/core/constants/app_strings.dart test/features/assistant/assistant_action_label_test.dart
git commit -m "fix(i18n): localize assistant chat replies, action labels, and starter prompts"
```

---

### Task 6: CCE feature — `_CceCopy` class, reject-reasons list, inline literals

**Files:**
- Modify: `lib/features/cce/cce_alert.dart:297,302,322,754-802`
- Modify: `lib/features/cce/widgets/cce_call_result_sheet.dart:52-61`
- Modify: `lib/core/constants/app_strings.dart` (extend `CceStrings` with ~30 new getters/methods; the existing `CceStrings` class already exists — reuse it, do not keep `_CceCopy` as a separate class)
- Test: `test/features/cce/cce_alert_copy_test.dart` (new)

**Interfaces:**
- Produces: ~30 new `CceStrings` getters/methods replacing every `_CceCopy` field 1:1 (see Step 3 for the full mapping) — `_CceCopy` is deleted entirely once all its fields are migrated.
- Produces: `CceStrings.rejectReasonLabel(String reasonKey)` — takes a STABLE key (not the display text) and returns the translated label; `CceStrings.rejectReasonKeys` — the stable key list, replacing `_rejectReasons`' dual role as both keys and display text.

The `_rejectReasons` list is compared by value elsewhere in the same file (`'Other'` at lines 75/156/318/322) — the fix must introduce a stable key separate from the display label so those comparisons keep working after localization. This is the most structurally involved task in this plan; the file's own doc comment (explaining why `_CceCopy` deliberately avoids depending on the Flutter strings layer) is the ROOT CAUSE and needs to be reversed, not preserved.

- [ ] **Step 1: Read the current `_rejectReasons` comparison sites in full**

Run: `grep -n "_rejectReasons\|'Other'" lib/features/cce/widgets/cce_call_result_sheet.dart`

Confirm every place `'Other'` (or another reason string) is used as a comparison key vs. as display text, so Step 3's key/label split doesn't break the "Other" special-case branch (e.g. showing a free-text field when "Other" is selected).

- [ ] **Step 2: Write the failing test**

```dart
// test/features/cce/cce_alert_copy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('CceStrings covers every former _CceCopy field with byte-identical English', () {
    AppLocale.current = AppLanguage.english;
    expect(CceStrings.unknownPatient, 'Patient');
    expect(CceStrings.referralReasonFallback, 'Referral');
    expect(CceStrings.attentionBadge, 'Needs attention');
    expect(CceStrings.onTrackBadge, 'On track');
    expect(CceStrings.completedBadge, 'Completed');
    expect(CceStrings.slaEmergencyWindow, '6 hours');
    expect(CceStrings.breachBadge(2), 'SLA BREACHED +2');
    expect(CceStrings.leftBadge('3h'), 'SLA: 3h left');
  });

  test('reject reasons expose stable keys independent of display label', () {
    AppLocale.current = AppLanguage.english;
    expect(CceStrings.rejectReasonKeys, contains('other'));
    expect(CceStrings.rejectReasonLabel('other'), 'Other');
  });
}
```

Run: `flutter test test/features/cce/cce_alert_copy_test.dart -v`
Expected: FAIL (members don't exist yet).

- [ ] **Step 3: Migrate every `_CceCopy` field into `CceStrings`, then delete `_CceCopy`**

Add to the existing `CceStrings` class in `app_strings.dart` (full 1:1 mapping from `_CceCopy`, lines 754-802 of `cce_alert.dart`):

```dart
static String get unknownPatient => getTranslatedString('Cce.unknownPatient', 'Patient');
static String get referralReasonFallback => getTranslatedString('Cce.referralReasonFallback', 'Referral');
static String get attentionBadge => getTranslatedString('Cce.attentionBadge', 'Needs attention');
static String get onTrackBadge => getTranslatedString('Cce.onTrackBadge', 'On track');
static String get completedBadge => getTranslatedString('Cce.completedBadge', 'Completed');
static String get slaEmergencyWindow => getTranslatedString('Cce.slaEmergencyWindow', '6 hours');
static String get slaUrgentWindow => getTranslatedString('Cce.slaUrgentWindow', '24 hours');
static String get slaRoutineWindow => getTranslatedString('Cce.slaRoutineWindow', '72 hours');
static String get stepSkVisit => getTranslatedString('Cce.stepSkVisit', 'SK Visit');
static String get stepReferred => getTranslatedString('Cce.stepReferred', 'Referred');
static String get stepFacility => getTranslatedString('Cce.stepFacility', 'Facility');
static String get stepArrived => getTranslatedString('Cce.stepArrived', 'Arrived');
static String get stepNotArrived => getTranslatedString('Cce.stepNotArrived', 'Not arrived');
static String get stepPending => getTranslatedString('Cce.stepPending', 'Pending');
static String get stepTreatment => getTranslatedString('Cce.stepTreatment', 'Treatment');
static String get stepTreated => getTranslatedString('Cce.stepTreated', 'Treated');
static String get stepInProgress => getTranslatedString('Cce.stepInProgress', 'In progress');
static String get stepDischarged => getTranslatedString('Cce.stepDischarged', 'Discharged');
static String get tagCareComplete => getTranslatedString('Cce.tagCareComplete', 'Care completed');
static String get tagAtFacility => getTranslatedString('Cce.tagAtFacility', 'At facility');
static String get tagNotCheckedIn => getTranslatedString('Cce.tagNotCheckedIn', 'Not checked in');
static String get tagTransportBarrier => getTranslatedString('Cce.tagTransportBarrier', 'Transport barrier?');
static String get actionRecommended => getTranslatedString('Cce.actionRecommended', 'Action recommended');
static String get atFacilityOnTrack => getTranslatedString('Cce.atFacilityOnTrack', 'At facility — care in progress');
static String get onTrackLine => getTranslatedString('Cce.onTrackLine', 'On track — no action needed');
static String breachBadge(int over) => getTranslatedString(
    'Cce.breachBadge', 'SLA BREACHED +{over}', params: {'over': '$over'});
static String leftBadge(String left) => getTranslatedString(
    'Cce.leftBadge', 'SLA: {left} left', params: {'left': left});
static String referredMetaWithFacility(String date, String facility, String reason) => getTranslatedString(
    'Cce.referredMetaWithFacility', 'Referred: {date} · {facility} · {reason}',
    params: {'date': date, 'facility': facility, 'reason': reason});
static String referredMeta(String date, String reason) => getTranslatedString(
    'Cce.referredMeta', 'Referred: {date} · {reason}', params: {'date': date, 'reason': reason});
static String notArrivedOverdue(String overdue, String slaWindow) => getTranslatedString(
    'Cce.notArrivedOverdue', 'Not arrived · {overdue} overdue · SLA was {slaWindow}',
    params: {'overdue': overdue, 'slaWindow': slaWindow});
static String treatmentOverdue(String slaWindow) => getTranslatedString(
    'Cce.treatmentOverdue', 'Treatment overdue · SLA was {slaWindow}', params: {'slaWindow': slaWindow});
static String awaitingReview(String waiting) => getTranslatedString(
    'Cce.awaitingReview', 'Checked in — awaiting review · {waiting} waiting', params: {'waiting': waiting});
static String dueSoon(String left) => getTranslatedString(
    'Cce.dueSoon', 'Due in {left} · act soon', params: {'left': left});
static String dischargedLine(String date) => getTranslatedString(
    'Cce.dischargedLine', 'Discharged {date} · care complete', params: {'date': date});
static String closedDeceased(String date) => getTranslatedString(
    'Cce.closedDeceased', 'Closed {date} · deceased', params: {'date': date});
static String tagEscalated(int level) => getTranslatedString(
    'Cce.tagEscalated', 'Escalated L{level}', params: {'level': '$level'});
// Inline literals found alongside _CceCopy usage (cce_alert.dart:297,302,322):
static String get wrongNumberClosed => getTranslatedString('Cce.wrongNumberClosed', 'Wrong number · closed');
static String callAttemptsStatus(int attempts, int retryAttempts, String remaining) => getTranslatedString(
    'Cce.callAttemptsStatus', '{attempts} of {retryAttempts} calls · {remaining} left',
    params: {'attempts': '$attempts', 'retryAttempts': '$retryAttempts', 'remaining': remaining});
static String get lastAttempt => getTranslatedString('Cce.lastAttempt', 'Last attempt');
static String get followingUp => getTranslatedString('Cce.followingUp', 'Following up');

// Reject reasons — stable key + translated label split.
static const List<String> rejectReasonKeys = [
  'treatmentOtherFacility', 'noMedicine', 'longDistance', 'transportCost',
  'longWaitingQueue', 'migrated', 'died', 'other',
];
static String rejectReasonLabel(String key) {
  switch (key) {
    case 'treatmentOtherFacility':
      return getTranslatedString('Cce.rejectReasonTreatmentOtherFacility', 'Treatment from other facility');
    case 'noMedicine':
      return getTranslatedString('Cce.rejectReasonNoMedicine', 'No Medicine');
    case 'longDistance':
      return getTranslatedString('Cce.rejectReasonLongDistance', 'Long Distance');
    case 'transportCost':
      return getTranslatedString('Cce.rejectReasonTransportCost', 'Transportation and unsupplied medicine cost');
    case 'longWaitingQueue':
      return getTranslatedString('Cce.rejectReasonLongWaitingQueue', 'Long waiting queue');
    case 'migrated':
      return getTranslatedString('Cce.rejectReasonMigrated', 'Migrated to other places');
    case 'died':
      return getTranslatedString('Cce.rejectReasonDied', 'Died');
    case 'other':
      return getTranslatedString('Cce.rejectReasonOther', 'Other');
    default:
      return key;
  }
}
```

Note: `rejectReasonKeys` stays `static const` deliberately — these are internal stable identifiers, never rendered as-is, so the const rule doesn't apply to them the way it does to display text.

In `cce_alert.dart`: replace every `_CceCopy.xxx` reference with the matching `CceStrings.xxx` call (mechanical rename across the file), then delete the `_CceCopy` class (lines 754-802) entirely. Fix the three inline literals at lines 297, 302, 322 to use the new `CceStrings.wrongNumberClosed`/`.callAttemptsStatus(...)`/`.lastAttempt`/`.followingUp` getters.

In `cce_call_result_sheet.dart`: replace `_rejectReasons` (lines 52-61) with `CceStrings.rejectReasonKeys`; everywhere the old list was iterated to build `_reasonChip` widgets, call `CceStrings.rejectReasonLabel(key)` for the displayed text while keeping `key` (not the label) as the stored/compared value; update the `'Other'` comparison sites found in Step 1 to compare against `'other'` (the new stable key) instead of the display string `'Other'`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/cce/cce_alert_copy_test.dart -v`
Expected: PASS

- [ ] **Step 5: Verify no other call sites reference the deleted `_CceCopy`**

Run: `grep -rn "_CceCopy" lib/`
Expected: no output (confirms full migration).

Run: `flutter analyze lib/features/cce/ lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/features/cce/ -v`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/cce/ lib/core/constants/app_strings.dart test/features/cce/cce_alert_copy_test.dart
git commit -m "fix(i18n): migrate CCE _CceCopy class and reject-reasons list into CceStrings"
```

---

### Task 7: Scribe widgets + realtime ASR controller

**Files:**
- Modify: `lib/features/scribe/scribe_permission_service.dart:125,129,133`
- Modify: `lib/features/scribe/widgets/ai_field_indicator.dart:82,84,86,152,164,175,267,273,380,382,383,469`
- Modify: `lib/features/scribe/widgets/scribe_review_sheet.dart:149-151,158-160,167-169,176-178,291,312`
- Modify: `lib/features/realtime_asr/realtime_asr_controller.dart:231,290,429,430-432,570,589,842,844`
- Modify: `lib/core/constants/app_strings.dart` (extend `ScribeStrings`/`ScribeBannerStrings`/`RealtimeAsrStrings`)
- Test: `test/features/scribe/ai_field_indicator_labels_test.dart` (new)

**Interfaces:**
- Produces: `ScribeBannerStrings.confidenceHigh`, `.confidenceMedium`, `.confidenceReviewNeeded`, `.statusAccepted`, `.statusModified`, `.processingEllipsis`, `.stopLabel`, `.aiScribeLabel`, `.fieldsExtractedCount(int n)`, `.acceptTooltip`, `.editTooltip`, `.rejectTooltip`.
- Produces: `ScribeStrings.bulletRecordsAudio`, `.bulletReviewBeforeSave`, `.bulletAudioDeletedAfterProcessing`.
- Produces: `ScribeStrings.soapSubjectiveTitle`/`.soapSubjectiveSubtitle`, `.soapObjectiveTitle`/`.soapObjectiveSubtitle`, `.soapAssessmentTitle`/`.soapAssessmentSubtitle`, `.soapPlanTitle`/`.soapPlanSubtitle`, `.confidencePctModel(int pct, String model)`, `.aiModelFallback`.
- Produces: `RealtimeAsrStrings.connectionError(String detail)`, `.couldNotStart(String detail)`, `.noMicSignal`, `.micSignalStuck`, `.bloodPressurePrefix(String bp)`, `.glucosePrefix(String glucose)`, `.diagnosisPrefix(String diagnosis)`, `.comorbiditiesPrefix(String list)` — the last two reusing `RealtimeAsrStrings.bloodPressure`/`.bloodGlucose`/`.comorbidities` that already exist but are currently unused in `realtime_asr_controller.dart`; check those exact existing getter names first (`grep -n "bloodPressure\|bloodGlucose\|comorbidities" lib/core/constants/app_strings.dart` inside `RealtimeAsrStrings`) and reuse them rather than adding new ones if they already produce the needed "BP"/"Glucose"/"Diagnosis"/"Comorbidities" prefix text.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/scribe/ai_field_indicator_labels_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('confidence-level labels route through AppStrings', () {
    AppLocale.current = AppLanguage.english;
    expect(ScribeBannerStrings.confidenceHigh, 'High confidence');
    expect(ScribeBannerStrings.confidenceMedium, 'Medium');
    expect(ScribeBannerStrings.confidenceReviewNeeded, 'Review needed');
  });

  test('accept/modified status chip labels route through AppStrings', () {
    AppLocale.current = AppLanguage.english;
    expect(ScribeBannerStrings.statusAccepted, 'Accepted');
    expect(ScribeBannerStrings.statusModified, 'Modified');
  });
}
```

Run: `flutter test test/features/scribe/ai_field_indicator_labels_test.dart -v`
Expected: FAIL (members don't exist).

- [ ] **Step 2: Add getters to `ScribeBannerStrings`/`ScribeStrings`/`RealtimeAsrStrings`, then wire every call site**

Follow the exact same `getTranslatedString('Code', 'exact original text', {params})` pattern as every prior task for each of the ~30 literals listed in the Files/Interfaces sections above. Two call sites need special care:

`ai_field_indicator.dart:469` — `'$fieldCount fields extracted from recording'` needs a `{fieldCount}` param: `ScribeBannerStrings.fieldsExtractedCount(int n) => getTranslatedString('ScribeBanner.fieldsExtractedCount', '{fieldCount} fields extracted from recording', params: {'fieldCount': '$n'});`.

`scribe_review_sheet.dart:312` — `'$confidencePct% confidence · $model'` where `model` defaults to `'AI'` (line 291) — add `ScribeStrings.aiModelFallback` (`'AI'`) for the fallback, and `ScribeStrings.confidencePctModel(int pct, String model)` (`getTranslatedString('Scribe.confidencePctModel', '{pct}% confidence · {model}', params: {'pct': '$pct', 'model': model})`) for the combined string.

`realtime_asr_controller.dart:570,589,842,844` — these currently hardcode "BP:", "Glucose:", "Diagnosis:", "Comorbidities:" prefixes instead of reusing `RealtimeAsrStrings.bloodPressure`/`.bloodGlucose`/`.comorbidities` (confirmed to already exist and already be used correctly elsewhere in `ai_scribe_banner.dart:598-599` per this session's research — reuse them, do not create duplicates). Add only the missing `.diagnosis` getter if one doesn't already exist (check first).

- [ ] **Step 3: Run test to verify it passes**

Run: `flutter test test/features/scribe/ai_field_indicator_labels_test.dart -v`
Expected: PASS

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/features/scribe/ lib/features/realtime_asr/ lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/features/scribe/ -v`
Expected: all pass (check against Task 15's known-baseline list for any pre-existing unrelated failures in this directory).

- [ ] **Step 5: Commit**

```bash
git add lib/features/scribe/ lib/features/realtime_asr/ lib/core/constants/app_strings.dart test/features/scribe/ai_field_indicator_labels_test.dart
git commit -m "fix(i18n): localize scribe widget labels and realtime ASR controller messages"
```

---

### Task 8: Shared-widget Semantics/tooltip sweep + dashboard remainder

**Files:**
- Modify: `lib/core/widgets/patient_filter_panel.dart:588-593`
- Modify: `lib/features/visit/widgets/visit_tier_chip.dart:29`
- Modify: `lib/features/dashboard/mission_dashboard_screen.dart:891,1375,1597,1686,1792,1800`
- Modify: `lib/features/dashboard/sk_performance_screen.dart:141-142,293,295,297,365-372,512`
- Modify: `lib/features/dashboard/sk_performance_repository.dart:90-95`
- Modify: `lib/features/dashboard/widgets/ai_brief_card.dart:239,440`
- Modify: `lib/core/models/mission_brief.dart:14-25`
- Modify: `lib/features/dashboard/widgets/compact_summary_strip.dart:28,69,80,93`
- Modify: `lib/features/dashboard/widgets/mission_progress_card.dart:54`
- Modify: `lib/features/dashboard/widgets/critical_alert_banner.dart:53,96,108,204`
- Modify: `lib/features/dashboard/widgets/referral_operations_widget.dart:45,265,276`
- Modify: `lib/core/constants/app_strings.dart` (add getters to `MissionDashboardStrings`, `PerformanceStrings`)
- Test: `test/features/dashboard/mission_dashboard_labels_test.dart` (new)

**Interfaces:**
- Produces: `MissionDashboardStrings.filterUnavailable(String label)`, `.filterSelected(String label)`, `.filterBy(String label)` — the same three-variant `Semantics.label` template, reused by BOTH `patient_filter_panel.dart` and `visit_tier_chip.dart` (previously duplicated verbatim across the two files — fix once, reuse twice).
- Produces: `MissionDashboardStrings.searchResultsNotInQueue`, `.referralAlertsSemantic(int total)`, `.notificationsCountSemantic(int count)`, `.notificationsSemantic`, `.unknownFallback`, `.expandRiskFactors`, `.collapseRiskFactors`, `.visitsSuffix`, `.urgentSuffix`, `.workSuffix`, `.todaysProgressHeader(String date)`, `.openCriticalCase(String name)`, `.moreAlerts(int n)`, `.dismissAlertTooltip`, `.daysOverdueSuffix(int n)`, `.viewReferralStatusSemantic`, `.slaBreachedBanner`.
- Produces: `PerformanceStrings.performanceTab`, `.myPatientsTab`, `.serviceLabel`, `.nextVisitLabel`, `.lastVisitLabel`, `.outOf100`, `.dueStatus(...)` (mirrors the confirmed `driverLabel`-style bug in `_SpiceDueText._resolve()` — same fix shape as Task 4's `driverInsight`), and a fix for `sk_performance_repository.dart`'s `ratingFor()` (same twin-bug pattern again).
- Produces: `PerformanceStrings.weekdayLabels`/`.weekLabels` — converted from `static const List<String>` to `static List<String> get`.

This task bundles every remaining `Semantics.label`/`tooltip` raw-literal site across dashboard and shared widgets, plus three more instances of the confirmed "switch/branch returns raw literal, assigned to a variable, rendered via `Text`" bug (`_SpiceDueText._resolve()`, `sk_performance_repository.ratingFor()`, `DayPriorityLevel.label`) — the same shape already fixed once for `MissionDashboardStrings.driverLabel` and once more in Task 4's `driverInsight`. Fixing all three here closes out that entire bug family.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/dashboard/mission_dashboard_labels_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';
import 'package:uhis_lf_mobile/core/models/mission_brief.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('shared filter-chip semantics template is reusable across widgets', () {
    AppLocale.current = AppLanguage.english;
    expect(MissionDashboardStrings.filterBy('ANC'), 'Filter by ANC');
    expect(MissionDashboardStrings.filterSelected('ANC'), 'ANC filter, selected');
    expect(MissionDashboardStrings.filterUnavailable('ANC'), 'ANC filter, unavailable');
  });

  test('DayPriorityLevel.label routes through AppStrings', () {
    AppLocale.current = AppLanguage.english;
    expect(DayPriorityLevel.critical.label, 'Critical');
    expect(DayPriorityLevel.high.label, 'High');
    expect(DayPriorityLevel.medium.label, 'Medium');
    expect(DayPriorityLevel.low.label, 'Low');
  });

  test('PerformanceStrings.weekdayLabels has 7 entries', () {
    AppLocale.current = AppLanguage.english;
    expect(PerformanceStrings.weekdayLabels, ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
  });
}
```

Run: `flutter test test/features/dashboard/mission_dashboard_labels_test.dart -v`
Expected: FAIL (members don't exist / `DayPriorityLevel.label` still returns raw literals directly rather than via a getter that could be intercepted — this test currently passes trivially for `DayPriorityLevel` since the text matches; its value is guarding against wording drift once Step 2 routes it through `getTranslatedString`).

- [ ] **Step 2: Add the shared filter-chip template and wire both call sites**

In `MissionDashboardStrings`:
```dart
static String filterBy(String label) =>
    getTranslatedString('MissionDashboard.filterBy', 'Filter by {label}', params: {'label': label});
static String filterSelected(String label) => getTranslatedString(
    'MissionDashboard.filterSelected', '{label} filter, selected', params: {'label': label});
static String filterUnavailable(String label) => getTranslatedString(
    'MissionDashboard.filterUnavailable', '{label} filter, unavailable', params: {'label': label});
```

In `patient_filter_panel.dart:588-593` and `visit_tier_chip.dart:29`, replace both files' duplicated ternary logic with calls to these three shared getters (e.g. `isDisabled ? MissionDashboardStrings.filterUnavailable(label) : isActive ? MissionDashboardStrings.filterSelected(label) : MissionDashboardStrings.filterBy(label)`).

- [ ] **Step 3: Fix `DayPriorityLevel.label`, `_SpiceDueText._resolve()`, and `sk_performance_repository.ratingFor()`**

`lib/core/models/mission_brief.dart:14-25` — add `import 'package:uhis_lf_mobile/core/constants/app_strings.dart';`, replace each `switch`/`case` raw-literal return with a call to new `MissionDashboardStrings` getters `.priorityCritical`, `.priorityHigh`, `.priorityMedium`, `.priorityLow`.

`sk_performance_screen.dart`'s `_SpiceDueText._resolve()` (lines 365-372) — add `PerformanceStrings.dueRoutine`, `.dueTomorrow`, `.dueUpcomingInDays(int days)`, `.dueToday`, `.overdueByDays(int d)`, replace each raw-literal return with the matching getter, preserving the existing `(text, color)` tuple return shape.

`sk_performance_repository.dart:90-95` (`ratingFor`) — add `PerformanceStrings.ratingExcellent`, `.ratingGood`, `.ratingFair`, `.ratingNeedsImprovement`, replace each raw-literal return.

- [ ] **Step 4: Fix the remaining Semantics/tooltip/`Text` literals in this task**

For each site below, add one getter to `MissionDashboardStrings` (mirroring the exact fallback text) and wire it in:

- `mission_dashboard_screen.dart:891` → `.searchResultsNotInQueue`
- `mission_dashboard_screen.dart:1375` → `.referralAlertsSemantic(int total)`
- `mission_dashboard_screen.dart:1686` → `.notificationsCountSemantic(int count)` / `.notificationsSemantic` (ternary's two branches)
- `mission_dashboard_screen.dart:1792` → `.unknownFallback` (`'Unknown'`)
- `mission_dashboard_screen.dart:1800` → add a small gender wire-value → label lookup (`'Male'`/`'Female'`/other → translated), mirroring the `Programme.fromString()`-style pattern used elsewhere this session, rather than a single flat getter, since this is rendering a raw DB value, not a fixed UI string.
- `sk_performance_screen.dart:141-142` → `.performanceTab` (`'Performance'`), `.myPatientsTab` (`'My Patients'`)
- `sk_performance_screen.dart:293,295,297` → `.serviceLabel`, `.nextVisitLabel`, `.lastVisitLabel`
- `sk_performance_screen.dart:512` → `.outOf100` (`'/ 100'`)
- `ai_brief_card.dart:239` → `.expandRiskFactors`/`.collapseRiskFactors` (ternary)
- `compact_summary_strip.dart:28` → `.openAiBriefCritical`/`.openAiBrief` (ternary)
- `compact_summary_strip.dart:69,80,93` → `.visitsSuffix` (`'visits'`), `.urgentSuffix` (`'urgent'`), `.workSuffix` (`'work'`)
- `mission_progress_card.dart:54` → reuse the EXISTING `MissionDashboardStrings.aiBriefTodayHeader(...)` getter (already correctly used by `ai_brief_card.dart:76` for the identical text) instead of adding a new one — this file just missed calling it.
- `critical_alert_banner.dart:53` → `.openCriticalCase(String name)`
- `critical_alert_banner.dart:96` → `.moreAlerts(int n)` (handle the existing manual pluralization the same way as elsewhere in this plan)
- `critical_alert_banner.dart:108` → `.dismissAlertTooltip`
- `critical_alert_banner.dart:204` and `referral_operations_widget.dart:276` → ONE shared getter `.daysOverdueSuffix(int n)` (`'+{n}d'`) — same text duplicated in both files, fix once.
- `referral_operations_widget.dart:45` → `.viewReferralStatusSemantic`
- `referral_operations_widget.dart:265` → `.slaBreachedBanner` (`'🔴 SLA BREACHED'`)

- [ ] **Step 5: Convert `PerformanceStrings.weekdayLabels`/`.weekLabels` from `static const` to `static List<String> get`**

```dart
static List<String> get weekdayLabels => [
      getTranslatedString('Performance.weekdayMon', 'M'),
      getTranslatedString('Performance.weekdayTue', 'T'),
      getTranslatedString('Performance.weekdayWed', 'W'),
      getTranslatedString('Performance.weekdayThu', 'T'),
      getTranslatedString('Performance.weekdayFri', 'F'),
      getTranslatedString('Performance.weekdaySat', 'S'),
      getTranslatedString('Performance.weekdaySun', 'S'),
    ];
static List<String> get weekLabels => [
      getTranslatedString('Performance.week1', 'W1'),
      getTranslatedString('Performance.week2', 'W2'),
      getTranslatedString('Performance.week3', 'W3'),
      getTranslatedString('Performance.week4', 'W4'),
    ];
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/dashboard/mission_dashboard_labels_test.dart -v`
Expected: PASS

- [ ] **Step 7: Verify**

Run: `flutter analyze lib/core/widgets/patient_filter_panel.dart lib/features/visit/widgets/visit_tier_chip.dart lib/features/dashboard/ lib/core/models/mission_brief.dart lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/features/dashboard/ -v`
Expected: all pass (baseline-check against Task 15's known failures — `mission_dashboard_service_tier_test.dart` has one pre-existing unrelated failure).

- [ ] **Step 8: Commit**

```bash
git add lib/core/widgets/patient_filter_panel.dart lib/features/visit/widgets/visit_tier_chip.dart lib/features/dashboard/ lib/core/models/mission_brief.dart lib/core/constants/app_strings.dart test/features/dashboard/mission_dashboard_labels_test.dart
git commit -m "fix(i18n): dedupe and localize dashboard Semantics labels and branch-based label generators"
```

---

### Task 9: Visit-feature remainder

**Files:**
- Modify: `lib/features/visit/visit_flow_header.dart:68`
- Modify: `lib/features/visit/widgets/form_fields/age_or_dob_field.dart:121,139`
- Modify: `lib/features/visit/vital_classifier.dart:9-18`
- Modify: `lib/core/constants/app_strings.dart` (already has `ChildAssessmentStrings.complicationOptions` const-list bug from the structural audit — fix here since it's triage-adjacent; add getters for the above)
- Modify: `lib/features/visit/triage/child_assessment_section.dart:658` (call-site wiring for the `complicationOptions` fix)
- Investigate (do not blindly fix): `lib/features/visit/symptom_catalog.dart` (top-level file, distinct from `lib/features/visit/triage/`)
- Test: `test/features/visit/vital_classifier_label_test.dart` (new)

**Interfaces:**
- Produces: `VisitFlowStrings.step2TitlePregnancyChecks` (reuses the existing `VisitFlowStrings` class already used for `step1Title`/`step3Title` in this same file).
- Produces: `EnrollmentStrings.ageUnitYear`/`.ageUnitYears` — **check first**: Task 2's plan already fixes an `EnrollmentAge`/age-unit bug pattern in the enrollment flow from the prior session's rounds; `age_or_dob_field.dart` is a SEPARATE widget with its own local `_ageUnit` ternary — confirm whether `EnrollmentStrings` already has a reusable year/years getter (it likely does, from the earlier enrollment round — `grep -n "ageUnitYear" lib/core/constants/app_strings.dart` first) and reuse it rather than adding a duplicate.
- Produces: `VitalClassifierStrings.normal`, `.low`, `.high`, `.critical` (new class, since `vital_classifier.dart` currently has none).
- Produces: `ChildAssessmentStrings.complicationDiarrhea`, `.complicationPneumonia`, `.complicationCannotStandOrWalk`, `.complicationCannotMaintainBalance`, `.complicationCannotSpeakTwoWords` — converts `complicationOptions` from `static const List<String>` to `static List<String> get`.

- [ ] **Step 1: Investigate `symptom_catalog.dart` liveness before deciding whether to fix or delete it**

Run: `grep -rn "VisitSession\.symptoms\|VisitSession\.vitals\|SymptomCatalog\.forProgramme\|VitalCatalog\.forProgramme" lib/ --include=*.dart | grep -v "lib/features/visit/visit_controller.dart\|lib/features/visit/symptom_catalog.dart"`

- If this returns any screen/widget that actually renders `VisitSession.symptoms`/`.vitals` (not just `visit_controller.dart` writing to them), the ~50 raw literals in `SymptomCatalog`/`VitalCatalog` (lines 26-33,38-57,62-69,74-81 and 146-320) are a real, live gap — proceed to Step 2 to fix them with the same mechanical `getTranslatedString` pattern as every other task (one getter per `label:`/`instruction:` value, grouped under a new `SymptomCatalogStrings` class), reusing existing `Triage.symptom.<code>`-style codes from `TriageStrings.symptomLabel()` wherever a symptom name in this file duplicates one already covered there (e.g. `'Fever'`, `'Cough'`, `'Diarrhea'` almost certainly already have codes — check `TriageStrings.symptomLabel` first and reuse its codes rather than minting new ones for the same words).
- If nothing renders it, this file (and `VisitController`'s use of it) is dead code superseded by the `triage/unified_symptom_catalog.dart` + `AiScribeTriageVocab` pipeline — skip the translation fix and instead note it as a candidate for Task 11's dead-code cleanup (do not delete it in THIS task without explicit confirmation, since `VisitController` is actively provider-registered; flag it in the Task 15 final report instead).

- [ ] **Step 2: Write the failing test for `VitalClassification.label`**

```dart
// test/features/visit/vital_classifier_label_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/features/visit/vital_classifier.dart';

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
```

Run: `flutter test test/features/visit/vital_classifier_label_test.dart -v`
Expected: This currently PASSES trivially (raw literals match) — same rationale as Task 8 Step 1: this test locks the wording before the refactor so any drift is caught.

- [ ] **Step 3: Add `VitalClassifierStrings` and wire it in**

```dart
abstract final class VitalClassifierStrings {
  VitalClassifierStrings._();
  static String get normal => getTranslatedString('VitalClassifier.normal', 'Normal');
  static String get low => getTranslatedString('VitalClassifier.low', 'Low');
  static String get high => getTranslatedString('VitalClassifier.high', 'High');
  static String get critical => getTranslatedString('VitalClassifier.critical', 'Critical');
}
```

In `vital_classifier.dart`, add the `app_strings.dart` import and replace the `switch (this)` body in `VitalClassification.label` to return `VitalClassifierStrings.normal`/`.low`/`.high`/`.critical` per case.

- [ ] **Step 4: Fix `visit_flow_header.dart` and `age_or_dob_field.dart`**

`visit_flow_header.dart:68` — add `VisitFlowStrings.step2TitlePregnancyChecks` (`getTranslatedString('VisitFlow.step2TitlePregnancyChecks', 'Pregnancy checks')`) to the existing `VisitFlowStrings` class, replace the raw `'Pregnancy checks'` literal.

`age_or_dob_field.dart:121,139` — after confirming (per the Interfaces note) whether `EnrollmentStrings` already has a reusable year/years getter from an earlier round, replace both `_ageUnit = ... ? 'year' : 'years';` sites with that getter (or add `EnrollmentStrings.ageUnitYear`/`.ageUnitYears` if truly absent, matching the exact same fix shape used for the enrollment flow's own age-unit bug).

- [ ] **Step 5: Fix `ChildAssessmentStrings.complicationOptions`**

Convert in `app_strings.dart`:
```dart
static List<String> get complicationOptions => [
      getTranslatedString('ChildAssessment.complicationDiarrhea', 'Diarrhea'),
      getTranslatedString('ChildAssessment.complicationPneumonia', 'Pneumonia'),
      getTranslatedString('ChildAssessment.complicationCannotStandOrWalk', 'Cannot stand or walk'),
      getTranslatedString('ChildAssessment.complicationCannotMaintainBalance', 'Cannot maintain body balance'),
      getTranslatedString('ChildAssessment.complicationCannotSpeakTwoWords', 'Cannot speak two meaningful words'),
    ];
```
Confirm `child_assessment_section.dart:658`'s `_ComplicationPicker` iterates this list and renders each item via `Text(option, ...)` unchanged — no call-site code change needed beyond the list itself becoming a getter (Dart allows calling a `static List<String> get` anywhere a `static const List<String>` was read).

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/visit/vital_classifier_label_test.dart -v`
Expected: PASS

- [ ] **Step 7: Verify**

Run: `flutter analyze lib/features/visit/visit_flow_header.dart lib/features/visit/widgets/form_fields/age_or_dob_field.dart lib/features/visit/vital_classifier.dart lib/features/visit/triage/child_assessment_section.dart lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/features/visit/ -v`
Expected: all pass (baseline-check against Task 15's known failures — `triage_view_model_test.dart` has two pre-existing unrelated failures).

- [ ] **Step 8: Commit**

```bash
git add lib/features/visit/visit_flow_header.dart lib/features/visit/widgets/form_fields/age_or_dob_field.dart lib/features/visit/vital_classifier.dart lib/features/visit/triage/child_assessment_section.dart lib/core/constants/app_strings.dart test/features/visit/vital_classifier_label_test.dart
git commit -m "fix(i18n): localize vital classification labels and remaining visit-flow literals"
```

---

### Task 10: `app_strings.dart` structural bugs — live getter-bypass fixes

**Files:**
- Modify: `lib/core/constants/app_strings.dart:1539-1545` (`ScribeStrings`)
- Modify: `lib/core/constants/app_strings.dart:2807-2816` (`TriageResultStrings`)
- Modify: `lib/core/constants/app_strings.dart:2840-2843,3110-3111,3157-3158,3169-3170` (`SymptomPickerStrings` — 4 remaining bugs the earlier round's fix missed)
- Modify: `lib/core/constants/app_strings.dart:3780-3781,3789-3790,3809-3813,3865,3903-3929` (`UnifiedFormStrings`)
- Modify: `lib/core/constants/app_strings.dart:4923-4924` (`EnrollStrings.confirmCta`)
- Test: `test/core/constants/app_strings_getter_bypass_test.dart` (new)

**Interfaces:** No new public API — every fix here is an in-place body rewrite of an EXISTING getter/method, keeping its exact signature. This is the same bug class fixed for `SymptomPickerStrings`/`EpiVisitRecoStrings`/`EpiStrings.overdueBanner` in the immediately-prior translation round — these 13 sites are the ones that round's file-by-file scope missed, confirmed live (not dead code) via call-site greps.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/constants/app_strings_getter_bypass_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('ScribeStrings.uploadProgress/recordingTimer are byte-identical after the fix', () {
    AppLocale.current = AppLanguage.english;
    expect(ScribeStrings.uploadProgress(42), 'Uploading…  42%');
  });

  test('TriageResultStrings.stepSubtitle is byte-identical after the fix', () {
    AppLocale.current = AppLanguage.english;
    expect(TriageResultStrings.stepSubtitle(0), 'Step 1 of 3 · Tap all symptoms mentioned');
    expect(TriageResultStrings.stepSubtitle(1), 'Step 2 of 3 · AI triage active');
    expect(TriageResultStrings.stepSubtitle(2), 'Step 3 of 3 · Fill in what you see');
  });

  test('SymptomPickerStrings remaining bypass getters are byte-identical', () {
    AppLocale.current = AppLanguage.english;
    expect(SymptomPickerStrings.scribeBannerSubtitleFor(isFemale: true), 'Symptoms appear automatically as she talks');
    expect(SymptomPickerStrings.scribeDoneWithCount(1), 'Scribe complete · 1 symptom detected');
    expect(SymptomPickerStrings.symptomsSelectedStatus(2), '2 symptoms selected');
  });

  test('UnifiedFormStrings.programmeBadgeLabel is byte-identical for known form types', () {
    AppLocale.current = AppLanguage.english;
    expect(UnifiedFormStrings.programmeBadgeLabel('anc'), 'ANC');
    expect(UnifiedFormStrings.programmeBadgeLabel('vitals'), 'Vitals');
  });

  test('EnrollStrings.confirmCta is byte-identical', () {
    AppLocale.current = AppLanguage.english;
    expect(EnrollStrings.confirmCta(3), 'Confirm Enrollment (3 selected)');
    expect(EnrollStrings.confirmCta(0), 'Select Programmes');
  });
}
```

Run: `flutter test test/core/constants/app_strings_getter_bypass_test.dart -v`
Expected: PASS trivially (English text is unchanged before the fix) — as with Tasks 8/9, this test's purpose is to lock exact wording so Step 3's rewrite can't silently drift it.

- [ ] **Step 2: For each of the 13 sites, read the exact current body first**

Run: `sed -n '1535,1550p;2805,2820p;2838,2860p;3105,3175p;3775,3935p;4920,4930p' lib/core/constants/app_strings.dart`

Confirm every branch/parameter against this live output before rewriting — the line numbers above are from research and may have shifted from earlier tasks' edits to this same file; re-grep by getter name if a line offset looks wrong (e.g. `grep -n "static String uploadProgress\|static String recordingTimer\|static String stepSubtitle\|static String scribeBannerSubtitleFor\|static String scribeDoneWithCount\|static String symptomsSelectedStatus\|static String symptomsSelected\b\|static String addSymptomSheetCounter\|static String validationFieldsRequired\|static String triageSymptomsCount\|static String trendWeeksAgo\|static String vsLastWeight\|static String programmeBadgeLabel\|static String confirmCta" lib/core/constants/app_strings.dart`).

- [ ] **Step 3: Rewrite each body to route through `getTranslatedString`**

Apply the identical transform pattern used throughout this whole plan and the prior two rounds to each of the 13 sites — one `getTranslatedString('Class.methodName<Branch>', 'exact branch text', params: {...})` call per distinct branch. Worked example for `ScribeStrings.uploadProgress`:

```dart
// before
static String uploadProgress(double pct) => 'Uploading…  ${pct.toStringAsFixed(0)}%';
// after
static String uploadProgress(double pct) => getTranslatedString(
    'Scribe.uploadProgress', 'Uploading…  {pct}%', params: {'pct': pct.toStringAsFixed(0)});
```

Apply the same shape to the remaining 12 sites (`recordingTimer`, `TriageResultStrings.stepSubtitle`'s 3 branches, `SymptomPickerStrings.scribeBannerSubtitleFor`'s 2 branches, `.scribeDoneWithCount`'s 3 branches, `.symptomsSelectedStatus`, `.symptomsSelected` — note these last two are exact duplicates called from different sites; give them distinct codes but they may share implementation via one private helper if that's cleaner, `.addSymptomSheetCounter`'s 2 branches, `UnifiedFormStrings.validationFieldsRequired`, `.triageSymptomsCount`, `.trendWeeksAgo`'s 3 branches, `.vsLastWeight`, `.programmeBadgeLabel`'s 11 branches, `EnrollStrings.confirmCta`'s 2 branches).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/constants/app_strings_getter_bypass_test.dart -v`
Expected: PASS

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test -v 2>&1 | tail -50`
Expected: no NEW failures vs. Task 15's baseline (these getters are called from `unified_form_screen.dart` and `visit_step_header.dart` — re-run those screens' widget tests specifically if any exist: `find test -iname "*unified_form*" -o -iname "*visit_step_header*"`).

- [ ] **Step 6: Commit**

```bash
git add lib/core/constants/app_strings.dart test/core/constants/app_strings_getter_bypass_test.dart
git commit -m "fix(i18n): close remaining getter-bypass bugs in ScribeStrings/TriageResultStrings/SymptomPickerStrings/UnifiedFormStrings/EnrollStrings"
```

---

### Task 11: Delete confirmed-dead localization code

**Files:**
- Modify: `lib/core/constants/app_strings.dart` (delete dead fields/methods across 8 classes)

**Interfaces:** None — pure deletion. Per Engineering Design Standards ("Maintainability... no dead or commented-out code"), confirmed-dead getters should be removed, not migrated or left in place.

Every item below was confirmed via repo-wide grep (by the structural-audit research pass) to have **zero references anywhere outside its own declaration in `app_strings.dart`**. Re-confirm each with a fresh grep immediately before deleting (code may have changed since the research pass), since deleting a live call site by mistake would break a build.

- [ ] **Step 1: Re-confirm each dead-code candidate**

Run this exact check for every symbol below before deleting it:
```bash
for sym in greetingBangla greetingEnglish skAsksBangla skAsksEnglish symptomBangla skOpenerPhraseBn callDoctorNowBn strokeSignBn morningHeadachesBn chestTightnessBn highSaltBn familyHistoryBn tbBengali tbLabel defaultReferralReasons householdTypes incomeRanges disabilityStatuses relationships healthWorkerOptions villageOptions; do
  echo "=== $sym ==="
  grep -rn "\b$sym\b" lib/ test/ | grep -v "lib/core/constants/app_strings.dart:"
done
```
Expected: empty output for every symbol (confirming zero external references). If any symbol shows a real reference, remove it from this task's deletion list and investigate why the research pass missed it before proceeding.

- [ ] **Step 2: Delete the dead fields, grouped by class**

- `PatientContextStrings`: delete `greetingBangla`, `greetingEnglish` (app_strings.dart:722-724).
- `VisitTriageStrings`: delete `skAsksBangla`, `skAsksEnglish` (app_strings.dart:1499-1501).
- `TriageStrings`: delete the entire dead English/Bangla const-field block `symptomConvulsions`…`symptomWeakness`/`symptomConvulsionsBn`…`symptomJaundiceBn` (app_strings.dart:1630-1784) AND the `symptomBangla(String code)` switch method (app_strings.dart:1787) that only reads them — do NOT touch `TriageStrings.symptomLabel(code)`, the separate, live, correctly-implemented method.
- `ComposerStrings`: delete the dead const-field blocks `sectionVitals`…`fieldFootWound` (app_strings.dart:2088-2184) and `sectionAncVitals`…`sectionPncChild` (app_strings.dart:2551-2566) — do NOT touch `.sectionTitle(sectionId)`/`.fieldLabel(key)`, the separate, live, correctly-implemented switch methods.
- `SymptomPickerStrings`: delete `skOpenerPhraseBn` (app_strings.dart:3092).
- `NabaStrings`: delete `callDoctorNowBn` (app_strings.dart:3497).
- `NcdScreeningStrings`: delete `strokeSignBn`, `morningHeadachesBn`, `chestTightnessBn`, `highSaltBn`, `familyHistoryBn` (app_strings.dart:3709,3713,3716,3719,3722).
- `EnrollStrings`: delete `tbBengali`, `tbLabel` (app_strings.dart:4907-area — confirm exact lines via Step 1's grep, since no TB tile is ever rendered on `programme_enroll_screen.dart`).
- `ReferralStrings`: delete `defaultReferralReasons` (app_strings.dart:1005-1014).
- `EnrollmentStrings`: delete `householdTypes`, `incomeRanges`, `disabilityStatuses`, `relationships`, `healthWorkerOptions`, `villageOptions` (dead sibling lists superseded by the live `*V2`/`gendersHead`/`gendersMember`/`phoneCategoryOptions`/`idTypesV2`/`occupationOptions`/`incomeRangeOptions` lists that already route through `optionDisplay`/`getTranslatedString` correctly).

- [ ] **Step 3: Verify nothing broke**

Run: `flutter analyze lib/core/constants/app_strings.dart`
Expected: 0 errors (a broken reference to a deleted symbol would surface here immediately).

Run: `flutter test -v 2>&1 | tail -50`
Expected: no NEW failures vs. Task 15's baseline.

- [ ] **Step 4: Commit**

```bash
git add lib/core/constants/app_strings.dart
git commit -m "chore: remove confirmed-dead localization fields superseded by live getTranslatedString-based getters"
```

---

### Task 12: Core clinical briefing-rules and referral-evaluator finding messages

**Files:**
- Modify: `lib/core/clinical/briefing_rules/anc_briefing_rules.dart:70,81,93,99,115`
- Modify: `lib/core/clinical/briefing_rules/ncd_briefing_rules.dart:54,60`
- Modify: `lib/core/clinical/briefing_rules/pnc_briefing_rules.dart:94`
- Modify: `lib/core/clinical/briefing_rules/child_immunization_briefing_rules.dart:74`
- Modify: `lib/core/clinical/briefing_rules/pregnancy_outcome_briefing_rules.dart:47`
- Modify: `lib/core/clinical/referral_evaluator.dart:319,327,337,343,352,356,365,404` (and confirm the full remaining list in Step 1)
- Modify: `lib/core/constants/app_strings.dart` (new `ClinicalFindingStrings` class)
- Test: `test/core/clinical/briefing_rules/clinical_finding_messages_test.dart` (new)

**Interfaces:**
- Produces: `ClinicalFindingStrings` — one getter per distinct `ClinicalFinding.message` literal across all 5 briefing-rules files, plus one per `referralReasons` literal in `referral_evaluator.dart`.

These are `ClinicalFinding.message` values — per that class's own doc comment, "the rendered, patient-facing message text for this finding," joined verbatim and shown on the AI-insight/Before-You-Knock summary in `patient_context_screen.dart`. This is clinically-meaningful content (same sensitivity tier as the EPI/referral content fixed in the prior translation round), so accuracy matters — do not paraphrase, only relocate the exact existing English wording behind a getter.

- [ ] **Step 1: Enumerate every `ClinicalFinding(message: '...')` and `referralReasons.add('...')`/`referralReasons = [...]` literal across the 6 files**

Run: `grep -n "message:\s*'" lib/core/clinical/briefing_rules/*.dart` and `grep -n "referralReasons" -A 2 lib/core/clinical/referral_evaluator.dart`

Cross-check the exact set against the list in this task's Files section — the research pass may not have caught every occurrence (it explicitly flagged `referral_evaluator.dart` for "a closer follow-up pass to confirm every consumption site"). Use this step's fresh grep as the authoritative list, not the line numbers above alone.

- [ ] **Step 2: Write the failing test**

```dart
// test/core/clinical/briefing_rules/clinical_finding_messages_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/constants/app_strings.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('ClinicalFindingStrings preserves exact existing clinical wording', () {
    AppLocale.current = AppLanguage.english;
    expect(ClinicalFindingStrings.ancBpAboveSafeThreshold,
        'BP is above the safe threshold. Watch for pre-eclampsia.');
    expect(ClinicalFindingStrings.ncdBpAboveNormal,
        'BP is above normal. Requires review and follow-up.');
    expect(ClinicalFindingStrings.pncSevereAnemia, 'Severe anemia.');
    expect(ClinicalFindingStrings.childImmunizationOnSchedule,
        'Immunization on schedule, growth on track.');
    expect(ClinicalFindingStrings.pregnancyOutcomeStillbirthOrNeonatalDeath,
        'Stillbirth or neonatal death recorded.');
  });
}
```

Run: `flutter test test/core/clinical/briefing_rules/clinical_finding_messages_test.dart -v`
Expected: FAIL (members don't exist).

- [ ] **Step 3: Add `ClinicalFindingStrings` with one getter per Step 1 finding, then wire every file**

```dart
abstract final class ClinicalFindingStrings {
  ClinicalFindingStrings._();
  static String get ancBpAboveSafeThreshold => getTranslatedString(
      'ClinicalFinding.ancBpAboveSafeThreshold', 'BP is above the safe threshold. Watch for pre-eclampsia.');
  static String get ancBpRisingTwoVisits => getTranslatedString(
      'ClinicalFinding.ancBpRisingTwoVisits', 'BP has risen over the last two visits. Monitor closely.');
  static String get ancSevereAnemia => getTranslatedString('ClinicalFinding.ancSevereAnemia', 'Severe anemia.');
  static String get ancAnemiaReinforceIron => getTranslatedString(
      'ClinicalFinding.ancAnemiaReinforceIron', 'Anemia noted. Reinforce iron-folic intake.');
  static String get ancIronFolicBelowExpected => getTranslatedString(
      'ClinicalFinding.ancIronFolicBelowExpected', 'Iron-folic intake is below the expected daily rate.');
  static String get ncdBpAboveNormal => getTranslatedString(
      'ClinicalFinding.ncdBpAboveNormal', 'BP is above normal. Requires review and follow-up.');
  static String get ncdBloodSugarElevated => getTranslatedString(
      'ClinicalFinding.ncdBloodSugarElevated', 'Blood sugar is elevated. Requires review and follow-up.');
  static String get pncSevereAnemia => getTranslatedString('ClinicalFinding.pncSevereAnemia', 'Severe anemia.');
  static String get childImmunizationOnSchedule => getTranslatedString(
      'ClinicalFinding.childImmunizationOnSchedule', 'Immunization on schedule, growth on track.');
  static String get pregnancyOutcomeStillbirthOrNeonatalDeath => getTranslatedString(
      'ClinicalFinding.pregnancyOutcomeStillbirthOrNeonatalDeath', 'Stillbirth or neonatal death recorded.');
  // Referral-evaluator reasons — add one getter per literal confirmed in Step 1,
  // following this exact pattern:
  static String get referralDangerSignsPresent =>
      getTranslatedString('ClinicalFinding.referralDangerSignsPresent', 'Danger signs present');
  static String get referralSuspectedPreEclampsia =>
      getTranslatedString('ClinicalFinding.referralSuspectedPreEclampsia', 'Suspected pre-eclampsia');
  static String get referralAbnormalFundalHeight =>
      getTranslatedString('ClinicalFinding.referralAbnormalFundalHeight', 'Abnormal fundal height');
  static String get referralAbnormalPulse =>
      getTranslatedString('ClinicalFinding.referralAbnormalPulse', 'Abnormal pulse');
  static String get referralUrinaryBilirubinPresent =>
      getTranslatedString('ClinicalFinding.referralUrinaryBilirubinPresent', 'Urinary bilirubin present');
  static String get referralChronicIllnessUntreated =>
      getTranslatedString('ClinicalFinding.referralChronicIllnessUntreated', 'Chronic illness untreated');
  static String get referralAbnormalWeightGain =>
      getTranslatedString('ClinicalFinding.referralAbnormalWeightGain', 'Abnormal weight gain');
  static String get referralSuspectedDiabetes =>
      getTranslatedString('ClinicalFinding.referralSuspectedDiabetes', 'Suspected diabetes');
  // Add any further referralReasons literals Step 1's fresh grep turns up,
  // following this identical one-getter-per-literal shape.
}
```

In each of the 6 files, add the `app_strings.dart` import and replace every literal identified in Step 1 with its matching `ClinicalFindingStrings` getter.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/clinical/briefing_rules/clinical_finding_messages_test.dart -v`
Expected: PASS

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/core/clinical/ lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/core/clinical/ -v`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/core/clinical/ lib/core/constants/app_strings.dart test/core/clinical/briefing_rules/clinical_finding_messages_test.dart
git commit -m "fix(i18n): localize clinical briefing-rules finding messages and referral-evaluator reasons"
```

---

### Task 13: Core sync progress + notification fallback literals

**Files:**
- Modify: `lib/core/sync/sync_progress.dart:79-91`
- Modify: `lib/core/sync/offline_push_service.dart:148,158,308,461-463,470-471,479`
- Modify: `lib/core/notifications/repeat_scheduler.dart:84,86`
- Modify: `lib/core/constants/app_strings.dart` (add getters to `SyncStrings`; reuse existing `OfflineSyncStrings` for `offline_push_service.dart`)
- Test: `test/core/sync/sync_step_labels_test.dart` (new)

**Interfaces:**
- Produces: `SyncStrings.connectingToServer`, `.downloadingPatients`, `.downloadingFollowUps`, `.downloadingReferrals`, `.processingData`, `.readyStatus`.
- `offline_push_service.dart` should reuse the EXISTING `OfflineSyncStrings.completed`/`.failed` (confirmed to already exist but be unreachable dead code today) — do not add new getters here; fix the ROOT CAUSE so those existing getters actually get used, per Step 3.

The `offline_push_service.dart` fix is a bug fix, not just a translation gap: `OfflineSyncStrings.completed`/`.failed` already exist and are already the fallback shown in `offline_sync_screen.dart:275-277`, but `OfflinePushResult.message` is ALWAYS set to a raw literal on every outcome, so the translated fallback never fires — same shape as the `EnrollmentController`/`enrollmentFailed` bug fixed in the prior translation round.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/sync/sync_step_labels_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_lf_mobile/core/app_locale.dart';
import 'package:uhis_lf_mobile/core/sync/sync_progress.dart';

void main() {
  tearDown(() => AppLocale.current = AppLanguage.english);

  test('SyncStepX.label is byte-identical to the existing English text', () {
    AppLocale.current = AppLanguage.english;
    // Read sync_progress.dart first to confirm the exact enum/class name and
    // case names before writing these assertions — do not guess.
  });
}
```

Run: `grep -n "label\|class Sync" lib/core/sync/sync_progress.dart`
Use the exact type/case names found to fill in the test above with real assertions (one per step label, matching the 6 literals at lines 79-91) before proceeding — do not leave this test as a stub.

- [ ] **Step 2: Add `SyncStrings` getters and wire `sync_progress.dart`**

```dart
static String get connectingToServer => getTranslatedString('Sync.connectingToServer', 'Connecting to server');
static String get downloadingPatients => getTranslatedString('Sync.downloadingPatients', 'Downloading patients');
static String get downloadingFollowUps => getTranslatedString('Sync.downloadingFollowUps', 'Downloading follow-ups');
static String get downloadingReferrals => getTranslatedString('Sync.downloadingReferrals', 'Downloading referrals');
static String get processingData => getTranslatedString('Sync.processingData', 'Processing data');
static String get readyStatus => getTranslatedString('Sync.readyStatus', 'Ready');
```

Add the `app_strings.dart` import to `sync_progress.dart` and replace each `label` literal at lines 79-91 with its matching getter.

- [ ] **Step 3: Fix `offline_push_service.dart`'s root-cause message bug**

Read `offline_sync_screen.dart:270-280` first to confirm the exact fallback-check shape (`_message ?? OfflineSyncStrings.completed`-style or similar), then change `offline_push_service.dart` so `OfflinePushResult.message` is only set to a raw literal for genuinely unclassified/unexpected outcomes — for the two clearly-classifiable common outcomes (success, generic failure), set `message` to `OfflineSyncStrings.completed`/`.failed` directly instead of a raw literal, mirroring exactly how the prior round's `EnrollmentController.submitHousehold()` fix worked. For the more specific raw literals that don't have an existing `OfflineSyncStrings` equivalent (`'Not authenticated — sign in again before syncing'`, `'Sync already in progress'`, `'Nothing pending to sync'`, `'Follow-up sync failed — retry Offline Sync'`, `'Sync reported Failed for some records'`, `'Sync accepted — server still processing. Open Offline Sync again to refresh.'`), add new specific getters to `OfflineSyncStrings` for each and use those instead of the generic fallback, so no clinically-relevant detail is lost.

- [ ] **Step 4: Fix `repeat_scheduler.dart`'s notification fallback**

Add `NotificationStrings.referralReminderTitle` (`'Referral reminder'`) and `.referralReminderBody` (`'You have a pending referral alert.'`) (create `NotificationStrings` if no such class exists yet — check first), replace lines 84 and 86.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/sync/sync_step_labels_test.dart -v`
Expected: PASS

- [ ] **Step 6: Verify**

Run: `flutter analyze lib/core/sync/ lib/core/notifications/ lib/core/constants/app_strings.dart`
Expected: 0 errors.

Run: `flutter test test/core/sync/ test/features/sync/ -v`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/core/sync/ lib/core/notifications/ lib/core/constants/app_strings.dart test/core/sync/sync_step_labels_test.dart
git commit -m "fix(i18n): localize sync progress steps and fix offline-push message fallback bug"
```

---

### Task 14: Author Bangla for the 68 pre-existing missing `strings.json` codes

**Files:**
- Modify: `assets/translations/strings.json` (add 68 entries — no Dart code changes; every one of these 68 codes already correctly calls `getTranslatedString` today, they are simply absent from the JSON)

**Interfaces:** None — pure content addition.

Per the user's standing instruction this session ("add Bangla for all of it now," applied identically to the 320-code gap closed in the immediately-prior round), author Bangla for this older, smaller, pre-existing cluster too, so the whole app stops silently falling back to English for these namespaces. The 68 codes cluster into: `OfflineSync.*` (10), `DebugDb.*` (10, dev-only tooling — lower priority but still include for completeness), `Cce.*` (8), `Settings.*` (3) plus `settings`/`settingsSubtitle`, and ~35 singleton codes (`missedReasonLabel`, `referralFacilityLabel`, `q7RangeError`, `Triage.ancRevisitMessageNormal`, etc.).

- [ ] **Step 1: Re-extract the current authoritative missing-code list**

Run:
```bash
python3 - <<'EOF'
import re, json
with open('lib/core/constants/app_strings.dart', encoding='utf-8') as f:
    src = f.read()
codes = sorted(set(re.findall(r"getTranslatedString\(\s*'([^']+)'", src)))
with open('assets/translations/strings.json', encoding='utf-8') as f:
    translations = json.load(f)
missing = [c for c in codes if c not in translations]
print(len(missing))
for c in missing: print(c)
EOF
```
Expected: the count should be close to 68 but may differ slightly if Tasks 1-13 introduced or removed any of these specific codes — use THIS run's list as authoritative, not the hardcoded 68 from research.

- [ ] **Step 2: For each code, get its exact English fallback text**

Run the same fallback-extraction approach used in the prior round (regex over `getTranslatedString('code', 'fallback'`) to build a `code → English text` map for this run's missing-code list. Manually verify any code whose fallback contains Dart interpolation (`$var`) or a ternary — per the prior round's lessons, re-read the source directly for those rather than trusting a naive regex extraction, and convert to `{param}` template form before authoring Bangla.

- [ ] **Step 3: Write Bangla for each code**

Author natural, clear Bangla matching the established register and vocabulary (see Global Constraints) for each of the ~68 codes. This is content-writing, not code-editing — no test applies. Pay particular attention to the `Cce.*` cluster (call-result sheet: `willingYes`/`willingNo`/`willingToVisitUhc`/`notWillingReason`/`otherReasonHint`/`callResultTitle`/`callResultPrompt`/`callResultSubmit`) since it's clinically/operationally meaningful (whether a patient will visit the health complex), and `Triage.ancRevisitMessageNormal`/`.ancRevisitMessageHighRisk`/`.ancVisitedTodayMessage`/`.pwEpisodeSubtitle` since these are clinical ANC messages.

- [ ] **Step 4: Merge into `strings.json` and validate**

Run:
```bash
python3 -c "import json; json.load(open('assets/translations/strings.json', encoding='utf-8')); print('JSON valid')"
```
Expected: `JSON valid`, no exception.

Run:
```bash
python3 - <<'EOF'
import json
with open('assets/translations/strings.json', encoding='utf-8') as f:
    d = json.load(f)
missing = []  # re-paste this run's Step 1 list here
for c in missing:
    assert c in d and d[c].get('bn'), f"{c} still missing or empty"
print("All codes now have non-empty bn text")
EOF
```

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/`
Expected: 0 errors (JSON-only change, but confirms nothing else regressed).

Run: `flutter test 2>&1 | tail -20`
Expected: same failure count/names as Task 15's established baseline.

- [ ] **Step 6: Commit**

```bash
git add assets/translations/strings.json
git commit -m "feat(i18n): add Bangla translations for 68 pre-existing missing codes (OfflineSync, DebugDb, CCE, Settings, misc)"
```

---

### Task 15: Full-app verification, build, and device spot-check

**Files:** None modified — verification only.

- [ ] **Step 1: Establish/confirm the pre-existing failure baseline**

Run: `flutter test 2>&1 | tee /tmp/plan_final_test_run.log | tail -15`

Extract the failing-test list:
```bash
grep -E '\[E\]$' /tmp/plan_final_test_run.log | sed -E 's/^[0-9:]+ \+[0-9]+( -[0-9]+)?: //; s/ \[E\]$//' | sort -u > /tmp/plan_final_failures.txt
wc -l /tmp/plan_final_failures.txt
```
Expected: **37** (the confirmed-stable baseline established earlier this session, spanning `locale_provider_test.dart`, `auth_state_logout_wipe_integration_test.dart`, `app_database_wipe_test.dart`, `encounter_dao_vitals_test.dart`, `mission_dashboard_service_tier_test.dart`, `offline_sync_service_wipe_test.dart`, `form_prefill_vital_recovery_test.dart`, `ai_prefill_guard_test.dart`, `field_visibility_rules_test.dart`, `unified_form_notifier_clear_fields_test.dart`, `unified_payload_mapper_eye_care_test.dart`, `triage_view_model_test.dart` ×2, `visit_flow_screen_test.dart` ×6, plus several `loading /...` compile-load failures already confirmed pre-existing on the unmodified baseline). If the count or names differ from 37, diff against this list and investigate any NEW failure before proceeding — do not assume it's unrelated.

- [ ] **Step 2: Full static analysis**

Run: `flutter analyze lib/`
Expected: 0 errors (info/warning-level lints are fine and pre-existing).

- [ ] **Step 3: Confirm zero remaining missing-code regressions**

Re-run Task 14 Step 1's extraction script one final time against the fully-merged codebase.
Expected: 0 missing codes (every code in `app_strings.dart` now has a `strings.json` entry) — this is the plan's completion criterion for the translation-coverage half of the work.

- [ ] **Step 4: Build and install to the physical device**

Run:
```bash
flutter build apk --debug --dart-define=API_BASE_URL=https://spice-dev-backend.uhis.labsplatform.com/ --dart-define=PASSWORD_HASH_KEY=spice_uat
adb devices -l
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am force-stop com.medtroniclabs.uhis_next
adb shell monkey -p com.medtroniclabs.uhis_next -c android.intent.category.LAUNCHER 1
adb shell pidof com.medtroniclabs.uhis_next
```
Expected: build succeeds, install succeeds, a PID is returned (app launched and running).

- [ ] **Step 5: Manual spot-check, both locales**

In Bangla mode, confirm: household detail "Add Member" button, programme-enrollment screen tiles, pregnancy-registration EDD chip month name, CCE alert cards (badges, SLA lines, journey-strip step labels), CCE call-result sheet reject-reason chips, assistant chat starter chips and action buttons, scribe AI-field-indicator confidence/status chips, dashboard critical-alert banner and referral-operations widget, SK performance screen tabs and due-status text, a network-failure login/lock/PIN error message (e.g. airplane mode), and the offline-sync screen's status messages. In English mode, spot-check the same screens to confirm no visual regression (identical rendering to before this plan).

- [ ] **Step 6: Final report**

Summarize: total commits made, total new `strings.json` codes added across Tasks 1-13 (relocated-code convention — English fallback only, pending translator) vs. Task 14 (actively Bangla-authored), and the final dead-code line count removed in Task 11.
