import '../constants/app_strings.dart';

/// Progress state for the initial data sync screen.
///
/// Used by [SyncProgressScreen] to render step-by-step progress with
/// item counts and estimated completion.
class SyncProgress {
  const SyncProgress({
    this.currentStep = SyncStep.connecting,
    this.totalSteps = 5,
    this.itemsDone = 0,
    this.itemsTotal = 0,
    this.entityName = '',
    this.error,
    this.isComplete = false,
    this.retryAttempt,
    this.retryMaxAttempts,
    this.hasChanges = true,
    this.persistPhase,
  });

  final SyncStep currentStep;
  final int totalSteps;
  final int itemsDone;
  final int itemsTotal;
  /// Free-form label. Must NOT hold localized copy: this object outlives the
  /// language-keyed MaterialApp remount (OfflineSyncService is an app-level
  /// singleton above it), so anything localized at emit time stays frozen in
  /// the old language after a switch. Emitters pass data; the UI localizes at
  /// build. See [retryAttempt].
  final String entityName;
  final String? error;
  final bool isComplete;

  /// 1-based attempt currently being retried, or null when not retrying.
  /// An int rather than a message for the reason given on [entityName].
  final int? retryAttempt;
  final int? retryMaxAttempts;

  bool get isRetrying => retryAttempt != null && retryMaxAttempts != null;

  /// Which part of the local write is running, when [currentStep] is
  /// [SyncStep.processingData].
  ///
  /// An enum, not a label: this object outlives the language-keyed MaterialApp
  /// remount, so text stored here would freeze in the emitting language. The
  /// UI resolves it at build (see SyncPersistPhaseX.label).
  final SyncPersistPhase? persistPhase;

  /// Whether this sync actually wrote anything.
  ///
  /// A warm pull that finds nothing new still completes, and the derived-data
  /// recompute it would trigger walks every patient — measured at **19 s for
  /// 3566 patients after a 1.3 s no-op sync**. Since connectivity changes fire
  /// a sync on every network flap, ungated that is near-continuous CPU and
  /// battery burn recomputing values that cannot have changed. Defaults true so
  /// any other completion path still refreshes.
  final bool hasChanges;

  /// 0.0 to 1.0 overall progress.
  double get overallProgress {
    if (isComplete) return 1.0;
    final stepProgress = currentStep.index / totalSteps;
    final itemProgress = itemsTotal > 0 ? itemsDone / itemsTotal : 0.0;
    // Weight: 80% step progress, 20% item progress within step
    return stepProgress * 0.8 + (itemProgress * 0.2 / totalSteps);
  }

  bool get hasError => error != null;

  SyncProgress copyWith({
    SyncStep? currentStep,
    int? totalSteps,
    int? itemsDone,
    int? itemsTotal,
    String? entityName,
    String? error,
    bool? isComplete,
    int? retryAttempt,
    int? retryMaxAttempts,
    bool? hasChanges,
    SyncPersistPhase? persistPhase,
  }) =>
      SyncProgress(
        currentStep: currentStep ?? this.currentStep,
        totalSteps: totalSteps ?? this.totalSteps,
        itemsDone: itemsDone ?? this.itemsDone,
        itemsTotal: itemsTotal ?? this.itemsTotal,
        entityName: entityName ?? this.entityName,
        error: error,
        isComplete: isComplete ?? this.isComplete,
        retryAttempt: retryAttempt ?? this.retryAttempt,
        retryMaxAttempts: retryMaxAttempts ?? this.retryMaxAttempts,
        hasChanges: hasChanges ?? this.hasChanges,
        persistPhase: persistPhase ?? this.persistPhase,
      );

  static const SyncProgress initial = SyncProgress();

  static SyncProgress completed({bool hasChanges = true}) => SyncProgress(
        currentStep: SyncStep.done,
        isComplete: true,
        hasChanges: hasChanges,
      );

  static SyncProgress failed(String message) => SyncProgress(
        error: message,
      );
}

/// Sub-phases of the local write, reported while [SyncStep.processingData] is
/// current.
///
/// The persist runs 45-66 s on a Pixel 10a for 1398 households / 3566 members
/// — long enough that a bare spinner tells the SK nothing about whether the app
/// is working or wedged. Each phase has a row count known before it starts, so
/// progress here is honest rather than decorative (unlike the server fetch,
/// whose duration nobody can predict).
enum SyncPersistPhase {
  households,
  members,
  patients,
  programmes,
  followUps,
  finalising,
}

/// Discrete steps in the sync process.
enum SyncStep {
  connecting,
  fetchingPatients,
  fetchingFollowUps,
  fetchingReferrals,
  processingData,
  done,
}

extension SyncStepX on SyncStep {
  String get label {
    switch (this) {
      case SyncStep.connecting:
        return SyncStrings.connectingToServer;
      case SyncStep.fetchingPatients:
        return SyncStrings.downloadingPatients;
      case SyncStep.fetchingFollowUps:
        return SyncStrings.downloadingFollowUps;
      case SyncStep.fetchingReferrals:
        return SyncStrings.downloadingReferrals;
      case SyncStep.processingData:
        return SyncStrings.processingData;
      case SyncStep.done:
        return SyncStrings.readyStatus;
    }
  }

  String get icon {
    switch (this) {
      case SyncStep.connecting:
        return '🔗';
      case SyncStep.fetchingPatients:
        return '👥';
      case SyncStep.fetchingFollowUps:
        return '📋';
      case SyncStep.fetchingReferrals:
        return '🔀';
      case SyncStep.processingData:
        return '⚙️';
      case SyncStep.done:
        return '✅';
    }
  }
}

/// Localized label for each persist phase. Resolved at build time so a
/// mid-sync language switch is followed, matching SyncStepX.label.
extension SyncPersistPhaseX on SyncPersistPhase {
  String get label => switch (this) {
        SyncPersistPhase.households => SyncStrings.savingHouseholds,
        SyncPersistPhase.members => SyncStrings.savingMembers,
        SyncPersistPhase.patients => SyncStrings.savingPatients,
        SyncPersistPhase.programmes => SyncStrings.savingProgrammes,
        SyncPersistPhase.followUps => SyncStrings.savingFollowUps,
        SyncPersistPhase.finalising => SyncStrings.finalising,
      };
}
