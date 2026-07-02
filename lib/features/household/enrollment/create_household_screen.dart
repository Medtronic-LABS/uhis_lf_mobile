import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/user_hierarchy_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'widgets/enrollment_section_header.dart';
import 'widgets/enrollment_input_field.dart';
import 'widgets/enrollment_segmented_buttons.dart';
import 'widgets/enrollment_dropdown.dart';
import 'widgets/enrollment_sticky_bar.dart';

/// Step 1 of household enrollment: household information.
///
/// Redesigned layout: navy AppBar with subtitle, scrollable body with sticky
/// bottom CTA, two grouped sections. Uses [EnrollmentDropdown] for health
/// worker, village, and occupation selectors.
class CreateHouseholdScreen extends StatefulWidget {
  const CreateHouseholdScreen({super.key});

  @override
  State<CreateHouseholdScreen> createState() => _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends State<CreateHouseholdScreen> {
  late TextEditingController _houseNumberCtrl;
  late TextEditingController _totalMembersCtrl;
  late TextEditingController _incomeCtrl;
  late TextEditingController _disabilityCountCtrl;

  String? _selectedHealthWorker;
  String? _selectedVillage;
  String? _householdType;
  String? _selectedOccupation;
  String _hasDisability = 'No';

  @override
  void initState() {
    super.initState();
    _houseNumberCtrl = TextEditingController();
    _totalMembersCtrl = TextEditingController();
    _incomeCtrl = TextEditingController();
    _disabilityCountCtrl = TextEditingController();

    // Rebuild the CTA enabled-state as the required text fields change.
    _houseNumberCtrl.addListener(_onFormChanged);
    _totalMembersCtrl.addListener(_onFormChanged);

    // Defer so ChangeNotifierProvider finishes its first build before
    // notifyListeners() is called (avoids !_dirty assertion).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = context.read<EnrollmentController>();
      if (controller.household == null) {
        final auth = context.read<AuthRepository>();
        final hierarchy = context.read<UserHierarchyService>();

        final userId = await auth.userId();
        final villages = hierarchy.villages ?? [];
        final subVillages = hierarchy.subVillages ?? [];

        final firstVillage = villages.isNotEmpty ? villages.first : null;
        final firstSubVillage =
            subVillages.isNotEmpty ? subVillages.first : null;

        if (!mounted) return;
        controller.initializeHousehold(
          healthWorkerId: userId?.toString() ?? '',
          villageId: firstVillage?.id.toString() ?? '',
          villageName: firstVillage?.name,
          subVillageId: firstSubVillage?.id.toString(),
          subVillageName: firstSubVillage?.name,
        );
      }
    });
  }

  @override
  void dispose() {
    _houseNumberCtrl.removeListener(_onFormChanged);
    _totalMembersCtrl.removeListener(_onFormChanged);
    _houseNumberCtrl.dispose();
    _totalMembersCtrl.dispose();
    _incomeCtrl.dispose();
    _disabilityCountCtrl.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  /// Mandatory fields for Step 1 (spec: keep CTA disabled until all present).
  bool get _isFormComplete =>
      _selectedHealthWorker != null &&
      _selectedVillage != null &&
      _householdType != null &&
      _houseNumberCtrl.text.trim().isNotEmpty &&
      _totalMembersCtrl.text.trim().isNotEmpty;

  void _handleNext(EnrollmentController controller) {
    controller.updateHousehold(
      householdType: _householdType ?? '',
      numberOfMembers: int.tryParse(_totalMembersCtrl.text) ?? 0,
      houseNumber: _houseNumberCtrl.text,
      occupation: _selectedOccupation ?? '',
      monthlyIncome: _incomeCtrl.text.isEmpty ? '0' : _incomeCtrl.text,
      disabilityQuestion: _hasDisability == 'Yes',
      disabilityDetails: _hasDisability == 'Yes'
          ? _disabilityCountCtrl.text
          : null,
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
          backgroundColor: const Color(0xFFF5F6FB),
          appBar: AppBar(
            backgroundColor: AppColors.navy,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Create Household',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
                  children: [
                    // Subtitle banner beneath the AppBar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        EnrollmentStrings.createHouseholdAppBarSubtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),

                    // ── Section: Household Information ─────────────────────
                    const EnrollmentSectionHeader(
                      title: EnrollmentStrings.householdInfoSectionHeader,
                    ),
                    const SizedBox(height: 16),

                    // Health Worker
                    EnrollmentDropdown(
                      label: EnrollmentStrings.healthWorkerLabel,
                      options: EnrollmentStrings.healthWorkerOptions,
                      value: _selectedHealthWorker,
                      onChanged: (v) =>
                          setState(() => _selectedHealthWorker = v),
                      hint: 'Select health worker',
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Village
                    EnrollmentDropdown(
                      label: EnrollmentStrings.villageLabel,
                      options: EnrollmentStrings.villageOptions,
                      value: _selectedVillage,
                      onChanged: (v) => setState(() => _selectedVillage = v),
                      hint: EnrollmentStrings.villageHint,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Household Type
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.householdTypeLabel,
                      options: EnrollmentStrings.householdTypesV2,
                      selectedValue: _householdType,
                      onChanged: (v) => setState(() => _householdType = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Household Number (auto-generated, read-only)
                    if (controller.household != null)
                      EnrollmentInputField(
                        label: EnrollmentStrings.householdNumberLabel,
                        controller: TextEditingController(
                          text: controller.household!.householdNumber,
                        ),
                        readOnly: true,
                        customBorderColor: const Color(0xFFA7F3D0),
                        customFillColor: const Color(0xFFECFDF5),
                        customTextColor: const Color(0xFF059669),
                        labelSuffix: const Text(
                          EnrollmentStrings.autoGeneratedSuffix,
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF059669),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // House Number
                    EnrollmentInputField(
                      label: EnrollmentStrings.houseNumberLabel,
                      hint: EnrollmentStrings.houseNumberHint,
                      controller: _houseNumberCtrl,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Total Household Members
                    EnrollmentInputField(
                      label: EnrollmentStrings.totalMembersLabel,
                      hint: EnrollmentStrings.totalMembersHint,
                      controller: _totalMembersCtrl,
                      keyboardType: TextInputType.number,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Household Head Occupation
                    EnrollmentDropdown(
                      label: EnrollmentStrings.householdHeadOccupationLabel,
                      options: EnrollmentStrings.occupationOptions,
                      value: _selectedOccupation,
                      onChanged: (v) =>
                          setState(() => _selectedOccupation = v),
                      hint: 'Select occupation',
                    ),
                    const SizedBox(height: 16),

                    // Monthly Household Income
                    EnrollmentInputField(
                      label: EnrollmentStrings.monthlyIncomeInputLabel,
                      hint: EnrollmentStrings.monthlyIncomeInputHint,
                      controller: _incomeCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Any person with disability?
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.disabilityAnyPersonLabel,
                      options: EnrollmentStrings.disabilityYesNo,
                      selectedValue: _hasDisability,
                      onChanged: (v) => setState(() => _hasDisability = v),
                    ),

                    // Number of persons with disability (conditional)
                    if (_hasDisability == 'Yes') ...[
                      const SizedBox(height: 16),
                      EnrollmentInputField(
                        label:
                            EnrollmentStrings.disabilityPersonCountLabel,
                        hint: EnrollmentStrings.disabilityPersonCountHint,
                        controller: _disabilityCountCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),

                // ── Sticky bottom CTA ──────────────────────────────────────
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EnrollmentStickyBar(
                    label: EnrollmentStrings.continueArrow,
                    enabled: _isFormComplete,
                    onPressed: () => _handleNext(controller),
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
