# Home screen: pixel-match the approved (v13) design

## Context

The Home/Dashboard screen (`mission_dashboard_screen.dart`) has drifted from the
approved mockup in small, cumulative ways — mostly spacing/typography values
that predate the v13 redesign, plus a handful of already-defined design tokens
that were never wired up. This is a **visual-only** pass: no business logic,
navigation, data flow, API calls, state management, or visit-status logic
changes. Category icon redesign is explicitly out of scope.

**Authoritative source:** `/Users/amresh/labs/UHIS/leapfrog-setup/apon_sushashthya_v13.html`,
Home screen = `<div class="screen" id="s2">`, lines 1294–1493 (+ shared CSS,
lines 8–1096). Confirmed `design_v11/` describes a superseded (pre-v13) layout
for this screen (AI ribbon + stat-grid + village chips, none of which exist in
v13's actual markup) — **do not use it as a source.**

Two scope decisions were resolved with the user before finalizing this plan,
because several pieces of the "Home screen" are actually shared widgets whose
styling also renders on other tabs:

1. **Header greeting/subtitle typography** (`AppTextStyles.headerTitle`/
   `.headerSub`) is also used by the Lock screen (`lock_header.dart`).
   → **Decision: add new Home-only styles** (`dashboardGreeting`/
   `dashboardGreetingSub`) instead of editing the shared tokens. Lock screen
   stays untouched.
2. **`MissionQueueCard`** (visit cards) is also rendered on the Patients tab
   (household list) and Tasks tab (referral list) — 5 shared call sites.
   **`PatientFilterPanel`** (village tabs + category bubbles) is also
   rendered on the Patients tab.
   → **Decision: edit these shared widgets directly.** Patients/Tasks tabs
   will visually tighten as a side effect — accepted, since it reuses
   existing components (per constraint) rather than forking near-duplicate
   variants, and the changes are a density/consistency improvement, not a
   regression.

Bottom-nav styling is a third shared surface (all 4 tabs, via a single global
`NavigationBarThemeData`) — there is no way to scope this to Home only by
construction, so it's treated as an accepted global tune, not a decision
point.

## Section-by-section changes

Values below are the *effective* mockup values already reconciled against
CSS cascade traps (see note under Visit Cards). Where the current code is
already spec-exact, that's called out explicitly as **no change**.

### 1. Header (`_DashboardHeader`, `mission_dashboard_screen.dart:936-1012`)

- Icon order, icon sizes (21/21/22), inter-icon gap (14px = `AppSpacing.xxl`),
  header-row bottom margin (14px), notification badge (16×16, `#E8356D`,
  2px navy border, 9px/800 text) — **all already spec-exact** (done in the
  prior icon-reorder PR). No change.
- Greeting text: 23px → **20px**, weight w800 (unchanged). New style
  `AppTextStyles.dashboardGreeting` (Home-only, see Tokens below); replaces
  `headerTitle` at this one call site only.
- Subtitle: 14px → **12px**, weight w400 (unchanged), color unchanged
  (`AppColors.onDarkLow`). New style `AppTextStyles.dashboardGreetingSub`;
  replaces `headerSub` at this one call site only. Subtitle-to-greeting gap
  (1px) already matches spec — no change.
- Container padding: currently `EdgeInsets.fromLTRB(16, topPadding+10, 8, 10)`.
  Spec's `.header{padding:0 20px 18px}` — top is literally **0** (the
  mockup's separate fake `.status-bar` block above `.header` already
  accounts for that space; Flutter's real safe-area inset — `topPadding` —
  is the direct equivalent, so no *extra* literal offset belongs on top of
  it). Target: **`EdgeInsets.fromLTRB(20, topPadding, 20, 18)`** — i.e. drop
  the `+10` on top entirely, and change the bottom from 10 to **18** (this
  bottom value also is the effective header→referral-banner gap, since the
  banner sits directly below with no margin-top of its own — see the
  Vertical rhythm table below).

### 2. Search bar (`GlobalSearchBar`, `global_search_bar.dart:15-102`)

- Height: 44 → **40**.
- Leading search icon: 20 → **16**.
- Trailing QR icon: 22 → **20**.
- Radius: currently `AppRadius.patRow` (14) → should be **`AppRadius.button`**
  (12) — this token's own doc comment already says `.search-bar`; it was
  simply never wired up here. Exact spec match (`border-radius:12px`).
