/// Step 4 of the visit flow: full-screen visit completion.
///
/// Replaces the inline completion dialog from [VisitFormScreen] with a
/// dedicated route so deep-link navigation and the back stack are clean.
///
/// Engineering Design Standards:
///   - Pure UI — no API calls, no I/O.
///   - All strings from [VisitCompleteStrings].
///   - Programme header color resolved via [_headerColor].
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import '../../core/theme/app_theme.dart';

class VisitCompleteScreen extends StatelessWidget {
  const VisitCompleteScreen({
    super.key,
    required this.visitId,
    required this.patientLabel,
    required this.primaryProgramme,
    required this.referralRecommended,
    required this.origin,
    this.memberId,
    this.householdId,
  });

  final String visitId;
  final String patientLabel;
  final String primaryProgramme;
  final bool referralRecommended;
  final String? memberId;
  final String? householdId;

  /// 'dashboard' | 'patients' — controls back navigation.
  final String origin;

  Color _headerColor(Programme p) => switch (p) {
        Programme.anc || Programme.pnc => AppColors.ancHeader,
        Programme.ncd => AppColors.ncdHeader,
        Programme.imci => AppColors.imciHeader,
        Programme.tb => AppColors.tbHeader,
        _ => AppColors.navy,
      };

  @override
  Widget build(BuildContext context) {
    final programme = Programme.fromString(primaryProgramme);
    final headerColor = _headerColor(programme);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(VisitCompleteStrings.title),
        backgroundColor: headerColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.h6xl,
            vertical: AppSpacing.h6xl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.h8xl),

              // ── Success icon ────────────────────────────────────────────
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 80,
                  color: AppColors.statusSuccess,
                ),
              ),
              const SizedBox(height: AppSpacing.h6xl),

              // ── Saved label ─────────────────────────────────────────────
              Text(
                VisitCompleteStrings.saved,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),

              // ── Programme chip ──────────────────────────────────────────
              if (programme != Programme.unknown)
                Chip(
                  label: Text(
                    primaryProgramme.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: headerColor,
                  side: BorderSide.none,
                ),

              const SizedBox(height: AppSpacing.h6xl),

              // ── Referral warning card ───────────────────────────────────
              if (referralRecommended) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xxxl),
                  decoration: BoxDecoration(
                    color: AppColors.statusCriticalSurface,
                    borderRadius: BorderRadius.circular(AppRadius.patRow),
                    border: Border.all(
                      color: AppColors.statusCriticalBorder,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.statusCritical,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          VisitCompleteStrings.referralWarning,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.statusCriticalText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.h8xl),
              ],

              const SizedBox(height: AppSpacing.h8xl),

              // ── Action buttons ──────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Teleconsult — only for ANC / PNC
                  if (programme == Programme.anc ||
                      programme == Programme.pnc) ...[
                    FilledButton.icon(
                      onPressed: () => context.push(
                        '/teleconsult',
                        extra: {
                          'patientLabel': patientLabel,
                          'patientId': memberId ?? '',
                        },
                      ),
                      icon: const Icon(Icons.video_call_rounded),
                      label: const Text(VisitCompleteStrings.bookTeleconsult),
                      style: FilledButton.styleFrom(
                        backgroundColor: headerColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // AI Counselling — for EPI (immunisation) and IMCI (child health)
                  if (programme == Programme.epi || programme == Programme.imci) ...[
                    FilledButton.icon(
                      onPressed: () => context.push(
                        '/counselling',
                        extra: {
                          'patientLabel': patientLabel,
                          'patientId': memberId ?? '',
                        },
                      ),
                      icon: const Icon(Icons.health_and_safety_rounded),
                      label: const Text(VisitCompleteStrings.sendCounsellingMessage),
                      style: FilledButton.styleFrom(
                        backgroundColor: headerColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // Create referral — only when referral is recommended
                  if (referralRecommended) ...[
                    OutlinedButton(
                      onPressed: () => context.go('/tasks'),
                      child: const Text(VisitCompleteStrings.createReferral),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // Back to home — always shown
                  TextButton(
                    onPressed: () => context.go('/home'),
                    child: const Text(VisitCompleteStrings.backToHome),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
