/// Lean wire DTO for a single vaccination record in the CHILD_IMMUNIZATION
/// offline-sync payload — POST /offline-service/offline-sync/create.
///
/// Deliberately NOT [VaccinationDetailDto] (immunisation_dto.dart): that
/// class models the legacy spice-service /immunisation/create contract and
/// its toJson() unconditionally emits type/value/scheduledDate/displayOrder/
/// category/vaccineOrder — fields the offline-sync contract does not want
/// and that would corrupt the exact wire shape below.
class ChildImmunizationVaccinationRecord {
  const ChildImmunizationVaccinationRecord({
    required this.vaccineName,
    required this.status,
    this.vaccinatedDate,
    this.reason,
  });

  final String vaccineName;

  /// Exactly 'Vaccinated' or 'Missed' — case-sensitive on the wire.
  final String status;

  /// Wire-format date "yyyy-MM-ddT00:00:00+00:00" — present only when
  /// [status] is 'Vaccinated'.
  final String? vaccinatedDate;

  /// Present only when [status] is 'Missed'.
  final String? reason;

  Map<String, dynamic> toJson() => {
        'vaccineName': vaccineName,
        if (vaccinatedDate != null) 'vaccinatedDate': vaccinatedDate,
        'status': status,
        if (reason != null) 'reason': reason,
      };

  /// Formats [date] the way the backend expects. Reimplemented locally
  /// rather than promoting UnifiedPayloadMapper's private _asDateWire() to
  /// a shared util — that helper parses messy dynamic form-answer input
  /// (ISO strings, epoch-ms strings, etc.); this caller always has a
  /// well-typed DateTime from a date picker, so a 4-line formatter is
  /// simpler than widening that class's API for one external caller.
  static String dateWire(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-${day}T00:00:00+00:00';
  }
}
