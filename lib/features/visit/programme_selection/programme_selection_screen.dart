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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProgrammeSelectionViewModel>.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Consumer<ProgrammeSelectionViewModel>(
            builder: (context, vm, _) {
              return Column(
                children: [
                  Expanded(child: _buildBody(context, vm)),
                  _ContinueBar(
                    selectedCount: vm.selectedProgrammes.length,
                    onContinue: () => widget.onContinue(vm.selectedProgrammes),
                  ),
                ],
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
        const Text(
          ProgrammeSelectionStrings.aiRecommendedTitle,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
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
            onSkip: () {
              vm.removeProgramme(rec.programme);
              _showProgrammeToast(context, rec.programme, added: false);
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
            foregroundColor: AppColors.navy,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openAddProgrammeSheet(
    BuildContext context,
    ProgrammeSelectionViewModel vm,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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

/// Shared confirmation toast. Pops a 1.5 s SnackBar at the bottom of the
/// scaffold whenever the SK adds or removes a programme from the
/// recommendations or the add-programme sheet.
void _showProgrammeToast(
  BuildContext context,
  Programme programme,
  {required bool added}
) {
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
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: AppColors.aiPurple),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  ProgrammeSelectionStrings.loadingTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ),
              SizedBox(
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
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            ProgrammeSelectionStrings.loadingSubtitle,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
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
        final w = width ??
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 36, color: AppColors.textMuted),
            const SizedBox(height: 12),
            const Text(
              ProgrammeSelectionStrings.failedTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              ProgrammeSelectionStrings.failedSubtitle,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            ProgrammeSelectionStrings.currentProgrammeTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          if (!hasCurrent)
            const Text(
              ProgrammeSelectionStrings.currentProgrammeNone,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: currentProgrammes
                  .map(
                    (p) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p.wireTag,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.statusWarning),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.statusWarning),
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
                      fontSize: 12, color: AppColors.statusWarningText),
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
    final surfaceColor = isSelected ? AppColors.aiSurfaceStart : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(20),
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
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    ProgrammeSelectionStrings.currentBadge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent),
                ),
                child: Text(
                  ProgrammeSelectionStrings.confidenceChip(
                      recommendation.confidencePct),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final bullet in recommendation.rationale)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 6),
                    child: Icon(Icons.circle, size: 4, color: AppColors.navy),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bullet.text,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.navy,
                          ),
                        ),
                        if (bullet.source.displayLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
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
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSelected ? onSkip : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: const Text(ProgrammeSelectionStrings.rejectCta),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: isSelected ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.navy.withValues(alpha: 0.4),
                  ),
                  child: Text(
                    isSelected
                        ? ProgrammeSelectionStrings.currentBadge
                        : ProgrammeSelectionStrings.acceptCta,
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

  /// Programmes a user can manually add. We surface the full set known to
  /// the mobile app and exclude any already-selected programmes; SK can untick
  /// from the chip row below to remove.
  static const List<Programme> _allProgrammes = <Programme>[
    Programme.anc,
    Programme.pnc,
    Programme.ncd,
    Programme.tb,
    Programme.imci,
    Programme.epi,
    Programme.nutrition,
    Programme.familyPlanning,
    Programme.cataract,
    Programme.eyeCare,
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final selected = vm.selectedProgrammes;
        final available =
            _allProgrammes.where((p) => !selected.contains(p)).toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                const Text(
                  ProgrammeSelectionStrings.addProgrammeSheetTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  ProgrammeSelectionStrings.addProgrammeSheetSubtitle,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        ProgrammeSelectionStrings.addProgrammeSheetEmpty,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              onTap: () {
                                vm.addProgramme(p);
                                Navigator.of(context).pop();
                                onAdded(p);
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.add_rounded,
                                        size: 14,
                                        color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      p.wireTag,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.navy,
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

// ─── Continue bar ────────────────────────────────────────────────────────────

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.selectedCount, required this.onContinue});

  final int selectedCount;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onContinue,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.pink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
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
