# Network Log Page Implementation Plan (uhis_lf_mobile#778)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hidden "Network" page, opened by 10 taps on the Offline Sync header or the login logo, that lists the configured endpoints and a local, sanitised log of every request (full URL, method, status, duration).

**Architecture:** One idempotent Dio interceptor, inserted before the retry interceptor and attached to every HTTP client, reports to a synchronous in-memory recorder that batches epoch-guarded writes into a capped `network_log` SQLCipher table. The coaching SDK's own requests are pulled over the existing MethodChannel (contract v1) and merged. A registry test fails when a new transport is not registered.

**Tech Stack:** Flutter/Dart, Dio 5.11, go_router 14.8, Provider, sqflite_sqlcipher (tests: `sqflite_common_ffi`).

**Spec:** `docs/superpowers/specs/2026-11-26-network-log-page-design.md` (sections cited as "spec §n"). Parent: Medtronic-LABS/leapwell#14. PR1 = T1-T9a. T9b waits for SDK `spice-coaching-android#21` and the rebuilt AAR.

## Global Constraints
- Engineering Design Standards (leapwell `CLAUDE.md`): layered code, no hardcoded copy (`lib/core/constants/app_strings.dart` + `assets/translations/strings.json` with en and bn, never `test/i18n_untranslated_baseline.txt`), config only via `AppConfig`, narrow catches (never bare `catch (_)`), new behaviour ships with a test.
- Verify per task: `flutter test <touched test files>` and `flutter analyze`; add `flutter build apk --debug` where `main.dart` or `android/` changes. Never read or edit `env*.json` or `android/key.properties`.
- Schema 59 -> 60. Table cap: newest 2,000 rows. Recorder buffer cap 500; flush after 3 s, immediately on status >= 400 or error, on `AppLifecycleState.paused`, and on page open. Insert batches of at most 50 rows.
- Stored URL: at most 2,048 chars (truncate to 2,047 + `…`). Never store or read headers, bodies, cookies, tokens or `e.message`.
- Page: 200 rows per page, copy at most 200 newest rows (respecting the active service filter). Trigger: 10 taps, each within 2 s of the previous, `HitTestBehavior.opaque`.
- Clear only on user switch (`AppDatabase.wipeAllData`) and the page's Clear button, never on ordinary logout.
- SDK contract: `contract_version` / `sdk_event_version` = 1; any other value maps to `unavailable`.
- URL query allowlist (value always `<redacted>`): `_count, _lang, encounter, key, language, model, since, limit, offset, cursor, from_date, to_date`.

## Review Focus
1. Email in a URL path (`forgot-password/<email>/mobile`) is stored as `{id}`, never raw (T1).
2. Requests in flight or buffered while `wipeAllData` runs must not appear after the user switch (T3, T4).
3. A failing DB write, full buffer or throwing recorder never fails or delays the HTTP request (T4, T5).
4. A retried request with N attempts yields exactly N rows, no duplicate (T5).
5. SDK missing, older, uninitialised or returning a malformed payload never throws and shows a status line (T9a, T8b).

## File Structure
- `lib/core/net_log/`: `url_sanitizer.dart`, `service_classifier.dart`, `network_log_entry.dart`, `network_request_recorder.dart`, `db_network_request_recorder.dart`, `network_log_interceptor.dart`, `network_log_dao.dart`, `native_network_event_source.dart`, `network_log_repository.dart`.
- `lib/core/api/request_extras.dart` (shared `kAttemptKey = 'uhisAttempt'`, moved from `api_client.dart:19`).
- `lib/core/widgets/hidden_tap_trigger.dart`; `lib/features/debug/network_log_screen.dart`, `network_log_controller.dart`.
- Modified: `app_database.dart`, `app_config.dart`, `api_client.dart`, `main.dart`, `router.dart`, `micro_coaching_service.dart`, `app_strings.dart`, `strings.json`, `offline_sync_screen.dart`, `login_screen.dart`, the OWN-site clients (spec §7a), `realtime_asr_channel_io.dart`, `shukhee_client_factory.dart`, `pubspec.yaml`.

