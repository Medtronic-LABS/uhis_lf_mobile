# Changelog

All notable developer-facing changes to this app are documented here, grouped
by the work session/theme that produced them. This complements (does not
replace) `store_assets/release_notes/` — those are user-facing Play Store
copy per shipped version; this file tracks the underlying engineering
changes, including ones in dependency apps this app consumes.

## Unreleased — Teleconsult consent: embedded in Call Logs at booking

Replaces the two-record consent design (a separate `Shukhee Consent Log`
doctype plus an after-the-fact linking step, matched on `encounter_id`/
`visit_id`) with a single-request design: an Agreed decision now rides along
in the same booking request that starts the call and is written directly
onto the resulting `Call Logs` row; a Decline is sent immediately,
fire-and-forget, to its own lightweight record. This removes an entire class
of bugs the old design produced — a deferred local upload racing the
synchronous booking call, wedged sync state silently blocking the upload
forever, a version-only match that could cross-attach a different patient's
decision, and a plumbing bug that sent an empty `patientId`.

### This app (`uhis_lf_mobile`)

- **Embed teleconsult consent directly in the booking call, drop the local
  upload queue** — the Agreed consent decision (`version`/`versionId`/`lng`/
  `itemsChecked`) is carried forward and sent as part of the same
  `start_consultation` request that books the call, instead of being queued
  locally and uploaded later. Removes the entire local SQLite queue/DAO/
  service/uploader stack (`teleconsult_consent_log_*`) and
  `PostSyncRefresher`'s flush for it; `schemaVersion` bumped to 57 with a
  migration dropping the now-orphaned table on existing installs. A Decline
  is sent immediately via `ShukheeConsentClient.recordDecline` — there is no
  Call Logs row to embed it on, so this is its only record. Also fixes a real
  bug found while testing this change: the teleconsult button was threading
  the household member id through as the patient id for both the consent
  screen and the booking call, instead of the visit's own resolved
  `patientId` — empty for some visits, which silently made every consent
  decision for them unrecordable server-side.
- **Fetch the teleconsult kill-switch live, not just at login** — the
  backend-driven kill-switch (below) now also re-checks on every mount of
  the "Call a doctor" button / teleconsult history section, and on the app's
  actual relaunch-with-restored-session path (previously missed, so flipping
  the backend flag had no visible effect even after a relaunch).
- **Add a manual refresh affordance** next to the disabled "Call a doctor"
  button, so an SK can re-check the kill-switch on demand without
  relaunching the app.
- **Add a backend-driven kill-switch for the Shukhee teleconsult feature** —
  a second gate alongside the build-time `TELECONSULT_ENABLED` dart-define:
  a server-side flag (`Shukhee Settings.teleconsult_enabled`, default OFF)
  lets a build ship with the feature compiled in everywhere while it stays
  actually hidden until a given backend's Shukhee gateway route is verified
  working — no new app release needed to flip it per environment.
- **Fix a malformed Shukhee gateway URL** when `API_BASE_URL` has no trailing
  slash — `AppConfig.shukheeApiBaseUrl`/`spiceNextCoreApiBaseUrl` were
  concatenating `apiBaseUrl + 'admin-api'` with no separator, producing a
  mangled, DNS-unresolvable host on any build whose `API_BASE_URL`
  dart-define lacked the trailing slash the default value happened to have.

### Dependency apps (consumed by this app)

- **`shukhee_sdk`** (PR #1, merged) — `ShukheeClient.startConsultation` gains
  optional `versionId`/`lng`/`itemsChecked` parameters, forwarded as
  `version_id`/`lng`/`items_checked` form fields so the backend can embed
  the consent decision directly onto the `Call Logs` row it creates.
- **`shukhee_integration`** (backend, PR #12, merged) — `start_consultation`
  resolves and embeds the consent decision directly onto the `Call Logs`
  row it inserts (new `consent_version`/`consent_lng`/`consent_items`/
  `consent_filled_text` fields, plus a new `Call Log Consent Item` child
  doctype); adds `record_consent_decline` for the Decline path (new,
  lightweight `Shukhee Consent Decline` doctype); retires the old
  `Shukhee Consent Log`/`Shukhee Consent Log Item` doctypes and the
  `attach_consent_to_call`/`get_call_consent` endpoints via a
  `post_model_sync` patch.
