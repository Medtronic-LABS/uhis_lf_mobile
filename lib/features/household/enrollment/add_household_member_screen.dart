import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'models/household_enrollment_models.dart';
import 'widgets/enrollment_section_header.dart';
import 'widgets/enrollment_input_field.dart';
import 'widgets/enrollment_segmented_buttons.dart';
import 'widgets/enrollment_button.dart';

/// Screen for adding a new household member.
///
/// Collects member's personal details in 9 steps:
/// NID scan CTA, birth registration, name, DOB picker + approx age, gender,
/// marital status, disability, mobile + checkbox, village input (if external).
class AddHouseholdMemberScreen extends StatefulWidget {
  const AddHouseholdMemberScreen({super.key});

  @override
  State<AddHouseholdMemberScreen> createState() =>
      _AddHouseholdMemberScreenState();
}

class _AddHouseholdMemberScreenState extends State<AddHouseholdMemberScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _idNumberCtrl;
  late TextEditingController _mobileCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _villageCtrl;

  String? _idType = 'NID';
  String? _gender;
  String? _maritalStatus;
  String? _disabilityStatus;
  String? _relationshipToHead;
  bool _mobileAvailable = true;
  bool _isExternalMember = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _idNumberCtrl = TextEditingController();
    _mobileCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();
    _villageCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idNumberCtrl.dispose();
    _mobileCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    _villageCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        _dobCtrl.text = formatted;
        _calculateAge(picked);
      });
    }
  }

  void _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    _ageCtrl.text = age.toString();
  }

  void _handleAddMember(EnrollmentController controller) {
    if (_nameCtrl.text.isEmpty ||
        _idNumberCtrl.text.isEmpty ||
        _dobCtrl.text.isEmpty ||
        _gender == null ||
        _maritalStatus == null ||
        _relationshipToHead == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final member = HouseholdMember(
      name: _nameCtrl.text,
      age: int.tryParse(_ageCtrl.text) ?? 0,
      gender: _gender!,
      dateOfBirth: _dobCtrl.text,
      idType: _idType ?? 'NID',
      idNumber: _idNumberCtrl.text,
      mobileNumber: _mobileAvailable ? _mobileCtrl.text : null,
      mobileAvailable: _mobileAvailable,
      maritalStatus: _maritalStatus!,
      disabilityStatus: _disabilityStatus ?? 'None',
      relationshipToHead: _relationshipToHead!,
      villageId: _isExternalMember ? _villageCtrl.text : null,
    );

    controller.addMember(member);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Member added successfully'),
        duration: Duration(seconds: 2),
      ),
    );

    // Navigate back to success screen
    context.pop();
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
              EnrollmentStrings.addMemberTitle,
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
                  EnrollmentSectionHeader(
                    title: EnrollmentStrings.addMemberTitle,
                    subtitle: 'Add a new member to the household',
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.aiSurfaceStart,
                      borderRadius:
                          BorderRadius.circular(AppRadius.card),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 20,
                          color: AppColors.aiPurple,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                EnrollmentStrings.nidScanCTA,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.aiPurple,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Scan ID to pre-fill fields (optional)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: AppColors.aiPurple,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  EnrollmentInputField(
                    label: EnrollmentStrings.memberNameLabel,
                    hint: EnrollmentStrings.memberNameHint,
                    controller: _nameCtrl,
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _selectDate,
                    child: EnrollmentInputField(
                      label: EnrollmentStrings.dateOfBirthLabel,
                      hint: EnrollmentStrings.dateOfBirthHint,
                      controller: _dobCtrl,
                      isRequired: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  EnrollmentInputField(
                    label: EnrollmentStrings.ageLabel,
                    hint: EnrollmentStrings.approximateAgeHint,
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSegmentedButtons(
                    label: EnrollmentStrings.genderLabel,
                    options: EnrollmentStrings.genders,
                    selectedValue: _gender,
                    onChanged: (value) {
                      setState(() => _gender = value);
                    },
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSegmentedButtons(
                    label: EnrollmentStrings.idTypeLabel,
                    options: EnrollmentStrings.idTypes,
                    selectedValue: _idType,
                    onChanged: (value) {
                      setState(() => _idType = value);
                    },
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentInputField(
                    label: EnrollmentStrings.idNumberLabel,
                    hint: EnrollmentStrings.idNumberHint,
                    controller: _idNumberCtrl,
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSegmentedButtons(
                    label: EnrollmentStrings.maritalStatusLabel,
                    options: EnrollmentStrings.maritalStatuses,
                    selectedValue: _maritalStatus,
                    onChanged: (value) {
                      setState(() => _maritalStatus = value);
                    },
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSegmentedButtons(
                    label: EnrollmentStrings.disabilityStatusLabel,
                    options: EnrollmentStrings.disabilityStatuses,
                    selectedValue: _disabilityStatus,
                    onChanged: (value) {
                      setState(() => _disabilityStatus = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSegmentedButtons(
                    label: 'Relationship to Head',
                    options: EnrollmentStrings.relationships,
                    selectedValue: _relationshipToHead,
                    onChanged: (value) {
                      setState(() => _relationshipToHead = value);
                    },
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _mobileAvailable,
                        onChanged: (value) {
                          setState(() => _mobileAvailable = value ?? true);
                        },
                        activeColor: AppColors.navy,
                      ),
                      Expanded(
                        child: Text(
                          EnrollmentStrings.mobileNumberLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_mobileAvailable) ...[
                    const SizedBox(height: 8),
                    EnrollmentInputField(
                      label: EnrollmentStrings.mobileNumberLabel,
                      hint: EnrollmentStrings.mobileNumberHint,
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _isExternalMember,
                        onChanged: (value) {
                          setState(() => _isExternalMember = value ?? false);
                        },
                        activeColor: AppColors.navy,
                      ),
                      Expanded(
                        child: const Text(
                          'From different village?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isExternalMember) ...[
                    const SizedBox(height: 8),
                    EnrollmentInputField(
                      label: EnrollmentStrings.memberVillageLabel,
                      hint: EnrollmentStrings.memberVillageHint,
                      controller: _villageCtrl,
                    ),
                  ],
                  const SizedBox(height: 32),
                  EnrollmentButton(
                    label: 'Add Member',
                    onPressed: () => _handleAddMember(controller),
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
