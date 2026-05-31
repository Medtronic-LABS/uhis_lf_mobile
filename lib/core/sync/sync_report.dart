/// Aggregate counts returned by [OfflineSyncService.coldSync] /
/// [OfflineSyncService.warmSync]. Surfaced in the dashboard sync strip so the
/// SK sees what actually moved.
class SyncReport {
  const SyncReport({
    required this.startedAt,
    required this.finishedAt,
    this.patients = 0,
    this.followUps = 0,
    this.immunisations = 0,
    this.assessments = 0,
    this.referrals = 0,
    this.errors = const <String>[],
    this.wasFullSync = false,
  });

  factory SyncReport.empty() {
    final now = DateTime.now();
    return SyncReport(startedAt: now, finishedAt: now);
  }

  final DateTime startedAt;
  final DateTime finishedAt;
  final int patients;
  final int followUps;
  final int immunisations;
  final int assessments;
  final int referrals;
  final List<String> errors;
  final bool wasFullSync;

  bool get ok => errors.isEmpty;

  SyncReport copyWith({
    DateTime? finishedAt,
    int? patients,
    int? followUps,
    int? immunisations,
    int? assessments,
    int? referrals,
    List<String>? errors,
    bool? wasFullSync,
  }) =>
      SyncReport(
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        patients: patients ?? this.patients,
        followUps: followUps ?? this.followUps,
        immunisations: immunisations ?? this.immunisations,
        assessments: assessments ?? this.assessments,
        referrals: referrals ?? this.referrals,
        errors: errors ?? this.errors,
        wasFullSync: wasFullSync ?? this.wasFullSync,
      );
}
