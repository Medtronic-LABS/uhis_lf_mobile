import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';
import '../../../core/theme/app_theme.dart';
import 'programme_recommendation_models.dart';
import 'programme_recommendation_repository.dart';
import 'programme_selection_view_model.dart';

/// Step-2 screen — AI Programme Recommendation.
///
/// Sits between the Step-1 symptom picker and the Step-3 vitals + form. Calls
/// /programme-recommendation/recommend, surfaces recommendations grounded in
/// BRAC + Bangladesh national clinical guidelines, and lets the SK pick the
/// final set of programmes whose forms should load.
///
/// The host (VisitFlowScreen) supplies the request payload and receives the
/// final selection via [onContinue].
class ProgrammeSelectionScreen extends StatefulWidget {
  const ProgrammeSelectionScreen({
    super.key,
    required this.request,
    required this.currentProgrammes,
    required this.onContinue,
  });

  /// Pre-built request payload — see VisitFlowScreen for assembly. Lives on
  /// the host so the screen has zero coupling to DAOs.
  final Map<String, dynamic> request;

  /// Programmes the patient is already enrolled in. Seeded into selection.
  final Set<Programme> currentProgrammes;

  /// Fired when SK taps Continue with the final programme set.
  final ValueChanged<Set<Programme>> onContinue;

  @override
  State<ProgrammeSelectionScreen> createState() =>
      _ProgrammeSelectionScreenState();
}

class _ProgrammeSelectionScreenState extends State<ProgrammeSelectionScreen> {
  late final ProgrammeSelectionViewModel _vm;

  @override
  void initState() {
    super.initState();
    debugPrint('[_ProgrammeSelectionScreenState] initState');
    _vm = ProgrammeSelectionViewModel(
      repository: context.read<ProgrammeRecommendationRepository>(),
      request: widget.request,
      currentProgrammes: widget.currentProgrammes,
    );
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    debugPrint('[_ProgrammeSelectionScreenState] dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProgrammeSelectionViewModel>.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        body: SafeArea(
          child: Consumer<ProgrammeSelectionViewModel>(
            builder: (context, vm, _) {
              return Column(
                children: [Expanded(child: _buildBody(context, vm))],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ProgrammeSelectionViewModel vm) {
    if (vm.isLoading) return const _LoadingSkeleton();
    if (vm.error != null && vm.response == null) {
      return _ErrorState(onRetry: () => vm.load());
    }

    final resp = vm.response;
    final notice = resp?.crossProgrammeNotice;
    final recs = resp?.recommendations ?? const <ProgrammeRecommendation>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.xxxl,
        AppSpacing.xxxl,
        AppSpacing.xxxl,
      ),
      children: [
        // Cross-program notice (callout)
        if (notice != null) _CrossProgrammeNoticeCard(notice: notice),
        if (notice != null) const SizedBox(height: 12),

        // Current Programme widget
        _CurrentProgrammeCard(
          currentProgrammes: widget.currentProgrammes,
          aiRecommendations: recs,
        ),
        const SizedBox(height: 12),

        // AI Recommended Programmes header
        Text(
          ProgrammeSelectionStrings.aiRecommendedTitle,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),

        // Recommendation cards
        for (final rec in recs) ...[
          _RecommendationCard(
            recommendation: rec,
            isSelected: vm.isSelected(rec.programme),
            onAccept: () {
              vm.addProgramme(rec.programme);
              _showProgrammeToast(context, rec.programme, added: true);
            },
            onSkip: () async {
              final ok = await _confirmSkip(context, rec.programme);
              if (!ok) return;
              vm.removeProgramme(rec.programme);
              if (context.mounted) {
                _showProgrammeToast(context, rec.programme, added: false);
              }
            },
          ),
          const SizedBox(height: 10),
        ],

        // Add another programme
        OutlinedButton.icon(
          onPressed: () => _openAddProgrammeSheet(context, vm),
          icon: const Icon(Icons.add, size: 18),
          label: const Text(ProgrammeSelectionStrings.addProgrammeCta),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
          ),
        ),

        // CTA — inline at scroll bottom so it moves with content.
        const SizedBox(height: 12),
        _ContinueBar(
          selectedCount: vm.selectedProgrammes.length,
          onContinue: () => _openReviewSheet(context, vm),
        ),
      ],
    );
  }

  /// Modal review before the form opens. Lists every programme the SK has
  /// confirmed; chips carry × to remove inline. SK can still hit "+ Add"
  /// from inside the sheet so they don't have to dismiss and re-tap.
  Future<void> _openReviewSheet(
    BuildContext context,
    ProgrammeSelectionViewModel vm,
  ) async {
    debugPrint('[_ProgrammeSelectionScreenState] _openReviewSheet');
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ReviewBeforeContinueSheet(
        vm: vm,
        onAdd: () {
          Navigator.of(ctx).pop(false);
          _openAddProgrammeSheet(context, vm);
        },
      ),
    );
    if (confirmed == true && context.mounted) {
      widget.onContinue(vm.selectedProgrammes);
    }
  }

