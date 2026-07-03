import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../models/household_enrollment_models.dart';

class EnrollmentMemberCard extends StatelessWidget {
  const EnrollmentMemberCard({
    required this.member,
    this.onTap,
    this.onRemove,
    this.showRemoveButton = false,
    super.key,
  });

  final HouseholdMember member;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool showRemoveButton;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.aiPurpleLight,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textOnNavy,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${member.age}y',
                          style: AppTextStyles.vitalUnit,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          child: Text(
                            '•',
                            style: AppTextStyles.vitalUnit,
                          ),
                        ),
                        Text(
                          member.gender,
                          style: AppTextStyles.vitalUnit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (member.relationshipToHead.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.statusSuccessSurface,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Text(
                    member.relationshipToHead,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.statusSuccessText,
                    ),
                  ),
                ),
            ],
          ),
          if (member.nidScanned) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.statusSuccessSurface,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 12,
                    color: AppColors.statusSuccess,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'NID Scanned',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.statusSuccessText,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showRemoveButton) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Material(
                  child: InkWell(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.statusCriticalSurface,
                        borderRadius:
                            BorderRadius.circular(AppRadius.button),
                      ),
                      child: const Text(
                        'Remove',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.statusCritical,
                        ),
                      ),
                    ),
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
