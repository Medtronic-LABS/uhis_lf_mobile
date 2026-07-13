// DTOs matching the Android SPICE app's immunisation API contract.
//
// Android source: ImmunisationDTO, ImmunisationRequestDTO,
// ImmunisationSummaryDTO in spice_mobile/Spice-SL/app/src/main/java/.../dto/
//
// Backend: POST /spice-service/immunisation/{list,create,summary-create}

// ── Single vaccine record ────────────────────────────────────────────────────

class VaccinationDetailDto {
  const VaccinationDetailDto({
    this.id,
    required this.type,
    required this.value,
    this.status,
    required this.vaccineName,
    required this.scheduledDate,
    this.vaccinatedDate,
    this.doseClosureWeeks,
    this.reason,
    required this.displayOrder,
    required this.category,
    required this.vaccineOrder,
  });

  final String? id;

  /// Offset type — 'WEEK' | 'MONTH' | 'DAY' (uppercase to match Android).
  final String type;

  /// Offset value (e.g. 6 for "6 Weeks", 9 for "9 Months", 0 for "At Birth").
  final int value;

  /// 'Vaccinated' | 'Missed' | 'Upcoming'
  final String? status;

  final String vaccineName;

  /// ISO-8601 date string e.g. "2024-03-15".
  final String scheduledDate;
  final String? vaccinatedDate;
  final String? doseClosureWeeks;
  final String? reason;
  final int displayOrder;
  final String category;
  final int vaccineOrder;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'type': type,
        'value': value,
        if (status != null) 'status': status,
        'vaccineName': vaccineName,
        'scheduledDate': scheduledDate,
        if (vaccinatedDate != null) 'vaccinatedDate': vaccinatedDate,
        if (doseClosureWeeks != null) 'doseClosureWeeks': doseClosureWeeks,
        if (reason != null) 'reason': reason,
        'displayOrder': displayOrder,
        'category': category,
        'vaccineOrder': vaccineOrder,
      };

  factory VaccinationDetailDto.fromJson(Map<String, dynamic> j) =>
      VaccinationDetailDto(
        id: j['id'] as String?,
        type: j['type'] as String? ?? 'DAY',
        value: (j['value'] as num?)?.toInt() ?? 0,
        status: j['status'] as String?,
        vaccineName: j['vaccineName'] as String? ?? '',
        scheduledDate: j['scheduledDate'] as String? ?? '',
        vaccinatedDate: j['vaccinatedDate'] as String?,
        doseClosureWeeks: j['doseClosureWeeks'] as String?,
        reason: j['reason'] as String?,
        displayOrder: (j['displayOrder'] as num?)?.toInt() ?? 0,
        category: j['category'] as String? ?? '',
        vaccineOrder: (j['vaccineOrder'] as num?)?.toInt() ?? 0,
      );
}

// ── Fetch request ─────────────────────────────────────────────────────────────

class ImmunisationListRequestDto {
  const ImmunisationListRequestDto({
    required this.patientReference,
    this.memberId,
    required this.patientId,
    required this.birthDate,
  });

  final String patientReference;
  final String? memberId;
  final int patientId;

  /// ISO-8601 date e.g. "2024-01-15".
  final String birthDate;

  Map<String, dynamic> toJson() => {
        'patientReference': patientReference,
        if (memberId != null) 'memberId': memberId,
        'patientId': patientId,
        'birthDate': birthDate,
      };
}

// ── Create request ────────────────────────────────────────────────────────────

class MedicalReviewEncounterDto {
  const MedicalReviewEncounterDto({
    this.patientReference,
    this.patientId,
    this.villageId,
    this.memberId,
    this.householdId,
  });

  final String? patientReference;
  final int? patientId;
  final String? villageId;
  final String? memberId;
  final String? householdId;

  Map<String, dynamic> toJson() => {
        if (patientReference != null) 'patientReference': patientReference,
        if (patientId != null) 'patientId': patientId,
        if (villageId != null) 'villageId': villageId,
        if (memberId != null) 'memberId': memberId,
        if (householdId != null) 'householdId': householdId,
      };
}

class ImmunisationCreateRequestDto {
  const ImmunisationCreateRequestDto({
    required this.immunisationList,
    required this.encounter,
    this.missedReason,
  });

  final List<VaccinationDetailDto> immunisationList;
  final MedicalReviewEncounterDto encounter;
  final String? missedReason;

  Map<String, dynamic> toJson() => {
        'immunisationList': immunisationList.map((v) => v.toJson()).toList(),
        'encounter': encounter.toJson(),
        if (missedReason != null) 'missedReason': missedReason,
      };
}

// ── Summary create request ────────────────────────────────────────────────────

class ImmunisationSummaryCreateDto {
  const ImmunisationSummaryCreateDto({
    this.vaccinated,
    this.missedVaccine,
    this.missedReason,
    this.lastScheduledDate,
    this.lastScheduledDateReason,
    this.encounterId,
    this.nextVaccinationDuration,
    this.nextVaccinationDose,
    this.nextVaccinationDate,
  });

  final int? vaccinated;
  final int? missedVaccine;
  final String? missedReason;
  final String? lastScheduledDate;
  final String? lastScheduledDateReason;
  final String? encounterId;
  final String? nextVaccinationDuration;
  final List<String>? nextVaccinationDose;
  final String? nextVaccinationDate;

  Map<String, dynamic> toJson() => {
        if (vaccinated != null) 'vaccinated': vaccinated,
        if (missedVaccine != null) 'missedVaccine': missedVaccine,
        if (missedReason != null) 'missedReason': missedReason,
        if (lastScheduledDate != null) 'lastScheduledDate': lastScheduledDate,
        if (lastScheduledDateReason != null)
          'lastScheduledDateReason': lastScheduledDateReason,
        if (encounterId != null) 'encounterId': encounterId,
        if (nextVaccinationDuration != null)
          'nextVaccinationDuration': nextVaccinationDuration,
        if (nextVaccinationDose != null)
          'nextVaccinationDose': nextVaccinationDose,
        if (nextVaccinationDate != null)
          'nextVaccinationDate': nextVaccinationDate,
      };
}
