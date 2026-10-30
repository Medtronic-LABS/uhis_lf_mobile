import '../../../core/constants/app_strings.dart';

/// Validates a vaccination "date administered" against the patient's DOB and,
/// when known, the dose's minimum eligible age. Shared by
/// [_UpdateStatusSheet] (immunisation_timeline_screen.dart) and the
/// scan-review sheet (epi_scan_review_sheet.dart) — both let a date in
/// (manual pick or OCR/Gemini scan) that can be clinically wrong for this
/// child, so both need the same two floor checks at save time.
///
/// [earliestEligibleDate] is the dose's own [VaccineEntry.scheduledDate] /
/// [VaccineMilestone.scheduledDate] (DOB + the EPI schedule's minimum
/// offset, e.g. DOB + 9 months for MR1) — passing it catches a 3-month-old
/// somehow being recorded against the 9-month dose, which the DOB check
/// alone would miss (the date can be well after DOB and still be months
/// too early for that specific vaccine).
///
/// Returns a localized error, or null when [date] clears both floors.
String? validateVaccinationDate(
  DateTime date, {
  DateTime? dob,
  DateTime? earliestEligibleDate,
}) {
  if (dob != null) {
    final dobFloor = DateTime(dob.year, dob.month, dob.day);
    if (date.isBefore(dobFloor)) return EpiStrings.dateBeforeDobError;
  }
  if (earliestEligibleDate != null) {
    final eligibleFloor = DateTime(
      earliestEligibleDate.year,
      earliestEligibleDate.month,
      earliestEligibleDate.day,
    );
    if (date.isBefore(eligibleFloor)) {
      return EpiStrings.dateBeforeEligibleAgeError;
    }
  }
  return null;
}
