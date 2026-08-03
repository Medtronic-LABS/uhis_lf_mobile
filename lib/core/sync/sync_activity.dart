/// Cross-service "is anything syncing" signal.
///
/// Gap-analysis finding #3: `OfflinePushService.isPushInFlight`,
/// `AssessmentRepository._isSyncing`, and `OfflineSyncService._running` are
/// three independent locks that never checked each other — `pushAll()` had no
/// reference to the assessment-only push, and neither push path had any
/// reference to a pull in progress. A form-submit push and a pull-to-refresh
/// could run concurrently, each writing to overlapping tables.
///
/// Extracted to its own dependency-free file (rather than having each class
/// import the other two) specifically to avoid a circular import between
/// `offline_push_service.dart`, `offline_sync_service.dart`, and
/// `assessment_repository.dart` — `assessment_repository.dart` already
/// imports `offline_push_service.dart` today.
///
/// These are still plain booleans with no age-gate/timeout, unlike the
/// DB-side `resetStuckInProgress` pattern used for stuck row *statuses* — a
/// follow-up should turn this into a real coordinator (single active-sync
/// flag, self-clearing after e.g. 2 minutes) so a bypassed `finally` block
/// can't wedge every sync path shut forever. Tracked as required follow-up
/// work in `docs/data_sync_gap_analysis.md` (#3), not shipped here.
abstract final class SyncActivity {
  SyncActivity._();

  /// True while [OfflinePushService.pushAll] (manual/auto/initial full push —
  /// households + members + assessments + follow-ups) is running.
  static bool householdMemberPushInFlight = false;

  /// True while [AssessmentRepository.syncPendingAssessments] (the
  /// submit-triggered, assessment-only push) is running.
  static bool assessmentPushInFlight = false;

  /// True while [OfflineSyncService]'s cold/warm/relogin pull is running.
  static bool pullInFlight = false;

  static bool get anyInFlight =>
      householdMemberPushInFlight || assessmentPushInFlight || pullInFlight;
}