- Remove the 1×22 vertical divider between the input and the QR button —
  not present in the mockup at all (optional but recommended; pure
  simplification, zero functional impact).
- Hint text ("Name, Mobile, NID") already fixed in a prior PR — no change.

### 3. Referral alert banner (`_ReferralAlertBanner`, `:1014-1166`)

- Background: currently `tokens.statusCritical` (generic red, `#EF4444`/
  `#F87171`) → should be **`AppColors.referralAlertBg`/`.referralAlertBgDark`**
  (`#DC2626`/`#B91C1C`) — this token already exists, comment-labeled "explicit
  #DC2626 from v13," and is currently unused anywhere in the app. This is a
  real color correction, not just a token swap.
- Shadow: recolor to match (`0 2px 6px rgba(220,38,38,0.25)` — same shape,
  just rebased off the new background color).
- Badge (16×16, white@25%, count text) and pulse dot (6×6, `#FEF08A`) —
  already spec-exact. Label typography (12px/w700/white) — already
  spec-exact. **No change** to any of these.
- Verify during implementation whether the banner currently renders full-
  bleed (edge-to-edge under the header) or inset within body padding —
  spec bleeds it via `margin: 0 -16px 12px`. If it's currently inset, apply
  the equivalent bleed technique.

### 4. Village tabs (`VillageFilterTab`, `patient_filter_panel.dart:294-339`)

- Gap between tabs (18px), underline thickness (2.5px), row bottom hairline
  (1.5px `#E5E7EB`), tab padding (`8,1,1,9`) — **all already spec-exact**. No
  change.