  Future<void> _openAddProgrammeSheet(
    BuildContext context,
    ProgrammeSelectionViewModel vm,
  ) async {
    debugPrint('[_ProgrammeSelectionScreenState] _openAddProgrammeSheet');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AddProgrammeSheet(
        vm: vm,
        onAdded: (p) => _showProgrammeToast(context, p, added: true),
      ),
    );
  }
}

/// Confirm the SK wants to add a manually-selected programme. Returns true
/// when the SK taps "Yes, add", false otherwise (including dismiss).
Future<bool> _confirmAdd(BuildContext context, Programme programme) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.patRow),
      ),
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.statusSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.rxIcon),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.add_circle_outline_rounded,
              color: AppColors.statusSuccess,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ProgrammeSelectionStrings.addConfirmTitle(programme.wireTag),
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        ProgrammeSelectionStrings.addConfirmBody,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        0,
        AppSpacing.xxxl,
        AppSpacing.xl,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(ProgrammeSelectionStrings.addConfirmCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.statusSuccess,
            foregroundColor: Colors.white,
          ),
          child: const Text(ProgrammeSelectionStrings.addConfirmCta),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Confirm the SK wants to skip an AI-recommended programme. Surfaces the
/// safety reminder that the AI recommended it before letting the SK drop it.
Future<bool> _confirmSkip(BuildContext context, Programme programme) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.patRow),
      ),
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.statusCritical.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.rxIcon),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.statusCritical,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ProgrammeSelectionStrings.skipConfirmTitle(programme.wireTag),
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        ProgrammeSelectionStrings.skipConfirmBody,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        0,
        AppSpacing.xxxl,
        AppSpacing.xl,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(ProgrammeSelectionStrings.skipConfirmCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.statusCritical,
            foregroundColor: Colors.white,
          ),
          child: const Text(ProgrammeSelectionStrings.skipConfirmCta),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Shared confirmation toast. Pops a 1.5 s SnackBar at the bottom of the
/// scaffold whenever the SK adds or removes a programme from the
/// recommendations or the add-programme sheet.
void _showProgrammeToast(
  BuildContext context,
  Programme programme, {
  required bool added,
}) {
  if (programme == Programme.unknown) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 1500),
      behavior: SnackBarBehavior.floating,
      backgroundColor: added ? AppColors.statusSuccess : AppColors.navy,
      content: Row(
        children: [
          Icon(
            added ? Icons.check_circle_rounded : Icons.remove_circle_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              added
                  ? ProgrammeSelectionStrings.toastAdded(programme.wireTag)
                  : ProgrammeSelectionStrings.toastRemoved(programme.wireTag),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Loading skeleton ────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 18,
                color: AppColors.aiPurple,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ProgrammeSelectionStrings.loadingTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppColors.aiPurple),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
          child: Text(
            ProgrammeSelectionStrings.loadingSubtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xl),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.patRow),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBar(width: 140, height: 14),
                const SizedBox(height: 10),
                _SkeletonBar(widthFraction: 0.9, height: 10),
                const SizedBox(height: 6),
                _SkeletonBar(widthFraction: 0.7, height: 10),
                const SizedBox(height: 6),
                _SkeletonBar(widthFraction: 0.8, height: 10),
              ],
            ),
          ),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({this.width, this.widthFraction, required this.height});
  final double? width;
  final double? widthFraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w =
            width ??
            (widthFraction != null
                ? constraints.maxWidth * widthFraction!
                : constraints.maxWidth);
        return Container(
          width: w,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }
}

