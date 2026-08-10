# Consolidated permission request — design

**Status:** design, parked 2026-08-10. Not implemented.
**Related:** `background_sync_foreground_service_design.md` (the battery-optimisation prompt this folds in)

## Context

SKs meet permission dialogs at four unrelated moments, each mid-task:

| Permission | Asked when | Where |
|---|---|---|
| Notifications | App start, unprompted | `main.dart:312` → `_bootstrapNotifications()` |
| Microphone | First AI Scribe record tap | `ScribePermissionService` (4 call sites) |
| Camera | First NID scan during enrolment | `enrollment_entry_sheet.dart:104, 312` |
| Location | First household enrolment | `LocationService` ← `enrollment_controller.dart:363` |

Two of those interrupt work in front of a patient — recording symptoms, scanning an ID.
A non-technical user under that pressure taps Deny to clear the dialog, and the feature then
appears broken with no explanation and no obvious way back.

Separately, `BatteryOptimizationGate` already asks its own one-time question on the dashboard,
making two setup conversations where there should be one.

## The constraint that shapes everything

**Android will not show a single combined dialog.** It shows one per permission group,
sequentially. `permission_handler` (already a dependency, `^11.3.1`) supports
`[Permission.a, Permission.b].request()`, which queues them back-to-back.

So "one-shot" means **one moment, several taps, once ever** — not one dialog. Worth stating
plainly to anyone reviewing this, because the phrase invites the wrong expectation.

## Goals

1. Every permission is asked in one sitting, while the SK is set up and not mid-visit.
2. Each is explained in Bangla before the system asks.
3. A denial never blocks onboarding, and never leaves a dead-looking button later.

Non-goal: forcing grants. An SK who declines keeps a working app with degraded features.

## Design

### Where

A permissions step in `/onboarding` — it already exists and already routes onward
(`onboarding_screen.dart:53, 88`), and it sits after login and before sync, when the SK is
sitting down.

### Flow

```
login → onboarding
          │
          ├─ rationale screen (one card per permission, plain Bangla)
          │     "অনুমতি দিন"
          │        ↓
          ├─ batch request: camera, microphone, location, notifications
          │        ↓
          ├─ battery-optimisation prompt (folded in from the dashboard)
          │        ↓
          └─ continue regardless of outcome → /pin-setup → /sync
```

### Components

**`PermissionRationaleScreen`** — one card per permission: icon, what it is for in the SK's
terms ("ছবি তুলতে", "কণ্ঠস্বর রেকর্ড করতে", "খানার অবস্থান", "মনে করিয়ে দিতে"), and a single
continue button. Copy lives in `app_strings.dart`; the i18n ratchet enforces translations.

**`PermissionGate`** (mirrors `BatteryOptimizationGate`) — decides whether to show the step,
issues the batch request, records the outcome. "Asked once" persists in
`flutter_secure_storage`, the same mechanism `BatteryOptimizationGate` uses. Pure decision
logic, separate from both the plugin and the UI, so the rule is testable without a device.

**Request order:** camera → microphone → location → notifications. Notifications last
deliberately: it is the least alarming, so if an SK fatigue-denies by the last dialog, it costs
least.

### Keep the existing point-of-use checks

The lazy checks in `ScribePermissionService`, `enrollment_entry_sheet` and `LocationService`
**stay**. They become a rare fallback rather than the primary path, and they are what saves the
feature when:

- the SK denied at onboarding but later wants the feature,
- a permission was revoked in Settings after being granted,
- the app was upgraded from a build without this flow, so onboarding never ran.

Removing them would trade four well-timed prompts for one badly-timed failure.

### Permanent denial

`permission_handler` reports `isPermanentlyDenied`. Re-requesting then does nothing at all —
no dialog, no callback — which is the worst outcome: a button that looks dead. Detect it and
deep-link to app settings with an explanation, reusing the intent-with-fallback pattern in
`DeviceBatteryPlugin.openBatterySettings()`.

## Testing

**Unit** — `PermissionGate`: shows once and never again; a denial still records "asked";
permanent denial routes to settings rather than re-requesting; an unreadable storage flag
suppresses rather than repeats (same rule as `BatteryOptimizationGate`).

**Widget** — the rationale screen renders a card per permission and continues on either answer.

**On device** — `adb shell pm clear com.medtroniclabs.uhis_next` between runs. Permissions
cannot be un-granted from inside the app, and **after two denials Android permanently denies
without showing a dialog**, which silently changes what is being tested. Verify at least once
on a real Xiaomi/Transsion handset, where vendor ROMs add their own permission layers.

## Effort

~1.5–2 days: rationale screen and strings (½), gate + batch request + persistence (½), wiring
into onboarding and folding in the battery prompt (½), tests (½).

## Out of scope, but adjacent

`SCHEDULE_EXACT_ALARM` is declared in the manifest. On Android 13+ that is a Settings toggle
rather than a runtime dialog, and Play restricts the permission. Worth establishing whether the
referral SLA alarms genuinely need *exact* timing or whether inexact would do — a separate
question, but the same family of work.
