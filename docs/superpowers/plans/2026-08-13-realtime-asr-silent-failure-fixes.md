# Realtime ASR Silent-Failure Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the confirmed and highest-confidence causes of the intermittent "recording completes, no transcript, no form fields, no visible error" realtime ASR bug — two of which were caught live on a physical device during manual testing while this plan was being written, not just hypothesized from static analysis.

**Architecture:** No architecture changes. This is a sequence of small, surgical fixes to the existing `RealtimeAsrController` (Flutter client) and `run_bridge_session` (Python backend proxy), each independently shippable and each directly traceable to a specific piece of evidence (either the prior static investigation or the live manual-test logs captured today). Diagnostics added in the prior two tasks (`AsrDiagnostics` client-side, `asr_diagnostics.py` server-side) are the verification tool for every fix below — each task's "how to verify" step reads the same `[AsrDiag]` event stream, not new instrumentation.

**Tech Stack:** Flutter/Dart (`uhis_lf_mobile`), Python/FastAPI (`leapfrog-ai-service`), `flutter_test` + `pytest`.

## Global Constraints

- No reconnection logic, no VAD threshold changes, no protocol changes, no auth changes — every task below is a targeted correctness fix, not a resilience overhaul. If a task's investigation reveals that fixing it properly requires one of these, stop and flag it rather than scope-creeping into it.
- Every new/changed log line must stay PHI-safe: no transcript text, no audio, no clinical values, no tokens/headers. Reuse the existing `AsrDiagnostics.event` (Dart) / `log_event` (Python) chokepoints — do not invent a second logging path.
- Preserve the existing Engineering Design Standards from `leapfrog-setup/CLAUDE.md` and `uhis_lf_mobile/CLAUDE.md`: no hardcoded strings outside `app_strings.dart`, narrow exception handling, small intention-revealing functions.
- Two repos are in play. All paths below are relative to `leapfrog-setup/` unless the task header says otherwise: client paths start `uhis_lf_mobile/`, backend paths start `leapfrog-ai-service/`.
- Every task must leave both repos' existing test suites green (`flutter test` / `pytest tests/`) in addition to its own new test.

---

## Evidence index (why these seven tasks, in this order)

| # | Finding | Source | Confidence |
|---|---|---|---|
| 1 | `RealtimeAsrController` used after `dispose()` → real crash | **Live-caught tonight**, physical Pixel 10a, debug build | Confirmed |
| 2 | T6: a dead WS channel gets resurrected into `listening` | Static investigation (Part 2), traced to exact lines | Confirmed by code reading; live occurrence not yet isolated |
| 3 | Realtime errors are structurally invisible in `AiScribeBanner` (`isActive` excludes `error`) | Static investigation (Part 2) | Confirmed by code reading |
| 4 | Backend never receives `encounterId` → `encounter_id=unknown` on every backend event | **Live-confirmed tonight** in every backend log line | Confirmed |
| 5 | Final extraction cancelled on stop/disconnect, losing the SK's last utterance | **Live-caught tonight** (`ASR_FINAL_EXTRACT_CANCELLED`, `exitPath=client_disconnect`) | Confirmed |
| 6 | A single bad Sarvam frame can silently end the whole session with no clear signal | Static investigation (Part 1/2, hypothesis H2/T7) | Hypothesized; not yet observed live |
| 7 | Three `RealtimeAsrController`s created/disposed within 10s without ever starting | **Live-observed tonight** | Observed; root cause unknown |

Tasks are ordered by (a) confirmed-live before hypothesized, (b) client safety fixes before behavior fixes, (c) fixes that unblock future diagnosis (encounterId) done early.

---

## Task 1: Guard `RealtimeAsrController` against use-after-dispose

**Why this is first:** this crashed for real, tonight, twice, in the middle of a live test session (`Unhandled Exception: A RealtimeAsrController was used after being disposed.`). It's a real bug, not a hypothesis, and it's the cheapest, lowest-risk fix in this plan — it only makes an already-invalid operation into a no-op instead of a throw.

**Root cause:** `ChangeNotifier`'s post-dispose guard (`_debugAssertNotDisposed()`) is wrapped in `assert()`, which is stripped in release builds — so in production this same misuse would silently succeed against disposed internal state instead of throwing. It only surfaced tonight because the test APK was built with `flutter build apk --debug`. Something (most likely `_teardown()`'s own async chain, or the `extractNow()` 20s safety-timeout callback, or `_onSocketDone` firing after the widget that owns this controller already disposed it) calls a method that ends in `notifyListeners()` after `dispose()` already ran.

**Files:**
- Modify: `uhis_lf_mobile/lib/features/realtime_asr/realtime_asr_controller.dart`
- Test: `uhis_lf_mobile/test/features/realtime_asr/realtime_asr_controller_test.dart` (already exists from the instrumentation task)

**Interfaces:**
- Consumes: nothing new.
- Produces: a private `bool get isDisposed` — no public API change. `AiScribeBanner` and all other current callers are unaffected.

- [ ] **Step 1: Write the failing test**

Add to `realtime_asr_controller_test.dart` (reuses the existing `FakeRecordPlatform`/`_dev_patches`-style harness already in that file):

