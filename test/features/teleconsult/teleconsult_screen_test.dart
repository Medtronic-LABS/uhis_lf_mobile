/// Widget tests for [TeleconsultScreen], scoped to the states reachable
/// without ever rendering [ShukheeCallView] -- that widget hosts a real
/// platform WebView with no test double in this harness (see the SDK's own
/// test suite for coverage of everything below the WebView boundary, and
/// `webview-vs-tab-repro.spec.ts` / `initiate-call-dialog.spec.ts` in
/// `frappe-uhis-next/e2e` for the desk-side proof the top-level-navigation
/// approach actually joins a real call). Every test here keeps
/// `startConsultation` failing so the screen never transitions into the
/// `Connected` stage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/features/teleconsult/teleconsult_screen.dart';

/// Records every [startConsultation] call and always fails it with
/// [exception] (or a fresh one from [exceptionBuilder] per call, if given) --
/// keeps every test on this side of the Connected/WebView stage.
class _FailingShukheeClient extends ShukheeClient {
  _FailingShukheeClient(this.exceptionBuilder)
      : super(
          ShukheeConfig(baseUrl: '', authTokenProvider: () async => 'test-token'),
        );

  final ShukheeException Function() exceptionBuilder;
  final List<String> contactNumbers = [];
  final List<String> reasons = [];
  final List<String?> encounterIds = [];
  int callCount = 0;

  @override
  Future<ShukheeBooking> startConsultation({
    required String contactNumber,
    required String reason,
    String requestedSpeciality = 'General Physician',
    String? encounterId,
    String? patientName,
    String? patientDob,
    String? patientGender,
  }) async {
    callCount++;
    contactNumbers.add(contactNumber);
    reasons.add(reason);
    encounterIds.add(encounterId);
    throw exceptionBuilder();
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows the connecting/booking state before the network call resolves', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('slow'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
      )),
    );

    // First frame, before the (fake, but still async) network call settles.
    expect(find.text(TeleconsultStrings.connecting), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('prompts for a phone number when none was supplied, and cancelling pops without booking', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('should not be called'));

    await tester.pumpWidget(
      _wrap(Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => TeleconsultScreen(
            patientLabel: 'Test Patient',
            patientId: 'p1',
            reason: 'Fever',
            client: client,
          ),
        ),
      )),
    );
    // Bounded pumps, not pumpAndSettle: the booking stage's indeterminate
    // CircularProgressIndicator animates forever and would time it out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(TeleconsultStrings.phonePromptTitle), findsOneWidget);

    // Submitting with an empty field pops the screen rather than booking.
    await tester.tap(find.text(TeleconsultStrings.phonePromptSubmit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.callCount, 0);
  });

  testWidgets('books with the phone entered in the prompt sheet', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('boom'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        reason: 'Fever',
        client: client,
      )),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), '+8801999999999');
    await tester.tap(find.text(TeleconsultStrings.phonePromptSubmit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.callCount, 1);
    expect(client.contactNumbers.single, '+8801999999999');
  });

  testWidgets('passes the given reason and encounterId through to the booking call', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('boom'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        visitId: 'VISIT-1',
        reason: 'Severe pneumonia, referral recommended',
        client: client,
      )),
    );
    await tester.pumpAndSettle();

    expect(client.reasons.single, 'Severe pneumonia, referral recommended');
    expect(client.encounterIds.single, 'VISIT-1');
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
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text(TeleconsultStrings.notProvisionedTitle), findsOneWidget);
    expect(find.text(TeleconsultStrings.tryAgain), findsNothing);
  });

  testWidgets('shows a retryable error state for ShukheeBookingException, and Retry re-books', (tester) async {
    final client = _FailingShukheeClient(() => const ShukheeBookingException('Network error'));

    await tester.pumpWidget(
      _wrap(TeleconsultScreen(
        patientLabel: 'Test Patient',
        patientId: 'p1',
        patientPhone: '+8801000000000',
        reason: 'Fever',
        client: client,
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('Network error'), findsOneWidget);
    expect(client.callCount, 1);

    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();

    expect(client.callCount, 2);
  });
}