---

### Task 1: UrlSanitizer and shared vectors
**Files:** Create `lib/core/net_log/url_sanitizer.dart`, `test/fixtures/net_log/url_sanitizer_vectors.json`; Test `test/core/net_log/url_sanitizer_test.dart`.
**Produces:** `abstract final class UrlSanitizer { static String sanitize(String raw); }` pure, total, never throws.
- [ ] **Step 1:** Write the vectors file `{ "vectors_version": 1, "cases": [{name, input, expected}] }` with every row of the spec §7f table plus: userinfo/fragment dropped, `%2540` double-encoded email -> `{id}`, `::not a url` -> `<unparsable>`, 3,000-char URL ends with `…` and is 2,048 chars, Bengali-digit run (6+) -> `{id}`, `users/42` unchanged, presigned GCS query dropped. Write the test: asserts `vectors_version == 1`, every case equals `sanitize(input)`, and 500 random garbage strings never throw and never exceed 2,048 chars.
- [ ] **Step 2:** Run `flutter test test/core/net_log/url_sanitizer_test.dart`; expected FAIL (file missing).
- [ ] **Step 3:** Implement per spec §7f steps 1-6 (parse, scheme/host/port, per-segment mask rule with up-to-3x percent-decode, allowlisted query keys in original order once each, cap). Portable regexes only (no look-behind). "Digit" is any Unicode decimal digit.
- [ ] **Step 4:** Run the test; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): URL sanitiser for the network log (#778)`.

### Task 2: Configured endpoints and ServiceClassifier
**Files:** Modify `app_config.dart` (`:31`, `:114-117`, `:140`, `:152-164`, `:417`, `:446-484`), `micro_coaching_service.dart:12-16`; Create `lib/core/net_log/service_classifier.dart`; Test `test/core/net_log/service_classifier_test.dart`, `test/core/config/configured_endpoints_test.dart`.
**Produces:** `class ConfiguredEndpoint { final String service; final String url; final String rule; }`; `AppConfig.configuredEndpoints -> List<ConfiguredEndpoint>` (url getters only, never `hfToken`); `MicroCoachingService.sdkBaseUrl(String url) -> String` (public form of `_sdkUrl`); `ServiceClassifier(List<ConfiguredEndpoint>).classify(String url) -> String` returning `auth-service|user-service|spice-service|offline-service|fhir-server|ai-scribe|micro-coaching|admin-api|other-host|other`.
- [ ] **Step 1:** Tests: (a) longest base-prefix match wins over first path segment; (b) direct `AI_SERVICE_URL` host -> `ai-scribe`; (c) storage host -> `other-host`; (d) unknown path on the API host -> `other`; (e) each existing getter still returns the same URL and `configuredEndpoints` carries its rule text (e.g. `API_BASE_URL + /admin-api`).
- [ ] **Step 2:** Run both files; expected FAIL.
- [ ] **Step 3:** Refactor each URL getter to a private resolver returning `(url, rule)`; the getter returns `.url`. Make `_sdkUrl` public as `sdkBaseUrl`. Implement the classifier in the order of spec §7c.
- [ ] **Step 4:** Run both files plus `flutter test test/core/config`; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): configured endpoints and service classifier (#778)`.

### Task 3: Schema 60, NetworkLogDao, wipe seam
**Files:** Modify `app_database.dart` (`:27`, `:141`, `_allTables ~:2547`, `wipeAllData ~:2579`, new `if (from < 60)` after the `from < 57` block); Create `lib/core/net_log/network_log_entry.dart`, `network_log_dao.dart`; Test `test/core/net_log/network_log_dao_test.dart`; extend `test/core/db/app_database_migration_test.dart`, `app_database_wipe_test.dart`, `test/core/auth/auth_state_logout_wipe_test.dart`.
**Produces:**
- `class NetworkLogEntry { startedAtMs, source ('dart'|'native'), nativeId?, service, method, url, finalUrl?, statusCode?, durationMs?, timing ('total'|'headers'|'handshake'), attempt, errorType?, epoch }`.
- `AppDatabase.tableNetworkLog`; `abstract interface class WipeParticipant { void onWipeStarting(); Future<void> onWipeInTransaction(Transaction tx); }`; `void AppDatabase.addWipeParticipant(WipeParticipant p)`.
- `NetworkLogDao(AppDatabase)`: `Future<void> insertBatch(List<NetworkLogEntry>, {bool Function()? isCurrent})` (first statement in the transaction is `isCurrent` check; then insert; then `DELETE FROM network_log WHERE id <= (SELECT MAX(id) FROM network_log) - 2000`), `Future<int> mergeNative(List<NetworkLogEntry>, {required int floorMs})` (INSERT OR IGNORE, rows with `startedAtMs < floorMs` skipped), `Future<List<NetworkLogEntry>> page({required int limit, required int offset, String? service})` ordered `started_at_ms DESC, id DESC`, `Future<Map<String,int>> countsByService()`, `Future<List<NetworkLogEntry>> newest(int limit, {String? service})`, `Future<void> clear()` (deletes rows and sets the floor to now in one transaction), `Future<({int cursor, int floorMs})> nativeState()`, `Future<void> setNativeCursor(int)` (via `SyncMetaDao`, entity `network_log.native`).
- [ ] **Step 1:** Tests: DAO insert of 2,050 rows keeps the newest 2,000; page order/filter/offset; counts; `insertBatch` writes nothing when `isCurrent` returns false; `mergeNative` dedupes on `(native_id, started_at_ms)` and honours the floor; `clear` sets the floor. Migration: `onUpgrade(db, 59, 60)` creates the table, the three indexes (DDL in spec §7e) and seeds `sync_meta('network_log.native')` with cursor 0, floor 0; existing data kept. Wipe: `network_log` truncated; `onWipeStarting` runs before the transaction and `onWipeInTransaction` inside it; the floor row equals wipe time afterwards. Existing `telemetry_wipe_exclusion_test.dart` stays green. `logout()` leaves `network_log` rows in place.
- [ ] **Step 2:** Run the six files; expected FAIL.
- [ ] **Step 3:** Implement: `schemaVersion = 60`; one `_createNetworkLog(DatabaseExecutor)` called from `createSchema` and the `from < 60` block; add the table to `_allTables`; `wipeAllData` calls `onWipeStarting()` on all participants first and `onWipeInTransaction(tx)` last inside its transaction.
- [ ] **Step 4:** Run the six files and `flutter test test/core/db`; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): network_log table, DAO and wipe seam (#778)`.

### Task 4: Recorder
**Files:** Create `lib/core/net_log/network_request_recorder.dart`, `db_network_request_recorder.dart`; Test `test/core/net_log/db_network_request_recorder_test.dart`.
**Consumes:** `NetworkLogDao`, `WipeParticipant`, `NetworkLogEntry` (T3).
**Produces:** `abstract interface class NetworkRequestRecorder { int get epoch; void record(NetworkLogEntry e); }`; `class NoopNetworkRequestRecorder implements NetworkRequestRecorder` (const); `class DbNetworkRequestRecorder implements NetworkRequestRecorder, WipeParticipant { DbNetworkRequestRecorder(NetworkLogDao dao, {Duration flushDelay = const Duration(seconds: 3), int maxBuffer = 500}); Future<void> flush(); void clearBuffer(); int get droppedCount; }`. `record` is synchronous, never throws, never awaits; the timer is armed only while the buffer is non-empty.
- [ ] **Step 1:** Tests (injectable flush trigger, fake DAO): status >= 400 or an error entry flushes immediately; the 501st entry drops the oldest and `droppedCount == 1`; a `DatabaseException` from the DAO adds the batch size to `droppedCount` and nothing else throws; `clearBuffer()` empties the buffer and increments `epoch`; an entry with a stale epoch is dropped by `record`; a flush that began before `clearBuffer()` writes nothing (its `isCurrent` returns false); batches are at most 50 rows.
- [ ] **Step 2:** Run the file; expected FAIL.
- [ ] **Step 3:** Implement; `onWipeStarting()` calls `clearBuffer()`; catch only `DatabaseException`.
- [ ] **Step 4:** Run the file; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): batched epoch-guarded network request recorder (#778)`.

### Task 5: Interceptor and ApiClient wiring
**Files:** Create `lib/core/net_log/network_log_interceptor.dart`, `lib/core/api/request_extras.dart`; Modify `api_client.dart` (`:19`, `:88-261`, `:347-377`), `main.dart` (`:145-155`, `:224`, `:603-624`); Test `test/core/net_log/network_log_interceptor_test.dart` using `_ScriptedAdapter` from `test/core/api/api_retry_test.dart:15`.
**Consumes:** `NetworkRequestRecorder`, `UrlSanitizer`, `ServiceClassifier`/`AppConfig.configuredEndpoints` (T1, T2, T4).
**Produces:** `NetworkLogInterceptor.attach(Dio dio, NetworkRequestRecorder recorder)` (idempotent: no-op when an instance is already present); `ApiClient.create({NetworkRequestRecorder networkRecorder = const NoopNetworkRequestRecorder()})`; `NetworkRequestRecorder get ApiClient.networkRecorder`; `void ApiClient.attachNetworkLog(Dio dio)`; `attachAiServiceAuth` also attaches the log; `const String kAttemptKey` in `request_extras.dart`.
- [ ] **Step 1:** Tests through `ApiClient.create(networkRecorder: fake)`: 200 -> one row with sanitised URL and status; 404 -> one row; 401 -> one row and `onUnauthorized` still fires; a retry-safe 500 retried to success -> N rows with `attempt` 1..N and no duplicate; timeout -> `errorType == 'connectionTimeout'`; second `attach` -> still one row; request carrying a Bearer header and a body -> no recorded field contains either; a recorder that throws from `record` does not fail the request.
- [ ] **Step 2:** Run the file; expected FAIL.
- [ ] **Step 3:** Implement: the interceptor starts a `Stopwatch` in `onRequest` (stored in `extra['netLogSw']`, with the recorder epoch), records in `onResponse`/`onError` (`errorType = e.type.name`, `null` for `badResponse`; `finalUrl` only when `response.redirects` is non-empty; `timing = 'headers'` for `ResponseType.stream`, else `'total'`); wraps `record` in a try/catch for `Exception` so it can never break a request. Insert it in `ApiClient.create()` between the tenant/app-version interceptor and the retry interceptor (`:219`). In `main.dart`: open `AppDatabase` before `ApiClient.create`, build `DbNetworkRequestRecorder(NetworkLogDao(appDb))`, `appDb.addWipeParticipant(recorder)`, pass it to `create`, provide `Provider<NetworkRequestRecorder>.value` next to `Provider<ApiClient>.value`, and call `unawaited(recorder.flush())` when the lifecycle state is `paused`.
- [ ] **Step 4:** Run the file, `flutter test test/core/api`, `flutter analyze`, `flutter build apk --debug`; expected PASS and a built APK.
- [ ] **Step 5:** Commit `feat(mobile): log every ApiClient request to the network log (#778)`.

### Task 6a: Remaining Dio sites
**Files:** Modify `frappe_client.dart:59,175`, `call_log_sync_client.dart:84`, `shukhee_encounter_link_client.dart:24`, `shukhee_consent_client.dart:18,123`, `scribe_api_service.dart:262`, `user_hierarchy_service.dart:648,680`, `assistant_repository.dart:62`, `main.dart:223,245`; Test: each client's existing test file.
**Consumes:** `NetworkRequestRecorder`, `ApiClient.attachNetworkLog`, `NetworkLogInterceptor.attach` (T5).
**Produces:** optional `NetworkRequestRecorder? networkRecorder` constructor parameter on `FrappeClient`, `CallLogSyncClient`, `ShukheeEncounterLinkClient`, `ShukheeConsentClient` (attached to `_dio`, including an injected test Dio); factories pass `api.networkRecorder`.
- [ ] **Step 1:** For each client, a test with a scripted adapter and a fake recorder: one call records exactly one row with the sanitised URL (the `get_controls` call on `user_hierarchy_service` records its 404).
- [ ] **Step 2:** Run the touched test files; expected FAIL.
- [ ] **Step 3:** Add the parameter or `api.attachNetworkLog(dio)` call at each site.
- [ ] **Step 4:** Run the touched test files, `flutter analyze`; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): log requests from the remaining Dio clients (#778)`.

### Task 6b: WebSocket
**Files:** Modify `realtime_asr_channel_io.dart:17-20`, `realtime_asr_channel_web.dart` (signature only), `realtime_asr_controller.dart:446`; Test `test/features/realtime_asr/realtime_ws_log_test.dart`.
**Produces:** `connectRealtimeChannel(Uri uri, Map<String,String> headers, {NetworkRequestRecorder? recorder})`.
- [ ] **Step 1:** Test with a fake channel whose `ready` completes -> one row `method == 'WS'`, `statusCode == 101`, `timing == 'handshake'`; `ready` fails with `SocketException` -> `errorType == 'connectionError'`, and the controller's own `onError` path still runs.
- [ ] **Step 2:** Run it; expected FAIL.
- [ ] **Step 3:** Start a `Stopwatch` at connect, observe `channel.ready`, map errors with explicit `is` checks (`WebSocketChannelException` -> `wsError`, `SocketException` -> `connectionError`, `HandshakeException` -> `badCertificate`, `TimeoutException` -> `connectionTimeout`, else `unknown`); the controller passes `_service.api.networkRecorder`.
- [ ] **Step 4:** Run it plus `flutter test test/features/realtime_asr`; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): log the realtime ASR WebSocket handshake (#778)`.

### Task 6c: Shukhee in release and SDK pin
**Files:** Modify `shukhee_client_factory.dart:56-88`, `pubspec.yaml:55-58`; Test `test/features/teleconsult/shukhee_client_factory_test.dart`.
**Produces:** `Dio buildShukheeDio(ShukheeConfig config, NetworkRequestRecorder recorder)` (mirrors the SDK's `BaseOptions` as `_buildDebugDio` does; the `[ShukheeDebug]` interceptor is added only under `kDebugMode`).
- [ ] **Step 1:** Test `ShukheeClient(config, dio: buildShukheeDio(config, fake)).getSpecialities()` against a scripted adapter records one row; in a non-debug run no `[ShukheeDebug]` interceptor is present.
- [ ] **Step 2:** Run it; expected FAIL.
- [ ] **Step 3:** `buildShukheeClient` always passes the Dio. Pin the `shukhee_sdk` git dependency to the full SHA of the commit currently resolved (`dd9742c6…`, take the full SHA from the pub cache directory name or `ls-remote`), keeping the URL.
- [ ] **Step 4:** Run it, `flutter pub get`, `flutter analyze`; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): inject the logging Dio into the Shukhee client and pin the SDK (#778)`.

### Task 6d: Registry and SDK drift tests
**Files:** Create `test/core/net_log/transport_registry.dart`, `transport_registry_test.dart`, `shukhee_sdk_drift_test.dart`.
- [ ] **Step 1:** `transport_registry_test` scans `lib/**/*.dart` (comment lines stripped) for `\bDio\s*\(`, `IOWebSocketChannel`, `WebSocketChannel\.connect`, `HttpClient\(\)`, `package:http/`, `http\.(get|post|put|delete|Client|Request)\(`, `ShukheeClient\(`; the (file, count) set must equal the registry; each entry has a coverage kind and its file must contain the evidence token (`attachNetworkLog(`, `attachAiServiceAuth(`, `networkRecorder`, `recorder:`). A self-test shows an unregistered `Dio(` in a temp fixture fails. `shukhee_sdk_drift_test` resolves the SDK root from `.dart_tool/package_config.json` and asserts exactly one `Dio(` in `lib/src/shukhee_client.dart`, written as `dio ??`.
- [ ] **Step 2:** Run both (they should already pass once T5-T6c are in; write the registry from the spec §7a inventory first and confirm the self-test fails when an entry is removed).
- [ ] **Step 3-4:** Fix registry or evidence gaps until green: `flutter test test/core/net_log`.
- [ ] **Step 5:** Commit `test(mobile): transport registry and Shukhee SDK drift guard (#778)`.

### Task 7: HiddenTapTrigger
**Files:** Create `lib/core/widgets/hidden_tap_trigger.dart`; Test `test/core/widgets/hidden_tap_trigger_test.dart`.
**Produces:** `HiddenTapTrigger({int taps = 10, Duration window = const Duration(seconds: 2), required VoidCallback onTriggered, required Widget child})` using `GestureDetector(behavior: HitTestBehavior.opaque)`.
- [ ] **Step 1:** Tests: 9 taps do not fire; 10 fire once; a gap over 2 s resets the count; a tap on the padding area of the child counts.
- [ ] **Step 2:** Run it; expected FAIL. **Step 3:** Implement. **Step 4:** Run; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): hidden tap trigger widget (#778)`.

### Task 8a: Repository and controller
**Files:** Create `native_network_event_source.dart`, `network_log_repository.dart`, `lib/features/debug/network_log_controller.dart`; Test `test/core/net_log/network_log_repository_test.dart`.
**Consumes:** `NetworkLogDao`, `NetworkRequestRecorder` (flush), `UrlSanitizer`, `AppConfig.configuredEndpoints`, `MicroCoachingService.sdkBaseUrl`.
**Produces:** `enum NativeNetworkStatus { ok, unavailable, notInitialized, failed }`; `class NativeNetworkEventsResult { NativeNetworkStatus status; List<NetworkLogEntry> events; int maxId; }`; `abstract interface class NativeNetworkEventSource { Future<NativeNetworkEventsResult> fetch({required int afterId, int limit = 200}); }`; `class UnavailableNativeNetworkEventSource implements NativeNetworkEventSource` (always returns `unavailable`; the source T8b provides in `main.dart` until T9a replaces it); `NetworkLogRepository({required NetworkLogDao dao, required NetworkRequestRecorder recorder, required NativeNetworkEventSource native})` with `Future<NetworkLogPage> load({String? service, int offset = 0})` (flush, pull native up to 3 calls of 200 from the stored cursor, reset the cursor to 0 when `maxId < cursor`, re-sanitise every native `url`, `mergeNative` with the floor, then read a page and counts) and `Future<List<NetworkLogEntry>> copyRows({String? service})` (max 200); `NetworkLogController extends ChangeNotifier` with `service`, `rows`, `counts`, `nativeStatus`, `droppedCount`, `loadMore()`, `refresh()`, `clear()`.
- [ ] **Step 1:** Tests with a fake native source: each status leaves Dart rows intact and exposes the status; a raw presigned URL from the source is stored without its query; cursor reset on store reset; floor respected after `clear()`; `copyRows` caps at 200 and honours the filter.
- [ ] **Step 2:** Run it; expected FAIL. **Step 3:** Implement. **Step 4:** Run; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): network log repository and controller (#778)`.

### Task 8b: Page, route, triggers, strings
**Files:** Create `lib/features/debug/network_log_screen.dart`; Modify `router.dart` (`:71`, route near `:116-149`), `offline_sync_screen.dart:121-127`, `login_screen.dart:251-259`, `app_strings.dart`, `assets/translations/strings.json`, `analytics_events.dart` and `analytics_route_observer.dart:19-34`, `main.dart` (providers); Test `test/features/debug/network_log_screen_test.dart`, extend `test/i18n_key_coverage_test.dart` expectations only through the new keys.
**Produces:** route `GoRoute(path: '/diagnostics/network', name: 'network-diagnostics')` allowed without auth (`if (loc == '/diagnostics/network') return null;` beside the `/forgot-password` exemption, before the re-entry branch); triggers keyed `Key('networkLog.trigger.login')` (login logo) and `Key('networkLog.trigger.offlineSync')` (the card header `Text`), each `context.push('/diagnostics/network')`; `NetworkLogStrings` (en + bn; bn drafted, flagged for native-speaker review in the PR); `AnalyticsScreen.networkDiagnostics = 'network_diagnostics'`. Not wrapped in `PhiScreen`.
- [ ] **Step 1:** Widget tests: endpoint rows render with rule text; chips filter and show counts; scrolling past 200 loads the next page; "native capture unavailable" line shows for `unavailable`, `notInitialized` and `failed`; copy puts at most 200 lines on the clipboard; clear empties the list; 10 taps on each trigger push the route; a signed-out router test reaches `/diagnostics/network` and `/login?from=lock` still allows it.
- [ ] **Step 2:** Run it plus `flutter test test/i18n_key_coverage_test.dart`; expected FAIL.
- [ ] **Step 3:** Implement the screen as `ListView.builder` inside `SelectionArea`; widgets hold no logic (controller does).
- [ ] **Step 4:** Run the files, `flutter analyze`, `flutter build apk --debug`; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): hidden Network diagnostics page (#778)`.

### Task 9a: Dart side of the native pull
**Files:** Modify `micro_coaching_service.dart`; Create `MicroCoachingNetworkEventSource` in `native_network_event_source.dart`; Modify `main.dart` (replace `UnavailableNativeNetworkEventSource` with `MicroCoachingNetworkEventSource` in the provider); Test `test/core/services/micro_coaching_network_events_test.dart`.
**Produces:** `static Future<NativeNetworkEventsResult> MicroCoachingService.getNetworkEvents({required int afterId, int limit = 200})` calling `invokeMethod('getNetworkEvents', {afterId, limit, contract_version: 1})`; returns `unavailable` without calling when `kIsWeb || defaultTargetPlatform != TargetPlatform.android`; catches only `MissingPluginException` (-> `unavailable`) and `PlatformException` (-> `failed`); validates the payload with `is` checks (malformed row skipped and counted, malformed envelope -> `failed`, `sdk_event_version != 1` -> `unavailable`); `error_type` values pass through verbatim.
- [ ] **Step 1:** Tests with `TestDefaultBinaryMessengerBinding`: unregistered channel -> `unavailable`; handler throwing `PlatformException` -> `failed`; `notInitialized` response; version 2 -> `unavailable`; malformed row skipped; `debugDefaultTargetPlatformOverride = iOS` makes no call; a good payload maps to entries with `source == 'native'`, `timing == 'headers'`.
- [ ] **Step 2:** Run it; expected FAIL. **Step 3:** Implement. **Step 4:** Run it plus `flutter test test/core/net_log`; expected PASS.
- [ ] **Step 5:** Commit `feat(mobile): pull native coaching SDK network events (#778)`.

### Task 9b (blocked: after SDK #21 is merged and the AAR rebuilt)
**Files:** Modify `android/app/src/main/kotlin/com/medtroniclabs/uhis_next/MicroCoachingPlugin.kt` (new `"getNetworkEvents"` case before `else -> result.notImplemented()` at `:425`; read on `Dispatchers.IO`, `result.success` on the main thread; `!MicroCoachingSDK.isInitialized()` returns `{status:"notInitialized", events:[], max_id:0, sdk_event_version:1}`), replace `android/app/libs/micro-coaching-sdk.aar`, `build.gradle.kts:152`.
- [ ] Steps: confirm the AAR exposes the call; add the handler; run `flutter test`, `flutter analyze`, `flutter build apk --debug`; on the Pixel (release build, env file copied by the owner) open Coaching, tap 10 times on both headers, and confirm native rows, the `admin-api` 404 and no emails, ids or signatures in any URL; run the stale-`libapp.so` check. Commit `feat(mobile): serve native network events to the Network page (#778)`.

## Task ledger (filled during execution)
| Task | Commit | Spec review | Quality review | Security / QA |
|---|---|---|---|---|
| T1-T9a, T9b | | | | `lw-security` on T1, T3, T4, T5, T8b, T9a |
