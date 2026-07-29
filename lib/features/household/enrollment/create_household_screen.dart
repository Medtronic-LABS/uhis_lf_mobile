import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/user_hierarchy_service.dart';
import '../../../core/db/member_dao.dart';
import '../../../core/debug/console_log.dart';
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
  late TextEditingController _idNumberCtrl;
  late TextEditingController _mobileCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _ageCtrl;

  String? _idType = 'BRN';
  String? _gender;
  String? _maritalStatus;
  String? _disabilityStatus;
  bool _prefilledFromScan = false;

  // ── Validation ──────────────────────────────────────────────────────────────
  final Map<String, GlobalKey> _fieldKeys = {};
  Map<String, String?> _fieldErrors = {};

  static const _validationOrder = [
    'ssWorker', 'village', 'householdType', 'totalMembers',
    'headName', 'idNumber', 'mobile', 'dob', 'gender', 'maritalStatus',
  ];

  GlobalKey _key(String name) =>
      _fieldKeys.putIfAbsent(name, GlobalKey.new);

  void _clearError(String name) {
    if (_fieldErrors[name] != null) setState(() => _fieldErrors.remove(name));
  }

  Map<String, String?> _runValidation() {
    const req = 'Required';
    return {
      if (_selectedSsWorker == null) 'ssWorker': req,
      if (_selectedVillage == null) 'village': req,
      if (_householdType == null) 'householdType': req,
      if (_totalMembersCtrl.text.trim().isEmpty) 'totalMembers': req,
      if (_nameCtrl.text.trim().isEmpty) 'headName': req,
      if (_idNumberCtrl.text.trim().isEmpty) 'idNumber': req,
      if (_mobileCtrl.text.trim().isEmpty) 'mobile': req,
      if (_dobCtrl.text.trim().isEmpty) 'dob': 'Date of birth required',
      if (_gender == null) 'gender': req,
      if (_maritalStatus == null) 'maritalStatus': req,
    };
  }

  void _scrollToFirstError() {
    for (final k in _validationOrder) {
      if (_fieldErrors[k] != null) {
        final ctx = _fieldKeys[k]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.15,
          );
        }
        return;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[_CreateHouseholdScreenState] initState');

    // Household controllers
    _totalMembersCtrl = TextEditingController();
    _incomeCtrl = TextEditingController();
    _disabilityCountCtrl = TextEditingController();

    // Head controllers
    _nameCtrl = TextEditingController();
    _idNumberCtrl = TextEditingController();
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

        // Ensure static-data has been fetched before reading the lists.
        // prefetch() is a no-op if already loaded; safe to await here.
        await hierarchy.prefetch();
        if (!mounted) return;

        final userId = await auth.userId();
        if (!mounted) return;
        final villages = hierarchy.villages ?? [];
        final subVillages = hierarchy.subVillages ?? [];

        final firstVillage = villages.isNotEmpty ? villages.first : null;
        // Prefer the first sub-village that belongs to the chosen village;
        // fall back to the global first only if none map to it.
        final matchingSubs = firstVillage == null
            ? subVillages
            : subVillages
                .where((sv) => sv.villageId == firstVillage.id)
                .toList();
        final firstSubVillage = matchingSubs.isNotEmpty
            ? matchingSubs.first
            : (subVillages.isNotEmpty ? subVillages.first : null);

        if (!mounted) return;
        // Auto-select first SS worker from the SK's assigned SS list.
        final ssWorkers = hierarchy.ssWorkers ?? [];
        final firstSs = ssWorkers.isNotEmpty ? ssWorkers.first : null;
        // The SS worker's own sub-villages are the authoritative pull scope;
        // prefer them over the village-filtered top-level list.
        final ssSeedSub = (firstSs != null && firstSs.subVillages.isNotEmpty)
            ? firstSs.subVillages.first
            : firstSubVillage;
        setState(() {
          _selectedSsWorker = firstSs;
          // Seed the dropdown selections so a valid village + sub-village are
          // sent even when the SK does not manually change them.
          _selectedVillage = firstVillage;
          _selectedSubVillage = ssSeedSub;
        });
        await controller.initializeHousehold(
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
    debugPrint('[_CreateHouseholdScreenState] dispose');
    _totalMembersCtrl.dispose();
    _incomeCtrl.dispose();
    _disabilityCountCtrl.dispose();
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
        _fieldErrors.remove('dob');
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

  Future<void> _handleContinue(EnrollmentController controller) async {
    final errors = _runValidation();
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      _scrollToFirstError();
      return;
    }
    setState(() => _fieldErrors = {});
    debugPrint('[_CreateHouseholdScreenState] _handleContinue householdType=$_householdType ssWorker=${_selectedSsWorker?.id} village=${_selectedVillage?.id} fromNidScan=${widget.fromNidScan}');
    // Guarantee a valid sub-village even if the SK never opened the dropdown.
    // Android scopes member/assessment sync to sub-village IDs, so a household
    // enrolled with an empty sub-village (→ 0) is invisible in the Spice app.
    if (_selectedSubVillage == null) {
      // Prefer the selected SS worker's caseload sub-villages (== pull scope),
      // then fall back to the village-filtered top-level list.
      final ssSubs = _selectedSsWorker?.subVillages ?? const [];
      if (ssSubs.isNotEmpty) {
        _selectedSubVillage = ssSubs.first;
      } else if (_selectedVillage != null) {
        final hierarchy = context.read<UserHierarchyService>();
        final subs = (hierarchy.subVillages ?? [])
            .where((sv) => sv.villageId == _selectedVillage!.id)
            .toList();
        if (subs.isNotEmpty) _selectedSubVillage = subs.first;
      }
    }

    // Keep the village hierarchy internally consistent: when the chosen
    // sub-village (which drives Android's pull scope) declares its own parent
    // village, use that as the household villageId rather than the separately
    // displayed village dropdown, which may not be the sub-village's parent.
    final effectiveVillageId =
        (_selectedSubVillage?.villageId?.isNotEmpty == true)
            ? _selectedSubVillage!.villageId
            : _selectedVillage?.id;

    // Update both sections in the controller
    controller.updateHousehold(
      healthWorkerId: _selectedSsWorker?.id,
      householdType: _householdType ?? '',
      numberOfMembers: int.tryParse(_totalMembersCtrl.text) ?? 0,
      houseNumber: '',
      occupation: _selectedOccupation ?? '',
      monthlyIncome: _incomeCtrl.text.isEmpty ? '0' : _incomeCtrl.text,
      disabilityQuestion: _hasDisability == 'Yes',
      disabilityDetails:
          _hasDisability == 'Yes' ? _disabilityCountCtrl.text : null,
      villageId: effectiveVillageId,
      villageName: _selectedVillage?.name,
      subVillageId: _selectedSubVillage?.id ?? '',
      subVillageName: _selectedSubVillage?.name ?? '',
    );

    controller.updateHead(
      name: _nameCtrl.text,
      age: int.tryParse(_ageCtrl.text) ?? 0,
      gender: _gender!,
      dateOfBirth: _dobCtrl.text,
      idType: _idType ?? 'BRN',
      idNumber: _idNumberCtrl.text,
      mobileNumber: _mobileCtrl.text,
      mobileAvailable: true,
      maritalStatus: _maritalStatus!,
      disabilityStatus: _disabilityStatus ?? 'Absent',
      nidScanned: widget.fromNidScan && _prefilledFromScan,
    );

    final controllerErrors = [
      ...controller.validateHouseholdForm(),
      ...controller.validateHeadForm(),
    ];
    if (controllerErrors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controllerErrors.first),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Dedup check: warn if head's NID already exists in local members table.
    final headNid = _idNumberCtrl.text.trim();
    if (headNid.isNotEmpty) {
      final existing =
          await context.read<MemberDao>().getByNationalId(headNid);
      if (existing != null && mounted) {
        ConsoleLog.warn(
            '[Enrollment] possible duplicate head, existing FHIR id: ${existing.fhirId}');
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dlgCtx) => AlertDialog(
            title: Text(EnrollmentStrings.duplicateTitle),
            content: Text(
              '${EnrollmentStrings.duplicateBody}\n\n${existing.name ?? headNid}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(false),
                child: Text(EnrollmentStrings.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dlgCtx).pop(false);
                  context.push('/patients/${existing.id}');
                },
                child: Text(EnrollmentStrings.duplicateViewRecord),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dlgCtx).pop(true),
                child: Text(EnrollmentStrings.duplicateContinue),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
    }

    if (mounted) context.push('/household/enrollment/success');
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
                fontFamily: AppFonts.display,
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

                    SizedBox(key: _key('ssWorker'), height: 0),
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
                          final ssSubs = ss.subVillages;
                          setState(() {
                            _selectedSsWorker = ss;
                            if (ssSubs.isNotEmpty) {
                              _selectedSubVillage = ssSubs.first;
                            }
                            _fieldErrors.remove('ssWorker');
                          });
                        },
                        hint: EnrollmentStrings.healthWorkerHint,
                        isRequired: true,
                        errorText: _fieldErrors['ssWorker'],
                      );
                    }),
                    const SizedBox(height: 14),

                    SizedBox(key: _key('village'), height: 0),
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
                          final subs = (hierarchy.subVillages ?? [])
                              .where((sv) => sv.villageId == village.id)
                              .toList();
                          setState(() {
                            _selectedVillage = village;
                            _selectedSubVillage =
                                subs.isNotEmpty ? subs.first : null;
                            _fieldErrors.remove('village');
                          });
                        },
                        hint: EnrollmentStrings.villageHint,
                        isRequired: true,
                        errorText: _fieldErrors['village'],
                      );
                    }),
                    const SizedBox(height: 14),
                    Builder(builder: (context) {
                      final hierarchy =
                          context.watch<UserHierarchyService>();
                      // Prefer the selected SS worker's assigned sub-villages —
                      // those IDs are exactly the SK's sync pull scope. Only
                      // fall back to the village-filtered top-level list when
                      // the SS carries none.
                      final ssSubs = _selectedSsWorker?.subVillages ?? const [];
                      final allSubVillages = hierarchy.subVillages ?? [];
                      final List<SubVillageRef> subVillages = ssSubs.isNotEmpty
                          ? ssSubs
                          : (_selectedVillage == null
                              ? allSubVillages
                              : allSubVillages
                                  .where((sv) =>
                                      sv.villageId == _selectedVillage!.id)
                                  .toList());
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

                    SizedBox(key: _key('householdType'), height: 0),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.householdTypeLabel,
                      options: EnrollmentStrings.householdTypesV2,
                      selectedValue: _householdType,
                      onChanged: (v) => setState(() {
                        _householdType = v;
                        _fieldErrors.remove('householdType');
                      }),
                      isRequired: true,
                      errorText: _fieldErrors['householdType'],
                    ),
                    const SizedBox(height: 14),

                    SizedBox(key: _key('totalMembers'), height: 0),
                    EnrollmentInputField(
                      label: EnrollmentStrings.totalMembersLabel,
                      hint: EnrollmentStrings.totalMembersHint,
                      controller: _totalMembersCtrl,
                      keyboardType: TextInputType.number,
                      isRequired: true,
                      onChanged: (_) => _clearError('totalMembers'),
                      errorText: _fieldErrors['totalMembers'],
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

                    // Scanned NID editable card
                    if (_prefilledFromScan) ...[
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.tbSurface,
                          border: Border.all(color: AppColors.statusSuccessBorder),
                          borderRadius: BorderRadius.circular(AppRadius.field),
                        ),
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.auto_awesome, size: 14, color: AppColors.statusSuccessAction),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Scanned from NID — edit if needed',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.statusSuccessActionDark,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() => _prefilledFromScan = false),
                                  child: const Text(
                                    'Clear',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.statusCritical,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            EnrollmentInputField(
                              label: EnrollmentStrings.idNumberLabel,
                              hint: EnrollmentStrings.idNumberHint,
                              controller: _idNumberCtrl,
                              onChanged: (_) => _clearError('idNumber'),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(key: _key('headName'), height: 0),
                            EnrollmentInputField(
                              label: EnrollmentStrings.headNameLabel,
                              hint: EnrollmentStrings.headNameHint,
                              controller: _nameCtrl,
                              isRequired: true,
                              onChanged: (_) => _clearError('headName'),
                              errorText: _fieldErrors['headName'],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(key: _key('dob'), height: 0),
                            GestureDetector(
                              onTap: _selectDate,
                              child: AbsorbPointer(
                                child: EnrollmentInputField(
                                  label: EnrollmentStrings.dateOfBirthLabel,
                                  hint: EnrollmentStrings.dateOfBirthHint,
                                  controller: _dobCtrl,
                                  readOnly: true,
                                  errorText: _fieldErrors['dob'],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Name field — shown only when not pre-filled from scan
                    if (!_prefilledFromScan) ...[
                      SizedBox(key: _key('headName'), height: 0),
                      EnrollmentInputField(
                        label: EnrollmentStrings.headNameLabel,
                        hint: EnrollmentStrings.headNameHint,
                        controller: _nameCtrl,
                        isRequired: true,
                        onChanged: (_) => _clearError('headName'),
                        errorText: _fieldErrors['headName'],
                      ),
                      const SizedBox(height: 14),
                    ],

                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.idTypeLabel,
                      options: EnrollmentStrings.idTypesV2,
                      selectedValue: _idType,
                      onChanged: (v) => setState(() => _idType = v),
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),

                    if (!_prefilledFromScan) ...[
                      SizedBox(key: _key('idNumber'), height: 0),
                      EnrollmentInputField(
                        label: EnrollmentStrings.idNumberLabel,
                        hint: EnrollmentStrings.idNumberHint,
                        controller: _idNumberCtrl,
                        isRequired: true,
                        onChanged: (_) => _clearError('idNumber'),
                        errorText: _fieldErrors['idNumber'],
                      ),
                      const SizedBox(height: 14),
                    ],

                    SizedBox(key: _key('mobile'), height: 0),
                    EnrollmentInputField(
                      label: EnrollmentStrings.mobileNumberLabel,
                      hint: EnrollmentStrings.mobileNumberHint,
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      isRequired: true,
                      onChanged: (_) => _clearError('mobile'),
                      errorText: _fieldErrors['mobile'],
                      inputFormatters: [LengthLimitingTextInputFormatter(14)],
                    ),
                    const SizedBox(height: 14),

                    // Date of Birth — hidden when pre-filled from scan (card has it)
                    if (!_prefilledFromScan) ...[
                      SizedBox(key: _key('dob'), height: 0),
                      GestureDetector(
                        onTap: _selectDate,
                        child: AbsorbPointer(
                          child: EnrollmentInputField(
                            label: EnrollmentStrings.dateOfBirthLabel,
                            hint: EnrollmentStrings.dateOfBirthHint,
                            controller: _dobCtrl,
                            readOnly: true,
                            errorText: _fieldErrors['dob'],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    EnrollmentInputField(
                      label: EnrollmentStrings.ageLabel,
                      hint: EnrollmentStrings.ageHint,
                      controller: _ageCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),

                    SizedBox(key: _key('gender'), height: 0),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.genderLabel,
                      options: EnrollmentStrings.gendersHead,
                      selectedValue: _gender,
                      onChanged: (v) => setState(() {
                        _gender = v;
                        _fieldErrors.remove('gender');
                      }),
                      isRequired: true,
                      errorText: _fieldErrors['gender'],
                    ),
                    const SizedBox(height: 14),

                    SizedBox(key: _key('maritalStatus'), height: 0),
                    EnrollmentDropdown(
                      label: EnrollmentStrings.maritalStatusLabel,
                      options: EnrollmentStrings.maritalStatusesV2,
                      value: _maritalStatus,
                      onChanged: (v) => setState(() {
                        _maritalStatus = v;
                        _fieldErrors.remove('maritalStatus');
                      }),
                      hint: 'Select status',
                      isRequired: true,
                      errorText: _fieldErrors['maritalStatus'],
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
