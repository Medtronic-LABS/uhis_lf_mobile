import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'widgets/enrollment_section_header.dart';
import 'widgets/enrollment_input_field.dart';
import 'widgets/enrollment_segmented_buttons.dart';
import 'widgets/enrollment_button.dart';

/// Step 2 of household enrollment: household head information.
///
/// Collects head's personal details (name, age, DOB, gender, marital status,
/// disability, contact info). Pre-fills from NID scan if available. Validates
/// on blur and navigates to success screen or add member flow.
class HouseholdHeadInfoScreen extends StatefulWidget {
  const HouseholdHeadInfoScreen({super.key});

  @override
  State<HouseholdHeadInfoScreen> createState() =>
      _HouseholdHeadInfoScreenState();
}

class _HouseholdHeadInfoScreenState extends State<HouseholdHeadInfoScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _idNumberCtrl;
  late TextEditingController _mobileCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _ageCtrl;

  String? _idType = 'NID';
  String? _gender;
  String? _maritalStatus;
  String? _disabilityStatus;
  bool _mobileAvailable = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _idNumberCtrl = TextEditingController();
    _mobileCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();

    // Pre-fill from NID scan if available
    final controller = context.read<EnrollmentController>();
    if (controller.nidScanResult != null) {
      final scan = controller.nidScanResult!;
      _nameCtrl.text = scan['name'] ?? '';
      _idNumberCtrl.text = scan['idNumber'] ?? '';
      if (scan['dateOfBirth'] != null) {
        _dobCtrl.text = scan['dateOfBirth'];
      }
      if (scan['gender'] != null) {
        _gender = scan['gender'];
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idNumberCtrl.dispose();
    _mobileCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
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

  void _handleNext(EnrollmentController controller) {
    if (_nameCtrl.text.isEmpty ||
        _idNumberCtrl.text.isEmpty ||
        _dobCtrl.text.isEmpty ||
        _gender == null ||
        _maritalStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    controller.updateHead(
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
    );

    // Navigate to success screen with option to add more members
    context.push('/household/enrollment/success');
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
              EnrollmentStrings.householdHeadTitle,
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
                    EnrollmentStrings.householdHeadSubtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  EnrollmentSectionHeader(
                    title: EnrollmentStrings.householdHeadTitle,
                    subtitle: 'Information about the household head',
                  ),
                  const SizedBox(height: 20),
                  EnrollmentInputField(
                    label: EnrollmentStrings.headNameLabel,
                    hint: EnrollmentStrings.headNameHint,
                    controller: _nameCtrl,
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
                    hint: EnrollmentStrings.ageHint,
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
