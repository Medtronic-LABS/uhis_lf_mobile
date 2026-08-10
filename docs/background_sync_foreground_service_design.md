# Background sync — foreground service + in-app progress

**Status:** design, approved 2026-08-10. Not yet implemented.
**Related:** `data_sync_gap_analysis.md` (#3 — SyncActivity follow-up work)

## Context

A full sync is long enough that it cannot survive the device's screen timeout, and today
nothing in the app defends it.

Measured on a Pixel 10a against `uhis-next-backend.labsplatform.com` on 2026-08-10:

| Event | Time |
|---|---|
| `sync-fetch` issued | 13:52:11.4 |
| Bundle received (1398 households, 3566 members, 176 follow-ups) | 13:54:04.7 |
| Bundle persisted, sync complete | 13:54:50.9 |

**~113 s time-to-first-byte, ~160 s end to end.** The device's `screen_off_timeout` is **30 s**.

In the same session, an earlier sync did not survive: `sync-fetch` went out at 13:51:32 (pid 9306),
and ~33 s later the process had been replaced by a cold start (pid 9858) that went through lock →
PIN → dashboard. No response was ever received. The exact cause (system kill vs. user action) was
not recoverable from the log, but the arithmetic is unambiguous: a 113-second operation cannot
survive a 30-second screen timeout unattended.

Current defences — all absent:

| Defence | State |
|---|---|
| Wakelock / keep-screen-on | None. `WAKE_LOCK` is declared (`AndroidManifest.xml:19`) but never acquired |
| Foreground service for sync | None. Sync is plain in-app async work |
| Lifecycle handling | None. No `WidgetsBindingObserver` in `lib/features/sync/` or `lib/core/sync/` |
| Battery-optimisation exemption | Not whitelisted — subject to Doze and App Standby |

Second, related gap: **sync progress is invisible outside `/sync`.** `SyncProgressScreen` is the
only consumer of `progressStream` / `isRunning` in the app, and `/sync` is reachable only from
login (`login_screen.dart:118`), PIN setup (`pin_setup_screen.dart:52`), and onboarding
(`onboarding_screen.dart:88`). The 113-second sync above ran while the SK was on the dashboard with
no indication anything was happening.

## Goals

1. A sync that starts keeps running when the app is minimized or the screen sleeps.
2. The SK can see sync progress from anywhere in the app, and from outside it.
3. No change to sync logic, its isolate, its DB handle, or its session.

Explicit non-goals: surviving swipe-away or reboot (rejected — WorkManager's deferred scheduling
would break "sync starts now, after login"), and cancelling a sync mid-run.

## Architecture

Sync logic stays in Dart, in the same isolate. The Android service exists only to hold the process
in the foreground-service state — which exempts it from cached-process freezing and Doze network
restrictions — and to render a notification.

```
OfflineSyncService._runSync()   ─┐
OfflinePushService.pushAll()     ├→ SyncActivity setters → onActiveChanged(true)
AssessmentRepository push       ─┘                │
                                                  ↓
                                   SyncForegroundController
                                       ↓                    ↓
                     startForeground(dataSync)      BottomNavShell strip
                     + ongoing notification         (in-app, all tabs)
                                       ↓                    ↓
              progressStream / push notifier ──→ update("households 240/1200")
                                                  ↓
                       last flag clears → onActiveChanged(false) → stop()
```

### Components

**`SyncForegroundService.kt`** (new) — a `Service` that calls
`startForeground(id, notification, FOREGROUND_SERVICE_TYPE_DATA_SYNC)` and updates its notification
on demand. Contains no sync logic. Own low-importance `NotificationChannel` so a multi-minute sync
never buzzes. `onStartCommand` returns `START_NOT_STICKY` — if the process dies there is no
in-flight sync to resume, and a system restart with no context would be worse than nothing. Content
intent opens `MainActivity` with a route extra for `/sync`.

**`SyncForegroundPlugin.kt`** (new) — MethodChannel `com.medtroniclabs.uhis_next/sync_foreground`,
mirroring `MicroCoachingPlugin`. Methods: `start(title, text)`, `update(text, done, total)`,
`stop()`, `showFailure(text)`.

**`AndroidManifest.xml`** — declare `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_DATA_SYNC`
explicitly (today they are inherited from `micro-coaching-sdk.aar`, which no longer reflects who
uses them), plus:
```xml
<service android:name=".SyncForegroundService"
         android:exported="false"
         android:foregroundServiceType="dataSync" />
```

**`SyncForegroundNotifier`** (new, `lib/core/sync/`) — abstract interface with
`MethodChannelSyncForegroundNotifier` and `NoopSyncForegroundNotifier` implementations. Callers
depend on the interface; tests and web get the no-op. Carries no business logic, mirroring
`MicroCoachingService`'s channel-wrapper style.

**`SyncForegroundController`** (new, `lib/core/sync/`) — the single owner. Subscribes to
`SyncActivity.onActiveChanged`; starts the service on the false→true edge and stops it on
true→false. Formats notification text from `OfflineSyncService.progressStream` and
`OfflinePushService`'s notifier. Constructed once in `main.dart` beside the existing singletons.

**`SyncActivity`** (modify, `lib/core/sync/sync_activity.dart`) — convert the three public mutable
bools to setters routed through one place, firing `onActiveChanged(bool)` on the `anyInFlight`
edge. Its own doc comment already flags that it should become a real coordinator; this is the
minimum needed here and removes the raw-field mutation. Call sites in `OfflineSyncService`,
`OfflinePushService` and `AssessmentRepository` change from assignment to setter.

**`BottomNavShell`** (modify, `lib/app/bottom_nav.dart:124`) — a slim progress strip at the top of
the shell body, shown while a sync is in flight. It wraps every authed tab via
`StatefulShellRoute.indexedStack` (`router.dart:148`), so one widget covers dashboard, patients,
tasks and assistant. Determinate when `SyncProgress.itemsTotal > 0`, indeterminate otherwise. Copy
comes from `SyncStrings`.

**Implemented as informational, not tappable** — a deliberate change from the original design.
`SyncProgressScreen`'s progress listener calls `_navigateAfterSync()` when the sync completes
(`sync_progress_screen.dart:83-88`), so tapping into `/sync` mid-session would yank the SK to
`/home` the moment the sync finished, losing whatever they were doing. Making it tappable requires
first teaching that screen to distinguish "arrived here from login" from "opened mid-session".

`/sync` is not inside this shell (it is a top-level route, `router.dart:129`), so the strip and the
full-screen progress can never appear together — no special-casing needed.

Reattach needs no new work: `progressStream` is a broadcast stream and
`SyncProgressScreen._startSync` (lines 76-110) already handles joining a sync started in the
background, including the already-complete case.

## Error handling

- **The service is best-effort; sync never depends on it.** Every notifier call is wrapped so a
  `PlatformException` is logged and swallowed at the controller boundary — sync continues exactly
  as it does today. A failure to show a notification must never fail a sync.
- **`ForegroundServiceStartNotAllowedException` (Android 12+).** Starting a foreground service from
  the background is restricted. Most syncs start while the app is visible, but `SyncConnectivity`
  can fire an `AutomaticSync` while backgrounded. Catch it, log it, and run the sync without the
  service — degraded, not broken.
- **`stop()` is idempotent and lives in the controller's edge handler**, driven by the
  `SyncActivity` flags the services already clear in their own `finally` blocks.
- **Overlapping operations.** A pull and an assessment push can run concurrently. The controller
  reacts only to `anyInFlight` edges, so the service starts once and stops when the last operation
  clears — never mid-flight.
- **Failure surfacing.** On sync failure the controller replaces the ongoing notification with a
  dismissible one carrying the localized reason (now available via the `NetworkException` thrown by
  `offline_sync_service.dart`), then `stopForeground(STOP_FOREGROUND_DETACH)` so it survives.

## Android version constraints

| Version | Constraint | Handling |
|---|---|---|
| 12 (API 31) | Cannot start an FGS from the background | Catch `ForegroundServiceStartNotAllowedException`, degrade to in-app sync |
| 13 (API 33) | `POST_NOTIFICATIONS` runtime permission | Already declared (`AndroidManifest.xml:15`) and requested (`notification_service.dart:49`) |
| 14 (API 34) | FGS must declare a type; `dataSync` needs its permission | Declared in manifest as above |
| 15 (API 35) | `dataSync` FGS capped at 6 cumulative hours per 24 h; system calls `Service.onTimeout()` | Far above a ~3-minute sync. Implement `onTimeout` to stop cleanly rather than be force-stopped |

**Play Console.** After this change the app itself uses `FOREGROUND_SERVICE_DATA_SYNC`, where today
it only inherits it from the coaching SDK. The declaration must cover this use. This is a net
simplification: a sync with a live progress notification is easier to demonstrate in the required
video than the Gemma model download, and is a more defensible justification.

## Testing

**Unit**
- `SyncActivity` fires `onActiveChanged(true)` exactly once when a second operation starts while
  one is already running, and `false` only when the last one clears.
- `SyncForegroundController` with a fake `SyncForegroundNotifier`: `start` once per sync session,
  `update` on progress events, `stop` on completion and on failure.
- A notifier that throws `PlatformException` does not propagate — sync completes normally.

**Widget**
- `BottomNavShell` renders the strip while `anyInFlight`, hides it when clear, and routes to
  `/sync` on tap.

**On device (Pixel 10a)** — the test that actually matters, and note it is invalid while charging,
because Doze does not engage on AC power:
```bash
adb shell dumpsys battery unplug
adb shell input keyevent 26            # screen off
adb shell dumpsys deviceidle force-idle
# … run a full sync, wait ~3 min …
adb shell dumpsys deviceidle unforce && adb shell dumpsys battery reset
```
Expected: the ongoing notification persists, `adb logcat` shows the sync progressing through the
screen-off window, and `Bundle persisted` appears without the process being replaced. Compare
against the 2026-08-10 baseline, where the process was replaced ~33 s in.

## Out of scope

- Surviving swipe-away or reboot (WorkManager) — deferred start is unacceptable for post-login sync.
- Cancelling a sync from the notification — needs a `CancelToken` threaded through pull and push
  plus a guarantee that no partial bundle is persisted. Worth revisiting once this ships.
- The server-side cost of a 113-second bundle. Pagination or streaming so the first byte arrives
  early would help far more than any client change; raise with the backend team separately.
