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
  });

  final SyncStep currentStep;
  final int totalSteps;
  final int itemsDone;
  final int itemsTotal;
  final String entityName;
  final String? error;
  final bool isComplete;

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
  }) =>
      SyncProgress(
        currentStep: currentStep ?? this.currentStep,
        totalSteps: totalSteps ?? this.totalSteps,
        itemsDone: itemsDone ?? this.itemsDone,
        itemsTotal: itemsTotal ?? this.itemsTotal,
        entityName: entityName ?? this.entityName,
        error: error,
        isComplete: isComplete ?? this.isComplete,
      );

  static const SyncProgress initial = SyncProgress();

  static SyncProgress completed() => const SyncProgress(
        currentStep: SyncStep.done,
        isComplete: true,
      );

  static SyncProgress failed(String message) => SyncProgress(
        error: message,
      );
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
        return 'Connecting to server';
      case SyncStep.fetchingPatients:
        return 'Downloading patients';
      case SyncStep.fetchingFollowUps:
        return 'Downloading follow-ups';
      case SyncStep.fetchingReferrals:
        return 'Downloading referrals';
      case SyncStep.processingData:
        return 'Processing data';
      case SyncStep.done:
        return 'Ready';
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
