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

  static bool _householdMemberPushInFlight = false;
  static bool _assessmentPushInFlight = false;
  static bool _pullInFlight = false;

  /// Fired when [anyInFlight] changes — true when the first operation starts,
  /// false when the last one finishes. Never fired for transitions between two
  /// concurrent operations, so a subscriber can safely treat it as a
  /// start/stop pair.
  ///
  /// A plain function rather than a stream or ChangeNotifier so this file stays
  /// dependency-free (see the note above about the circular-import hazard).
  /// [SyncForegroundController] uses it to run the Android foreground service
  /// for exactly as long as something is syncing.
  static void Function(bool active)? onActiveChanged;

  /// True while [OfflinePushService.pushAll] (manual/auto/initial full push —
  /// households + members + assessments + follow-ups) is running.
  static bool get householdMemberPushInFlight => _householdMemberPushInFlight;
  static set householdMemberPushInFlight(bool value) =>
      _mutate(() => _householdMemberPushInFlight = value);

  /// True while [AssessmentRepository.syncPendingAssessments] (the
  /// submit-triggered, assessment-only push) is running.
  static bool get assessmentPushInFlight => _assessmentPushInFlight;
  static set assessmentPushInFlight(bool value) =>
      _mutate(() => _assessmentPushInFlight = value);

  /// True while [OfflineSyncService]'s cold/warm/relogin pull is running.
  static bool get pullInFlight => _pullInFlight;
  static set pullInFlight(bool value) => _mutate(() => _pullInFlight = value);

  static bool get anyInFlight =>
      _householdMemberPushInFlight ||
      _assessmentPushInFlight ||
      _pullInFlight;

  /// Applies a flag change and notifies only on the [anyInFlight] edge, so
  /// overlapping operations start the foreground service once and stop it when
  /// the last one clears — never mid-flight.
  static void _mutate(void Function() apply) {
    final before = anyInFlight;
    apply();
    final after = anyInFlight;
    if (before != after) onActiveChanged?.call(after);
  }

  /// Test hook — clears every flag and the listener between cases. Not
  /// annotated `@visibleForTesting` so this file keeps zero package imports.
  static void resetForTest() {
    _householdMemberPushInFlight = false;
    _assessmentPushInFlight = false;
    _pullInFlight = false;
    onActiveChanged = null;
  }
}
