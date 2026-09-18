/// Widget tests for [TeleconsultScreen], scoped to the states reachable
/// without ever rendering [ShukheeCallView] -- that widget hosts a real
/// platform WebView with no test double in this harness (see the SDK's own
/// test suite for coverage of everything below the WebView boundary, and
/// `webview-vs-tab-repro.spec.ts` / `initiate-call-dialog.spec.ts` in
/// `frappe-uhis-next/e2e` for the desk-side proof the top-level-navigation
/// approach actually joins a real call). Every test here keeps
/// `startConsultation` failing so the screen never transitions into the
/// `connected` stage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/teleconsult_prescription_dao.dart';
import 'package:uhis_next/core/theme/app_theme.dart';
import 'package:uhis_next/features/teleconsult/teleconsult_permission_service.dart';
import 'package:uhis_next/features/teleconsult/teleconsult_screen.dart';

/// Records every [startConsultation] call and always fails it with
/// [exceptionBuilder]'s result -- keeps every test on this side of the
/// `connected`/WebView stage.
class _FailingShukheeClient extends ShukheeClient {
  _FailingShukheeClient(this.exceptionBuilder, {this.delay = Duration.zero})
      : super(
          ShukheeConfig(baseUrl: '', authTokenProvider: () async => 'test-token'),
        );

  final ShukheeException Function() exceptionBuilder;

  /// Optional artificial delay before throwing -- lets a test reliably
  /// observe the transient "connecting" stage (which otherwise resolves to
  /// "error" within the same microtask-queue drain as a single `pump()`,
  /// since nothing here awaits real elapsed time by default).
  final Duration delay;

  final List<String> contactNumbers = [];
  final List<String> reasons = [];
  final List<String?> encounterIds = [];
  final List<String> specialities = [];
  final List<Map<String, List<ShukheeMediaFile>>> mediaGroupsCalls = [];
  int callCount = 0;

  /// Mirrors the real Shukhee sandbox's live speciality list (confirmed via
  /// `GET /patient/emergency-request-specialities`) so form tests exercise
  /// the same data shape production does -- including the sandbox's own
  /// data quirk of every entry sharing the *same* specialityId ("9"), which
  /// is exactly what caused every card to render as selected at once before
  /// selection was keyed off .title instead (see teleconsult_screen.dart's
  /// `_selectedSpeciality` doc comment).
  @override
  Future<List<ShukheeSpeciality>> getSpecialities() async => const [
        ShukheeSpeciality(specialityId: '9', title: 'General Physician'),
        ShukheeSpeciality(specialityId: '9', title: 'Sexual Wellness'),
        ShukheeSpeciality(specialityId: '9', title: 'Diabetic Coach'),
        ShukheeSpeciality(specialityId: '9', title: 'Maternity Coach'),
      ];

  @override
  Future<ShukheeBooking> startConsultation({
    required String contactNumber,
    required String reason,
    String requestedSpeciality = 'General Physician',
    String? encounterId,
    String? patientName,
    String? patientDob,
    String? patientGender,
    Map<String, List<ShukheeMediaFile>> mediaGroups = const {},
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    callCount++;
    contactNumbers.add(contactNumber);
    reasons.add(reason);
    encounterIds.add(encounterId);
    specialities.add(requestedSpeciality);
    mediaGroupsCalls.add(mediaGroups);
    throw exceptionBuilder();
  }
}

/// Always grants (or always denies, per [granted]) without touching any real
/// OS permission API.
class _FakePermissionService extends TeleconsultPermissionService {
  _FakePermissionService({this.granted = true});

  final bool granted;

