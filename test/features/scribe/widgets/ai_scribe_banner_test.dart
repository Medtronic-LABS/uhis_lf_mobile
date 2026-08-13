/// Widget test for [AiScribeBanner]'s realtime-ASR error visibility.
///
/// Regression coverage for the bug described in
/// `.superpowers/sdd/2026-08-13-realtime-asr-silent-failure-fixes/task-3-brief.md`:
/// [RealtimeAsrController.isActive] deliberately excludes
/// [RealtimeAsrState.error] (it means "session occupying the mic/socket"),
/// but the banner used to gate *rendering* on `isActive` alone — so the
/// instant a live session errored, the banner fell back to looking like the
/// plain idle "tap to record" state, and the only widget that ever displayed
/// `errorMessage` ([AiScribeLiveAsrPanel]) unmounted with it. The SK never
/// saw the error.
///
/// [AiScribeBanner] builds its own [RealtimeAsrController] internally (not
/// injectable), and its [ScribePermissionService] is hardcoded to the real
/// implementation — so this test reaches [RealtimeAsrState.error] via the
/// same real mic-permission-denied path production code takes, using the
/// permission_handler plugin's own supported test seam
/// ([PermissionHandlerPlatform.instance]) to make [ScribePermissionService]
/// see a "denied" status without a real platform channel or any network
/// call. Declining the on-screen rationale sheet then completes the "denied"
/// path deterministically, matching [RealtimeAsrController]'s own
/// `mic_permission_denied` category (see
/// test/features/realtime_asr/realtime_asr_controller_test.dart, which
/// reaches the same state by injecting a fake [ScribePermissionService]
/// directly into [RealtimeAsrController] — not an option here since
/// [AiScribeBanner] doesn't expose that seam).
library;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/api/realtime_asr_service.dart';
import 'package:uhis_next/core/api/scribe_api_service.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/preferences/scribe_audio_settings_notifier.dart';
import 'package:uhis_next/core/preferences/vad_tuning_notifier.dart';
import 'package:uhis_next/features/scribe/scribe_controller.dart';
import 'package:uhis_next/features/scribe/scribe_permission_service.dart';
import 'package:uhis_next/features/scribe/widgets/ai_scribe_banner.dart';

/// Minimal fake of the `record` plugin's platform interface — same
/// convention as `test/features/realtime_asr/realtime_asr_controller_test.dart`'s
/// `FakeRecordPlatform`. [ScribeController] and [RealtimeAsrController] both
/// construct a `record` recorder eagerly; this test never reaches any actual
/// recording call (both the mic-permission-denied path and the
/// encounterId-forwarding test's [_CapturingRealtimeAsrService] return/throw
/// before any recorder method is invoked), so only construction-adjacent
/// calls need a safe (non-throwing) stand-in.
class _FakeRecordPlatform extends RecordPlatform {
  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// Fakes the `permission_handler` plugin's platform interface so
/// `Permission.microphone.status` resolves to "denied" (not "granted", not
/// "permanently denied") without a real platform channel — the exact seam
/// the `permission_handler` package's own test suite uses to stub this
/// interface. "Denied" (rather than "permanently denied") is what routes
/// [ScribePermissionService] through the in-app rationale sheet instead of
/// the settings dialog, so declining it is a plain widget tap, not a
/// simulated OS settings round-trip.
class _DeniedPermissionHandlerPlatform extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.denied;
}

/// Same seam as [_DeniedPermissionHandlerPlatform], resolved "granted"
/// instead — lets a test drive [RealtimeAsrController.start] past the
/// mic-permission check (which short-circuits immediately on
/// `status.isGranted`, see [ScribePermissionService.ensureMicPermission])
/// without a real platform channel, so the banner's call into
/// [RealtimeAsrService.connectionInfo] is actually reached.
class _GrantedPermissionHandlerPlatform extends PermissionHandlerPlatform {
  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.granted;
}

