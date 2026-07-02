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
import 'widgets/enrollment_dropdown.dart';
import 'widgets/enrollment_sticky_bar.dart';

/// Step 2 of household enrollment: household head information.
///
/// Redesigned layout: navy AppBar, scrollable body with sticky bottom CTA.
/// Collects head's name, ID type/number, mobile (with "Not Available" toggle),
/// DOB (date picker), age (auto-calculated), gender, marital status, disability.
class HouseholdHeadInfoScreen extends StatefulWidget {
  const HouseholdHeadInfoScreen({
    super.key,
    this.fromNidScan = false,
    this.scannedNidNumber,
    this.scannedName,
    this.scannedDateOfBirth,
  });

  final bool fromNidScan;

  /// Fields read on-device from the entry-overlay NID card scan, if any.
  final String? scannedNidNumber;
  final String? scannedName;
  final String? scannedDateOfBirth;

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

  String? _idType = 'BRN';
  String? _gender;
  String? _maritalStatus;
  String? _disabilityStatus;
  bool _mobileNotAvailable = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _idNumberCtrl = TextEditingController();
    _mobileCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();

    // Rebuild the CTA enabled-state as the required text fields change.
    _nameCtrl.addListener(_onFormChanged);
    _idNumberCtrl.addListener(_onFormChanged);

    // Prefill from the on-device NID card scan. Name / DOB / NID are read from
    // the Latin side of the card; father & mother (Bangla) stay for the SK.
    if (widget.fromNidScan) {
      if (widget.scannedNidNumber?.isNotEmpty ?? false) {
        _idNumberCtrl.text = widget.scannedNidNumber!;
        _idType = 'National ID';
        _prefilledFromScan = true;
      }
      if (widget.scannedName?.isNotEmpty ?? false) {
        _nameCtrl.text = widget.scannedName!;
        _prefilledFromScan = true;
      }
      final dob = widget.scannedDateOfBirth;
      if (dob != null && dob.isNotEmpty) {
        _dobCtrl.text = dob;
        final parsed = DateTime.tryParse(dob);
        if (parsed != null) _calculateAge(parsed);
        _prefilledFromScan = true;
      }
    }
  }

  bool _prefilledFromScan = false;

  @override
  void dispose() {
    _nameCtrl.removeListener(_onFormChanged);
    _idNumberCtrl.removeListener(_onFormChanged);
    _nameCtrl.dispose();
    _idNumberCtrl.dispose();
    _mobileCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  /// Mandatory head fields (spec: keep CTA disabled until all present).
  bool get _isFormComplete =>
      _nameCtrl.text.trim().isNotEmpty &&
      _idNumberCtrl.text.trim().isNotEmpty &&
      _gender != null &&
      _maritalStatus != null;

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.navy,
              onPrimary: Colors.white,
              surface: AppColors.cardSurface,
            ),
          ),
          child: child!,
        );
      },
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
      idType: _idType ?? 'BRN',
      idNumber: _idNumberCtrl.text,
      mobileNumber: _mobileNotAvailable ? null : _mobileCtrl.text,
      mobileAvailable: !_mobileNotAvailable,
      maritalStatus: _maritalStatus!,
      disabilityStatus: _disabilityStatus ?? 'Absent',
    );

    context.push('/household/enrollment/success');
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
              'Household Head',
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
                    // ── Section header ─────────────────────────────────────
                    const EnrollmentSectionHeader(
                      title:
                          EnrollmentStrings.householdHeadSectionHeader,
                    ),
                    const SizedBox(height: 20),

                    // Auto-filled-from-scan banner
                    if (_prefilledFromScan) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 15,
                              color: Color(0xFF059669),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                EnrollmentStrings.headPrefilledFromScan,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Household Head's Name
                    EnrollmentInputField(
                      label: EnrollmentStrings.headNameLabel,
                      hint: EnrollmentStrings.headNameHint,
                      controller: _nameCtrl,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // ID Type
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.idTypeLabel,
                      options: EnrollmentStrings.idTypesV2,
                      selectedValue: _idType,
                      onChanged: (v) => setState(() => _idType = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // ID Number
                    EnrollmentInputField(
                      label: EnrollmentStrings.idNumberLabel,
                      hint: EnrollmentStrings.idNumberHint,
                      controller: _idNumberCtrl,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Mobile Number + Not Available checkbox
                    if (!_mobileNotAvailable) ...[
                      EnrollmentInputField(
                        label: EnrollmentStrings.mobileNumberLabel,
                        hint: EnrollmentStrings.mobileNumberHint,
                        controller: _mobileCtrl,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _mobileNotAvailable,
                            onChanged: (v) => setState(
                              () => _mobileNotAvailable = v ?? false,
                            ),
                            activeColor: AppColors.navy,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          EnrollmentStrings.mobileNotAvailableHint,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Date of Birth (date picker)
                    GestureDetector(
                      onTap: _selectDate,
                      child: AbsorbPointer(
                        child: EnrollmentInputField(
                          label: EnrollmentStrings.dateOfBirthLabel,
                          hint: EnrollmentStrings.dateOfBirthHint,
                          controller: _dobCtrl,
                          readOnly: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Age (auto-calculated from DOB, manually editable)
                    EnrollmentInputField(
                      label: EnrollmentStrings.ageLabel,
                      hint: EnrollmentStrings.ageHint,
                      controller: _ageCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Gender
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.genderLabel,
                      options: EnrollmentStrings.gendersHead,
                      selectedValue: _gender,
                      onChanged: (v) => setState(() => _gender = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Marital Status
                    EnrollmentDropdown(
                      label: EnrollmentStrings.maritalStatusLabel,
                      options: EnrollmentStrings.maritalStatusesV2,
                      value: _maritalStatus,
                      onChanged: (v) => setState(() => _maritalStatus = v),
                      hint: 'Select status',
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),

                    // Disability
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.disabilityStatusLabel,
                      options: EnrollmentStrings.disabilityStatusesV2,
                      selectedValue: _disabilityStatus,
                      onChanged: (v) =>
                          setState(() => _disabilityStatus = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),

                // ── Sticky bottom CTA ──────────────────────────────────────
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EnrollmentStickyBar(
                    label: EnrollmentStrings.createHouseholdCTA,
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
