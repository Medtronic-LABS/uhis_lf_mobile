# Service Selection & Auto-Select — Reference

Explanation-only writeup of how Step 1's service cards decide what's shown, what's locked, and how
programmes get auto-selected without the SK tapping them. No code changes are proposed here — this is
a map of current behavior, produced to answer "what is the logic for showing services for a patient,
and how does auto-selecting work."

Source files: `lib/features/visit/triage/symptom_picker_screen.dart` (`_InlineServiceSelector`),
`lib/features/visit/triage/programme_grid_sync.dart`, `lib/features/visit/triage/service_selection_resolver.dart`,
`lib/features/visit/pathway/pathway_rules_v1.dart`, `lib/features/visit/triage/patient_context_builder.dart`.

## 1. Patient-context age/gender thresholds

| Getter | Condition | Age in months |
|---|---|---|
| `isNeonate` | age < 2 months | 0–1 |
| `isInfant` | age < 12 months | 0–11 |
| `isUnder5` | age < 60 months | 0–59 |
| `isReproductiveAge` | 14y ≤ age < 55y | 168–660 |
| `isAdult` | age ≥ 18y | ≥216 |
| `isEyeCareCataractEligible` | age ≥ 35y, any sex | ≥420 |
| `isPostpartum` | delivery within last 42 days | — |
| `isPregnant` | (pregnancyFacts ∨ activeProgrammes⊇{anc,pw} ∨ raw-JSON flag) ∧ ¬hasDelivered | — |

## 2. Step 1 card — visibility gate (`_visibleCards`, ~line 2270)

| Card | Programme | Shown when |
|---|---|---|
| PW / Pregnancy | — | female ∧ reproductive age |
| Pregnancy Outcome | — | female ∧ reproductive age |
| ANC | anc | female ∧ reproductive age ∧ not under-5 |
| PNC | pnc | female ∧ reproductive age ∧ not under-5 |
| Family Planning | familyPlanning | female ∧ reproductive age ∧ not under-5 |
| NCD | ncd | `isAdult` (≥18y) |
| Eye Care | eyeCare | `isEyeCareCataractEligible` (≥35y) |
| Cataract | cataract | `isEyeCareCataractEligible` (≥35y) |
| Child Health (IMCI) | imci | `isUnder5` |
| Vaccination | — | `isUnder5` |
| **TB** | tb | **no card exists — by design, unreachable** |
| EPI | epi | no dedicated card; added silently at Continue if due |

Any adult-only card is blanket-hidden for an under-5 patient (line 2281) before its specific rule runs.

## 3. Step 1 card — lock gate (`_isLocked`, ~line 2310)

| Card | Locked when | Never locked? |
|---|---|---|
| PW | delivery-visit mode ∨ postpartum ∨ open pregnancy episode exists | |
| ANC | PW not toggled on ∨ delivery mode ∨ within revisit interval (15d, or 1d if last visit high-risk) | |
| Pregnancy Outcome | not (pregnant ∧ not postpartum) ∨ no open pregnancy episode | |
| PNC | not postpartum | |
| Family Planning | currently pregnant (not postpartum) | |
| NCD | | ✅ never locked |
| Eye Care | | ✅ never locked |
| Cataract | | ✅ never locked |
| IMCI / Child Health | | ✅ hard-coded never locked |
| Vaccination | separate `vaccinationLocked` flag | |

## 4. Auto-selection — three independent mechanisms

| # | Mechanism | Fires when | Adds | Can be suppressed by |
|---|---|---|---|---|
| a | `ProgrammeGridSync.additionsFromPathways` | every symptom-selection change | any pathway-engine-activated or symptom-catalog-tagged programme not yet selected | SK dismissal this visit (`dismissedBySk`); ANC never resurrected if revisit-too-soon; PW never resurrected if an episode is already open |
| b | `ProgrammeGridSync.applicableEnrolledSeed` | once, at patient load | historical/enrolled programmes filtered by current pregnant/postpartum state (ANC/PW only if pregnant; PNC only if postpartum; FP hidden while pregnant) | tb/nutrition never seeded (pilot-scope); ANC stripped again if revisit-too-soon; PW stripped again if episode open |
| c | `ServiceSelectionResolver.finalize` | once, at "Continue" tap | forces PNC on a delivery visit; auto-adds PW alongside a surviving ANC selection | pilot-scope exclusion (tb/nutrition, silent); PW-registration-blocked; postpartum/revisit blocks stop ANC (and therefore its PW auto-add) first |

## 5. `ServiceSelectionResolver.finalize()` — rule order

| Step | Rule | Outcome if triggered |
|---|---|---|
| 1 | Delivery visit | force-add PNC |
| 2 | Pilot-scope exclusion | silently drop `tb`, `nutrition` (epi is exempt) |
| 3 | PW already registered | drop PW; if selection now empty → `silentlyEmptied`, stop |
| 4 | ANC + postpartum | drop ANC → `ancBlockedPostpartum`, stop |
| 5 | ANC + revisit too soon | drop ANC → `ancBlockedRevisit`, stop |
| 6 | ANC survives, PW not already registered | auto-add PW |
| 7 | — | sort survivors: imci(10) → pw(15) → anc(20) → pnc(25) → tb(30) → nutrition(35) → ncd(40) → familyPlanning(45) → cataract(46) → eyeCare(47) → epi(100) |

## 6. Pathway vs. selectable service — the two layers

| Layer | What it is | Where it lives | User-visible effect |
|---|---|---|---|
| **Pathway** | A rule-engine *suggestion* — programme + priority + rationale, derived from symptoms/history via `PathwayRulesV1` | `pathway_engine.dart` / `pathway_rules_v1.dart` | Drives the ✦ sparkle badge and rationale text; not itself submittable |
| **Selected service** | Membership in `_selectedProgrammes` | `symptom_picker_screen.dart` | What's actually tappable, toggleable, and submitted |

The bridge is mechanism **4a**: every activated pathway gets pushed into the selected set (unless
dismissed or blocked), so a pathway suggestion auto-ticks a card — but the SK can always untick it, and
a locked card is never resurrected even if a pathway would otherwise re-add it.
