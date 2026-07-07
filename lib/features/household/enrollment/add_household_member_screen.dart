import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_repository.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'enrollment_entry_sheet.dart';
import 'nid_ocr_service.dart';
import 'patient_lookup_repository.dart';
import 'models/household_enrollment_models.dart';
import 'widgets/enrollment_input_field.dart';
import 'widgets/enrollment_segmented_buttons.dart';
import 'widgets/enrollment_dropdown.dart';
import 'widgets/enrollment_sticky_bar.dart';

/// Screen for adding a new household member.
///
/// Redesigned with numbered questions (Q1–Q9), sticky bottom CTA.
/// NID scan is a purple gradient CTA button; after mock scan a green
/// confirmation chip appears and name/DOB/gender fields are auto-filled.
class AddHouseholdMemberScreen extends StatefulWidget {
  const AddHouseholdMemberScreen({super.key});

  @override
  State<AddHouseholdMemberScreen> createState() =>
      _AddHouseholdMemberScreenState();
}

class _AddHouseholdMemberScreenState extends State<AddHouseholdMemberScreen> {
  late TextEditingController _brnCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _mobileCtrl;
  late TextEditingController _villageCtrl;


  String? _gender;
  String? _maritalStatus;
  String? _disabilityStatus = 'Absent';
  bool _mobileNotAvailable = false;
  bool _nidScanned = false;

  /// Set when the scanned NID matches a patient already registered on the
  /// server — surfaces a de-duplication banner and loads authoritative details.
  Patient? _existingPatient;