```dart
test('calling stop() after dispose() does not throw', () async {
  final ctrl = buildController(Uri.parse('ws://127.0.0.1:1'), granted: false);
  ctrl.bindContext(_dummyContext());
  await ctrl.start(encounterId: 'enc-dispose-guard');
  ctrl.dispose();
  // Must not throw "used after being disposed" — this reproduces the
  // shape of the live crash (a call landing after dispose()), just via
  // a synchronous call instead of the harder-to-reproduce async race.
  expect(() => ctrl.stop(), returnsNormally);
});

test('extractNow safety-timeout callback firing after dispose does not throw', () async {
  final ctrl = buildController(Uri.parse('ws://127.0.0.1:1'), granted: false);
  ctrl.bindContext(_dummyContext());
  await ctrl.start(encounterId: 'enc-dispose-guard-2');
  ctrl.dispose();
  // extractNow()'s Future.delayed(_extractionSafetyTimeout, ...) callback
  // can still be scheduled from before dispose() — pump past it and
  // confirm no notifyListeners()-after-dispose throw.
  await Future<void>.delayed(const Duration(seconds: 21));
});
```

- [ ] **Step 2: Run tests to verify they fail (or pass suspiciously)**

Run: `flutter test test/features/realtime_asr/realtime_asr_controller_test.dart --plain-name "after dispose"`
Expected: depends on which method the live crash actually came from; at minimum this documents current behavior before the fix. If both pass already, that's fine — Step 4 below still needs to hold for every call path, not just these two.

- [ ] **Step 3: Add the disposed guard**

In `realtime_asr_controller.dart`, add a field right after the other diagnostics-only state (near `bool _summaryEmitted = false;`):

```dart
  /// Set exactly once, in [dispose]. Every method that can run after an
  /// async gap (an awaited call, a Future.delayed callback, a stream
  /// event) must check this before touching state or calling
  /// notifyListeners() — ChangeNotifier's own post-dispose guard is wrapped
  /// in `assert()`, which compiles out in release builds, so without this
  /// check a post-dispose call silently operates on a disposed instance in
  /// production and throws only in debug builds (this is exactly what
  /// crashed a live test session — see Task 1 of the remediation plan).
  bool _disposed = false;
```

Replace every bare `notifyListeners();` call in this file with a guarded call through one new private helper — add the helper right next to `_logEvent`:

```dart
  /// Guarded notifyListeners() — every call site in this file goes through
  /// here instead of calling notifyListeners() directly, so a callback that
  /// resumes after [dispose] (an awaited call, a Timer, a Future.delayed)
  /// can never throw "used after being disposed".
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }
```

Then do a file-wide replace of `notifyListeners();` → `_safeNotify();` in this file (every call site: `start()`, `stop()`, `extractNow()`, `_onAudioChunk`/`_trackStuckAmplitude`, `_onMessage`, `_onSocketDone`, `_setError`). Do not touch `dispose()` itself — it calls `super.dispose()`, not `notifyListeners()`.

Also guard the two methods most likely to run long after dispose — add an early return at the top of each:

```dart
  Future<void> stop() async {
    if (_disposed) return;
    if (_state == RealtimeAsrState.idle ||
```

```dart
  void _onSocketDone() {
    if (_disposed) return;
    final previousState = _state;
```

Finally, set the flag first in `dispose()`:

```dart
  @override
  void dispose() {
    _disposed = true;
    _autoExtractTimer?.cancel();
    _audioSub?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _recorder.dispose();
    _emitSessionSummaryOnce();
    super.dispose();
  }
```

- [ ] **Step 4: Run the tests again**

Run: `flutter test test/features/realtime_asr/realtime_asr_controller_test.dart`
Expected: PASS — all existing tests plus the two new ones from Step 1, with zero "used after being disposed" exceptions anywhere in the run output.

- [ ] **Step 5: Run the full client test suite to confirm no regression**

Run: `flutter test`
Expected: PASS, same pass/fail counts as before this change (no new failures introduced).

- [ ] **Step 6: Manual verification path (for the next physical-device session)**

Rebuild and reinstall per the same steps used tonight (`flutter build apk --debug --dart-define=AI_SERVICE_URL=http://localhost:8095 ...`, `adb reverse tcp:8095 tcp:8095`, uninstall+install+launch on the Pixel 10a). Repeat the same navigation pattern that triggered the crash tonight (rapid back-out of a visit screen while a realtime session is active/stopping) and confirm the `[AsrDiag]` logcat stream shows no `Unhandled Exception` line.

- [ ] **Step 7: Commit**

```bash
git add lib/features/realtime_asr/realtime_asr_controller.dart test/features/realtime_asr/realtime_asr_controller_test.dart
git commit -m "fix: guard RealtimeAsrController against use-after-dispose

A live test session crashed with 'RealtimeAsrController was used after
being disposed' — real in debug builds, silently corrupting state in
release builds since the underlying ChangeNotifier check is assert-only.
Route every notifyListeners() through a disposed-guarded helper."
```

---

## Task 2: Stop resurrecting a dead WS channel into `listening` (T6)

**Why now:** this is the single highest-ranked static hypothesis from the original investigation, and it's cheap to fix now that Task 1's disposed-guard makes the surrounding code safer to touch.

