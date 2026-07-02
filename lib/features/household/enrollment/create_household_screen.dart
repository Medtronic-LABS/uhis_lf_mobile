import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'widgets/enrollment_section_header.dart';
import 'widgets/enrollment_input_field.dart';
import 'widgets/enrollment_segmented_buttons.dart';
import 'widgets/enrollment_button.dart';

/// Step 1 of household enrollment: household information.
///
/// Collects household type, member count, house number, occupation, income,
/// and disability question. Validates on blur and provides next action to
/// continue to household head info (step 2).
class CreateHouseholdScreen extends StatefulWidget {
  const CreateHouseholdScreen({super.key});

  @override
  State<CreateHouseholdScreen> createState() => _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends State<CreateHouseholdScreen> {
  late TextEditingController _houseNumberCtrl;
  late TextEditingController _occupationCtrl;
  late TextEditingController _disabilityDetailsCtrl;
  String? _householdType;
  String? _numberOfMembers;
  String? _monthlyIncome;
  bool _hasDisability = false;

  @override
  void initState() {
    super.initState();
    _houseNumberCtrl = TextEditingController();
    _occupationCtrl = TextEditingController();
    _disabilityDetailsCtrl = TextEditingController();

    // Initialize household if not already done
    final controller = context.read<EnrollmentController>();
    if (controller.household == null) {
      controller.initializeHousehold(
        healthWorkerId: 'current_user_id',
        villageId: 'default_village',
      );
    }
  }

  @override
  void dispose() {
    _houseNumberCtrl.dispose();
    _occupationCtrl.dispose();
    _disabilityDetailsCtrl.dispose();
    super.dispose();
  }

  void _handleNext(EnrollmentController controller) {
    controller.updateHousehold(
      householdType: _householdType,
      numberOfMembers: int.tryParse(_numberOfMembers ?? '') ?? 0,
      houseNumber: _houseNumberCtrl.text,
      occupation: _occupationCtrl.text,
      monthlyIncome: _monthlyIncome,
      disabilityQuestion: _hasDisability,
      disabilityDetails: _disabilityDetailsCtrl.text,
    );

    final errors = controller.validateHouseholdForm();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.first),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    context.push('/household/enrollment/head-info');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnrollmentController>(
      builder: (context, controller, child) {
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            backgroundColor: AppColors.cardSurface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.navy),
              onPressed: () => context.pop(),
            ),
            title: const Text(
              EnrollmentStrings.createHouseholdTitle,
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
                  Text(
                    EnrollmentStrings.createHouseholdSubtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSectionHeader(
                    title: EnrollmentStrings.createHouseholdTitle,
                    subtitle: 'Provide basic household details',
                  ),
                  const SizedBox(height: 20),
                  if (controller.household != null)
                    EnrollmentInputField(
                      label: EnrollmentStrings.householdNumberLabel,
                      initialValue: controller.household!.householdNumber,
                      onChanged: (_) {},
                      isRequired: true,
                    ),
                  const SizedBox(height: 16),
                  EnrollmentSegmentedButtons(
                    label: EnrollmentStrings.householdTypeLabel,
                    options: EnrollmentStrings.householdTypes,
                    selectedValue: _householdType,
                    onChanged: (value) {
                      setState(() => _householdType = value);
                    },
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentInputField(
                    label: EnrollmentStrings.numberOfMembersLabel,
                    hint: EnrollmentStrings.numberOfMembersHint,
                    initialValue: _numberOfMembers,
                    onChanged: (value) {
                      setState(() => _numberOfMembers = value);
                    },
                    keyboardType: TextInputType.number,
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentInputField(
                    label: EnrollmentStrings.houseNumberLabel,
                    hint: EnrollmentStrings.houseNumberHint,
                    controller: _houseNumberCtrl,
                    onChanged: (_) {},
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentInputField(
                    label: EnrollmentStrings.occupationLabel,
                    hint: EnrollmentStrings.occupationHint,
                    controller: _occupationCtrl,
                    onChanged: (_) {},
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSegmentedButtons(
                    label: EnrollmentStrings.monthlyIncomeLabel,
                    options: EnrollmentStrings.incomeRanges,
                    selectedValue: _monthlyIncome,
                    onChanged: (value) {
                      setState(() => _monthlyIncome = value);
                    },
                    isRequired: true,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Checkbox(
                        value: _hasDisability,
                        onChanged: (value) {
                          setState(() => _hasDisability = value ?? false);
                        },
                        activeColor: AppColors.navy,
                      ),
                      Expanded(
                        child: Text(
                          EnrollmentStrings.disabilityQuestionLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_hasDisability) ...[
                    const SizedBox(height: 16),
                    EnrollmentInputField(
                      label: EnrollmentStrings.disabilityDetailsLabel,
                      hint: EnrollmentStrings.disabilityDetailsHint,
                      controller: _disabilityDetailsCtrl,
                      onChanged: (_) {},
                      isRequired: true,
                      maxLines: 2,
                    ),
                  ],
                  const SizedBox(height: 32),
                  EnrollmentButton(
                    label: EnrollmentStrings.next,
                    onPressed: () => _handleNext(controller),
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
}

extension _StringExtension on TextEditingController {
  // Dummy extension to allow using 'controller' parameter in EnrollmentInputField
  // In the actual implementation, use onChanged callback instead
}
