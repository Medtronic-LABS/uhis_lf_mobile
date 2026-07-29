import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_repository.dart';
import '../../../core/db/member_dao.dart';
import '../../../core/debug/console_log.dart';
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
enum _DuplicateAction { viewRecord, continueAnyway, cancel }

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


  String? _gender;
  String? _maritalStatus;
  String? _disabilityStatus = 'Absent';
  bool _nidScanned = false;
  String _idType = 'BRN';
  String? _ageSummary;
  String? _guardianName;

  /// Age in whole years — used for validation and the `age` field sent to the
  /// server. Distinct from [_ageCtrl] which shows the most human-meaningful
  /// unit (months for babies < 1 year, days for newborns).
  int _ageInYears = 0;

  /// Unit label shown next to the age field after DOB auto-fill.
  /// Empty for manual entry (user implies years).
  String _ageUnit = '';

  final Map<String, GlobalKey> _fieldKeys = {};
  Map<String, String?> _fieldErrors = {};

  static const _validationOrder = ['name', 'dob', 'gender', 'maritalStatus', 'guardian', 'mobile'];

  GlobalKey _key(String name) =>
      _fieldKeys.putIfAbsent(name, GlobalKey.new);

  void _clearError(String name) {
    if (_fieldErrors[name] != null) setState(() => _fieldErrors.remove(name));
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

  static String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return null;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return 'Invalid phone number';
    if (RegExp(r'(\d)\1{4,}').hasMatch(digits)) return 'Invalid phone number';
    return null;
  }

  /// Set when the scanned NID matches a patient already registered on the
  /// server — surfaces a de-duplication banner and loads authoritative details.
  Patient? _existingPatient;

  @override
  void initState() {
    debugPrint('[_AddHouseholdMemberScreenState] initState');
    super.initState();
    _brnCtrl = TextEditingController();
    _nameCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();
    _mobileCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final headMobile = context.read<EnrollmentController>().householdHead?.mobileNumber;
      if (headMobile != null && headMobile.isNotEmpty) {
        setState(() => _mobileCtrl.text = headMobile);
      }
    });
  }

  @override
  void dispose() {
    debugPrint('[_AddHouseholdMemberScreenState] dispose');
    _brnCtrl.dispose();
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _ageCtrl.dispose();
    _mobileCtrl.dispose();
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

    int years = now.year - dob.year;
    int months = now.month - dob.month;
    int days = now.day - dob.day;

    if (days < 0) {
      months--;
      days += DateTime(now.year, now.month, 0).day;
    }
    if (months < 0) {
      years--;
      months += 12;
    }

    _ageInYears = years;

    // Mirror Android getAgeOrDobDisplay: show years ≥1, else months, else days.
    if (years >= 1) {
      _ageCtrl.text = years.toString();
      _ageUnit = years == 1 ? 'year' : 'years';
      _ageSummary = months > 0
          ? '$years yr ${months}m old'
          : '$years year${years == 1 ? '' : 's'} old';
    } else if (months > 0) {
      _ageCtrl.text = months.toString();
      _ageUnit = months == 1 ? 'month' : 'months';
      _ageSummary = '$months month${months == 1 ? '' : 's'} old';
    } else {
      final d = days < 1 ? 1 : days;
      _ageCtrl.text = d.toString();
      _ageUnit = d == 1 ? 'day' : 'days';
      _ageSummary = days < 1 ? '< 1 day old' : '$days days old';
    }

    if (years <= 5) _maritalStatus = null;
  }

  Future<void> _scanNid() async {
    debugPrint('[_AddHouseholdMemberScreenState] _scanNid');
    final result = await showNidScannerForMember(context);
    if (!mounted || result == null) return;

    switch (result.status) {
      case NidScanStatus.success:
        final data = result.data!;
        setState(() {
          _nidScanned = true;
          _idType = 'National ID';
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
        break;
      case NidScanStatus.error:
        break;
      case NidScanStatus.cancelled:
        break;
      case NidScanStatus.skipped:
        // SK chose manual entry — leave all fields blank for hand-fill.
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

  Future<void> _handleSaveMember(EnrollmentController controller) async {
    debugPrint('[_AddHouseholdMemberScreenState] _handleSaveMember name=${_nameCtrl.text} gender=$_gender maritalStatus=$_maritalStatus');
    final maritalRequired = _ageInYears > 5;

    final errors = <String, String?>{
      if (_nameCtrl.text.trim().isEmpty) 'name': 'Required',
      if (_dobCtrl.text.trim().isEmpty) 'dob': 'Required',
      if (_gender == null) 'gender': 'Required',
      if (maritalRequired && _maritalStatus == null) 'maritalStatus': 'Required',
      if (_ageInYears < 1 && _guardianName == null) 'guardian': 'Required',
    };
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      _scrollToFirstError();
      return;
    }
    setState(() => _fieldErrors = {});

    final nid = _brnCtrl.text.trim();
    if (nid.isNotEmpty) {
      final existing =
          await context.read<MemberDao>().getByNationalId(nid);
      if (existing != null && mounted) {
        ConsoleLog.warn(
            '[Enrollment] possible duplicate, existing FHIR id: ${existing.fhirId}');
        final action = await _showDuplicateDialog(
          existingId: existing.id,
          existingName: existing.name ?? nid,
        );
        if (!mounted) return;
        if (action == _DuplicateAction.cancel) return;
      }
    }

    final mobile = _mobileCtrl.text.trim();
    final member = HouseholdMember(
      name: _nameCtrl.text,
      age: _ageInYears,
      gender: _gender!,
      dateOfBirth: _dobCtrl.text,
      idType: _idType == 'National ID' ? 'NID' : _idType,
      idNumber: _idType == 'Not Available' ? null : (nid.isNotEmpty ? nid : null),
      mobileNumber: mobile.isNotEmpty ? mobile : null,
      mobileAvailable: mobile.isNotEmpty,
      maritalStatus: _maritalStatus ?? '',
      disabilityStatus: _disabilityStatus ?? 'Absent',
      relationshipToHead: 'Other',
      villageId: controller.household?.subVillageId?.isNotEmpty == true
          ? controller.household!.subVillageId
          : controller.household?.villageId,
      nidScanned: _nidScanned,
      guardianName: _guardianName,
    );

    controller.addMember(member);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Member added successfully'),
        duration: Duration(seconds: 2),
      ),
    );

    context.pop();
  }

  Future<_DuplicateAction> _showDuplicateDialog({
    required String existingId,
    required String existingName,
  }) async {
    final result = await showDialog<_DuplicateAction>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(EnrollmentStrings.duplicateTitle),
        content: Text(
          '${EnrollmentStrings.duplicateBody}\n\n$existingName',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dlgCtx).pop(_DuplicateAction.viewRecord),
            child: Text(EnrollmentStrings.duplicateViewRecord),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dlgCtx).pop(_DuplicateAction.continueAnyway),
            child: Text(EnrollmentStrings.duplicateContinue),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dlgCtx).pop(_DuplicateAction.cancel),
            child: Text(EnrollmentStrings.cancel),
          ),
        ],
      ),
    );
    if (result == _DuplicateAction.viewRecord && mounted) {
      context.push('/patients/$existingId');
    }
    return result ?? _DuplicateAction.cancel;
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
                    // ── Q1: ID Type ────────────────────────────────────────
                    _QuestionLabel(number: 'Q1', text: 'ID Type'),
                    const SizedBox(height: 10),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.idTypeLabel,
                      options: EnrollmentStrings.idTypesV2,
                      selectedValue: _idType,
                      allowDeselect: false,
                      onChanged: (v) => setState(() {
                        _idType = v ?? 'BRN';
                        if (_idType != 'National ID') {
                          _nidScanned = false;
                          _brnCtrl.clear();
                          _existingPatient = null;
                        }
                      }),
                    ),
                    const SizedBox(height: 14),

                    // NID scan purple CTA — shown only for National ID
                    if (_idType == 'National ID') ...[
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
                                  Text(
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

                    // NID scan editable card — shown when scan succeeded so SK
                    // can correct OCR errors without rescanning.
                    if (_nidScanned) ...[
                      const SizedBox(height: 10),
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
                                  onTap: () => setState(() {
                                    _nidScanned = false;
                                    _brnCtrl.clear();
                                    _existingPatient = null;
                                  }),
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
                              label: EnrollmentStrings.nidNumberLabel,
                              hint: EnrollmentStrings.nidNumberHint,
                              controller: _brnCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                if (value.length >= 10) _lookupExisting(value);
                              },
                            ),
                            const SizedBox(height: 10),
                            EnrollmentInputField(
                              label: EnrollmentStrings.memberNameLabel,
                              hint: EnrollmentStrings.memberNameHint,
                              controller: _nameCtrl,
                              isRequired: true,
                              onChanged: (_) => _clearError('name'),
                              errorText: _fieldErrors['name'],
                            ),
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
                          ],
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
                                  Text(
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
                    ], // end National ID section

                    // BRN field — shown only when ID type is BRN
                    if (_idType == 'BRN') ...[
                      EnrollmentInputField(
                        label: 'Birth Registration Number (BRN)',
                        hint: 'Enter BRN',
                        controller: _brnCtrl,
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 20),

                    // ── Q2: Name — hidden when NID scanned (card has it) ──
                    if (!_nidScanned) ...[
                      SizedBox(key: _key('name'), height: 0),
                      _QuestionLabel(number: 'Q2', text: 'Name'),
                      const SizedBox(height: 10),
                      EnrollmentInputField(
                        label: EnrollmentStrings.memberNameLabel,
                        hint: EnrollmentStrings.memberNameHint,
                        controller: _nameCtrl,
                        isRequired: true,
                        onChanged: (_) => _clearError('name'),
                        errorText: _fieldErrors['name'],
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_nidScanned) const SizedBox(height: 20),

                    // ── Q3: Date of Birth — hidden when NID scanned (card has it) ──
                    if (!_nidScanned) ...[
                      SizedBox(key: _key('dob'), height: 0),
                      _QuestionLabel(number: 'Q3', text: 'Date of Birth'),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          _clearError('dob');
                          _selectDate();
                        },
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
                      const SizedBox(height: 8),
                      Text(
                        EnrollmentStrings.dobHelperText,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Approximate Age
                    EnrollmentInputField(
                      label: EnrollmentStrings.approximateAgeLabel,
                      hint: EnrollmentStrings.approximateAgeHint,
                      controller: _ageCtrl,
                      keyboardType: TextInputType.number,
                      labelSuffix: _ageUnit.isNotEmpty
                          ? Text(
                              '($_ageUnit)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            )
                          : null,
                      onChanged: (v) => setState(() {
                        _ageSummary = null;
                        _ageUnit = '';
                        final years = int.tryParse(v) ?? 99;
                        _ageInYears = years;
                        if (years <= 5) _maritalStatus = null;
                        if (years >= 1) _guardianName = null;
                      }),
                    ),
                    if (_ageSummary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _ageSummary!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.enrollmentSuccess,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ── Q4: Gender ─────────────────────────────────────────
                    SizedBox(key: _key('gender'), height: 0),
                    _QuestionLabel(number: 'Q4', text: 'Gender'),
                    const SizedBox(height: 10),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.genderLabel,
                      options: EnrollmentStrings.gendersMember,
                      selectedValue: _gender,
                      onChanged: (v) => setState(() {
                        _gender = v;
                        _fieldErrors.remove('gender');
                      }),
                      isRequired: true,
                      errorText: _fieldErrors['gender'],
                    ),
                    const SizedBox(height: 20),

                    // ── Q6: Marital Status — hidden for age ≤ 5 ───────────
                    if ((int.tryParse(_ageCtrl.text) ?? 99) > 5) ...[
                      SizedBox(key: _key('maritalStatus'), height: 0),
                      _QuestionLabel(number: 'Q6', text: 'Marital Status'),
                      const SizedBox(height: 10),
                      EnrollmentDropdown(
                        label: EnrollmentStrings.maritalStatusLabel,
                        options: EnrollmentStrings.maritalStatusesV2,
                        value: _maritalStatus,
                        onChanged: (v) => setState(() {
                          _maritalStatus = v;
                          _fieldErrors.remove('maritalStatus');
                        }),
                        hint: 'Select status',
                        errorText: _fieldErrors['maritalStatus'],
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Guardian — required for members under 18 ──────────
                    if ((int.tryParse(_ageCtrl.text) ?? 99) < 1) ...[
                      SizedBox(key: _key('guardian'), height: 0),
                      _QuestionLabel(number: 'Q7', text: 'Guardian'),
                      const SizedBox(height: 10),
                      Consumer<EnrollmentController>(
                        builder: (context, ctrl, _) {
                          final guardianOptions = [
                            if (ctrl.householdHead?.name != null)
                              ctrl.householdHead!.name,
                            ...ctrl.members.map((m) => m.name),
                          ];
                          return EnrollmentDropdown(
                            label: EnrollmentStrings.guardianLabel,
                            options: guardianOptions,
                            value: _guardianName,
                            onChanged: (v) => setState(() {
                              _guardianName = v;
                              _fieldErrors.remove('guardian');
                            }),
                            hint: EnrollmentStrings.guardianHint,
                            isRequired: true,
                            errorText: _fieldErrors['guardian'],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Q8: Disability ─────────────────────────────────────
                    _QuestionLabel(number: 'Q8', text: 'Disability'),
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
                    SizedBox(key: _key('mobile'), height: 0),
                    _QuestionLabel(number: 'Q8', text: 'Mobile Number'),
                    const SizedBox(height: 10),
                    EnrollmentInputField(
                      label: EnrollmentStrings.mobileNumberLabel,
                      hint: EnrollmentStrings.mobileNumberHint,
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                      onChanged: (_) => _clearError('mobile'),
                      errorText: _fieldErrors['mobile'],
                      inputFormatters: [LengthLimitingTextInputFormatter(14)],
                    ),
                    const SizedBox(height: 20),

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
