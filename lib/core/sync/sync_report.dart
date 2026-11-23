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
    this.households = 0,
    this.members = 0,
    this.errors = const <String>[],
    this.wasFullSync = false,
    this.failure,
    this.skipped = false,
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
  final int households;
  final int members;
  final List<String> errors;
  final bool wasFullSync;

  /// The error that stopped the sync, kept typed for analytics (LEAP-152).
  final Object? failure;

  /// True when the sync did not run because another one was in flight.
  final bool skipped;

  bool get ok => errors.isEmpty;

  SyncReport copyWith({
    DateTime? finishedAt,
    int? patients,
    int? followUps,
    int? immunisations,
    int? assessments,
    int? referrals,
    int? households,
    int? members,
    List<String>? errors,
    bool? wasFullSync,
    Object? failure,
    bool? skipped,
  }) =>
      SyncReport(
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        patients: patients ?? this.patients,
        followUps: followUps ?? this.followUps,
        immunisations: immunisations ?? this.immunisations,
        assessments: assessments ?? this.assessments,
        referrals: referrals ?? this.referrals,
        households: households ?? this.households,
        members: members ?? this.members,
        errors: errors ?? this.errors,
        wasFullSync: wasFullSync ?? this.wasFullSync,
        failure: failure ?? this.failure,
        skipped: skipped ?? this.skipped,
      );
}