/// Records the `encounterId` argument [AiScribeBanner] passes down into
/// [RealtimeAsrController.start] -> [RealtimeAsrService.connectionInfo] —
/// the regression seam for the bug where `_startAsr()` never forwarded
/// `widget.encounterId`, so this always arrived as `null` in production.
///
/// Throws immediately after capturing, instead of returning a connection and
/// letting `start()` attempt a real WebSocket handshake: [RealtimeAsrState]
/// wiring beyond this call (the socket, the recorder, the auto-extract
/// timer) is exercised and asserted elsewhere in this codebase — this test
/// only needs to prove the argument below, and `start()`'s own catch block
/// already turns this into a clean, immediate error state (see
/// `RealtimeAsrController.start`'s `catch (e, st)` clause).
class _CapturingRealtimeAsrService extends RealtimeAsrService {
  _CapturingRealtimeAsrService(super.api);

  String? capturedEncounterId;
  bool connectionInfoCalled = false;

  @override
  Future<RealtimeAsrConnectionInfo> connectionInfo({
    required String language,
    String model = 'saarika:v2.5',
    String? assessmentType,
    List<String>? symptomVocab,
    String? encounterId,
  }) async {
    connectionInfoCalled = true;
    capturedEncounterId = encounterId;
    throw StateError('_CapturingRealtimeAsrService: no real connection in this test');
  }
}

