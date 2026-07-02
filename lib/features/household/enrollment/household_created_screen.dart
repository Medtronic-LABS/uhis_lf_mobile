import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
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
    super.initState();
    // Add pre-filled mock members on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<EnrollmentController>();
      if (controller.members.isEmpty) {
        controller.addMember(
          HouseholdMember(
            name: 'Ajay Kumar',
            age: 42,
            gender: 'Male',
            dateOfBirth: '1982-05-20',
            idType: 'NID',
            idNumber: '1234567890123',
            relationshipToHead: 'Head',
            maritalStatus: 'Married',
            disabilityStatus: 'Absent',
            nidScanned: true,
          ),
        );

        controller.addMember(
          HouseholdMember(
            name: 'Asha Kumari',
            age: 38,
            gender: 'Female',
            dateOfBirth: '1986-08-15',
            idType: 'BRN',
            idNumber: '9876543210987',
            relationshipToHead: 'Spouse',
            maritalStatus: 'Married',
            disabilityStatus: 'Absent',
            nidScanned: false,
          ),
        );
      }
    });
  }

  Future<void> _handleSave(EnrollmentController controller) async {
    final success = await controller.submitHousehold();

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(EnrollmentStrings.enrollmentSuccess),
            duration: Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
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
          backgroundColor: const Color(0xFFF5F6FB),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    // ── Green success header (no AppBar) ───────────────────
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF14996A),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            EnrollmentStrings.householdCreatedTitle2,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$hhNumber · Char Bhadra',
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Household Details card
                          if (household != null) ...[
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.cardSurface,
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
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
                              const Text(
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
                                  borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Head',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF92400E),
              ),
            ),
          ),
          // NID scanned badge (if applicable)
          if (head.nidScanned) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '📇 NID scan',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF14996A),
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
            borderRadius: BorderRadius.circular(12),
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
