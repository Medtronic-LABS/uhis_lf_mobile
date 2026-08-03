/// Whether a patient qualifies for at least one clinical service/programme.
library;

/// True if a patient of this age qualifies for at least one clinical
/// service/programme, mirroring `SymptomPickerScreen`'s service-card
/// eligibility rules (`_InlineServiceSelector._visibleCards`): vaccination
/// and IMCI need `isUnder5`; every other programme (ANC/PNC/FP/PW/NCD/TB)
/// needs age 15+ (the female-only branches there are a subset of the 15+
/// rule, so gender never changes this *any-eligible* outcome — only which
/// specific card shows). The real gap is ages 5–14: too old for
/// vaccination/IMCI, too young for the 15+ programmes.
///
/// A null age fails OPEN (returns true) — an unknown age must never block a
/// patient from starting care.
///
/// `_visibleCards` is private to its file, so this can't be automatically
/// cross-checked against it — `test/core/clinical/service_eligibility_test.dart`
/// only pins this function's own behavior at the age boundaries. If
/// `_visibleCards`'s rules ever change, update this function to match by hand.
bool hasAnyEligibleProgramme({required int? ageYears}) {
  if (ageYears == null) return true;
  return ageYears < 5 || ageYears >= 15;
}
