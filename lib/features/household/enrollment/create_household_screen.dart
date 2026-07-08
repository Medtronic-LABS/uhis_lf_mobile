import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

/// Combined household + head enrollment form.
///
/// Merges the former Step 1 (household info) and Step 2 (household head info)
/// into a single scrollable screen. On "Continue" both sections are validated
/// and the controller is updated before navigating to the success/review screen.
class CreateHouseholdScreen extends StatefulWidget {
  const CreateHouseholdScreen({
    super.key,
    this.fromNidScan = false,
    this.scannedNidNumber,
    this.scannedName,
    this.scannedDateOfBirth,
  });

  final bool fromNidScan;
  final String? scannedNidNumber;
  final String? scannedName;
  final String? scannedDateOfBirth;

  @override
  State<CreateHouseholdScreen> createState() => _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends State<CreateHouseholdScreen> {
  // ── Household fields ────────────────────────────────────────────────────────
  late TextEditingController _houseNumberCtrl;
  late TextEditingController _totalMembersCtrl;
  late TextEditingController _incomeCtrl;
  late TextEditingController _disabilityCountCtrl;

  SsWorker? _selectedSsWorker;
  VillageRef? _selectedVillage;
  SubVillageRef? _selectedSubVillage;
  String? _householdType;
  String? _selectedOccupation;
  String _hasDisability = 'No';

  // ── Head fields ─────────────────────────────────────────────────────────────
  late TextEditingController _nameCtrl;
  late TextEditingController _fatherCtrl;
  late TextEditingController _motherCtrl;
  late TextEditingController _idNumberCtrl;
  late TextEditingController _mobileCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _ageCtrl;

  String? _idType = 'BRN';
  String? _gender;
  String? _maritalStatus;
  String? _disabilityStatus;
  bool _mobileNotAvailable = false;
  bool _prefilledFromScan = false;

  @override
  void initState() {
    super.initState();

    // Household controllers
    _houseNumberCtrl = TextEditingController()..addListener(_onFormChanged);
    _totalMembersCtrl = TextEditingController()..addListener(_onFormChanged);
    _incomeCtrl = TextEditingController();
    _disabilityCountCtrl = TextEditingController();

    // Head controllers
    _nameCtrl = TextEditingController()..addListener(_onFormChanged);
    _fatherCtrl = TextEditingController();
    _motherCtrl = TextEditingController();
    _idNumberCtrl = TextEditingController()..addListener(_onFormChanged);
    _mobileCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();

    // Pre-fill head from NID scan
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

    // Initialise the household controller after first build
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
        // Auto-select first SS worker from the SK's assigned SS list.
        final ssWorkers = hierarchy.ssWorkers ?? [];
        setState(() {
          _selectedSsWorker = ssWorkers.isNotEmpty ? ssWorkers.first : null;
        });
        controller.initializeHousehold(
          healthWorkerId: _selectedSsWorker?.id ?? userId?.toString() ?? '',
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
    _houseNumberCtrl
      ..removeListener(_onFormChanged)
      ..dispose();
    _totalMembersCtrl
      ..removeListener(_onFormChanged)
      ..dispose();
    _incomeCtrl.dispose();
    _disabilityCountCtrl.dispose();
    _nameCtrl
      ..removeListener(_onFormChanged)
      ..dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _idNumberCtrl
      ..removeListener(_onFormChanged)
      ..dispose();
    _mobileCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  void _onFormChanged() => setState(() {});

  bool get _isFormComplete =>
      // Household required
      _selectedSsWorker != null &&
      _selectedVillage != null &&
      _householdType != null &&
      _houseNumberCtrl.text.trim().isNotEmpty &&
      _totalMembersCtrl.text.trim().isNotEmpty &&
      // Head required
      _nameCtrl.text.trim().isNotEmpty &&
      _idNumberCtrl.text.trim().isNotEmpty &&
      _gender != null &&
      _maritalStatus != null &&
      _dobCtrl.text.trim().isNotEmpty;

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.navy,
            onPrimary: Colors.white,
            surface: AppColors.cardSurface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dobCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
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

  void _handleContinue(EnrollmentController controller) {
    // Update both sections in the controller
    controller.updateHousehold(
      healthWorkerId: _selectedSsWorker?.id,
      householdType: _householdType ?? '',
      numberOfMembers: int.tryParse(_totalMembersCtrl.text) ?? 0,
      houseNumber: _houseNumberCtrl.text,
      occupation: _selectedOccupation ?? '',
      monthlyIncome: _incomeCtrl.text.isEmpty ? '0' : _incomeCtrl.text,
      disabilityQuestion: _hasDisability == 'Yes',
      disabilityDetails:
          _hasDisability == 'Yes' ? _disabilityCountCtrl.text : null,
      villageId: _selectedVillage?.id,
      villageName: _selectedVillage?.name,
      subVillageId: _selectedSubVillage?.id ?? '',
      subVillageName: _selectedSubVillage?.name ?? '',
    );

    controller.updateHead(
      name: _nameCtrl.text,
      fatherName: _fatherCtrl.text.trim().isEmpty ? null : _fatherCtrl.text,
      motherName: _motherCtrl.text.trim().isEmpty ? null : _motherCtrl.text,
      age: int.tryParse(_ageCtrl.text) ?? 0,
      gender: _gender!,
      dateOfBirth: _dobCtrl.text,
      idType: _idType ?? 'BRN',
      idNumber: _idNumberCtrl.text,
      mobileNumber: _mobileNotAvailable ? null : _mobileCtrl.text,
      mobileAvailable: !_mobileNotAvailable,
      maritalStatus: _maritalStatus!,
      disabilityStatus: _disabilityStatus ?? 'Absent',
      nidScanned: widget.fromNidScan && _prefilledFromScan,
    );

    final errors = [
      ...controller.validateHouseholdForm(),
      ...controller.validateHeadForm(),
    ];
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.first),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    context.push('/household/enrollment/success');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EnrollmentController>(
      builder: (context, controller, _) {
        return Scaffold(
          backgroundColor: AppColors.pageBackground,
          appBar: AppBar(
            backgroundColor: AppColors.navy,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text(
              'Enroll Household',
              style: TextStyle(
                fontFamily: 'Nunito',
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.h5xl,
                    AppSpacing.xxxl,
                    AppSpacing.h5xl,
                    AppSpacing.stickyBarClearance,
                  ),
                  children: [
                    // ── Section 1: Household Information ───────────────────
                    const EnrollmentSectionHeader(
                      title: EnrollmentStrings.householdInfoSectionHeader,
                    ),
                    const SizedBox(height: 16),

                    Builder(builder: (context) {
                      final hierarchy =
                          context.watch<UserHierarchyService>();
                      final ssWorkers = hierarchy.ssWorkers ?? [];
                      return EnrollmentDropdown(
                        label: EnrollmentStrings.healthWorkerLabel,
                        options: ssWorkers.map((s) => s.name).toList(),
                        value: _selectedSsWorker?.name,
                        onChanged: (name) {
                          final ss = ssWorkers.firstWhere(
                            (s) => s.name == name,
                            orElse: () => ssWorkers.first,
                          );
                          setState(() => _selectedSsWorker = ss);
                        },
                        hint: EnrollmentStrings.healthWorkerHint,
                        isRequired: true,
                      );
                    }),
                    const SizedBox(height: 14),

                    Builder(builder: (context) {
                      final hierarchy =
                          context.watch<UserHierarchyService>();
                      final villages = hierarchy.villages ?? [];
                      return EnrollmentDropdown(
                        label: EnrollmentStrings.villageLabel,
                        options: villages.map((v) => v.name).toList(),
                        value: _selectedVillage?.name,
                        onChanged: (name) {
                          final village = villages.firstWhere(
                            (v) => v.name == name,
                            orElse: () => villages.first,
                          );
                          setState(() {
                            _selectedVillage = village;
                            _selectedSubVillage = null;
                          });
                        },
                        hint: EnrollmentStrings.villageHint,
                        isRequired: true,
                      );
                    }),
                    const SizedBox(height: 14),
                    Builder(builder: (context) {
                      final hierarchy =
                          context.watch<UserHierarchyService>();
                      final allSubVillages = hierarchy.subVillages ?? [];
                      final subVillages = _selectedVillage == null
                          ? allSubVillages
                          : allSubVillages
                              .where((sv) =>
                                  sv.villageId == _selectedVillage!.id)
                              .toList();
                      if (subVillages.isEmpty) return const SizedBox.shrink();
                      return Column(
                        children: [
                          EnrollmentDropdown(
                            label: EnrollmentStrings.subVillageLabel,
                            options:
                                subVillages.map((sv) => sv.name).toList(),
                            value: _selectedSubVillage?.name,
                            onChanged: (name) {
                              setState(() {
                                _selectedSubVillage = subVillages.firstWhere(
                                  (sv) => sv.name == name,
                                  orElse: () => subVillages.first,
                                );
                              });
                            },
                            hint: EnrollmentStrings.subVillageHint,
                          ),
                          const SizedBox(height: 14),
                        ],
                      );
                    }),

                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.householdTypeLabel,
                      options: EnrollmentStrings.householdTypesV2,
                      selectedValue: _householdType,
                      onChanged: (v) => setState(() => _householdType = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

                    if (controller.household != null)
                      EnrollmentInputField(
                        label: EnrollmentStrings.householdNumberLabel,
                        controller: TextEditingController(
                          text: controller.household!.householdNumber,
                        ),
                        readOnly: true,
                        customBorderColor: AppColors.statusSuccessBorder,
                        customFillColor: AppColors.tbSurface,
                        customTextColor: AppColors.statusSuccessAction,
                        labelSuffix: const Text(
                          EnrollmentStrings.autoGeneratedSuffix,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.statusSuccessAction,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),

                    EnrollmentInputField(
                      label: EnrollmentStrings.houseNumberLabel,
                      hint: EnrollmentStrings.houseNumberHint,
                      controller: _houseNumberCtrl,
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

                    EnrollmentInputField(
                      label: EnrollmentStrings.totalMembersLabel,
                      hint: EnrollmentStrings.totalMembersHint,
                      controller: _totalMembersCtrl,
                      keyboardType: TextInputType.number,
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

                    EnrollmentDropdown(
                      label: EnrollmentStrings.householdHeadOccupationLabel,
                      options: EnrollmentStrings.occupationOptions,
                      value: _selectedOccupation,
                      onChanged: (v) =>
                          setState(() => _selectedOccupation = v),
                      hint: 'Select occupation',
                    ),
                    const SizedBox(height: 14),

                    EnrollmentInputField(
                      label: EnrollmentStrings.monthlyIncomeInputLabel,
                      hint: EnrollmentStrings.monthlyIncomeInputHint,
                      controller: _incomeCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),

                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.disabilityAnyPersonLabel,
                      options: EnrollmentStrings.disabilityYesNo,
                      selectedValue: _hasDisability,
                      onChanged: (v) => setState(() => _hasDisability = v),
                    ),

                    if (_hasDisability == 'Yes') ...[
                      const SizedBox(height: 14),
                      EnrollmentInputField(
                        label: EnrollmentStrings.disabilityPersonCountLabel,
                        hint: EnrollmentStrings.disabilityPersonCountHint,
                        controller: _disabilityCountCtrl,
                        keyboardType: TextInputType.number,
                      ),
                    ],

                    // ── Divider ────────────────────────────────────────────
                    const SizedBox(height: 28),
                    Container(
                      height: 1,
                      color: AppColors.border,
                    ),
                    const SizedBox(height: 24),

                    // ── Section 2: Household Head ──────────────────────────
                    const EnrollmentSectionHeader(
                      title: EnrollmentStrings.householdHeadSectionHeader,
                    ),
                    const SizedBox(height: 16),

                    // NID scan pre-fill banner
                    if (_prefilledFromScan) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tbSurface,
                          border:
                              Border.all(color: AppColors.statusSuccessBorder),
                          borderRadius: BorderRadius.circular(AppRadius.field),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 15,
                              color: AppColors.statusSuccessAction,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                EnrollmentStrings.headPrefilledFromScan,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.statusSuccessActionDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    EnrollmentInputField(
                      label: EnrollmentStrings.headNameLabel,
                      hint: EnrollmentStrings.headNameHint,
                      controller: _nameCtrl,
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: EnrollmentInputField(
                            label: EnrollmentStrings.fatherNameLabel,
                            hint: 'Father\'s name',
                            controller: _fatherCtrl,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: EnrollmentInputField(
                            label: EnrollmentStrings.motherNameLabel,
                            hint: 'Mother\'s name',
                            controller: _motherCtrl,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.idTypeLabel,
                      options: EnrollmentStrings.idTypesV2,
                      selectedValue: _idType,
                      onChanged: (v) => setState(() => _idType = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

                    EnrollmentInputField(
                      label: EnrollmentStrings.idNumberLabel,
                      hint: EnrollmentStrings.idNumberHint,
                      controller: _idNumberCtrl,
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

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
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
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
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: EnrollmentInputField(
                            label: EnrollmentStrings.ageLabel,
                            hint: EnrollmentStrings.ageHint,
                            controller: _ageCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.genderLabel,
                      options: EnrollmentStrings.gendersHead,
                      selectedValue: _gender,
                      onChanged: (v) => setState(() => _gender = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

                    EnrollmentDropdown(
                      label: EnrollmentStrings.maritalStatusLabel,
                      options: EnrollmentStrings.maritalStatusesV2,
                      value: _maritalStatus,
                      onChanged: (v) => setState(() => _maritalStatus = v),
                      hint: 'Select status',
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

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

                // ── Sticky CTA ─────────────────────────────────────────────
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: EnrollmentStickyBar(
                    label: EnrollmentStrings.continueArrow,
                    enabled: _isFormComplete,
                    onPressed: () => _handleContinue(controller),
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