- Active tab text color: currently a raw `Color(0xFF111827)` → spec says
  active color = `var(--navy)`. Real fix: change to `AppColors.navy` (not
  just a tokenization exercise — it's currently the wrong color).
- Font size: `AppTextStyles.villageTab` 15px → **13px** (weight w700
  unchanged). Shared with the Patients tab — accepted per decision above.
- Row height: 38 → trim toward spec's intrinsic ~32-34px if it doesn't look
  cramped in visual QA; low priority.

### 5. Category filter row (`NeedFilter` enum + `NeedCategoryBubble` row)

Bubble *visual treatment* (44px circle, border, shadow-on-active) is out of
scope, per the original instruction — but the mockup's actual **roster,
labels, and icon glyphs** (`#catRow`, lines 1369-1377) were checked directly
against the current `NeedFilter` enum (`patient_filter_panel.dart:15-72`)
and against `MissionDashboardStrings.need*` (`app_strings.dart:1117-1125),
and two real content mismatches were found:

| Category | Mockup icon (concept) | Current Flutter icon | Fix |
|---|---|---|---|
| `highRisk` | ⚠️ warning | `Icons.warning_amber_rounded` | ✅ already matches |
| `ancMnch` | 🤰 pregnant | `Icons.pregnant_woman_rounded` | ✅ already matches |
| `childImmunisation` | 👶 baby | `Icons.child_care_rounded` | ✅ already matches |
| `ncd` | 💊 **pill/medication** | `Icons.monitor_heart_rounded` (heart monitor) | **Fix → `Icons.medication_rounded`** |
| `eyeCare` | 👁️ eye | `Icons.visibility_rounded` | ✅ already matches |
| `missedFollowUp` | ⏰ **clock** | `Icons.event_busy_rounded` (calendar-x) | **Fix → `Icons.access_time_rounded`** |
| `pendingReferral` | 📋 clipboard | `Icons.assignment_rounded` | ✅ already matches |
| `homeVisit` | 🏠 house | `Icons.home_rounded` | ✅ already matches |
| `facilityReferral` | 🏥 hospital | `Icons.local_hospital_rounded` | ✅ already matches |

Category count and order already match the mockup exactly (9 categories,
same sequence) — no roster change needed, only the 2 icon swaps above.

**Circle bg-color — verified, already 100% correct.** Every one of the 9
categories' `--bcolor`/`--bbg` pairs in the mockup was resolved to its exact
hex and diffed against `NeedFilter.activeColor`/`.activeSurface`
(`patient_filter_panel.dart:75-106`) byte-for-byte:

| Category | Mockup `--bcolor` / current token | Mockup `--bbg` / current token | Match? |
|---|---|---|---|
| highRisk | `#EF4444` / `statusCritical`(`0xFFEF4444`) | `#FEF2F2` / `catHighriskSurface`(`0xFFFEF2F2`) | ✅ exact |
| ancMnch | `#EC4899` / `pinkWorklist`(`0xFFEC4899`) | `#FDF2F8` / `ancSurface`(`0xFFFDF2F8`) | ✅ exact |
| childImmunisation | `#F59E0B` / `statusWarning`(`0xFFF59E0B`) | `#FFFBEB` / `catChildSurface`(`0xFFFFFBEB`) | ✅ exact |
| ncd | `#0D9488` / `catNcdBorder`(`0xFF0D9488`) | `#F0FDFA` / `catNcdSurface`(`0xFFF0FDFA`) | ✅ exact |
| eyeCare | `#3B82F6` / `infoAccent`(`0xFF3B82F6`) | `#EFF6FF` / `childSurface`(`0xFFEFF6FF`) | ✅ exact (token name is a pre-existing, already-commented naming quirk — value is right) |
| missedFollowUp | `#6B7280` / `textMuted`(`0xFF6B7280`) | `#F9FAFB` / `catMissedSurface`(`0xFFF9FAFB`) | ✅ exact |
| pendingReferral | `#8B5CF6` / `catReferralBorder`(`0xFF8B5CF6`) | `#F5F3FF` / `pncSurface`(`0xFFF5F3FF`) | ✅ exact (same pre-existing naming quirk, value right) |
| homeVisit | `#10B981` / `statusSuccess`(`0xFF10B981`) | `#ECFDF5` / `catHomeSurface`(`0xFFECFDF5`) | ✅ exact |
| facilityReferral | `#6366F1` / `catFacilityBorder`(`0xFF6366F1`) | `#EEF2FF` / `catFacilitySurface`(`0xFFEEF2FF`) | ✅ exact |

**No color fix needed anywhere in this row** — do not touch `activeColor`/
`activeSurface`. The active-state border width (2px) and active-shadow
(`0 2px 6px rgba(0,0,0,0.08)`, i.e. `Color(0x14000000)`/blur 6/offset(0,2) in
`NeedCategoryBubble`) are also already spec-exact — no change.

**Circle size — one real fix.** Bubble icon-circle diameter: currently
`width:46,height:46` (`NeedCategoryBubble`, `patient_filter_panel.dart:375-376`)
→ spec `.cat-bubble-icon{width:44px;height:44px}`. **Fix: 46 → 44.** Icon
glyph size inside the circle (currently 20) vs spec's `font-size:19px` is a
negligible 1px gap — optional, low priority, not required.

Label text — 4 of the 9 current labels are longer than the mockup's
abbreviated versions:

| Category | Mockup label | Current label (`app_strings.dart`) | Fix |
|---|---|---|---|
| `childImmunisation` | "Child / Immun." | "Child / Immunisation" | Shorten to **"Child / Immun."** |
| `missedFollowUp` | "Missed" | "Missed follow-up" | Shorten to **"Missed"** |
| `pendingReferral` | "Referral" | "Pending referral" | Shorten to **"Referral"** |
| `facilityReferral` | "Facility" | "Facility referral" | Shorten to **"Facility"** |
| (other 5) | — | — | Already match exactly |

These are content fixes, not a bubble-style redesign — consistent with the
original "don't redesign the icons" instruction (the 44px circle/border/
shadow treatment is untouched) while satisfying the explicit follow-up ask
to match the mockup's actual icon glyphs and label roster. Since `NeedFilter`
is shared with the Patients tab (same accepted tradeoff as village tabs),
these fixes apply there too.

- Gap between bubbles: 8 → **11**.
- Outer wrapper spacing: spec pulls this row closer to the village tabs above
  (`margin-top:-6px`) and tightens the gap to the visit list below
  (`margin-bottom:6px`) — apply equivalent trims if the current layout looks
  loose after the village-tab changes above land.

### 6. "Today's visits" title + AI-sorted badge (`_TodaysVisitsHeader`, `:1168-1235`)

- Title: `AppTextStyles.worklistRowLabel` 15.5px → **13.5px** (weight w800
  unchanged). Used exclusively here — zero ripple.
- Badge padding (`8,3`) already spec-exact — no change.
- Badge radius: currently inconsistent between the two code branches (`sm`=6
  in one, raw `8` in the other) — spec wants 8px consistently. Fix: use
  **`AppRadius.rxIcon`** (8.0, existing token) in both branches.
- Row-to-list spacing: nudge toward spec's 10px total gap if visual QA shows
  drift after other trims land.

### 7. Visit cards (`MissionQueueCard`, `mission_queue_card.dart:15-202`)

⚠️ **Cascade trap**: the mockup's per-card inline styles are overridden by a
`.vcard{...!important}` rule. The values below are the *already-reconciled
effective* values (post-cascade) — verified directly against the CSS, not
the inline-looking numbers that appear first in the markup.

- Card padding: `14,12,14,12` → **`12,9,12,9`** (i.e. `EdgeInsets.symmetric(horizontal:12, vertical:9)`).
- Card margin-bottom (call-site wrapper): 8 → **6**.
- Card radius: `AppRadius.patRow`(14) → **`AppRadius.button`**(12, existing
  token, exact match) — used on both the outer and inner `Container`.
- Text-block ↔ status-dot gap: `SizedBox(width:12)` → **`width:10`**.
- **Left border — remove the color-coding** (per objective): keep the 4px
  left border (spec still renders one), but make it **always neutral**
  (`AppColors.border`, `#E5E7EB`) instead of varying by `DashboardTier`. The
  mockup itself never color-codes this border — status is conveyed only by
  the right-side status pill.
- Name: `worklistPatientName` 15.5px → **13.5px** (w800 unchanged).
- Age/sex text: currently a raw inline style (`11.5px w600 #111827`) → spec
  is `11.5px w800 #111827` (weight is wrong today). Fix by wiring this into
  the existing-but-**currently unused** `AppTextStyles.worklistPatientMeta`
  token — adjust it to `11.5px/w800/#111827` and actually reference it here
  (resolves a dead-token finding and a pixel mismatch in one move).
- Reason/programme badge (`MissionReasonBadge`): text already spec-exact
  (10px/w700). Padding `8,3` → **`7,2`**; radius `AppRadius.sm`(6) →
  **`AppRadius.flag`**(5, existing token, exact match).
- Address: `worklistAddress` 14px/w600 → **12px/w400** (spec has no explicit
  weight override, i.e. inherits normal/400).
- Phone: `worklistPhone` 13px → **11.5px** (w400 unchanged).
- Status pill (`_StatusDot`/`worklistStatusPill`): 12.5px → **10px** (w800
  unchanged). Dot diameter 7×7 → **6×6**; dot-to-text gap `width:4` →
  **`width:3`**.
- `_VisitedBadge` radius: raw `4` → align to `AppRadius.flag`(5) for
  internal consistency with the reason badge (inference, not a literal spec
  match — there's no "visited" example in the mockup).
- Completed-state opacity (0.6) and all tier/status *logic* — **unchanged**,
  per constraints.

### 8. Floating action button (`_EnrolNewFab`, `:892-934`)

- Radius: `AppRadius.xl`(24) → **new `AppRadius.fabPill` = 28.0**.
- Background: `tokens.brandPink` → **`tokens.fabBackground`**
  (`WorklistCategoryColors.fabBackground` = `AppColors.pinkWorklist`,
  `#EC4899`) — this is the token this exact FAB was designed for and it's
  currently unused anywhere in the app.
- Shadow: replace `Material(elevation:2, shadowColor: brandPink@0.4)` with an
  explicit `BoxDecoration(boxShadow:[BoxShadow(color: tokens.fabShadow,
  blurRadius:20, offset:Offset(0,4))])` around the button — `tokens.fabShadow`
  (`WorklistCategoryColors.fabShadow` = `Color(0x73E8356D)`) is already the
  exact spec color (`rgba(232,53,109,0.45)`), also currently unused. Wrap the
  existing `Material`/`InkWell` inside this decorated `Container`, mirroring
  the shadow-Container-then-Material pattern already used by
  `MissionQueueCard` elsewhere in this codebase — not a new pattern.
- Padding: `14,9` → **`18,12`** (horizontal 18, vertical 12).
- Icon size: 15 → **16**. Icon-label gap: `width:6` → **`width:8`**.
- Label: 13px/w800 unchanged; consider dropping the current `letterSpacing:0.2`
  to match spec exactly (low priority).
- Position: verify only — Scaffold's default FAB placement already accounts
  for the bottom nav bar's height, which should match the mockup's
  `bottom:74px` intent without an explicit override. Flag as visual-QA-only;
  no code change expected unless verification finds a mismatch.

### 9. Bottom navigation (global `NavigationBarThemeData`, `app_theme.dart:2114` + dark-theme counterpart)

- Height: 64 → **56**.
- Icon size: 24 → **20**.
- Label font size: 11.5 → **10**.
- Keep the existing selected/unselected weight distinction (w800/w600) and
  color-swap dimming approach (navy/textMuted) — spec uses opacity dimming
  instead, but the current color-swap achieves an equivalent (arguably
  clearer) result; not worth introducing an `Opacity` wrapper for this.
- This is a **global** change (all 4 tabs) by construction — there is no
  Home-only variant of a persistent shell nav bar.

### 10. Vertical rhythm between sections (cross-cutting)

Every inter-section gap down the Home screen was traced end-to-end against
the mockup's actual box model (not just each section's own internal padding,
which sections 1-7 already cover). This resolves several gaps that were
previously mis-estimated or simply missing:

| Transition | Current (Flutter) | Spec | Fix |
|---|---|---|---|
| Safe-area top → greeting text | `topPadding + 10` | `topPadding + 0` | **Drop the `+10`** — see §1 |
| Icon row → search bar | `AppSpacing.xxl` (14) | `.header-row{margin-bottom:14px}` | ✅ already exact |
| Search bar → header's bottom edge | 10 | 18 | **Change to 18** — see §1 |
| Header bottom edge → referral banner top | (= header's own bottom padding, above) | same 18 (body's `padding-top` is zeroed for this screen) | covered by the row above |
| Referral banner bottom → village tabs top | `ListView` top padding = 12 | banner `margin: 0 -16px 12px` | ✅ already exact |
| Village-tab underline → category row top | `SizedBox(height:14)` | net ~8px (14px row-1 margin, minus the category wrapper's own `margin-top:-6px` pull) | **Change to 8** |
| Category row bottom → "Today's visits" title top | 0 (no gap — `PatientFilterPanel` and the visit-list `FutureBuilder` are adjacent `ListView` children with nothing between them) | cat-row wrapper `margin-bottom:6px` | **Add `SizedBox(height:6)`** between `PatientFilterPanel` and the queue `FutureBuilder` |
| "Today's visits" title → first visit card | `SizedBox(height:8)` (both empty/populated branches) | title row `margin-bottom:10px` | **Change to 10** |
| Visit card → next visit card | per-card wrapper `Padding(bottom:8)` | effective `margin-bottom:6px` | **Change to 6** (already listed in §7) |
| Overall scrollable content horizontal inset | `ListView` padding `14` (left/right) | `.body{padding:16px}` | **Change to 16** |

Bottom padding of the `ListView` (currently 100, for FAB clearance) is a
functional scroll-clearance value with no mockup equivalent (a static image
has no floating-button overlap concern) — **leave unchanged**.

### Overall

- "Reduce unnecessary vertical spacing" / "increase density" are satisfied
  cumulatively by the trims above — no separate action needed.
- "Reduce excessive shadows": `AppShadows.card` (used by `MissionQueueCard`
  and many other cards app-wide) is close to spec already
  (`0,2,8,rgba(0,0,0,0.06)` vs spec's `0,1,6,rgba(0,0,0,0.06)`) — leave
  unchanged; it's shared far beyond this screen and the gap is minor.

## Design tokens — additions & updates (`app_theme.dart`)

**New:**
- `AppTextStyles.dashboardGreeting` — Nunito 20 / w800 / white
- `AppTextStyles.dashboardGreetingSub` — NunitoSans 12 / w400 / `AppColors.onDarkLow`
- `AppRadius.fabPill` — 28.0

**Update in place** (font-size/weight only, no renames — confirmed safe per
the two scope decisions):
- `worklistRowLabel` 15.5→13.5
- `villageTab` 15→13
- `worklistPatientName` 15.5→13.5
- `worklistPatientMeta` 13→11.5, w700→w800 (+ wire it up — currently unused)
- `worklistAddress` 14→12, w600→w400
- `worklistPhone` 13→11.5
- `worklistStatusPill` 12.5→10
- `NavigationBarThemeData` (light + dark): height 64→56, icon size 24→20, label 11.5→10

**Newly wire up** (already exist, currently dead/unused or mis-referenced):
- `AppColors.referralAlertBg`/`.referralAlertBgDark` → `_ReferralAlertBanner` background
- `WorklistCategoryColors.fabBackground`/`.fabShadow` → `_EnrolNewFab`
- `AppRadius.button`(12) → search bar radius + visit-card radius (both currently wrongly use `patRow`=14)
- `AppRadius.flag`(5) → `MissionReasonBadge` radius (currently `sm`=6) + `_VisitedBadge` radius (currently raw 4)
- `AppRadius.rxIcon`(8) → AI-sorted badge radius (fixes an existing 6-vs-8 inconsistency between its two branches)

## Files to modify

1. `lib/core/theme/app_theme.dart` — 2 new text styles, 1 new radius, 7
   font-size/weight tweaks, `NavigationBarThemeData` ×2 (light/dark).
2. `lib/features/dashboard/mission_dashboard_screen.dart` — `_DashboardHeader`
   (padding, new greeting styles), `_ReferralAlertBanner` (recolor + verify
   bleed), `_TodaysVisitsHeader` (radius consistency), `_EnrolNewFab`
   (radius/color/shadow/padding/gap), visit-card wrapper margin (8→6).
3. `lib/features/search/global_search_bar.dart` — height, icon sizes, radius,
   optional divider removal.
4. `lib/core/widgets/patient_filter_panel.dart` — `VillageFilterTab`
   active-color fix + row/gap trims; `NeedFilter.icon` swap for `ncd` and
   `missedFollowUp`; `NeedCategoryBubble` row gap trim only.
5. `lib/features/visit/widgets/mission_queue_card.dart` — padding/margin/
   radius/gap/border-neutralize, age-text weight fix + wire up
   `worklistPatientMeta`, reason-badge padding/radius, status-dot size/gap,
   `_VisitedBadge` radius.
6. `lib/core/constants/app_strings.dart` — shorten 4 `MissionDashboardStrings.need*`
   labels (`childImmunisation`, `missedFollowUp`, `pendingReferral`,
   `facilityReferral`) to match the mockup's abbreviated text.

**No changes needed to:** `lib/app/bottom_nav.dart` (purely theme-driven —
only `app_theme.dart` changes), `notification_drawer.dart` (not in scope),
any routing/state/repository/API file (per constraints).

## Implementation order (smallest risk first)

| # | Change | Complexity | Risk | Ripples beyond Home? |
|---|---|---|---|---|
| 1 | AI-sorted badge radius fix (`rxIcon`) | Small | Low | No |
| 2 | Referral banner recolor (`referralAlertBg`) | Small | Low | No |
| 3 | Village-tab active color fix (navy) | Small | Low | Patients tab (color-only, safe) |
| 4 | New `dashboardGreeting`/`dashboardGreetingSub` tokens + wire into header | Small | Low | No |
| 5 | Header container padding trim | Small | Low | No |
| 6 | Search bar sizing (height/icons/radius/divider) | Small–Medium | Low | No |
| 7 | Category filter content fix (2 icon swaps + 4 label shortenings, circle 46→44) + row gap trim | Small | Low | Patients tab (content+spacing, low risk — corrections toward the approved design, not new invention; colors already verified correct, untouched) |
| 8 | Village-tab font-size + row-height trim | Small | Medium | Patients tab |
| 9 | FAB rework (`fabPill`, `fabBackground`/`fabShadow`, shadow restructure, padding/gap) | Medium | Low | No |
| 10 | Bottom-nav theme trim (height/icon/label) | Small | Low | All 4 tabs (accepted, unavoidable) |
| 11 | Visit-card typography tokens (name/meta/address/phone/status-pill) | Medium | Medium | Patients + Tasks tabs |
| 12 | Visit-card structural rework (padding/margin/radius/gap/border/badges) | Medium–Large | Medium | Patients + Tasks tabs |
| 13 | Vertical-rhythm pass (header padding, the 3 missing/wrong inter-section gaps, ListView horizontal inset) | Small | Low | No — do last, after all sections have their final internal sizes, so gaps are measured against the real end state, not a moving target |

Rationale: zero-ripple, single-file items first to build confidence fast;
the two accepted-ripple items (village tabs, then the larger visit-card
rework) go last since they need the most careful visual QA across all three
affected screens. #11 before #12 to keep the visit-card diff reviewable in
two passes rather than one large one.

## Regression risks

- **Patients tab + Tasks tab will visually change** (steps 3, 7, 8, 11, 12) —
  accepted tradeoff; visual QA must cover those two screens, not just Home.
- **Bottom-nav shrink is global** (step 10) — verify no icon/label clipping
  on Patients/Tasks/Assistant after the shrink.
- `e2e/tests/02-login.spec.ts` asserts `/Total Patients/i` is visible after
  login to confirm the dashboard loaded — **this text does not exist
  anywhere in the current dashboard** (confirmed via grep), so this test is
  **already broken independent of this work** (a leftover from a pre-v13
  dashboard with stat tiles). Not a new regression — don't let it be
  mistakenly blamed on this change.
- No existing widget test targets Dashboard/`MissionQueueCard`/
  `PatientFilterPanel`/`GlobalSearchBar`/`BottomNavShell` by name — a
  visual-only pass has no automated safety net here; rely on manual/emulator
  verification against the rendered mockup.
- `test/core/theme/app_theme_test.dart` checks every `ThemeExtension` type is
  present + spot-checks some color values — unaffected as long as no
  extension type/field is removed or renamed (this plan only adds 2 text
  styles + 1 radius + numeric tweaks).
- A separately-observed (and explicitly out-of-scope) data-logic detail: the
  tier→color mapping in `MissionQueueCard` currently maps both `critical` and
  `dueToday` tiers to `statusSuccess` for the border/dot — looks like it may
  be an inversion bug, but per constraints ("keep visit status logic
  unchanged") this plan does not touch it. Flagging only so it isn't
  conflated with a visual defect introduced by this work.
- FAB shadow restructure (Material elevation → explicit `BoxDecoration`
  shadow) changes paint order slightly — verify the tap ripple still renders
  correctly inside the new nested `Material`/`InkWell`, not just the static
  shadow appearance.

## Refactor / de-duplication opportunities (noted, not required for this pass)

- No single canonical `StatusPill`/`Badge` widget exists app-wide —
  `MissionQueueCard._StatusDot`, `UrgencyBadge`, `VisitTierChip`, and several
  private `_Badge`/`_Chip` classes elsewhere all reinvent "colored pill with
  text." Out of scope here, but this pass touches several of them
  individually, so it's a natural follow-up candidate.
- Reusing `AppRadius.button`/`.flag`/`.rxIcon` (pre-existing, exact-match
  tokens) instead of adding new radius constants is itself a small
  de-duplication win baked into this plan.
- Wiring up `AppColors.referralAlertBg`/`.referralAlertBgDark` and
  `WorklistCategoryColors.fabBackground`/`.fabShadow` (pre-existing,
  purpose-built, 100%-unused tokens) is itself a dead-code cleanup baked
  into this plan.
- `MissionQueueCard` vs `WorklistCard` (a separate, near-duplicate
  visit-card widget used only by the standalone Worklist screen) — two
  parallel "visit card" implementations exist in the codebase. Out of scope
  for this visual-only Home pass; flagged as a larger future consolidation
  candidate.

## Verification

- `flutter analyze` after each implementation-order group.
- No test suite exists specifically for the touched screens; confirm
  `test/core/theme/app_theme_test.dart` still passes (extension shape
  unchanged) and `flutter test` overall shows no *new* failures versus the
  current baseline (17 pre-existing unrelated failures at time of writing).
- Manual verification via the existing build/install/launch flow (fresh APK,
  install, launch): compare the Home screen against
  `apon_sushashthya_v13.html` rendered in a browser at 390px width,
  section-by-section per this plan. Additionally open the **Patients tab**
  and **Tasks tab** to confirm the shared-widget changes (steps 3, 7, 8, 11,
  12) render acceptably there too and nothing clips/overflows at the new
  tighter paddings.
