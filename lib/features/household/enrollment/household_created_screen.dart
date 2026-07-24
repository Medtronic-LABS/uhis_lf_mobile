import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/sync/offline_sync_service.dart';
import 'enrollment_controller.dart';
import 'models/household_enrollment_models.dart';
import 'widgets/enrollment_member_card.dart';
import 'widgets/enrollment_sticky_bar.dart';

/// Success screen: household has been enrolled.
///
/// Redesigned layout:
/// - Full-width green header (no AppBar) showing check icon, title, subtitle.
/// - Body: household detail card (2-column grid) + members section + Add Member
///   dashed button + Save navy button with sticky-bottom pattern.
class HouseholdCreatedScreen extends StatefulWidget {
  const HouseholdCreatedScreen({super.key});

  @override
  State<HouseholdCreatedScreen> createState() => _HouseholdCreatedScreenState();
}

class _HouseholdCreatedScreenState extends State<HouseholdCreatedScreen> {
  @override
  void initState() {
    debugPrint('[_HouseholdCreatedScreenState] initState');
    super.initState();
  }

  Future<void> _handleSave(EnrollmentController controller) async {
    debugPrint('[_HouseholdCreatedScreenState] _handleSave');
    final success = await controller.submitHousehold();

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(EnrollmentStrings.enrollmentSuccess),
            duration: Duration(seconds: 2),
          ),
        );

        // Trigger a warm sync so newly enrolled members appear in the member
        // list immediately after navigating home. Fire-and-forget — the sync
        // service shows its own progress indicator on the home screen.
        final sync = context.read<OfflineSyncService>();
        unawaited(sync.warmSync());

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          controller.reset();
          context.go('/home');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(controller.error ?? EnrollmentStrings.enrollmentFailed),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnrollmentController>(
      builder: (context, controller, child) {
        final household = controller.household;
        final head = controller.householdHead;
        final members = controller.members;
        final totalCount =
            head != null ? members.length + 1 : members.length;
        final hhNumber = household?.householdNumber ?? '';

        return Scaffold(
          backgroundColor: AppColors.pageBackground,
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.stickyBarClearance,
                  ),
                  children: [
                    // ── Maroon success header ───────────────────────────────
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF831843),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.h6xl,
                        AppSpacing.h7xl,
                        AppSpacing.h6xl,
                        AppSpacing.h7xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '✓ ${EnrollmentStrings.householdCreatedTitle2}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (hhNumber.isNotEmpty) hhNumber,
                              if ((household?.subVillageName ?? '').isNotEmpty)
                                household!.subVillageName!
                              else if ((household?.villageName ?? '').isNotEmpty)
                                household!.villageName!,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Body ───────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.h5xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Household Details card
                          if (household != null) ...[
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.cardSurface,
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(AppRadius.card),
                              ),
                              padding: const EdgeInsets.all(AppSpacing.xxxl),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    EnrollmentStrings.householdDetailsTitle,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.navy,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _DetailCell(
                                          label: EnrollmentStrings
                                              .detailLabelHouseholdNo,
                                          value: household.householdNumber,
                                        ),
                                      ),
                                      Expanded(
                                        child: _DetailCell(
                                          label: EnrollmentStrings
                                              .detailLabelHouseNo,
                                          value: household.houseNumber.isEmpty
                                              ? '—'
                                              : household.houseNumber,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _DetailCell(
                                          label: EnrollmentStrings
                                              .detailLabelVillage,
                                          value: 'Char Bhadra',
                                        ),
                                      ),
                                      Expanded(
                                        child: _DetailCell(
                                          label: EnrollmentStrings
                                              .detailLabelTotalMembers,
                                          value: household.numberOfMembers > 0
                                              ? household.numberOfMembers
                                                  .toString()
                                              : totalCount.toString(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Members section header + count badge
                          Row(
                            children: [
                              Text(
                                EnrollmentStrings.householdMembersSectionHeader,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.aiPurple,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Text(
                                  '$totalCount',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Head card
                          if (head != null) ...[
                            _HeadMemberCard(head: head),
                            const SizedBox(height: 10),
                          ],

                          // Other members
                          ...List.generate(members.length, (index) {
                            final member = members[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: EnrollmentMemberCard(member: member),
                            );
                          }),

                          const SizedBox(height: 6),

                          // Add Member — dashed border button
                          _DashedAddMemberButton(
                            onTap: () => context
                                .push('/household/enrollment/add-member'),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Sticky bottom CTA ──────────────────────────────────────
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EnrollmentStickyBar(
                    label: EnrollmentStrings.saveHousehold,
                    loading: controller.loading,
                    onPressed: () => _handleSave(controller),
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

// ── Private helper widgets ─────────────────────────────────────────────────

class _DetailCell extends StatelessWidget {
  const _DetailCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _HeadMemberCard extends StatelessWidget {
  const _HeadMemberCard({required this.head});

  final HouseholdHeadInfo head;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar with person icon
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.aiSurfaceStart,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '👤',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  head.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${head.age}y · ${head.gender}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // "Head" amber badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.statusWarningSurface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text(
              'Head',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.statusWarningText,
              ),
            ),
          ),
          // NID scanned badge (if applicable)
          if (head.nidScanned) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.tbSurface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text(
                '📇 NID scan',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.enrollmentSuccess,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashedAddMemberButton extends StatelessWidget {
  const _DashedAddMemberButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: AppColors.navy,
          radius: 12,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: AppColors.navy),
              const SizedBox(width: 8),
              Text(
                EnrollmentStrings.addMoreMembers,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    const dashWidth = 6.0;
    const dashSpace = 4.0;

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final remaining = metric.length - distance;
        final len = remaining < dashWidth ? remaining : dashWidth;
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