  @override
  void initState() {
    super.initState();
    _brnCtrl = TextEditingController();
    _nameCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();
    _mobileCtrl = TextEditingController();
    _villageCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _brnCtrl.dispose();
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    _mobileCtrl.dispose();
    _villageCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _scanNid() async {
    final result = await showNidScannerForMember(context);
    if (!mounted || result == null) return;

    switch (result.status) {
      case NidScanStatus.success:
        final data = result.data!;
        setState(() {
          _nidScanned = true;
          _existingPatient = null;
          if (data.nidNumber != null) _brnCtrl.text = data.nidNumber!;
          if (data.name != null) _nameCtrl.text = data.name!;
          final dob = data.dateOfBirth;
          if (dob != null) {
            _dobCtrl.text = dob;
            final parsed = DateTime.tryParse(dob);
            if (parsed != null) _calculateAge(parsed);
          }
        });
        final nid = data.nidNumber;
        if (nid != null) await _lookupExisting(nid);
      case NidScanStatus.notFound:
        _showSnack(EnrollmentStrings.nidScanNotFound);
      case NidScanStatus.error:
        _showSnack(EnrollmentStrings.nidScanError);
      case NidScanStatus.cancelled:
        break;
    }
  }

  /// Best-effort remote lookup: if the scanned NID is already registered, load
  /// the server's demographics over the OCR values (authoritative) and flag the
  /// duplicate. Offline / transport failures degrade silently to OCR-only.
  Future<void> _lookupExisting(String nid) async {
    final repo = context.read<PatientLookupRepository>();
    try {
      final patient = await repo.lookupByNid(nid);
      if (!mounted || patient == null) return;
      setState(() {
        _existingPatient = patient;
        final name = patient.name;
        if (name != null && name.isNotEmpty) _nameCtrl.text = name;
        final dob = patient.dob;
        if (dob != null && dob.isNotEmpty) {
          _dobCtrl.text = dob;
          final parsed = DateTime.tryParse(dob);
          if (parsed != null) _calculateAge(parsed);
        }
        _gender = _matchGender(patient.gender) ?? _gender;
        final phone = patient.phone;
        if (phone != null && phone.isNotEmpty) {
          _mobileCtrl.text = phone;
          _mobileNotAvailable = false;
        }
      });
    } on DioException catch (_) {
      // Offline or transport error — keep OCR values, no user-facing error.
    } on ApiException catch (e) {
      debugPrint('Add member: patient lookup failed: $e');
    }
  }

  /// Map a server gender string onto one of the segmented-button options,
  /// case-insensitively. Returns null when it doesn't match so the control is
  /// left untouched rather than desynced.
  String? _matchGender(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final g in EnrollmentStrings.gendersMember) {
      if (g.toLowerCase() == raw.toLowerCase()) return g;
    }
    return null;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _handleSaveMember(EnrollmentController controller) {
    if (_nameCtrl.text.isEmpty || _gender == null || _maritalStatus == null) {
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
      idType: _nidScanned ? 'NID' : 'BRN',
      idNumber: _brnCtrl.text.isNotEmpty ? _brnCtrl.text : null,
      mobileNumber: _mobileNotAvailable ? null : _mobileCtrl.text,
      mobileAvailable: !_mobileNotAvailable,
      maritalStatus: _maritalStatus!,
      disabilityStatus: _disabilityStatus ?? 'Absent',
      relationshipToHead: 'Other',
      villageId:
          _villageCtrl.text.isNotEmpty ? _villageCtrl.text : null,
      nidScanned: _nidScanned,
    );

    controller.addMember(member);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Member added successfully'),
        duration: Duration(seconds: 2),
      ),
    );

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnrollmentController>(
      builder: (context, controller, child) {
        final hhNumber = controller.household?.householdNumber ?? '';

        return Scaffold(
          backgroundColor: AppColors.pageBackground,
          appBar: AppBar(
            backgroundColor: AppColors.navy,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Member',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (hhNumber.isNotEmpty)
                  Text(
                    '${EnrollmentStrings.addMemberSubtitle} $hhNumber',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.h5xl,
                    AppSpacing.h5xl,
                    AppSpacing.h5xl,
                    AppSpacing.stickyBarClearance,
                  ),
                  children: [
                    // ── Q1: National ID ────────────────────────────────────
                    _QuestionLabel(number: 'Q1', text: 'National ID'),
                    const SizedBox(height: 10),

                    // NID scan purple CTA
                    Material(
                      borderRadius: BorderRadius.circular(AppRadius.patRow),
                      child: InkWell(
                        onTap: _scanNid,
                        borderRadius: BorderRadius.circular(AppRadius.patRow),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.aiPurple,
                                AppColors.aiPurpleLight,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.patRow),
                          ),
                          child: SizedBox(
                            height: 52,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ...[
                                  const Icon(
                                    Icons.qr_code_scanner,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    EnrollmentStrings.nidScanButtonLabel,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // NID scanned confirmation chip
                    if (_nidScanned) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tbSurface,
                          border: Border.all(color: AppColors.enrollmentSuccess),
                          borderRadius: BorderRadius.circular(AppRadius.field),
                        ),
                        child: Text(
                          EnrollmentStrings.nidDetailsCaptured(_brnCtrl.text),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.enrollmentSuccess,
                          ),
                        ),
                      ),
                    ],

                    // Existing-registration de-duplication banner
                    if (_existingPatient != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.childSurface,
                          border: Border.all(color: AppColors.infoAccent),
                          borderRadius: BorderRadius.circular(AppRadius.field),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              size: 16,
                              color: AppColors.infoAccentDark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    EnrollmentStrings.existingPatientLoaded(
                                      _existingPatient?.name ?? '',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.infoAccentDark,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    EnrollmentStrings.existingPatientHint,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.infoAccentDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),

                    // NID fallback note
                    Text(
                      EnrollmentStrings.nidScanNoBrnHint,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // BRN input (optional)
                    EnrollmentInputField(
                      label: 'Birth Registration Number (BRN)',
                      hint: 'Enter BRN if no NID',
                      controller: _brnCtrl,
                    ),
                    const SizedBox(height: 20),

                    // ── Q2: Name ───────────────────────────────────────────
                    _QuestionLabel(number: 'Q2', text: 'Name'),
                    const SizedBox(height: 10),
                    EnrollmentInputField(
                      label: EnrollmentStrings.memberNameLabel,
                      hint: EnrollmentStrings.memberNameHint,
                      controller: _nameCtrl,
                      isRequired: true,
                    ),
                    const SizedBox(height: 20),

                    // ── Q3: Date of Birth ──────────────────────────────────
                    _QuestionLabel(number: 'Q3', text: 'Date of Birth'),
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 8),
                    Text(
                      EnrollmentStrings.dobHelperText,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Approximate Age
                    EnrollmentInputField(
                      label: EnrollmentStrings.approximateAgeLabel,
                      hint: EnrollmentStrings.approximateAgeHint,
                      controller: _ageCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 20),

                    // ── Q4: Gender ─────────────────────────────────────────
                    _QuestionLabel(number: 'Q4', text: 'Gender'),
                    const SizedBox(height: 10),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.genderLabel,
                      options: EnrollmentStrings.gendersMember,
                      selectedValue: _gender,
                      onChanged: (v) => setState(() => _gender = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 20),

                    // ── Q6: Marital Status ─────────────────────────────────
                    _QuestionLabel(number: 'Q6', text: 'Marital Status'),
                    const SizedBox(height: 10),
                    EnrollmentDropdown(
                      label: EnrollmentStrings.maritalStatusLabel,
                      options: EnrollmentStrings.maritalStatusesV2,
                      value: _maritalStatus,
                      onChanged: (v) =>
                          setState(() => _maritalStatus = v),
                      hint: 'Select status',
                    ),
                    const SizedBox(height: 20),

                    // ── Q7: Disability ─────────────────────────────────────
                    _QuestionLabel(number: 'Q7', text: 'Disability'),
                    const SizedBox(height: 10),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.disabilityStatusLabel,
                      options: EnrollmentStrings.disabilityStatusesV2,
                      selectedValue: _disabilityStatus,
                      onChanged: (v) =>
                          setState(() => _disabilityStatus = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 20),

                    // ── Q8: Mobile Number ──────────────────────────────────
                    _QuestionLabel(number: 'Q8', text: 'Mobile Number'),
                    const SizedBox(height: 10),
                    if (!_mobileNotAvailable) ...[
                      EnrollmentInputField(
                        label: EnrollmentStrings.mobileNumberLabel,
                        hint: EnrollmentStrings.mobileNumberHint,
                        controller: _mobileCtrl,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 6),
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
                        const SizedBox(width: 8),
                        Text(
                          EnrollmentStrings.otpHelperText,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Q9: Village Name ───────────────────────────────────
                    _QuestionLabel(number: 'Q9', text: 'Village Name'),
                    const SizedBox(height: 10),
                    EnrollmentInputField(
                      label: EnrollmentStrings.memberVillageLabel,
                      hint: EnrollmentStrings.villageMemberHint,
                      controller: _villageCtrl,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      EnrollmentStrings.villageHelperText,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
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
                    label: EnrollmentStrings.saveMemberCTA,
                    onPressed: () => _handleSaveMember(controller),
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

/// Numbered question label prefix (e.g. "Q1 National ID").
class _QuestionLabel extends StatelessWidget {
  const _QuestionLabel({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