// ─── Error state ─────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.h6xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              ProgrammeSelectionStrings.failedTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              ProgrammeSelectionStrings.failedSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text(ProgrammeSelectionStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Current Programme card ──────────────────────────────────────────────────

class _CurrentProgrammeCard extends StatelessWidget {
  const _CurrentProgrammeCard({
    required this.currentProgrammes,
    required this.aiRecommendations,
  });

  final Set<Programme> currentProgrammes;
  final List<ProgrammeRecommendation> aiRecommendations;

  /// Consistency = AI recommended at least one of the patient's currently
  /// enrolled programmes with confidence ≥ 0.50.
  bool get _isConsistent {
    if (currentProgrammes.isEmpty) return false;
    return aiRecommendations.any(
      (r) => currentProgrammes.contains(r.programme) && r.confidence >= 0.50,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConsistent = _isConsistent;
    final hasCurrent = currentProgrammes.isNotEmpty;
    final indicatorColor = hasCurrent && isConsistent
        ? AppColors.statusSuccess
        : (hasCurrent ? AppColors.statusWarning : AppColors.textMuted);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.patRow),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ProgrammeSelectionStrings.currentProgrammeTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          if (!hasCurrent)
            Text(
              ProgrammeSelectionStrings.currentProgrammeNone,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: currentProgrammes
                  .map(
                    (p) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        p.wireTag,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (hasCurrent) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isConsistent
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: indicatorColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isConsistent
                        ? ProgrammeSelectionStrings.consistencyConsistent
                        : ProgrammeSelectionStrings.consistencyInconsistent,
                    style: TextStyle(fontSize: 12, color: indicatorColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Cross-programme notice ──────────────────────────────────────────────────

class _CrossProgrammeNoticeCard extends StatelessWidget {
  const _CrossProgrammeNoticeCard({required this.notice});
  final CrossProgrammeNotice notice;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.statusWarningSurface,
        borderRadius: BorderRadius.circular(AppRadius.patRow),
        border: Border.all(color: AppColors.statusWarning),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.statusWarning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  ProgrammeSelectionStrings.crossNoticeTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.statusWarningText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notice.message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.statusWarningText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recommendation card ─────────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.isSelected,
    required this.onAccept,
    required this.onSkip,
  });

  final ProgrammeRecommendation recommendation;
  final bool isSelected;
  final VoidCallback onAccept;
  final VoidCallback onSkip;

  Color _confidenceColor() {
    final c = recommendation.confidence;
    if (c >= 0.85) return AppColors.statusSuccess;
    if (c >= 0.70) return AppColors.statusInfo;
    if (c >= 0.50) return AppColors.statusWarning;
    return AppColors.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _confidenceColor();
    final borderColor = isSelected ? AppColors.aiBorder : AppColors.border;
    final surfaceColor = isSelected
        ? AppColors.aiSurfaceStart
        : Theme.of(context).colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.patRow),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  recommendation.programme.wireTag,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (recommendation.isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    ProgrammeSelectionStrings.currentBadge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: accent),
                ),
                child: Text(
                  ProgrammeSelectionStrings.confidenceChip(
                    recommendation.confidencePct,
                  ),
                  style: AppTextStyles.scorePill.copyWith(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final bullet in recommendation.rationale)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                    ),
                    child: Icon(
                      Icons.circle,
                      size: 4,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bullet.text,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (bullet.source.displayLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.aiSurfaceStart,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                bullet.source.displayLabel,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.aiPurple,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isSelected ? onSkip : null,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text(ProgrammeSelectionStrings.rejectCta),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.statusCritical,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.statusCritical
                          : AppColors.border,
                    ),
                    disabledForegroundColor: AppColors.textMuted.withValues(
                      alpha: 0.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSelected ? null : onAccept,
                  icon: Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.add_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isSelected
                        ? ProgrammeSelectionStrings.acceptedCta
                        : ProgrammeSelectionStrings.acceptCta,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.statusSuccess,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.statusSuccess.withValues(
                      alpha: 0.85,
                    ),
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Add programme sheet ─────────────────────────────────────────────────────

class _AddProgrammeSheet extends StatelessWidget {
  const _AddProgrammeSheet({required this.vm, required this.onAdded});
  final ProgrammeSelectionViewModel vm;
  final ValueChanged<Programme> onAdded;

  /// Programmes a user can manually add — all programmes now in kPilotProgrammes.
  static final List<Programme> _allProgrammes = Programme.kPilotProgrammes
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final selected = vm.selectedProgrammes;
        final available = _allProgrammes
            .where((p) => !selected.contains(p))
            .toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxxl,
              AppSpacing.xl,
              AppSpacing.xxxl,
              AppSpacing.xxxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  ProgrammeSelectionStrings.addProgrammeSheetTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ProgrammeSelectionStrings.addProgrammeSheetSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (available.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.h6xl,
                    ),
                    child: Center(
                      child: Text(
                        ProgrammeSelectionStrings.addProgrammeSheetEmpty,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: available
                        .map(
                          (p) => Material(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            child: InkWell(
                              onTap: () async {
                                final ok = await _confirmAdd(context, p);
                                if (!ok) return;
                                vm.addProgramme(p);
                                if (!context.mounted) return;
                                Navigator.of(context).pop();
                                onAdded(p);
                              },
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xl,
                                  vertical: AppSpacing.md,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.pill,
                                  ),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_rounded,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      p.wireTag,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Review-before-continue sheet ───────────────────────────────────────────
//
// Bottom sheet shown when the SK taps Continue. Lists every programme the SK
// has confirmed so far as a removable chip, and exposes "+ Add" so they can
// pull more from the manual list without dismissing first. Pops `true` when
// the SK confirms and the screen advances to the form; pops `false` when
// they back out.

class _ReviewBeforeContinueSheet extends StatelessWidget {
  const _ReviewBeforeContinueSheet({required this.vm, required this.onAdd});

  final ProgrammeSelectionViewModel vm;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final selected = vm.selectedProgrammes
            .where((p) => p != Programme.unknown)
            .toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxxl,
              AppSpacing.xl,
              AppSpacing.xxxl,
              AppSpacing.xxxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Grabber.
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Title row.
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.pink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.rxIcon),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.checklist_rounded,
                        size: 18,
                        color: AppColors.pink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ProgrammeSelectionStrings.reviewSheetTitle(
                              selected.length,
                            ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ProgrammeSelectionStrings.reviewSheetSubtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Selected programme chips with × remove.
                if (selected.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.xxxl,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppRadius.field),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ProgrammeSelectionStrings.reviewSheetEmpty,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selected
                        .map(
                          (p) => _ReviewChip(
                            programme: p,
                            onRemove: () => vm.removeProgramme(p),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 14),
                // Inline Add row.
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    ProgrammeSelectionStrings.reviewSheetAddMore,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Footer divider so the CTAs feel anchored to the sheet.
                Container(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                // Footer CTAs — equal height; primary takes 2/3 of the row
                // so the long "Continue with N programmes" label never wraps.
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onSurface,
                            side: const BorderSide(color: AppColors.border),
                            minimumSize: const Size.fromHeight(52),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                            textStyle: Theme.of(context).textTheme.titleSmall,
                          ),
                          child: const Text(
                            ProgrammeSelectionStrings.reviewSheetBack,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.pink,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.button,
                              ),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  selected.isEmpty
                                      ? ProgrammeSelectionStrings
                                            .continueCtaEmpty
                                      : ProgrammeSelectionStrings.continueCta(
                                          selected.length,
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReviewChip extends StatelessWidget {
  const _ReviewChip({required this.programme, required this.onRemove});
  final Programme programme;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            programme.wireTag,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Continue bar ────────────────────────────────────────────────────────────

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.selectedCount, required this.onContinue});

  final int selectedCount;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxxl,
          AppSpacing.md,
          AppSpacing.xxxl,
          AppSpacing.xxxl,
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onContinue,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.pink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            ),
            child: Text(
              selectedCount == 0
                  ? ProgrammeSelectionStrings.continueCtaEmpty
                  : ProgrammeSelectionStrings.continueCta(selectedCount),
            ),
          ),
        ),
      ),
    );
  }
}
