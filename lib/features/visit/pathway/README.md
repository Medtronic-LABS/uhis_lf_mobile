# Symptom-Driven Pathway Activation

This document describes the WHO-derived rules that map patient symptoms to clinical assessment pathways.

## How It Works

1. **SK picks symptoms** from the unified symptom catalog
2. **Pathway engine** evaluates rules against symptoms + patient context
3. **Activated pathways** determine which programme forms to assess

---

## Pathway Activation Rules

| Pathway | Demo Gate | Single Symptoms (anyOf) | Combinations (all-of) |
|---------|-----------|-------------------------|----------------------|
| **NEONATE** | age < 2mo | fever, cough, difficulty_breathing, diarrhea, vomiting, not_eating, convulsions, lethargy, umbilicus_red, jaundice, skin_rash | — |
| **ICCM** | age 2–59mo | fever, cough, diarrhea, difficulty_breathing, convulsions, lethargy, not_eating, chest_indrawing, stridor, muac_red, visible_wasting, edema_both_feet, ear_problem, skin_rash, eye_discharge | — |
| **ANC** | pregnant ♀ | pregnant, vaginal_bleeding, water_break, reduced_fetal_movement, labor_signs, swelling_face_hands, abdominal_pain, blurred_vision, headache_severe | — |
| **PNC** | postpartum ♀ | fever, vaginal_bleeding, headache_severe, blurred_vision, swelling_face_hands, abdominal_pain | — |
| **TB_SCREEN** | any | cough_over_2_weeks, hemoptysis, tb_contact | {night_sweats + weight_loss}, {night_sweats + fever} |
| **NCD-HTN** | age ≥ 18y | high_bp_known, headache_severe, dizziness, chest_pain, blurred_vision | — |
| **NCD-DM** | any | numbness, foot_wound, weight_loss | {polyuria + polydipsia} |
| **NUTRITION** | age < 5y | muac_red, visible_wasting, edema_both_feet | {not_eating + visible_wasting} |

---

## Mix-and-Match Scenarios

### Neonate (< 2 months)

| Symptoms | → Pathways |
|----------|------------|
| fever alone | NEONATE |
| fever + diarrhea | NEONATE |
| fever + muac_red | NEONATE + NUTRITION |
| convulsions + vomiting | NEONATE |

### Child (2–59 months)

| Symptoms | → Pathways |
|----------|------------|
| fever alone | ICCM |
| cough + fever | ICCM |
| muac_red alone | ICCM + NUTRITION |
| visible_wasting + not_eating | ICCM + NUTRITION |
| fever + night_sweats | ICCM + TB_SCREEN |
| cough_over_2_weeks | ICCM + TB_SCREEN |

### Pregnant Female (any age)

| Symptoms | → Pathways |
|----------|------------|
| pregnant alone | ANC |
| vaginal_bleeding | ANC (danger sign!) |
| headache_severe + blurred_vision | ANC + NCD-HTN (if ≥18y) |
| high_bp_known | ANC + NCD-HTN (if ≥18y) |
| fever + night_sweats | ANC + TB_SCREEN |
| swelling_face_hands | ANC (danger sign!) |

### Postpartum Female (< 6 weeks)

| Symptoms | → Pathways |
|----------|------------|
| fever alone | PNC |
| vaginal_bleeding | PNC (danger sign!) |
| headache_severe + blurred_vision | PNC + NCD-HTN (if ≥18y) |
| fever + night_sweats | PNC + TB_SCREEN |

### Adult (≥ 18 years, not pregnant/postpartum)

| Symptoms | → Pathways |
|----------|------------|
| cough_over_2_weeks | TB_SCREEN |
| night_sweats + weight_loss | TB_SCREEN + NCD-DM |
| night_sweats + fever | TB_SCREEN |
| high_bp_known | NCD-HTN |
| dizziness + headache_severe | NCD-HTN |
| chest_pain | NCD-HTN |
| polyuria + polydipsia | NCD-DM |
| numbness + foot_wound | NCD-DM |
| hemoptysis + weight_loss | TB_SCREEN + NCD-DM |

### Multi-pathway Combos (complex cases)

| Profile | Symptoms | → Pathways |
|---------|----------|------------|
| Child 3y | muac_red + cough_over_2_weeks | ICCM + TB_SCREEN + NUTRITION |
| Pregnant 25y | high_bp_known + blurred_vision | ANC + NCD-HTN |
| Adult 40y | cough_over_2_weeks + weight_loss + foot_wound | TB_SCREEN + NCD-DM |
| Adult 50y | night_sweats + weight_loss + dizziness | TB_SCREEN + NCD-DM + NCD-HTN |
| Postpartum 30y | fever + night_sweats + blurred_vision | PNC + TB_SCREEN + NCD-HTN |

---

## History-Based Auto-Triggers

Pathways can activate from patient history flags even without symptoms:

| Patient Flag | → Pathway |
|--------------|-----------|
| PREGNANCY / ANC | ANC |
| PNC / POSTNATAL | PNC |
| TB_SCREEN_DUE / TUBERCULOSIS | TB_SCREEN |
| HYPERTENSION / HTN / I10 | NCD-HTN |
| DIABETES / DM / E11 | NCD-DM |

---

## Clinical Thresholds

| Measure | Threshold | Source |
|---------|-----------|--------|
| MUAC red zone | < 11.5 cm | WHO IMCI 2014 |
| MUAC yellow zone | < 12.5 cm | WHO IMCI 2014 |
| BP systolic | ≥ 140 mmHg | WHO HEARTS |
| BP diastolic | ≥ 90 mmHg | WHO HEARTS |
| BP severe systolic | ≥ 160 mmHg | WHO ANC 2016 |
| BP severe diastolic | ≥ 110 mmHg | WHO ANC 2016 |
| Fasting glucose | ≥ 126 mg/dL | WHO PEN |
| Random glucose | ≥ 200 mg/dL | WHO PEN |
| TB cough duration | ≥ 14 days | WHO 4-Symptom Screen |
| Neonate age | < 2 months | WHO IMNCI |
| IMCI age | 2–59 months | WHO IMCI 2014 |
| Adult NCD age | ≥ 18 years | WHO PEN |
| PNC window | < 42 days postpartum | WHO PNC |

---

## Code References

- **Symptom Catalog**: `unified_symptom_catalog.dart`
- **Pathway Rules**: `pathway_rules_v1.dart`
- **Pathway Engine**: `pathway_engine.dart`
- **Patient Context**: `patient_context_builder.dart`
