import 'programme.dart';
import 'risk.dart';

/// The flat view-model the worklist UI consumes. Constructed by
/// `WorklistRepository` from joined `patients` + `patient_programmes` rows so
/// widgets never depend on raw DTO shapes (architecture §3.3 — FHIR boundary
/// lives at the repository).
///
/// Implements spec §2.8 band + modifier model. There is no composite numeric
/// severity — the worst single finding sets the band; modifier letters rank
/// within band.
class WorklistEntry {
  const WorklistEntry({
    required this.patientId,
    required this.displayName,
    this.age,
    this.gender,
    this.phoneNumber,
    this.nid,
    this.householdNo,
    this.householdName,
    this.villageId,
    this.villageName,
    this.programmes = const <Programme>{},
    required this.band,
    this.modifier = Modifier.none,
    this.reasons = const <String>[],
    this.rationale,
    this.nextDueAt,
    this.lastVisitAt,
  });

  final String patientId;
  final String displayName;
  final int? age;
  final String? gender;
  final String? phoneNumber;
  final String? nid;
  final String? householdNo;
  final String? householdName;
  final String? villageId;
  final String? villageName;
  final Set<Programme> programmes;
  final Band band;
  final Modifier modifier;
  final List<String> reasons;

  /// Structured rationale payload (architecture.md §3.4 contract).
  final RiskRationale? rationale;

  final DateTime? nextDueAt;
  final DateTime? lastVisitAt;

  bool get isUrgent => band == Band.band1;

  /// Pregnancy is a within-band sort boost (spec §2.8): pregnant patients
  /// always rank above non-pregnant patients in the same band.
  bool get isPregnant => programmes.contains(Programme.anc);

  /// Pure sort key driven by [band] + [modifier] — matches the value
  /// persisted in the SQLite `risk_score` column. Pregnancy and other
  /// tie-breakers are applied separately by the repository.
  int get sortRank => sortRankFor(band, modifier);
}
