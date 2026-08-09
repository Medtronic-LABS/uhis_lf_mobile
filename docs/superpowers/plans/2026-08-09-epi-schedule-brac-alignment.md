# Align the childhood immunisation schedule with BRAC's supplied table

## Context

BRAC supplied a one-page `VACCINATION SCHEDULE` (English + Bangla) as feedback on the
immunisation feature. It is to be treated as authoritative: the app's schedule must match
it exactly.

This is clinical, not cosmetic. The EPI engine drives what an SK is prompted to administer,
what shows as due or overdue, and what reaches the backend. A schedule that disagrees with
the national one produces wrong prompts at the point of care.

Two findings from exploration reshape the work:

1. **The local schedule is only the offline fallback.** `assets/forms/epi_schedule.json` is
   read by `EpiScheduleEngine.build()` only when the backend is unreachable. When online,
   `immunisation_timeline_screen.dart:203-273` fetches `POST /spice-service/immunisation/list`
   and that response wins. Editing the asset alone would not change production behaviour.
2. **Vaccine identity is already split three ways** and history matching is already broken.
   The local asset has `code` (`OPV2`) and `display` (`OPV-2`); the backend returns its own
   vocabulary (`Polio-(OPV 2)`, `Penta-2` — captured live in
   `epi_schedule_engine_test.dart:212-254`). The offline path stores `vaccine_code: v.code`
   while the online path stores `vaccine_code: dto.vaccineName`, so one column already holds
   two vocabularies, and the engine's `givenByCode[...]` lookup silently fails to match most
   numbered doses today — before any change here.

### Decisions taken (confirmed with the requester)

1. **Fully authoritative — replace.** The sheet is the target state.
2. **Sheet is exhaustive — remove what it omits.** `OPV0`, `HepB0`, `ROTA1`, `ROTA2`, `VITA1`
   come out of the schedule.
   > **Flagged and overridden:** I recommended keeping these, because Rotavirus and Vitamin A
   > are part of Bangladesh's national EPI, and removing them stops SKs being prompted for
   > doses they currently give. The requester chose removal on the basis that the sheet is
   > complete. **This should be confirmed with BRAC in writing before the change ships.**
   > Removal is schedule-only — historical rows for these vaccines are retained (decision 4),
   > so the decision is reversible by restoring the entries.
3. **App becomes the source of truth.** Stop consuming the backend schedule; build always
   from the local asset. The backend is used only for administered history.
4. **Preserve existing records; no migration.** Historical rows keep their identifiers and
   dates. This forbids renaming any `code`.
5. **Include the Bangla names** from the sheet.

## Required schedule (transcribed from the BRAC sheet)

| When | Vaccines | Bangla (as supplied) |
|---|---|---|
| At Birth | BCG | বিসিজি (BCG) |
| 6 Weeks | Pentavalent 1 (DPT, Hep B, Hib); PCV 1; OPV 1 | পেন্টাভ্যালেন্ট টিকা – প্রথম ডোজ (ডিপিটি, হেপাটাইটিস-বি, হিব); পিসিভি (PCV) – প্রথম ডোজ; ওপিভি (OPV) – প্রথম ডোজ |
| 10 Weeks | Pentavalent 2; PCV 2; OPV 2 | পেন্টাভ্যালেন্ট টিকা – দ্বিতীয় ডোজ; পিসিভি (PCV) – দ্বিতীয় ডোজ; ওপিভি (OPV) – দ্বিতীয় ডোজ |
| 14 Weeks | Pentavalent 3; PCV 3; OPV 3; IPV 1 | পেন্টাভ্যালেন্ট টিকা – তৃতীয় ডোজ; পিসিভি (PCV) – তৃতীয় ডোজ; ওপিভি (OPV) – তৃতীয় ডোজ; আইপিভি (IPV) - প্রথম ডোজ |
| 9 Months | MR 1; IPV 2 | এমআর (MR) - প্রথম ডোজ; আইপিভি (IPV) - দ্বিতীয় ডোজ |
| 15 Months | MR 2; TCV | এমআর (MR) - দ্বিতীয় ডোজ; টিসিভি (TCV) |

