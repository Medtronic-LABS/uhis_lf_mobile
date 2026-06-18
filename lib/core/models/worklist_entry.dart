import 'programme.dart';
import 'risk.dart';

/// The flat view-model the worklist UI consumes. Constructed by
/// `WorklistRepository` from joined `patients` + `patient_programmes` rows so
/// widgets never depend on raw DTO shapes (architecture §3.3 — FHIR boundary
/// lives at the repository).
class WorklistEntry {
  const WorklistEntry({
    required this.patientId,
    required this.displayName,
    this.age,
    this.householdNo,
    this.householdName,
    this.villageId,
    this.villageName,
    this.programmes = const <Programme>{},
    required this.score,
    required this.band,
    this.reasons = const <String>[],
    this.rationale,
    this.nextDueAt,
    this.lastVisitAt,
  });

  final String patientId;
  final String displayName;
  final int? age;
  final String? householdNo;
  final String? householdName;
  final String? villageId;
  final String? villageName;
  final Set<Programme> programmes;
  final int score;
  final RiskBand band;
  final List<String> reasons;

  /// Structured rationale payload (architecture.md §3.4 contract).
  /// Null for legacy entries loaded from cache before structured rationale shipped.
  final RiskRationale? rationale;

  final DateTime? nextDueAt;
  final DateTime? lastVisitAt;

  bool get isUrgent => band == RiskBand.urgent;
}