**Root cause (from the investigation, `realtime_asr_controller.dart`'s `start()`):** if the WS handshake fails while `_recorder.hasPermission()`/`.startStream()` are still being awaited, `onError`'s `_setError()` call can run *before* `start()`'s own unconditional `_state = RealtimeAsrState.listening;` write — silently overwriting the correctly-reported error back to a healthy-looking "Listening" state, with `_channel == null` underneath. The existing `ASR_LISTENING_WITHOUT_WS` diagnostic (added in the prior instrumentation task) already detects this condition; this task changes what happens once it's detected, instead of just logging it.

**Files:**
- Modify: `uhis_lf_mobile/lib/features/realtime_asr/realtime_asr_controller.dart`
- Test: `uhis_lf_mobile/test/features/realtime_asr/realtime_asr_controller_test.dart`

**Interfaces:**
- Consumes: `_teardown()`, `_setError()`, `_emitSessionSummaryOnce()` — all already exist, unchanged signatures.
- Produces: no new public API. `start()`'s external behavior changes only in the failure case: a session that would have silently claimed `listening` with a dead channel now correctly ends in `error` (which Task 3 below makes visible).

- [ ] **Step 1: Write the failing test**

The existing test `'WS closes during the recorder-start await → the resulting idle state is unconditionally overwritten back to listening'` in `realtime_asr_controller_test.dart` currently *documents* the bug (its own docstring says so). Replace its final assertions to assert the *fixed* behavior:

```dart
      final finalStateLine = logs.firstWhere((l) => l.contains('ASR_START_FINAL_STATE'));
      expect(finalStateLine, contains('currentState=idle'));
      // Fixed behavior: start() must NOT resurrect the already-torn-down
      // idle state back into listening.
      expect(ctrl.state, isNot(RealtimeAsrState.listening));
```

- [ ] **Step 2: Run test to verify it now fails against current code**

Run: `flutter test test/features/realtime_asr/realtime_asr_controller_test.dart --plain-name "T6"`
Expected: FAIL — `ctrl.state` is currently `RealtimeAsrState.listening`.

- [ ] **Step 3: Fix `start()`**

In `realtime_asr_controller.dart`, find the T6 instrumentation block (right before the unconditional `_state = RealtimeAsrState.listening;` write):

```dart
      final channelAvailable = _channel != null;
      _logEvent('ASR_START_FINAL_STATE', {
        'channelAvailable': channelAvailable,
        'currentState': _state.name,
        'recorderStarted': true,
      });
      if (!channelAvailable) {
        _logEvent('ASR_LISTENING_WITHOUT_WS', {'currentState': _state.name});
      }

      _state = RealtimeAsrState.listening;
      notifyListeners();
      _logEvent('ASR_LISTENING', const {});
```

Replace with:

```dart
      final channelAvailable = _channel != null;
      _logEvent('ASR_START_FINAL_STATE', {
        'channelAvailable': channelAvailable,
        'currentState': _state.name,
        'recorderStarted': true,
      });
      if (!channelAvailable) {
        _logEvent('ASR_LISTENING_WITHOUT_WS', {'currentState': _state.name});
        // The WS already failed (onError/onSocketDone already ran, or is
        // running) while we were awaiting the recorder — do not resurrect a
        // dead session by claiming `listening`. Tear down the mic stream we
        // just started and end this attempt as a failure instead.
        await _teardown(reason: 'start_failed_no_channel');
        if (_state != RealtimeAsrState.error) {
          _setError(
            RealtimeAsrStrings.couldNotStart('WebSocket unavailable'),
            category: 'ws_not_available_at_listening',
          );
        }
        _emitSessionSummaryOnce();
        return;
      }

      _state = RealtimeAsrState.listening;
      _safeNotify();
      _logEvent('ASR_LISTENING', const {});
```

- [ ] **Step 4: Run the test again**

Run: `flutter test test/features/realtime_asr/realtime_asr_controller_test.dart --plain-name "T6"`
Expected: PASS.

- [ ] **Step 5: Run the healthy-connection test to confirm no regression**

Run: `flutter test test/features/realtime_asr/realtime_asr_controller_test.dart --plain-name "healthy connection"`
Expected: PASS unchanged — a session where the channel *is* available must still reach `listening` exactly as before.

- [ ] **Step 6: Run the full client test suite**

Run: `flutter test`
Expected: PASS, no new failures.

- [ ] **Step 7: Commit**

```bash
git add lib/features/realtime_asr/realtime_asr_controller.dart test/features/realtime_asr/realtime_asr_controller_test.dart
git commit -m "fix: don't resurrect a dead WS channel into listening state (T6)

If the WS handshake fails while start() is still awaiting the recorder,
the controller previously overwrote the correctly-reported error back
to 'listening' with a null channel underneath — a session that looks
healthy but can never send or receive anything. Now tears down and
ends the attempt as a failure instead."
```

---

## Task 3: Make realtime ASR errors actually visible to the SK

**Why this must follow Task 2, not precede it:** Task 2 makes `start()` correctly land in `RealtimeAsrState.error` on failure — but the investigation found that `AiScribeBanner`'s `liveActive` check (`= _liveCtrl.isActive`) excludes `error` from `isActive`, so the *only* widget that reads `errorMessage` (`AiScribeLiveAsrPanel`) unmounts the instant state becomes `error`. Without this task, Task 2's fix just trades "stuck on Listening forever" for "silently reverts to idle" — still invisible to the SK, just a different flavor of invisible.

**Files:**
- Modify: `uhis_lf_mobile/lib/features/scribe/widgets/ai_scribe_banner.dart`
- Test: create `uhis_lf_mobile/test/features/scribe/widgets/ai_scribe_banner_test.dart` (no existing widget test file for this banner)

**Interfaces:**
- Consumes: `RealtimeAsrController.state`, `.errorMessage` (both already exist).
- Produces: no new public API on `AiScribeBanner` — this is a rendering-only change. Existing constructor parameters (`onReviewReady`, `onFormFill`, etc.) are untouched.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/scribe/widgets/ai_scribe_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:uhis_next/features/realtime_asr/realtime_asr_controller.dart';
import 'package:uhis_next/features/scribe/scribe_controller.dart';
import 'package:uhis_next/features/scribe/widgets/ai_scribe_banner.dart';

// Reuses the same fakes pattern as realtime_asr_controller_test.dart — see
// that file for FakeRecordPlatform / _FakePermissionService / etc. Import
// or duplicate the minimal fakes needed to drive one controller into
// RealtimeAsrState.error without a real WebSocket.

void main() {
  testWidgets('an errored live session shows an error message, not a bare idle banner',
      (tester) async {
    // Arrange: build the widget tree with a ScribeController and a
    // RealtimeAsrController already forced into RealtimeAsrState.error
    // with a known errorMessage (drive it via the same fakes used in
    // realtime_asr_controller_test.dart's mic-permission-denied test,
    // which reliably reaches `error` state without any network).
    //
    // Act: pump the widget tree.
    //
    // Assert:
    expect(find.text(RealtimeAsrStrings.micPermissionDenied), findsOneWidget);
    // And the banner must NOT look like the plain idle "tap to record"
    // state — assert the idle-only affordance (e.g. its distinctive title)
    // is absent while an unacknowledged error exists.
  });
}
```

(This test's exact widget-tree setup depends on how `ScribeController`/`RealtimeAsrController` are already constructed in this app's existing widget tests — check `test/features/scribe/` for an existing pattern to copy before writing this from scratch; if none exists, use `ChangeNotifierProvider.value` directly as `AiScribeBanner` itself does internally.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/scribe/widgets/ai_scribe_banner_test.dart`
Expected: FAIL — no error text renders today because the panel is unmounted.

- [ ] **Step 3: Fix the banner's visibility logic**

In `ai_scribe_banner.dart`, the `build()` method currently computes:

```dart
    final liveActive = _liveCtrl.isActive;
```

`isActive` excludes `RealtimeAsrState.error` by design (it's used elsewhere to mean "session occupying the mic/socket"), so don't change `isActive` itself — instead compute a second, rendering-specific flag and use it for the panel/title decision:

```dart
    final liveActive = _liveCtrl.isActive;
    // Distinct from `isActive`: `error` must still render (the panel that
    // shows `errorMessage`), even though the session itself is no longer
    // occupying the mic/socket. Using `isActive` alone here is exactly the
    // bug that made every realtime ASR error structurally invisible.
    final liveErrored = _liveCtrl.state == RealtimeAsrState.error;
    final showLivePanel = liveActive || liveErrored;
```

Then change every place in `build()` that currently gates on `liveActive` for the *rendering* decision (title, subtitle, the `AiScribeLiveAsrPanel` inclusion) to use `showLivePanel` instead — but keep `liveActive` (unchanged) for the `onTap` routing logic, since tapping an errored banner should still go through the existing `isError` branch semantics for the batch controller, not the live one. Concretely:

```dart
    final title = showLivePanel
        ? (liveErrored ? RealtimeAsrStrings.errorTitle : RealtimeAsrStrings.title)
        : _showDone
            ? SymptomPickerStrings.scribeBannerDone
            : ...
```

```dart
    final subtitle = showLivePanel
        ? (liveErrored
            ? (_liveCtrl.errorMessage ?? RealtimeAsrStrings.genericError)
            : switch (_liveCtrl.state) {
                RealtimeAsrState.connecting => RealtimeAsrStrings.connecting,
                RealtimeAsrState.stopping => RealtimeAsrStrings.stopping,
                _ => RealtimeAsrStrings.listening,
              })
        : ...
```

```dart
                if (showLivePanel) ...[
                  const SizedBox(height: 10),
                  AiScribeLiveAsrPanel(controller: _liveCtrl),
                ],
```

Add the two new strings (`errorTitle`, `genericError`) to the `RealtimeAsrStrings` class in `app_strings.dart` — do not hardcode them inline (Engineering Design Standards: no hardcoded user-facing strings outside `app_strings.dart`).

- [ ] **Step 4: Run the test again**

Run: `flutter test test/features/scribe/widgets/ai_scribe_banner_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full client test suite**

Run: `flutter test`
Expected: PASS, no regressions — specifically re-check any existing test that asserts on the banner's idle/recording/processing title strings, since `showLivePanel` changes which branch several ternaries take.

- [ ] **Step 6: Manual verification**

On the physical device: force a realtime error (e.g., toggle airplane mode right as tapping LIVE, or temporarily point `AI_SERVICE_URL` at an unreachable host) and confirm the banner now shows a visible error message instead of silently sitting idle.

- [ ] **Step 7: Commit**

```bash
git add lib/features/scribe/widgets/ai_scribe_banner.dart lib/core/constants/app_strings.dart test/features/scribe/widgets/ai_scribe_banner_test.dart
git commit -m "fix: show realtime ASR errors in the banner instead of hiding them

isActive deliberately excludes RealtimeAsrState.error (it means 'session
occupying the mic/socket'), but the banner used it to decide whether to
render anything at all — so every realtime error was structurally
invisible to the SK. Add a separate showLivePanel flag that also covers
the error state."
```

---

## Task 4: Send `encounterId` on the realtime WebSocket connection

**Why now:** the backend has accepted an `encounterId` query parameter since the prior instrumentation task, but tonight's live test confirmed the client still never sends it — every backend `[AsrDiag]` line reads `encounter_id=unknown`. This is the one remaining piece needed for the two diagnostic halves (client `ASR_SESSION_SUMMARY`, backend `ASR_BACKEND_SESSION_END`) to actually be joinable, which every later diagnosis (including verifying Tasks 5–6 below) depends on.

**Files:**
- Modify: `uhis_lf_mobile/lib/core/api/realtime_asr_service.dart`
- Test: `uhis_lf_mobile/test/core/api/realtime_asr_service_test.dart` (already exists)

**Interfaces:**
- Consumes: nothing new — `RealtimeAsrController` already has `_encounterId` (added in the prior instrumentation task) and already calls `_service.connectionInfo(...)`.
- Produces: `RealtimeAsrService.connectionInfo(...)` gains one new optional named parameter `encounterId`. `RealtimeAsrController.start()` passes its own `_encounterId` through.

- [ ] **Step 1: Write the failing test**

In `test/core/api/realtime_asr_service_test.dart`, add:

```dart
test('connectionInfo includes encounterId as a query parameter when provided', () async {
  final info = await service.connectionInfo(
    language: 'bn-IN',
    encounterId: 'enc-abc-123',
  );
  expect(info.uri.queryParameters['encounterId'], 'enc-abc-123');
});

test('connectionInfo omits encounterId when not provided', () async {
  final info = await service.connectionInfo(language: 'bn-IN');
  expect(info.uri.queryParameters.containsKey('encounterId'), isFalse);
});
```

(Match this test's setup to whatever fixture/fake `ApiClient` the existing tests in this file already use — do not introduce a second fixture pattern.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/api/realtime_asr_service_test.dart`
Expected: FAIL — `encounterId` doesn't exist as a parameter yet (compile error), or the query param is simply absent.

- [ ] **Step 3: Add the parameter**

In `realtime_asr_service.dart`, `connectionInfo`'s signature currently reads:

```dart
  Future<RealtimeAsrConnectionInfo> connectionInfo({
    required String language,
    String model = 'saarika:v2.5',
    String? assessmentType,
    List<String>? symptomVocab,
  }) async {
```

Add the new parameter:

```dart
  Future<RealtimeAsrConnectionInfo> connectionInfo({
    required String language,
    String model = 'saarika:v2.5',
    String? assessmentType,
    List<String>? symptomVocab,
    String? encounterId,
  }) async {
```

And in the `Uri(...)` construction inside the same method, add the query parameter alongside the existing ones (`assessmentType`, `symptomVocab`):

```dart
      queryParameters: {
        'language': language,
        'model': model,
        if (assessmentType != null) 'assessmentType': assessmentType,
        if (symptomVocab != null && symptomVocab.isNotEmpty)
          'symptomVocab': symptomVocab.join(','),
        if (encounterId != null && encounterId.isNotEmpty)
          'encounterId': encounterId,
        if (api.tenantId != null) 'tenantId': api.tenantId!,
      },
```

- [ ] **Step 4: Thread it through from the controller**

In `realtime_asr_controller.dart`'s `start()`, the existing call:

```dart
      final info = await _service.connectionInfo(
        language: language,
        assessmentType: assessmentType,
        symptomVocab: _symptomVocab,
      );
```

becomes:

```dart
      final info = await _service.connectionInfo(
        language: language,
        assessmentType: assessmentType,
        symptomVocab: _symptomVocab,
        encounterId: _encounterId,
      );
```

- [ ] **Step 5: Run the tests again**

Run: `flutter test test/core/api/realtime_asr_service_test.dart test/features/realtime_asr/realtime_asr_controller_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full client test suite**

Run: `flutter test`
Expected: PASS, no regressions.

- [ ] **Step 7: Manual verification**

Rebuild, reinstall on the Pixel 10a, start a realtime session, and confirm the `scribe-api` backend logs now show the *same* `encounter_id` as the client's own `[AsrDiag]` lines instead of `unknown`:

```bash
docker logs scribe-api --since 2m | grep AsrDiag
```

- [ ] **Step 8: Commit**

```bash
git add lib/core/api/realtime_asr_service.dart lib/features/realtime_asr/realtime_asr_controller.dart test/core/api/realtime_asr_service_test.dart
git commit -m "fix: send encounterId on the realtime WS connection

The backend has accepted an encounterId query param since the backend
diagnostics task, but the client never sent it — every backend
[AsrDiag] event read encounter_id=unknown, confirmed live tonight.
This is the last piece needed to join client and backend diagnostics
by a single correlation id."
```

---

## Task 5: Stop losing the final extraction on stop/disconnect

**Why now:** live-caught tonight — `ASR_FINAL_EXTRACT_CANCELLED` fired, `extractCompleted=1` out of `extractRequests=2`, `exitPath=client_disconnect`. Whatever the SK said right before that Step 1 session ended was never extracted. This is a backend fix.

**Root cause (`leapfrog-ai-service/app/services/realtime_bridge.py`, `run_bridge_session`):** the `finally` block around the main receive loop unconditionally cancels `extract_task` the moment the loop exits (via `stop`, `WebSocketDisconnect`, or any exception) — even when that task is a still-running LLM extraction over the session's final transcript. The client's own `stop()` is coded to *wait* (bounded) for exactly this reply before disconnecting, but the server doesn't reciprocate: it can cancel out from under a client that's still waiting. The current instrumentation already detects the pending case (`ASR_FINAL_EXTRACT_CANCELLED`); this task changes what happens once it's detected.

**Files:**
- Modify: `leapfrog-ai-service/app/services/realtime_bridge.py`
- Test: `leapfrog-ai-service/tests/test_realtime_diagnostics.py` (already exists)

**Interfaces:**
- Consumes: `extract_task` (existing local variable in `run_bridge_session`), `asyncio.wait_for` (stdlib).
- Produces: no signature changes — this only changes the `finally` block's internal behavior.

- [ ] **Step 1: Write the failing test**

The existing test `test_pending_final_extraction_cancellation_is_recorded` in `tests/test_realtime_diagnostics.py` currently asserts the *bug* (that `extractCancelled == 1`). Add a new test next to it that asserts the *fixed* behavior — the pending extraction should be drained, not cancelled, as long as it finishes within a bound:

```python
def test_pending_final_extraction_is_drained_not_lost_on_stop(client, caplog):
    """The fix: a pending final extraction gets a bounded chance to finish
    and deliver its reply instead of being cancelled outright."""
    patches = _apply(_dev_patches(_FakeSarvamSocketNoResponses()))
    try:
        with patch.object(realtime_bridge, "run_inference", side_effect=_slow_inference):
            with client.websocket_connect(
                "/scribe/realtime/transcribe?encounterId=enc-drain"
            ) as ws:
                ws.send_json({"type": "extract", "transcript": "last thing said"})
                ws.send_json({"type": "stop"})
                # _slow_inference sleeps 0.15s — well under the drain bound
                # this task adds — so the reply must still arrive before
                # the connection closes.
                msg = ws.receive_json()
                assert msg["type"] == "symptoms"
    finally:
        _undo(patches)

    end = next(l for l in _asr_lines(caplog) if "ASR_BACKEND_SESSION_END" in l)
    assert _field(end, "extractCompleted") == "1"
    assert _field(end, "extractCancelled") == "0"
```

Keep the existing `test_pending_final_extraction_cancellation_is_recorded` test too, but change its `_slow_inference` call to sleep *longer than the new drain bound* (see Step 3) so it still legitimately exercises the "genuinely too slow, gets cancelled" path rather than becoming a false failure:

```python
def _very_slow_inference(transcript, programme):
    time.sleep(6.0)  # exceeds the 5s drain bound added in this task
    return _FakeClinicalFields()
```

and update that one test to use `_very_slow_inference` instead of `_slow_inference`.

- [ ] **Step 2: Run tests to verify the new one fails**

Run: `pytest tests/test_realtime_diagnostics.py -v`
Expected: `test_pending_final_extraction_is_drained_not_lost_on_stop` FAILS (times out waiting for a reply that today is cancelled instead of delivered). The renamed-slowness test should still pass unchanged (still exercises real cancellation, just with a longer sleep).

- [ ] **Step 3: Fix the `finally` block**

In `realtime_bridge.py`, find the block (inside `run_bridge_session`, right after the `while True` receive loop):

```python
            finally:
                if extract_task is not None and not extract_task.done():
                    extract_cancelled += 1
                    log_event("ASR_FINAL_EXTRACT_CANCELLED", encounter_id)
                forward_task.cancel()
                if extract_task is not None:
                    extract_task.cancel()
```

Replace with:

```python
            finally:
                forward_task.cancel()
                if extract_task is not None and not extract_task.done():
                    # Give a still-in-flight final extraction a bounded
                    # chance to finish and deliver its reply — the client's
                    # own stop() already waits (up to 15s) for exactly this,
                    # so cancelling here unconditionally was strictly worse
                    # than draining: it guaranteed the loss of whatever the
                    # SK said right before ending the session. 5s covers the
                    # typical extraction latency observed in production logs
                    # (1-4s) with headroom, while still bounded so a
                    # genuinely stuck call can't hang the connection close.
                    try:
                        await asyncio.wait_for(extract_task, timeout=5.0)
                    except asyncio.TimeoutError:
                        extract_cancelled += 1
                        log_event("ASR_FINAL_EXTRACT_CANCELLED", encounter_id)
                        extract_task.cancel()
                    except Exception:  # noqa: BLE001 - run_extraction already
                        # logs+reports its own failures (ASR_EXTRACT_ERROR);
                        # this just prevents that exception from propagating
                        # into session teardown.
                        pass
                elif extract_task is not None:
                    extract_task.cancel()
```

- [ ] **Step 4: Run the tests again**

Run: `pytest tests/test_realtime_diagnostics.py -v`
Expected: PASS, both tests.

- [ ] **Step 5: Run the full backend test suite**

Run: `pytest tests/ -q`
Expected: same pass/fail counts as the pre-existing baseline documented in the prior instrumentation task's report (16 pre-existing, unrelated failures; no new ones).

- [ ] **Step 6: Rebuild and manually verify**

```bash
cd leapfrog-ai-service && docker compose up -d --build api worker
```

Repeat a short realtime session on the physical device, say something right before tapping stop, and confirm in `docker logs scribe-api` that `extractCompleted` increments for that final round (no `ASR_FINAL_EXTRACT_CANCELLED` for a normally-timed final utterance).

- [ ] **Step 7: Commit**

```bash
git add app/services/realtime_bridge.py tests/test_realtime_diagnostics.py
git commit -m "fix: drain the final extraction on stop instead of cancelling it

Confirmed live tonight: a session ending via disconnect lost its final
extraction (extractCompleted=1 of extractRequests=2, exitPath=
client_disconnect). The client's own stop() already waits up to 15s for
exactly this reply; the server was cancelling it unconditionally instead
of reciprocating. Now awaits a still-pending final extraction with a 5s
bound before falling back to cancellation."
```

---

## Task 6: Contain a single bad Sarvam frame so it doesn't silently end the whole session

**Why now, and why last among the "fix" tasks:** this is the highest-ranked *hypothesis* from the original static investigation (T8/H2), but — unlike Tasks 1, 4, and 5 — it has not yet been directly observed in tonight's live testing (that testing did surface a related, but distinct, real backend error: `inference produced no valid fields: gemini_json_parse_failed`, which is an *extraction* failure already handled by the existing `ASR_EXTRACT_ERROR` path from the instrumentation task, not a *transcription* failure). Do Tasks 1–5 first since they're confirmed; treat this one as "harden the next most-likely cause" rather than "fix a second confirmed bug."

**Scope decision needed before implementing — flag this to the user, don't just pick one silently:**

- **Option A (minimal, recommended default):** when `sarvam_ws.transcribe()` raises for a single audio frame, catch it locally (the diagnostic logging for this already exists — `ASR_SARVAM_TRANSCRIBE_ERROR`), send one explicit `{"type": "error", "message": "audio_transcription_failed"}` frame, then end the session exactly as today (no continuation, no reconnection) — the only change is that the ending is deliberate and clearly signaled instead of an uncaught exception falling through to the generic outer handler. Same failure *consequence* (session ends), better failure *signal*.
- **Option B (bigger change, do not implement without explicit sign-off):** survive a single bad frame and keep the session alive for subsequent frames. This changes actual ASR behavior (a session that would end today keeps running) and needs product agreement — out of scope for this plan unless requested.

This task implements **Option A only**.

**Files:**
- Modify: `leapfrog-ai-service/app/services/realtime_bridge.py`
- Test: `leapfrog-ai-service/tests/test_realtime_diagnostics.py`

**Interfaces:**
- Consumes: `log_event`, `categorize_exception` (already imported in this file).
- Produces: no signature changes.

- [ ] **Step 1: Write the failing test**

```python
def test_transcribe_failure_sends_explicit_error_frame_before_closing(client, caplog):
    """Option A: a per-frame transcribe() failure must send a clear,
    specific error frame — not rely on the generic outer exception handler
    (which forwards the raw SDK exception string)."""
    patches = _apply(_dev_patches(_FakeSarvamSocketTranscribeRaises()))
    try:
        with client.websocket_connect(
            "/scribe/realtime/transcribe?encounterId=enc-explicit-error"
        ) as ws:
            ws.send_json({"type": "audio", "data": "ZmFrZQ==", "sample_rate": 16000})
            msg = ws.receive_json()
            assert msg == {"type": "error", "message": "audio_transcription_failed"}
    finally:
        _undo(patches)

    end = next(l for l in _asr_lines(caplog) if "ASR_BACKEND_SESSION_END" in l)
    assert _field(end, "exitPath") == "transcription_failed"
    assert _field(end, "transcribeFailures") == "1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_realtime_diagnostics.py::test_transcribe_failure_sends_explicit_error_frame_before_closing -v`
Expected: FAIL — today's message is the raw exception string (`"sarvam transcribe timed out"`, from the existing `test_sarvam_transcribe_error_is_recorded_and_still_propagates` test), and `exitPath` is `backend_exception`, not `transcription_failed`.

- [ ] **Step 3: Add the explicit handling**

In `realtime_bridge.py`, find the audio-frame branch inside the main receive loop (already instrumented from the diagnostics task):

```python
                    if msg_type == "audio":
                        audio_frames_received += 1
                        raw_data = msg.get("data")
                        if isinstance(raw_data, str):
                            try:
                                audio_bytes_received += len(base64.b64decode(raw_data))
                            except Exception:  # noqa: BLE001 - counter only, never fail the frame over this
                                pass
                        transcribe_calls += 1
                        _transcribe_start = time.monotonic()
                        try:
                            await sarvam_ws.transcribe(
                                audio=msg["data"],
                                encoding=msg.get("encoding", "audio/wav"),
                                sample_rate=msg.get("sample_rate", 16000),
                            )
                            transcribe_successes += 1
                        except Exception as exc:  # noqa: BLE001 - log, then re-raise unchanged
                            transcribe_failures += 1
                            log_event(
                                "ASR_SARVAM_TRANSCRIBE_ERROR", encounter_id,
                                exceptionType=type(exc).__name__,
                                errorCategory=categorize_exception(exc),
                            )
                            raise
                        finally:
                            transcribe_duration_ms_total += int(
                                (time.monotonic() - _transcribe_start) * 1000
                            )
```

Replace the `except`/`raise` with an explicit client-facing signal, then a controlled break instead of an uncaught re-raise (so this specific failure gets its own `exit_path`, distinct from the generic `backend_exception` catch-all):

```python
                        except Exception as exc:  # noqa: BLE001 - report explicitly, then end the session deliberately
                            transcribe_failures += 1
                            log_event(
                                "ASR_SARVAM_TRANSCRIBE_ERROR", encounter_id,
                                exceptionType=type(exc).__name__,
                                errorCategory=categorize_exception(exc),
                            )
                            try:
                                await websocket.send_json({
                                    "type": "error",
                                    "message": "audio_transcription_failed",
                                })
                            except Exception:
                                pass
                            exit_path = "transcription_failed"
                            error_category = categorize_exception(exc)
                            break
```

`break` exits the `while True` loop the same way `stop`/`WebSocketDisconnect` do, so it flows into the *same* `finally` block Task 5 just fixed — Task 5's drain logic and this task's explicit signal compose correctly without any extra wiring.

- [ ] **Step 4: Run the test again**

Run: `pytest tests/test_realtime_diagnostics.py::test_transcribe_failure_sends_explicit_error_frame_before_closing -v`
Expected: PASS.

- [ ] **Step 5: Re-run the existing propagation test and update it to match the new, more specific behavior**

`test_sarvam_transcribe_error_is_recorded_and_still_propagates` currently asserts the raw exception string is forwarded. Update its assertion to match the new explicit message (the *fact* that the client is notified is what that test is protecting — the exact message improving is expected):

```python
            msg = ws.receive_json()
            assert msg == {"type": "error", "message": "audio_transcription_failed"}
```

- [ ] **Step 6: Run the full backend test suite**

Run: `pytest tests/ -q`
Expected: same pre-existing failure count as before (16), no new failures.

- [ ] **Step 7: Rebuild and commit**

```bash
docker compose up -d --build api worker
git add app/services/realtime_bridge.py tests/test_realtime_diagnostics.py
git commit -m "fix: send an explicit error frame on a per-frame Sarvam transcribe failure

Option A from the remediation plan: a single bad frame today propagates
as an uncaught exception, ending the session via the generic outer
handler (which forwards the raw SDK exception string as the client-
facing message). Now sends a specific, stable error message and a
distinct exit_path, without changing the session-ends-on-failure
behavior itself (Option B — surviving the frame and continuing — is
out of scope without explicit sign-off)."
```

---

## Task 7: Investigate the rapid controller create/dispose churn

**Why this is last, and why it's an investigation task, not a blind fix:** tonight's testing showed three `RealtimeAsrController`s created and disposed within ~10 seconds, each with `durationMs=null` (meaning `start()` was never called on any of them). This is not confirmed to be a bug — it may simply be normal rapid navigation between visit steps, each of which mounts its own `AiScribeBanner`. It needs a repro and a code-level explanation before it's safe to propose a fix; writing one now would be exactly the kind of placeholder ("add appropriate handling") this plan format forbids.

**Files:**
- Investigate: `uhis_lf_mobile/lib/features/scribe/widgets/ai_scribe_banner.dart` (`initState`/`dispose`), and whichever screen(s) host it — `lib/features/visit/triage/symptom_picker_screen.dart` and `lib/features/visit/forms/unified_form_screen.dart` (both instantiate `AiScribeBanner` per the earlier investigation's file trace).
- Deliverable: a short written finding (append to `docs/ai_scribe_asr_failure_investigation.md`, not a new doc), not code, unless the finding is a trivial one-line confirmation of a known pattern (e.g. `AnimatedSwitcher` or a `Consumer` rebuilding the banner's parent on every state change).

- [ ] **Step 1: Reproduce deliberately**

On the physical device (or emulator), with the same tightened logcat filter used tonight (`adb logcat -v brief flutter:V AndroidRuntime:E System.err:W '*:S' | grep -E '\[AsrDiag\]'`), navigate rapidly between Step 1 and Step 2 of a visit several times in a row without tapping the mic. Count how many `ASR_SESSION_SUMMARY encounter_id=unknown durationMs=null` lines appear per navigation, and note whether the count scales with the number of screen transitions (supports "expected, one per mount/unmount") or is higher (supports "something is rebuilding the banner's parent repeatedly on a single screen").

- [ ] **Step 2: If it scales 1:1 with navigations — confirm and close**

If each screen transition produces exactly one such summary, this is expected behavior (a banner mounts, its controller is constructed, the SK doesn't tap it, the screen unmounts). No fix needed. Add one sentence to `docs/ai_scribe_asr_failure_investigation.md`'s Part 3 confirming this was checked and is benign, so it isn't re-investigated later.

- [ ] **Step 3: If it does NOT scale 1:1 — find the rebuild trigger**

If a single screen produces multiple create/dispose cycles without the SK navigating, use Flutter DevTools' widget rebuild profiler (or add a temporary `debugPrint` in `AiScribeBanner`'s `initState`/`dispose`) to identify which ancestor widget is rebuilding and why (a common cause: a `Consumer`/`Selector` listening to a notifier that changes more often than intended, causing `AiScribeBanner` — a `StatefulWidget` without a `key` tying it to something stable — to be torn down and recreated by Flutter's element diffing instead of updated in place).

- [ ] **Step 4: Write up the finding**

Append a short section to `docs/ai_scribe_asr_failure_investigation.md` (Part 3) with: the exact ancestor widget/notifier identified, the code location, and — only if a fix is genuinely trivial and safe (e.g., adding a `ValueKey` to stabilize the widget's identity across rebuilds) — a follow-up task description for a *future* plan. Do not implement a fix inline in this task; this plan's scope is diagnosis for this item, matching the investigation-only framing of the two instrumentation tasks that preceded it.

- [ ] **Step 5: Commit the writeup**

```bash
git add docs/ai_scribe_asr_failure_investigation.md
git commit -m "docs: investigate rapid RealtimeAsrController create/dispose churn

Observed live during manual testing: three controllers created/disposed
within 10s without start() ever being called. Documents whether this
scales with actual navigation (benign) or points to an unnecessary
widget rebuild (needs a follow-up fix)."
```

---

## Self-review

**Spec coverage** — every item in the evidence table maps to a task: dispose crash → Task 1; T6 → Task 2; error invisibility → Task 3; correlation gap → Task 4; final-extraction loss → Task 5; per-frame Sarvam failure → Task 6; controller churn → Task 7.

**Placeholder scan** — no "TBD"/"add appropriate handling" in any step; Task 7 is explicitly scoped as an investigation with a real deliverable (a written finding), not a disguised "figure it out later."

**Type/name consistency** — `_safeNotify()` introduced in Task 1 is used by name in Task 2's Step 3 edit (`_safeNotify();` instead of `notifyListeners();`) so later tasks build on the same helper rather than reintroducing raw `notifyListeners()` calls. `encounterId` (Task 4) matches the parameter name already used server-side (`encounter_id` after FastAPI's alias mapping) and client-side (`_encounterId`, already present from the instrumentation task). `exit_path` values introduced across Tasks 5/6 (`transcription_failed`) don't collide with existing values (`normal_stop`, `client_disconnect`, `backend_exception`, `config_error`).