## Gap analysis (current vs required)

Current schedule: `assets/forms/epi_schedule.json`.

| Milestone | Required | Currently in app | Gap |
|---|---|---|---|
| At Birth | BCG | `BCG`, `OPV0`, `HepB0` | **Remove** `OPV0`, `HepB0` |
| 6 Weeks | PENTA1, PCV1, OPV1 | + `ROTA1` | **Remove** `ROTA1` |
| 10 Weeks | PENTA2, PCV2, OPV2 | + `ROTA2` | **Remove** `ROTA2` |
| 14 Weeks | PENTA3, PCV3, OPV3, IPV1 | PENTA3, PCV3, OPV3, `FIPV1` "fIPV — Dose 1" | **Relabel** display to IPV; keep code |
| 9 Months | MR1, IPV2 | `MR1`, `FIPV2`, **`TCV`**, `VITA1` | **Move `TCV` to 15 Months**; **remove** `VITA1`; relabel `FIPV2` |
| 15 Months | MR2, TCV | `MR2` only | **Add `TCV`** here |

Correct already: milestone set and timings (0d / 6w / 10w / 14w / 9m / 15m), Pentavalent /
PCV / OPV dose numbering, MR naming and both doses, IPV dose count and timing.

**The one outright clinical bug: `TCV` sits at 9 Months** (`epi_schedule.json:169-175`),
a full milestone early, paired with MR1 instead of MR2.

## Approach

### 1. Separate vaccine identity into three fields (prerequisite)

Decisions 4 and 5 cannot both hold under today's model, because `display` is simultaneously
the rendered label *and* the wire value (`immunisation_timeline_screen.dart:1601-1616` sends
`vaccineName: v.display`). Localising `display` would make a Bangla-locale SK POST Bangla
vaccine names. So, on `VaccineEntry` and in `epi_schedule.json`:

- **`code`** — stable internal id and local DB key. **Never changes.** Keeps `FIPV1`/`FIPV2`
  so existing `'${patientId}_FIPV1'` rows keep matching.
- **`wireName`** — the stable string sent as `vaccineName`. Seed it with each vaccine's
  *current* `display` value so already-synced records stay consistent, then leave it frozen.
- **`display`** — UI only, localisable, never persisted or transmitted.

This mirrors the split already used for `ChildAssessmentStrings.complicationOptionIds` /
`complicationOptionLabel(id)` and `CceStrings.rejectReasonKeys` / `rejectReasonLabel(key)`.

### 2. Make the app the source of truth **for the schedule only** — keep the API for the record

`POST /spice-service/immunisation/list` is not a schedule template: `VaccinationDetailDto`
carries `status` ('Vaccinated' | 'Missed' | 'Upcoming'), `vaccinatedDate` and `reason`
(`immunisation_dto.dart:10-45`). It is **the patient's immunisation record**. Dropping the
call would lose server-side history — on a fresh device or after Clear Data every dose already
given would reappear as due.

So split the two concerns:

- **Schedule** (which vaccines, at which milestone) → local asset, authoritative.
- **Administered record** (given / missed / when / why) → still `immunisation/list`.

Concretely, in `immunisation_timeline_screen.dart`: always build milestones from
`EpiScheduleEngine.build()`, and use the `immunisation/list` response only for its outcome
fields, discarding `type`, `value`, `displayOrder`, `vaccineOrder` and `doseClosureWeeks`.

This deletes three duplications on its own:
- `_dtosToMilestones()` (`:388-460`), a second milestone builder
- `_milestoneLabel()` (`:462-472`), a second milestone-label implementation in English literals
- the 28-day status window, currently hardcoded in both `epi_schedule_engine.dart:219-226`
  and `immunisation_timeline_screen.dart:424-432`