/// The banner wraps its tappable content in exactly one `Semantics(button:
/// ..., label: ...)` node (see `ai_scribe_banner.dart`'s `build()`) — found
/// here by that `button` property rather than by type, since `MaterialApp`/
/// `Scaffold` insert their own framework `Semantics` nodes elsewhere in the
/// tree. No existing test in this codebase asserts on a `Semantics` label
/// (confirmed via a repo-wide search), so this is a new, minimal pattern:
/// read the widget's `properties.label` directly rather than standing up the
/// full semantics-tree binding (`tester.ensureSemantics()`), since only the
/// label string — not focus/traversal order — is under test here.
String? _bannerSemanticsLabel(WidgetTester tester) {
  final semantics = tester.widgetList<Semantics>(
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.button == true),
  );
  return semantics.single.properties.label;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform originalRecordPlatform;
  late PermissionHandlerPlatform originalPermissionPlatform;
  late ApiClient apiClient;

  setUp(() async {
    originalRecordPlatform = RecordPlatform.instance;
    RecordPlatform.instance = _FakeRecordPlatform();

    originalPermissionPlatform = PermissionHandlerPlatform.instance;
    PermissionHandlerPlatform.instance = _DeniedPermissionHandlerPlatform();

    apiClient = await ApiClient.create();
  });

  tearDown(() {
    RecordPlatform.instance = originalRecordPlatform;
    PermissionHandlerPlatform.instance = originalPermissionPlatform;
  });

  Widget buildBanner({RealtimeAsrService? realtimeAsrService, String encounterId = 'enc-1'}) {
    final audioSettings = ScribeAudioSettingsNotifier(const FlutterSecureStorage());
    final scribeController = ScribeController(
      api: ScribeApiService(apiClient),
      permissionService: ScribePermissionService(),
      audioSettings: audioSettings,
    );

    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<ScribeController>.value(value: scribeController),
            Provider<RealtimeAsrService>.value(
              value: realtimeAsrService ?? RealtimeAsrService(apiClient),
            ),
            ChangeNotifierProvider<VadTuningNotifier>.value(
              value: VadTuningNotifier(const FlutterSecureStorage()),
            ),
            ChangeNotifierProvider<ScribeAudioSettingsNotifier>.value(
              value: audioSettings,
            ),
          ],
          child: AiScribeBanner(
            encounterId: encounterId,
            patientId: 'patient-1',
            isFemale: false,
            tapStartsLiveAsr: true,
            onReviewReady: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets(
      'an errored live session shows an error message, not a bare idle banner',
      (tester) async {
    await tester.pumpWidget(buildBanner());
    await tester.pump();

    // Sanity check on the starting point: plain idle banner, no error.
    expect(
      find.text(SymptomPickerStrings.scribeBannerTitleFor(isFemale: false)),
      findsOneWidget,
    );
    expect(
      _bannerSemanticsLabel(tester),
      SymptomPickerStrings.scribeBannerTitleFor(isFemale: false),
    );

    // Act: tap the idle banner — `tapStartsLiveAsr: true` routes this
    // through `RealtimeAsrController.start()`, which awaits
    // `ScribePermissionService.ensureMicPermission()` before ever touching
    // the network. That call shows the in-app rationale sheet first.
    //
    // Note: this deliberately avoids `pumpAndSettle()` here — while
    // permission resolution is pending, the banner shows an indeterminate
    // `CircularProgressIndicator` (the "connecting" mic-circle spinner),
    // which animates forever and would make `pumpAndSettle()` time out.
    await tester.tap(find.byType(AiScribeBanner));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(ScribeStrings.rationaleNotNow), findsOneWidget,
        reason: 'the rationale sheet should be showing while mic permission '
            'is not yet granted');
    await tester.tap(find.text(ScribeStrings.rationaleNotNow));
    await tester.pumpAndSettle();

    // Assert: the live session is now in RealtimeAsrState.error, and that
    // must be visible — not indistinguishable from the plain idle banner.
    expect(find.text(RealtimeAsrStrings.errorTitle), findsOneWidget);
    // The error message renders in both the banner subtitle and the inline
    // live panel — assert it is visible at all, not an exact count, since
    // that duplication is an implementation detail of where the panel
    // chooses to also echo it.
    expect(find.text(RealtimeAsrStrings.micPermissionDenied), findsWidgets);
    expect(
      find.text(SymptomPickerStrings.scribeBannerTitleFor(isFemale: false)),
      findsNothing,
      reason: 'an unacknowledged live-ASR error must not be indistinguishable '
          'from the plain idle "tap to record" banner',
    );
    // The visible title/subtitle are not what a screen-reader user hears —
    // the accessibility label must independently announce the error too,
    // or a screen-reader user gets no indication anything went wrong even
    // though sighted users now see the fix above.
    expect(_bannerSemanticsLabel(tester), RealtimeAsrStrings.errorTitle);
  });

  testWidgets(
      'tapping the banner forwards widget.encounterId into the realtime ASR '
      'connection request',
      (tester) async {
    // Regression coverage for the encounterId-not-forwarded bug: `_startAsr()`
    // in ai_scribe_banner.dart called `_liveCtrl.start(...)` without
    // `encounterId: widget.encounterId`, so the correlation id Task 4 added
    // never reached `RealtimeAsrService.connectionInfo` (and so never reached
    // the backend, or this widget's own `[AsrDiag]` log lines) in production —
    // even though `RealtimeAsrController` itself, and `RealtimeAsrService`
    // directly, both handled `encounterId` correctly. Unlike
    // `test/features/realtime_asr/realtime_asr_controller_test.dart`'s own
    // encounterId coverage (which calls `ctrl.start(encounterId: ...)`
    // directly), this drives the real production entry point — a tap on
    // [AiScribeBanner] — so it actually exercises the wiring that broke.
    PermissionHandlerPlatform.instance = _GrantedPermissionHandlerPlatform();
    final capturingService = _CapturingRealtimeAsrService(apiClient);

    await tester.pumpWidget(
      buildBanner(realtimeAsrService: capturingService, encounterId: 'enc-encounter-forwarding'),
    );
    await tester.pump();

    await tester.tap(find.byType(AiScribeBanner));

    // Mic permission is already granted, so `ensureMicPermission` returns
    // immediately without showing the rationale sheet — a few pumps are
    // enough to carry `start()` through to its `connectionInfo(...)` call.
    for (var i = 0; i < 50 && !capturingService.connectionInfoCalled; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(capturingService.connectionInfoCalled, isTrue,
        reason: 'start() should have reached RealtimeAsrService.connectionInfo '
            'by now');
    expect(capturingService.capturedEncounterId, 'enc-encounter-forwarding');
  });
}