  @override
  Future<bool> ensureCameraAndMicPermission(BuildContext context) async => granted;
}

// `_RecordSharedBanner` (rendered on both the connecting and wrap-up stages)
// reads `PartnerColors` off the real theme -- a bare MaterialApp's default
// ThemeData has no such extension registered, so tests need AppTheme.light.
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// Drives the booking form to submission: enters [phoneToEnter] if the field
/// is empty (it's pre-filled from `patientPhone` otherwise), optionally taps
/// a non-default speciality chip, then taps the submit button.
Future<void> _fillAndSubmitBookingForm(
  WidgetTester tester, {
  String? phoneToEnter,
  String? speciality,
}) async {
  // The speciality grid loads asynchronously (a live fetch in production) --
  // let it resolve before interacting with the form.
  await tester.pump();
  if (phoneToEnter != null) {
    await tester.enterText(find.byType(TextField), phoneToEnter);
  }
  if (speciality != null) {
    await tester.tap(find.text(speciality));
    await tester.pump();
  }
  await tester.tap(find.text(TeleconsultStrings.startConsultationButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // TeleconsultScreen resolves its TeleconsultPrescriptionDao up front, in
  // initState (see teleconsult_screen.dart) -- it must keep working after the
  // widget is disposed, when `context.read` is no longer safe, so it's
  // captured once eagerly instead of read lazily. Every test below must
  // therefore supply one; none of them ever complete a call (every
  // `_FailingShukheeClient` always throws), so a real but never-written-to
  // in-memory DAO is enough -- no fake/mock needed.
  late final TeleconsultPrescriptionDao testDao;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: AppDatabase.schemaVersion, onCreate: AppDatabase.createSchema),
    );
    testDao = TeleconsultPrescriptionDao(AppDatabase.forTesting(db));
  });

  testWidgets('shows the booking form with General Physician pre-selected', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('boom'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );

    expect(find.text(TeleconsultStrings.bookingTitle), findsOneWidget);

    // The speciality grid loads asynchronously (a live fetch in production).
    await tester.pump();
    expect(find.text(TeleconsultStrings.specialityGeneralPhysician), findsOneWidget);
    expect(find.text(TeleconsultStrings.startConsultationButton), findsOneWidget);
    expect(client.callCount, 0);
  });

  testWidgets('blocks submit and shows a validation error when contact number is empty', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('should not be called'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );

    // Let the speciality grid load -- the submit button is disabled until it
    // does, matching production (never lets a booking through with no
    // speciality selection yet resolved).
    await tester.pump();
    await tester.tap(find.text(TeleconsultStrings.startConsultationButton));
    await tester.pump();

    expect(find.text(TeleconsultStrings.contactNumberRequired), findsOneWidget);
    expect(client.callCount, 0);
  });

  testWidgets('books with the phone entered on the form, then shows the connecting screen', (tester) async {
    // A real (fake-clock) delay -- otherwise the permission-check hop and
    // the booking-call hop both resolve within the same pump()'s
    // microtask-queue drain, and the transient "connecting" stage is never
    // observably distinct from "error".
    final client = _FailingShukheeClient(() => const ShukheeBookingException('boom'), delay: const Duration(seconds: 5));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );

    await tester.pump(); // let the speciality grid load, enabling submit
    await tester.enterText(find.byType(TextField), '+8801999999999');
    await tester.tap(find.text(TeleconsultStrings.startConsultationButton));
    await tester.pump();

    expect(find.text(TeleconsultStrings.connectingHeaderTitle), findsOneWidget);
    expect(find.text(TeleconsultStrings.lookingForDoctor), findsOneWidget);

    // Advance past both the fake delay and the 2s connecting-gate timer so
    // nothing leaks into the next test.
    await tester.pump(const Duration(seconds: 6));
    expect(client.callCount, 1);
    expect(client.contactNumbers.single, '+8801999999999');
  });

  testWidgets('passes the given reason, encounterId, and default speciality through to the booking call', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('boom'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        visitId: 'VISIT-1',
        reason: 'Severe pneumonia, referral recommended',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );

    await _fillAndSubmitBookingForm(tester);

    expect(client.reasons.single, 'Severe pneumonia, referral recommended');
    expect(client.encounterIds.single, 'VISIT-1');
    expect(client.specialities.single, 'General Physician');
    // No photos picked -- no media group keys sent at all.
    expect(client.mediaGroupsCalls.single, isEmpty);
  });

  testWidgets('passes a non-default speciality selection through to the booking call', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('boom'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );

    await _fillAndSubmitBookingForm(
      tester,
      speciality: TeleconsultStrings.specialitySexualWellness,
    );

    expect(client.specialities.single, 'Sexual Wellness');
  });

  testWidgets('exactly one speciality card renders as selected at a time, even though the sandbox reuses one specialityId across all of them', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('boom'));
    final specialityLabels = [
      TeleconsultStrings.specialityGeneralPhysician,
      TeleconsultStrings.specialitySexualWellness,
      TeleconsultStrings.specialityDiabeticCoach,
      TeleconsultStrings.specialityMaternityCoach,
    ];

    Set<String> selectedLabels() {
      final selected = <String>{};
      for (final label in specialityLabels) {
        final text = tester.widget<Text>(find.text(label));
        if (text.style?.color == AppColors.navy) selected.add(label);
      }
      return selected;
    }

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );
    await tester.pump(); // let the speciality grid load

    expect(selectedLabels(), {TeleconsultStrings.specialityGeneralPhysician});

    await tester.tap(find.text(TeleconsultStrings.specialityMaternityCoach));
    await tester.pump();

    expect(selectedLabels(), {TeleconsultStrings.specialityMaternityCoach});
  });

  testWidgets('blocks booking entirely when camera/mic permission is denied', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('should not be called'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(granted: false),
      )),
    );

    await _fillAndSubmitBookingForm(tester);

    expect(client.callCount, 0);
    expect(find.text(TeleconsultStrings.cameraMicRequiredBody), findsOneWidget);
  });

  testWidgets('shows the non-retryable not-provisioned state for ShukheeNotProvisionedException', (tester) async {
    final client = _FailingShukheeClient(
      () => const ShukheeNotProvisionedException('No Provider record found for the calling user.'),
    );

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );

    await _fillAndSubmitBookingForm(tester);
    await tester.pumpAndSettle();

    expect(find.text(TeleconsultStrings.notProvisionedTitle), findsOneWidget);
    expect(find.text(TeleconsultStrings.tryAgain), findsNothing);
  });

  testWidgets('shows a retryable error state for ShukheeBookingException, and Retry re-books with the same values', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('Network error'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
        prescriptionDao: testDao,
        permissionService: _FakePermissionService(),
      )),
    );

    await _fillAndSubmitBookingForm(tester);
    await tester.pumpAndSettle();

    expect(find.text('Network error'), findsOneWidget);
    expect(client.callCount, 1);

    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();

    expect(client.callCount, 2);
    expect(client.contactNumbers, ['+8801000000000', '+8801000000000']);
    expect(client.specialities, ['General Physician', 'General Physician']);
  });

  // NOTE: the background-poll-survives-disposal fix in teleconsult_screen.dart
  // (removing the `mounted` guard around _savePrescriptionToVisit, resolving
  // TeleconsultPrescriptionDao in initState) has no widget test here. A
  // successful startConsultation unconditionally builds an offstage
  // ShukheeCallView (a real platform WebView) the moment the "connecting"
  // stage renders -- which this harness cannot support (see this file's top
  // doc comment: no WebViewPlatform test double exists), and building it
  // throws regardless of whether the underlying poll/save logic is correct.
  // Confirmed manually instead: a live device run's ConsoleLog showed
  // `[TeleconsultPrescription] saved ...` after backing out of an in-progress
  // call, and an ad hoc version of this test (a fake client that succeeds
  // startConsultation) reached the same save line before being removed for
  // that reason.
}