Fold the surviving status logic into `EpiScheduleEngine` alone, and read the window from the
per-milestone `doseClosureWeeks` field, which is parsed today but never consumed.

### 2a. Vaccine-name alias map (**required**, not optional)

Merging server outcomes onto locally-defined entries needs backend `vaccineName` → local
`code`. The backend's vocabulary differs from both local fields: it returns `Polio-(OPV 2)`
and `Penta-2` (captured live, `epi_schedule_engine_test.dart:212-254`) where local `code` is
`OPV2`/`PENTA2` and local `display` is `OPV-2`/`Pentavalent-2`. `EpiScheduleEngine.build()`
matches on `code` string equality (`:174-177, 209-210`), so this **silently fails today** for
most numbered doses.

Without the map, step 2 makes history *worse*, not better. Add a `wireAliases: [...]` list per
vaccine in `epi_schedule.json` (backend spellings seen in the wild, plus `wireName` and `code`
themselves), and resolve incoming records through it. Aliases are additive data — an unknown
spelling falls through to "unmatched" exactly as today, never to a wrong vaccine.

The alias list is a known-incomplete inventory of server spellings. Log unmatched incoming
`vaccineName` values so the gaps surface from real traffic rather than guesswork.

### 2b. De-scheduled vaccines still have server records

Removing `OPV0`, `HepB0`, `ROTA1`, `ROTA2`, `VITA1` from the schedule (decision 2) stops the
app *scheduling* them. It does not stop `immunisation/list` returning doses already recorded
against them.

**Assumption, following decision 4 (preserve as recorded):** such records are retained and
rendered as historical entries outside the scheduled milestones, not discarded. Dropping them
would make a child's existing Rotavirus and Vitamin A doses vanish from the timeline, which is
data loss in the SK's eyes even though nothing is deleted server-side. Confirm this is wanted;
it is a visible UI addition rather than a pure removal.

### 2c. Dead endpoint

`Endpoints.immunisationCreate` (`endpoints.dart:29-30`) is declared but never called anywhere
in `lib/`. Delete it, or record why it is being kept.

### 3. Correct the schedule data

Edit `assets/forms/epi_schedule.json` per the gap table: delete five entries, move `TCV` to
the 15-Months group, and relabel the two fIPV displays. No `code` changes.

### 4. Add Bangla vaccine names

Route `display` through the existing seam rather than adding a parallel mechanism: add
`Epi.vaccine.<CODE>` and `Epi.milestone.<KEY>` codes to `lib/core/constants/app_strings.dart`
with the JSON's English text as the fallback, and the sheet's Bangla in
`assets/translations/strings.json`. Then have every render site resolve through it —
`v.display` and `milestone.label` in `immunisation_timeline_screen.dart`,
`epi_visit_summary.dart`, and `child_immunization_briefing_rules.dart`.

Note `patient_context_screen.dart:1827-1836` renders `raw['vaccineName']` from frozen
historical JSON. That is out of scope and will keep showing whatever name was stored at save
time — expected under decision 4.

### API contract summary

Four paths are involved. Only the *interpretation* of one read changes; no write changes.

| Path | Direction | Change |
|---|---|---|
| `POST /spice-service/immunisation/list` | read | **Kept.** Consume outcome fields only; ignore its schedule fields. Match via the alias map (2a). |
| `POST /spice-service/immunisation/create` | write | Unused today — delete (2c). |
| `POST /spice-service/immunisation/summary-create` | write | **Unchanged.** |
| `POST /offline-service/offline-sync/create`, `assessmentType: 'CHILD_IMMUNIZATION'`, wrapped `childImmunization` (`local_assessment_dao.dart:575`) | write | **Payload unchanged.** `vaccineName` switches from `v.display` to the frozen `v.wireName`, seeded with today's `display` values — so the bytes on the wire are identical. |

No new endpoint is introduced, so the approved-endpoints rule in `endpoints.dart` is satisfied
without additions. No backend change is required for this work to land, and no already-synced
record changes meaning.

