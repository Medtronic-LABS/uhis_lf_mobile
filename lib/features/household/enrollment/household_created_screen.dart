import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'models/household_enrollment_models.dart';
import 'widgets/enrollment_status_header.dart';
import 'widgets/enrollment_member_card.dart';
import 'widgets/enrollment_button.dart';

/// Success screen: household has been enrolled.
///
/// Displays the household details, list of enrolled members, and options to
/// add more members or save and continue. Pre-populated with 2 mock members
/// for demonstration.
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
          disabilityStatus: 'None',
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
          disabilityStatus: 'None',
          nidScanned: false,
        ),
      );
    }
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

        // Navigate back to dashboard
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          context.go('/home');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.error ?? EnrollmentStrings.enrollmentFailed),
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

        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            backgroundColor: AppColors.cardSurface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: AppColors.navy),
              onPressed: () => context.pop(),
            ),
            title: const Text(
              EnrollmentStrings.householdCreatedTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EnrollmentStatusHeader(
                    title: EnrollmentStrings.householdCreatedTitle,
                    subtitle: EnrollmentStrings.householdCreatedSubtitle,
                    icon: Icons.check_circle,
                  ),
                  const SizedBox(height: 24),
                  if (household != null) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        border: Border.all(color: AppColors.border),
                        borderRadius:
                            BorderRadius.circular(AppRadius.card),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EnrollmentStrings.householdDetailsTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDetailRow(
                                  'Household #',
                                  household.householdNumber,
                                ),
                              ),
                              Expanded(
                                child: _buildDetailRow(
                                  'Type',
                                  household.householdType,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDetailRow(
                                  'House #',
                                  household.houseNumber,
                                ),
                              ),
                              Expanded(
                                child: _buildDetailRow(
                                  'Income',
                                  household.monthlyIncome,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          EnrollmentStrings.membersAddedLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.statusSuccessSurface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.button),
                          ),
                          child: Text(
                            EnrollmentStrings.membersAddedCount(
                              head != null ? members.length + 1 : members.length,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.statusSuccessText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (head != null)
                      EnrollmentMemberCard(
                        member: head,
                      ),
                    const SizedBox(height: 12),
                    ...List.generate(
                      members.length,
                      (index) => Column(
                        children: [
                          EnrollmentMemberCard(
                            member: members[index],
                          ),
                          if (index < members.length - 1)
                            const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.cardSurfaceMuted,
                        border: Border.all(
                          color: AppColors.border,
                          strokeAlign: BorderSide.strokeAlignCenter,
                          width: 1,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppRadius.card),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            context.push('/household/enrollment/add-member');
                          },
                          borderRadius: BorderRadius.circular(
                            AppRadius.card,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add,
                                  size: 20,
                                  color: AppColors.navy,
                                ),
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
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  EnrollmentButton(
                    label: EnrollmentStrings.saveHousehold,
                    onPressed: () => _handleSave(controller),
                    isLoading: controller.loading,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