### Critical files

- `assets/forms/epi_schedule.json` — schedule data, `wireName`, `wireAliases`
- `lib/features/visit/immunisation/epi_schedule_engine.dart` — build, status, sequencing,
  alias resolution
- `lib/features/visit/immunisation/immunisation_timeline_screen.dart` — schedule/record split,
  remove the duplicated milestone builders and status window, send `wireName`
- `lib/features/visit/immunisation/immunisation_dto.dart` — keep; narrow to outcome fields
- `lib/core/constants/app_strings.dart` + `assets/translations/strings.json` — Bangla

## Verification

Baseline first: `flutter test` and record failures by name — this repo carries pre-existing
failures, and `main` moved today, so the old count of 37 is stale. The EPI-adjacent suites
were 62/62 green at exploration time.

- `flutter analyze lib/` → 0 errors
- `flutter test test/features/visit/immunisation/ test/core/db/immunisation_dao_test.dart test/core/clinical/briefing_rules/`
- `flutter test` → no new failures vs the fresh baseline

Tests to add:
- Schedule matches the BRAC table exactly: each milestone's vaccine set and dose numbers;
  assert the five removed codes are absent and `TCV` resolves to 15 Months.
- **Row-matching regression guard** (no coverage today): record a dose under `FIPV1`, rebuild,
  assert it reads back as completed and does *not* reappear as due. This is the test that
  protects decision 4 against a future code rename.
- `wireName` is unchanged by locale: build under Bangla and assert the transmitted
  `vaccineName` is still the English wire string.
- Bangla resolution: `display` returns the sheet's Bangla under `AppLanguage.bangla` and the
  English fallback otherwise.
- Update `epi_schedule_engine_test.dart` — it asserts against real asset content
  (`'OPV0'`, `'At Birth'`, etc. at `:22-23,49,99`) and is the one suite genuinely coupled to
  the schedule. The `'Polio-(OPV 2)'` / `'Penta-2'` fixture at `:212-254` documents the
  pre-existing backend-vocabulary mismatch; keep it.

Additional API-facing tests:
- Alias resolution: a server record named `Polio-(OPV 2)` marks the local `OPV2` entry as
  completed; `Penta-2` marks `PENTA2`. These fail on today's code and are the regression
  guard for step 2a.
- An unrecognised server `vaccineName` resolves to no vaccine (never to a wrong one) and is
  logged.
- A server record for a de-scheduled vaccine (`ROTA1`) is retained and surfaced, not dropped.

Manual, on device (both locales):
1. Child born today → only BCG due at birth; no OPV-0, no Hep B.
2. Child aged 15 months → TCV and MR 2 due together; TCV absent at 9 months.
3. Child aged 14 weeks → IPV shows as "IPV — Dose 1", not "fIPV".
4. Record a dose, inspect the outbound payload → `vaccineName` is the English wire string
   even with the UI in Bangla, and byte-identical to what the current build sends.
5. **A child with doses already recorded server-side still shows them as completed after a
   fresh install** — this is the check that step 2 didn't regress history.
6. Airplane mode → schedule still renders from the local asset; reconnect → server outcomes
   merge onto it without duplicating or resetting entries.

## Out of scope, tracked

- `doseClosureWeeks` is inert in the local asset today; wiring it up (step 2) removes the
  hardcoded 28 but changes the upcoming-window behaviour if any milestone's value differs
  from 4 weeks. Check before relying on it.
- The pre-existing `vaccine_code` vocabulary split (offline writes `code`, online writes the
  backend's `vaccineName`) is *narrowed* by step 2a's alias map at read time, but rows already
  written under backend spellings are not rewritten (decision 4). Reads resolve correctly via
  aliases; the column keeps holding two vocabularies. A one-off normalisation pass is its own
  task, and needs the alias inventory from 2a to exist first.
- `child_immunization_briefing_rules.dart:15` keeps a separate 7-day due-soon window,
  deliberately different from the engine's window. Left alone.
