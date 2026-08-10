import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_repository.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/user_hierarchy_service.dart';
import '../../../core/db/household_dao.dart';
import '../../../core/db/member_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/db/roster_revision.dart';
import '../../../core/debug/console_log.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_strings.dart';
import 'enrollment_controller.dart';
import 'enrollment_dob.dart';
import 'enrollment_entry_sheet.dart';
import 'enrollment_id_number.dart';
import 'enrollment_mobile_number.dart';
import 'enrollment_repository.dart';
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

/// Spice `MemberRegistration.ADD_GUARDIAN_ID` (-2).
const _addGuardianOptionId = '-2';

class _GuardianOption {
  const _GuardianOption({
    required this.id,
    required this.name,
    this.fhirId,
  });

  final String id;
  final String name;
  final String? fhirId;
}

/// Redesigned with numbered questions (Q1–Q9), sticky bottom CTA.
/// NID scan is a purple gradient CTA button; after mock scan a green
/// confirmation chip appears and name/DOB/gender fields are auto-filled.
class AddHouseholdMemberScreen extends StatefulWidget {
  const AddHouseholdMemberScreen({
    super.key,
    this.existingHouseholdId,
    this.existingHouseholdReferenceId,
    this.existingVillageId,
    this.existingVillageName,
    this.existingSubVillageId,
    this.existingSubVillageName,
    this.fromNidScan = false,
    this.scannedNidNumber,
    this.scannedName,
    this.scannedDateOfBirth,
    this.initialMemberNames = const [],
  });

  /// When non-null, the screen operates in standalone mode: submits the member
  /// directly to [EnrollmentRepository.submitStandaloneMember] instead of
  /// adding to the enrollment controller's pending batch.
  final String? existingHouseholdId;
  final String? existingHouseholdReferenceId;

  /// Parent village of the household — distinct from [existingSubVillageId].
  /// spice-service resolves the hierarchy from both, so they must never carry
  /// the same id.
  final String? existingVillageId;
  final String? existingVillageName;
  final String? existingSubVillageId;
  final String? existingSubVillageName;

  final bool fromNidScan;
  final String? scannedNidNumber;
  final String? scannedName;
  final String? scannedDateOfBirth;

  /// Pre-populated member names from the caller (e.g. household detail screen).
  /// When non-empty, skips the DB query in [_loadHouseholdMembers].
  final List<String> initialMemberNames;

  bool get isStandalone => existingHouseholdId != null;

  @override
  State<AddHouseholdMemberScreen> createState() =>
      _AddHouseholdMemberScreenState();
}

/// Pushes an already-persisted member and stamps the result on its local row.
///
/// Deliberately free of any `State` / `BuildContext`: it outlives the screen,
/// which pops as soon as the local write lands. Every failure is swallowed and
/// left as a pending sync status — the member is already on disk, so a network
/// problem must never look like a failed save.
Future<void> _pushMemberInBackground({
  required EnrollmentRepository repo,
  required MemberDao memberDao,
  required HouseholdMember member,
  required String memberLocalId,
  required String householdFhirId,
  required String householdReferenceId,
  required String villageId,
  required String villageName,
  required String? subVillageId,
  required String? subVillageName,
  required int userId,
  required String userFhirId,
  required String organizationId,
  required String deviceId,
}) async {
  try {
    final result = await repo.submitStandaloneMember(
      member: member,
      householdId: householdFhirId,
      householdReferenceId: householdReferenceId,
      villageName: villageName,
      villageId: villageId,
      subVillageId: subVillageId,
      subVillageName: subVillageName,
      userId: userId,
      userFhirId: userFhirId,
      organizationId: organizationId,
      deviceId: deviceId,
      memberReferenceId: memberLocalId,
    );
    // Accepted by the server — park it so an Offline Sync started while we are
    // still polling cannot post the same member a second time.
    // resetStuckInProgress puts it back in the queue if status never lands.
    await memberDao.updateSyncStatus([memberLocalId], 'InProgress');
    // Without this the row stays unstamped forever, and the next Offline Sync
    // would post the same member again.
    await repo.pollAndApplyFhirIds(
      requestId: result.requestId,
      deviceId: deviceId,
      userId: userId,
      memberDao: memberDao,
    );
    debugPrint('[AddMember] background push done localId=$memberLocalId');
  } on DioException catch (e) {
    final isNetwork = e.response == null ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
    await memberDao.updateSyncStatus(
      [memberLocalId],
      isNetwork ? 'NetworkError' : 'NotSynced',
    );
    debugPrint('[AddMember] background push failed (${e.type}) — '
        'member $memberLocalId queued for retry');
  } on SocketException {
    await memberDao.updateSyncStatus([memberLocalId], 'NetworkError');
    debugPrint('[AddMember] offline — member $memberLocalId queued for retry');
  } catch (e) {
    await memberDao.updateSyncStatus([memberLocalId], 'NotSynced');
    debugPrint('[AddMember] background push error: $e');
  }
}

class _AddHouseholdMemberScreenState extends State<AddHouseholdMemberScreen> {
  late TextEditingController _brnCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _mobileCtrl;


  /// Parsed date of birth. [_dobCtrl] holds its DD-MM-YYYY rendering; the
  /// model and payload get [EnrollmentDob.wire].
  DateTime? _dob;
  String? _gender;
  String? _phoneCategory;

  /// Household head's mobile — used when phone category is
  /// "Head of Household". Loaded from the enrollment controller (new HH)
  /// or MemberDao (standalone link-member).
  String? _headMobileNumber;
  String? _maritalStatus;
  String? _disabilityStatus;
  bool _nidScanned = false;
  String? _idType;
  String? _ageSummary;

  /// Selected guardian member id (local PK in standalone, client UUID in batch).
  /// Spice stores Long `guardianId` — never a display name.
  String? _guardianId;

  /// Eligible guardians (age > 10) for the Spice guardian spinner.
  List<_GuardianOption> _guardianOptions = [];

  /// Age in whole years — used for validation and the `age` field sent to the
  /// server. Distinct from [_ageCtrl] which shows the most human-meaningful
  /// unit (months for babies < 1 year, days for newborns).
  int _ageInYears = 0;

  bool get _needsGuardian =>
      EnrollmentDob.needsGuardian(_dob, ageYears: _ageInYears);

  bool get _needsMaritalStatus =>
      EnrollmentDob.needsMaritalStatus(_dob, ageYears: _ageInYears);

  /// Unit label shown next to the age field after DOB auto-fill.
  /// Empty for manual entry (user implies years).
  String _ageUnit = '';

  bool _submitting = false;

  final Map<String, GlobalKey> _fieldKeys = {};
  Map<String, String?> _fieldErrors = {};

  static const _validationOrder = [
    'name', 'idType', 'idNumber', 'phoneCategory', 'mobile', 'dob', 'gender',
    'maritalStatus', 'guardian', 'disability',
  ];

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

  /// Set when the scanned NID matches a patient already registered on the
  /// server — surfaces a de-duplication banner and loads authoritative details.
  Patient? _existingPatient;

  @override
  void initState() {
    debugPrint('[_AddHouseholdMemberScreenState] initState standalone=${widget.isStandalone}');
    super.initState();
    _brnCtrl = TextEditingController();
    _nameCtrl = TextEditingController();
    _dobCtrl = TextEditingController();
    _ageCtrl = TextEditingController();
    _mobileCtrl = TextEditingController();

    // Pre-fill from NID scan when navigated here with scan data.
    if (widget.fromNidScan) {
      if (widget.scannedNidNumber?.isNotEmpty ?? false) {
        _brnCtrl.text = widget.scannedNidNumber!;
        _idType = 'National ID';
      }
      if (widget.scannedName?.isNotEmpty ?? false) {
        _nameCtrl.text = widget.scannedName!;
      }
      _applyDateOfBirth(EnrollmentDob.parse(widget.scannedDateOfBirth));
    }

    // Seed guardian candidates + resolve the household head's mobile so the
    // "Head of Household" phone-category option can autofill it.
    if (widget.isStandalone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHouseholdMembers());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctrl = context.read<EnrollmentController>();
        final head = ctrl.householdHead;
        final mobile = head?.mobileNumber?.trim();
        setState(() {
          if (mobile != null && mobile.isNotEmpty) {
            _headMobileNumber = mobile;
          }
          _guardianOptions = _batchGuardianOptions(ctrl);
        });
      });
    }
  }

  /// Spice `getOtherHouseholdExcludeTBPatient`: active HH members with age > 10.
  List<_GuardianOption> _batchGuardianOptions(EnrollmentController ctrl) {
    final options = <_GuardianOption>[];
    void consider(HouseholdMember? m) {
      if (m == null) return;
      final name = m.name.trim();
      final id = m.id?.trim() ?? '';
      if (name.isEmpty || id.isEmpty) return;
      final dob = EnrollmentDob.parse(m.dateOfBirth);
      if (!EnrollmentDob.isEligibleGuardian(dob, ageYears: m.age)) return;
      options.add(_GuardianOption(id: id, name: name));
    }

    consider(ctrl.householdHead);
    for (final m in ctrl.members) {
      consider(m);
    }
    return options;
  }

  Future<void> _loadHouseholdMembers() async {
    final hhId = widget.existingHouseholdId;
    if (hhId == null || !mounted) return;
    final dao = context.read<MemberDao>();
    // Try household_id first, then householdReferenceId as fallback (UUID vs FHIR ID).
    var entities = await dao.getByHouseholdId(hhId);
    if (entities.isEmpty && widget.existingHouseholdReferenceId != null &&
        widget.existingHouseholdReferenceId != hhId) {
      entities = await dao.getByHouseholdId(widget.existingHouseholdReferenceId!);
    }
    if (!mounted) return;

    final options = <_GuardianOption>[];
    String? headMobile;
    for (final e in entities) {
      if (!e.isActive) continue;
      final name = e.name?.trim() ?? '';
      if (name.isEmpty) continue;
      final dob = EnrollmentDob.parse(e.dob);
      // Age unknown from DOB alone falls through as ineligible (matches SQL
      // requiring a DOB older than 10 years).
      if (!EnrollmentDob.isEligibleGuardian(dob)) continue;
      options.add(_GuardianOption(
        id: e.id,
        name: name,
        fhirId: e.fhirId,
      ));
      if (e.isHouseholdHead) {
        final phone = e.phone?.trim();
        if (phone != null && phone.isNotEmpty) headMobile = phone;
      }
    }

    setState(() {
      _guardianOptions = options;
      if (headMobile != null) _headMobileNumber = headMobile;
    });
  }

  List<String> get _guardianDropdownIds => [
        ..._guardianOptions.map((o) => o.id),
        _addGuardianOptionId,
      ];

  String _guardianOptionLabel(String id) {
    if (id == _addGuardianOptionId) return EnrollmentStrings.addGuardian;
    for (final o in _guardianOptions) {
      if (o.id == id) return o.name;
    }
    return id;
  }

  String? _guardianFhirIdFor(String? id) {
    if (id == null) return null;
    for (final o in _guardianOptions) {
      if (o.id == id) return o.fhirId;
    }
    return null;
  }

  Future<void> _onGuardianChanged(String? value) async {
    if (value == _addGuardianOptionId) {
      // Do not keep ADD_GUARDIAN_ID selected — Spice rejects id < 0 on submit.
      setState(() {
        _guardianId = null;
        _fieldErrors.remove('guardian');
      });
      // DropdownButton pops its menu route after onChanged. Showing a dialog
      // in the same frame lets that pop dismiss the dialog immediately.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_handleAddGuardian());
      });
      return;
    }
    setState(() {
      _guardianId = value;
      _fieldErrors.remove('guardian');
    });
  }

  /// Spice `handleAddGuardian`: confirm leave (unsaved data lost) → open
  /// member registration for the same household.
  Future<void> _handleAddGuardian() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(EnrollmentStrings.alertTitle),
        content: Text(EnrollmentStrings.exitReason),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(false),
            child: Text(EnrollmentStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dlgCtx).pop(true),
            child: Text(OfflineSyncStrings.okay),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    // Unique formInstanceId forces a fresh MaterialPage (new State) so the
    // child form is discarded and a blank Add Member opens — same household.
    final formInstanceId = DateTime.now().microsecondsSinceEpoch.toString();
    if (widget.isStandalone) {
      final extra = <String, dynamic>{
        'householdId': widget.existingHouseholdId,
        'householdReferenceId':
            widget.existingHouseholdReferenceId ?? widget.existingHouseholdId,
        'villageId': widget.existingVillageId,
        'villageName': widget.existingVillageName,
        'subVillageId': widget.existingSubVillageId,
        'subVillageName': widget.existingSubVillageName,
        'formInstanceId': formInstanceId,
      };
      context.pushReplacement('/household/enrollment/link-member', extra: extra);
    } else {
      context.pushReplacement(
        '/household/enrollment/add-member',
        extra: <String, dynamic>{'formInstanceId': formInstanceId},
      );
    }
  }

  /// Spice: picking "Head of Household" copies the head's number; any other
  /// category clears the field so the SK enters a fresh number.
  void _onPhoneCategoryChanged(String? category) {
    setState(() {
      _phoneCategory = category;
      _fieldErrors.remove('phoneCategory');
      if (category == 'Head of Household') {
        _mobileCtrl.text = _headMobileNumber ?? '';
      } else {
        _mobileCtrl.clear();
      }
      _fieldErrors.remove('mobile');
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
      initialDate: _dob ?? DateTime.now(),
      firstDate: EnrollmentDob.earliestBirthDate(),
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

    if (picked != null) setState(() => _applyDateOfBirth(picked));
  }

  /// Single entry point for every source of a date of birth (picker, NID scan,
  /// server lookup) so the field, the age and the marital-status gate (age ≥ 14)
  /// can never drift apart. Call inside setState.
  void _applyDateOfBirth(DateTime? dob) {
    if (dob == null) return;
    _dob = dob;
    _dobCtrl.text = EnrollmentDob.display(dob);

    final age = EnrollmentAge.from(dob);
    _ageInYears = age.years;
    _ageCtrl.text = age.value.toString();
    _ageUnit = age.unit;
    _ageSummary = age.summary;

    // Spice handleDob: hide + reset marital status when age < 14.
    if (!EnrollmentDob.needsMaritalStatus(dob, ageYears: age.years)) {
      _maritalStatus = null;
    }
    // Spice handleDob: hide + reset guardian when age > 2.
    if (!EnrollmentDob.needsGuardian(dob, ageYears: age.years)) {
      _guardianId = null;
    }
  }

  /// Manual age entry is always whole years. Sets DOB to 01-01 of the
  /// implied birth year so the two fields stay consistent on the wire.
  void _applyAgeYears(String raw) {
    final years = int.tryParse(raw.trim());
    if (years == null) {
      _ageInYears = 0;
      _ageUnit = '';
      _ageSummary = null;
      return;
    }
    _ageInYears = years;
    _ageUnit = years == 1 ? EnrollmentStrings.ageUnitYear : EnrollmentStrings.ageUnitYears;
    _ageSummary = null;
    _dob = EnrollmentDob.fromAgeYears(years);
    _dobCtrl.text = EnrollmentDob.display(_dob!);
    if (!EnrollmentDob.needsMaritalStatus(_dob, ageYears: years)) {
      _maritalStatus = null;
    }
    if (!EnrollmentDob.needsGuardian(_dob, ageYears: years)) {
      _guardianId = null;
    }
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
          _applyDateOfBirth(EnrollmentDob.parse(data.dateOfBirth));
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
        _applyDateOfBirth(EnrollmentDob.parse(patient.dob));
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


  Future<void> _handleSaveMember(EnrollmentController controller) async {
    debugPrint('[_AddHouseholdMemberScreenState] _handleSaveMember name=${_nameCtrl.text} gender=$_gender maritalStatus=$_maritalStatus');
    final maritalRequired = _needsMaritalStatus;
    // Skipped for "Not Available", digits-and-length checked for National ID.
    final idError = EnrollmentIdNumber.validate(
      _idType,
      _brnCtrl.text,
      requiredMessage: CommonStrings.required,
    );

    // Android member_registration.json: phone_number_category, phone_number,
    // and disability are all isMandatory: true — do not soft-default them.
    final errors = <String, String?>{
      if (_idType == null) 'idType': CommonStrings.required,
      'idNumber': ?idError,
      if (_nameCtrl.text.trim().isEmpty) 'name': CommonStrings.required,
      if (_dobCtrl.text.trim().isEmpty) 'dob': CommonStrings.required,
      if (_gender == null) 'gender': CommonStrings.required,
      if (maritalRequired && _maritalStatus == null) 'maritalStatus': CommonStrings.required,
      // Spice: guardian mandatory when age ≤ 2; ADD_GUARDIAN_ID is not valid.
      if (_needsGuardian &&
          (_guardianId == null ||
              _guardianId == _addGuardianOptionId ||
              _guardianId!.isEmpty))
        'guardian': CommonStrings.required,
      if (_phoneCategory == null) 'phoneCategory': CommonStrings.required,
      'mobile': ?EnrollmentMobileNumber.validate(
        _mobileCtrl.text,
        required: true,
        requiredMessage: CommonStrings.required,
      ),
      if (_disabilityStatus == null) 'disability': CommonStrings.required,
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
      dateOfBirth: _dob == null ? '' : EnrollmentDob.wire(_dob!),
      idType: _idType == EnrollmentIdNumber.nationalId
          ? 'NID'
          : (_idType ?? EnrollmentIdNumber.brn),
      idNumber: EnrollmentIdNumber.isCollected(_idType)
          ? (nid.isNotEmpty ? nid : null)
          : null,
      mobileNumber: mobile,
      phoneNumberCategory: _phoneCategory,
      mobileAvailable: true,
      maritalStatus: _maritalStatus ?? '',
      disabilityStatus: _disabilityStatus!,
      relationshipToHead: 'Other',
      villageId: controller.household?.subVillageId?.isNotEmpty == true
          ? controller.household!.subVillageId
          : controller.household?.villageId,
      nidScanned: _nidScanned,
      guardianId: _needsGuardian ? _guardianId : null,
      guardianFhirId: _needsGuardian ? _guardianFhirIdFor(_guardianId) : null,
    );

    if (widget.isStandalone) {
      await _submitStandalone(member);
    } else {
      controller.addMember(member);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(EnrollmentStrings.memberAddedSuccess),
          duration: const Duration(seconds: 2),
        ),
      );
      context.pop();
    }
  }

  /// Submits a member to an already-synced household (standalone mode).
  /// Mirrors [LinkMemberScreen._submit] + [LinkMemberScreen._persistLocally].
  Future<void> _submitStandalone(HouseholdMember member) async {
    setState(() => _submitting = true);
    try {
      final auth = context.read<AuthRepository>();
      final api = context.read<ApiClient>();
      final memberDao = context.read<MemberDao>();
      final patientDao = context.read<PatientDao>();
      final hhDao = context.read<HouseholdDao>();
      final hierarchy = context.read<UserHierarchyService>();

      final userId = await auth.userId() ?? 0;
      final userFhirId = await auth.userFhirId() ?? '';
      final orgId = await auth.organizationFhirId() ?? '';
      final deviceId = await auth.deviceId();

      final repo = EnrollmentRepository(api);
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Resolve the household row this member hangs off. Callers pass either a
      // server id (household detail) or a local PK (select-household), and both
      // id spaces are plain integers — so trust the caller's explicit reference
      // id first and only then fall back to fhir_id/id lookups. Guessing wrong
      // files the member under another household, or under none, and no screen
      // can surface it again.
      final hhArg = widget.existingHouseholdId!;
      final hhRef = widget.existingHouseholdReferenceId;
      final household = (hhRef != null && hhRef.isNotEmpty
              ? await hhDao.getById(hhRef)
              : null) ??
          await hhDao.getByFhirId(hhArg) ??
          await hhDao.getById(hhArg);
      final localHhId = household?.id ?? hhRef ?? hhArg;
      final householdFhirId = household?.fhirId;
      debugPrint('[AddMember] household arg=$hhArg ref=$hhRef '
          '→ local=$localHhId fhir=$householdFhirId');

      // The member inherits the household's location, and the two levels stay
      // distinct: sending the same id as villageId and subVillageId is what
      // made fhir-mapper reject these members.
      var villageId = household?.villageId ?? widget.existingVillageId ?? '';
      var villageName = household?.village ?? widget.existingVillageName ?? '';
      var subVillageId =
          household?.subVillageId ?? widget.existingSubVillageId ?? '';
      var subVillageName =
          household?.subVillageName ?? widget.existingSubVillageName ?? '';

      // Households enrolled before v37 have no sub-village of their own, and a
      // NID-scan entry can arrive with neither — fall back to the worker's
      // hierarchy, then derive the missing level from the one we do have.
      if (subVillageId.isEmpty || villageId.isEmpty) {
        await hierarchy.prefetch();
        final subs = <SubVillageRef>[
          ...(hierarchy.ssWorkers ?? []).expand((s) => s.subVillages),
          ...(hierarchy.subVillages ?? const <SubVillageRef>[]),
        ];
        SubVillageRef? match;
        if (subVillageId.isNotEmpty) {
          match = subs.where((s) => s.id == subVillageId).firstOrNull;
        }
        // A pre-v37 household stored the sub-village in `village_id`.
        match ??= villageId.isNotEmpty
            ? subs.where((s) => s.id == villageId).firstOrNull
            : null;
        match ??= subs.firstOrNull;
        if (match != null) {
          subVillageId = match.id;
          subVillageName = match.name;
          final parentId = match.villageId ?? '';
          if (parentId.isNotEmpty && parentId != subVillageId) {
            villageId = parentId;
            villageName = (hierarchy.villages ?? const <VillageRef>[])
                    .where((v) => v.id == parentId)
                    .firstOrNull
                    ?.name ??
                villageName;
          }
        }
      }
      debugPrint('[AddMember] village=$villageId/$villageName '
          'subVillage=$subVillageId/$subVillageName');

      // Patients (and assessment scoping) key off the finest level available.
      final canonicalVillageId =
          subVillageId.isNotEmpty ? subVillageId : villageId;
      final canonicalVillageName =
          subVillageName.isNotEmpty ? subVillageName : villageName;

      final memberLocalId = await memberDao.insertLocal(
        HouseholdMemberEntity(
          id: '0',
          householdId: localHhId,
          householdFhirId: householdFhirId,
          householdReferenceId: localHhId,
          name: member.name,
          gender: member.gender,
          dob: member.dateOfBirth,
          phone: member.mobileNumber,
          nationalId: member.idNumber,
          idType: member.idType,
          villageId: villageId.isEmpty ? null : villageId,
          villageName: villageName.isEmpty ? null : villageName,
          subVillageId: subVillageId.isEmpty ? null : subVillageId,
          subVillageName: subVillageName.isEmpty ? null : subVillageName,
          maritalStatus: member.maritalStatus,
          disability: member.disabilityStatus.toLowerCase(),
          guardianId: member.guardianId,
          guardianFhirId: member.guardianFhirId,
          isHouseholdHead: false,
          isActive: true,
          isPregnant: false,
          createdAt: nowMs,
          updatedAt: nowMs,
          syncStatus: 'NotSynced',
        ),
      );
      await memberDao.setReferenceId(memberLocalId);

      await patientDao.upsertMany([
        Patient(
          id: memberLocalId,
          name: member.name,
          gender: member.gender,
          dob: member.dateOfBirth,
          phone: member.mobileNumber,
          nationalId: member.idNumber,
          villageId: canonicalVillageId,
          villageName: canonicalVillageName,
          householdId: localHhId,
          isActive: true,
          updatedAt: nowMs,
          rawJson: jsonEncode({
            'id': memberLocalId,
            'name': member.name,
            'gender': member.gender,
            'dateOfBirth': member.dateOfBirth,
            'phoneNumber': member.mobileNumber,
            'nationalId': member.idNumber,
            'villageId': canonicalVillageId,
            'houseHoldId': localHhId,
            'isActive': true,
          }),
        ),
      ]);
      debugPrint('[AddMember] standalone saved localId=$memberLocalId');
      // Select Household (and other HH cards) read households.member_count —
      // bump it to the live members-table headcount after each link.
      final liveCount = await memberDao.countByHousehold(localHhId);
      await hhDao.setMemberCount(localHhId, liveCount);
      bumpRosterRevision();

      // The member is safely on disk, so the save is already done as far as the
      // health worker is concerned — push in the background rather than making
      // them wait on (or fail because of) the network. Anything left NotSynced
      // is picked up by Offline Sync and by the reconnect trigger.
      //
      // Only push at all when the household exists server-side: otherwise the
      // create would carry a local PK as `householdId` and orphan the member,
      // so we leave it for Offline Sync, which posts household and members
      // together.
      if (householdFhirId != null && householdFhirId.isNotEmpty) {
        unawaited(
          _pushMemberInBackground(
            repo: repo,
            memberDao: memberDao,
            member: member,
            memberLocalId: memberLocalId,
            householdFhirId: householdFhirId,
            householdReferenceId: localHhId,
            villageId: villageId,
            villageName: villageName,
            // A legacy household whose hierarchy we could not resolve has one
            // id for both levels — send it as the village only, so
            // spice-service never sees a sub-village that is its own parent.
            subVillageId: subVillageId == villageId ? null : subVillageId,
            subVillageName: subVillageId == villageId ? null : subVillageName,
            userId: userId,
            userFhirId: userFhirId,
            organizationId: orgId,
            deviceId: deviceId,
          ),
        );
      } else {
        debugPrint('[AddMember] household $localHhId has no fhir_id yet — '
            'member queued for Offline Sync');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(EnrollmentStrings.memberAddedSuccess)),
      );
      // Pop back to the caller (household detail / select-household) so it can
      // re-read the roster it is showing. `go` would rebuild the whole branch
      // and can leave an older, already-queried list instance on screen — the
      // new member then stays invisible until the app is restarted.
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/patients/households');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(EnrollmentStrings.memberAddFailed(e)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
                Text(
                  EnrollmentStrings.addMemberAppBar,
                  style: const TextStyle(
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
                    // ── Q1: Name — hidden when NID scanned (card has it) ──
                    if (!_nidScanned) ...[
                      SizedBox(key: _key('name'), height: 0),
                      _QuestionLabel(
                        number: 'Q1',
                        text: EnrollmentStrings.memberNameLabel,
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
                      const SizedBox(height: 20),
                    ],

                    // ── Q2: ID Type ────────────────────────────────────────
                    _QuestionLabel(
                      number: 'Q2',
                      text: EnrollmentStrings.idTypeLabel,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(key: _key('idType'), height: 0),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.idTypeLabel,
                      options: EnrollmentStrings.idTypesV2,
                      selectedValue: _idType,
                      optionLabel: EnrollmentStrings.optionDisplay,
                      allowDeselect: false,
                      isRequired: true,
                      errorText: _fieldErrors['idType'],
                      onChanged: (v) => setState(() {
                        _idType = v;
                        _fieldErrors.remove('idType');
                        _fieldErrors.remove('idNumber');
                        if (_idType != EnrollmentIdNumber.nationalId) {
                          _nidScanned = false;
                          _brnCtrl.clear();
                          _existingPatient = null;
                        }
                      }),
                    ),
                    const SizedBox(height: 14),

                    // NID scan purple CTA — shown only for National ID
                    if (_idType == EnrollmentIdNumber.nationalId) ...[
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

                    // Manual entry for SKs who cannot scan (damaged card, no
                    // camera light); the scanned card below carries the same
                    // controller once a scan succeeds.
                    if (!_nidScanned) ...[
                      const SizedBox(height: 14),
                      SizedBox(key: _key('idNumber'), height: 0),
                      EnrollmentInputField(
                        label: EnrollmentIdNumber.label(_idType),
                        hint: EnrollmentIdNumber.hint(_idType),
                        controller: _brnCtrl,
                        isRequired: true,
                        keyboardType: EnrollmentIdNumber.keyboard(_idType),
                        inputFormatters: EnrollmentIdNumber.formatters(_idType),
                        onChanged: (value) {
                          _clearError('idNumber');
                          if (value.length >= 10) _lookupExisting(value);
                        },
                        errorText: _fieldErrors['idNumber'],
                      ),
                    ],

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
                                Expanded(
                                  child: Text(
                                    EnrollmentStrings.nidScannedHint,
                                    style: const TextStyle(
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
                                  child: Text(
                                    EnrollmentStrings.clearNidScan,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.statusCritical,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(key: _key('idNumber'), height: 0),
                            EnrollmentInputField(
                              label: EnrollmentStrings.nidNumberLabel,
                              hint: EnrollmentStrings.nidNumberHint,
                              controller: _brnCtrl,
                              keyboardType:
                                  EnrollmentIdNumber.keyboard(_idType),
                              inputFormatters:
                                  EnrollmentIdNumber.formatters(_idType),
                              onChanged: (value) {
                                _clearError('idNumber');
                                if (value.length >= 10) _lookupExisting(value);
                              },
                              errorText: _fieldErrors['idNumber'],
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
                                  isRequired: true,
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
                    if (_idType == EnrollmentIdNumber.brn) ...[
                      SizedBox(key: _key('idNumber'), height: 0),
                      EnrollmentInputField(
                        label: EnrollmentStrings.brnFieldLabel,
                        hint: EnrollmentStrings.brnNumberHint,
                        controller: _brnCtrl,
                        isRequired: true,
                        onChanged: (_) => _clearError('idNumber'),
                        errorText: _fieldErrors['idNumber'],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 20),

                    // ── Q3: Mobile number category ─────────────────────────
                    SizedBox(key: _key('phoneCategory'), height: 0),
                    _QuestionLabel(
                      number: 'Q3',
                      text: EnrollmentStrings.phoneCategoryLabel,
                    ),
                    const SizedBox(height: 10),
                    EnrollmentDropdown(
                      label: EnrollmentStrings.phoneCategoryLabel,
                      options: EnrollmentStrings.phoneCategoryOptions,
                      value: _phoneCategory,
                      optionLabel: EnrollmentStrings.optionDisplay,
                      onChanged: _onPhoneCategoryChanged,
                      hint: EnrollmentStrings.phoneCategoryHint,
                      isRequired: true,
                      errorText: _fieldErrors['phoneCategory'],
                    ),
                    const SizedBox(height: 14),

                    SizedBox(key: _key('mobile'), height: 0),
                    _QuestionLabel(
                      number: 'Q4',
                      text: EnrollmentStrings.mobileNumberLabel,
                    ),
                    const SizedBox(height: 10),
                    EnrollmentInputField(
                      label: EnrollmentStrings.mobileNumberLabel,
                      hint: EnrollmentStrings.mobileNumberHint,
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      isRequired: true,
                      validator: (v) => EnrollmentMobileNumber.validate(
                        v,
                        required: true,
                        requiredMessage: CommonStrings.required,
                      ),
                      onChanged: (_) => _clearError('mobile'),
                      errorText: _fieldErrors['mobile'],
                      inputFormatters: EnrollmentMobileNumber.formatters,
                    ),
                    const SizedBox(height: 20),

                    // ── Q5: Date of Birth — hidden when NID scanned (card has it) ──
                    if (!_nidScanned) ...[
                      SizedBox(key: _key('dob'), height: 0),
                      _QuestionLabel(
                        number: 'Q5',
                        text: EnrollmentStrings.dateOfBirthLabel,
                      ),
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
                            isRequired: true,
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

                    // Age (always years when typed manually)
                    EnrollmentInputField(
                      label: EnrollmentStrings.ageLabel,
                      hint: EnrollmentStrings.ageHint,
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
                      onChanged: (v) => setState(() => _applyAgeYears(v)),
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

                    // ── Q6: Gender ─────────────────────────────────────────
                    SizedBox(key: _key('gender'), height: 0),
                    _QuestionLabel(
                      number: 'Q6',
                      text: EnrollmentStrings.genderLabel,
                    ),
                    const SizedBox(height: 10),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.genderLabel,
                      options: EnrollmentStrings.gendersMember,
                      selectedValue: _gender,
                      optionLabel: EnrollmentStrings.optionDisplay,
                      onChanged: (v) => setState(() {
                        _gender = v;
                        _fieldErrors.remove('gender');
                      }),
                      isRequired: true,
                      errorText: _fieldErrors['gender'],
                    ),
                    const SizedBox(height: 20),

                    // ── Q7: Marital Status — hidden for age < 14 (Spice) ──
                    if (_needsMaritalStatus) ...[
                      SizedBox(key: _key('maritalStatus'), height: 0),
                      _QuestionLabel(
                        number: 'Q7',
                        text: EnrollmentStrings.maritalStatusLabel,
                      ),
                      const SizedBox(height: 10),
                      EnrollmentDropdown(
                        label: EnrollmentStrings.maritalStatusLabel,
                        options: EnrollmentStrings.maritalStatusesV2,
                        value: _maritalStatus,
                        optionLabel: EnrollmentStrings.optionDisplay,
                        onChanged: (v) => setState(() {
                          _maritalStatus = v;
                          _fieldErrors.remove('maritalStatus');
                        }),
                        hint: EnrollmentStrings.maritalStatusHint,
                        isRequired: true,
                        errorText: _fieldErrors['maritalStatus'],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        EnrollmentStrings.maritalStatusInfo,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Q8: Guardian — Spice: required when age ≤ 2 years ─────
                    if (_needsGuardian) ...[
                      SizedBox(key: _key('guardian'), height: 0),
                      _QuestionLabel(
                        number: 'Q8',
                        text: EnrollmentStrings.guardianLabel,
                      ),
                      const SizedBox(height: 10),
                      if (widget.isStandalone)
                        EnrollmentDropdown(
                          label: EnrollmentStrings.guardianLabel,
                          options: _guardianDropdownIds,
                          value: _guardianId,
                          optionLabel: _guardianOptionLabel,
                          onChanged: _onGuardianChanged,
                          hint: EnrollmentStrings.guardianHint,
                          isRequired: true,
                          errorText: _fieldErrors['guardian'],
                        )
                      else
                        Consumer<EnrollmentController>(
                          builder: (context, ctrl, _) {
                            // Refresh candidates as pending members are added.
                            final options = _batchGuardianOptions(ctrl);
                            final ids = [
                              ...options.map((o) => o.id),
                              _addGuardianOptionId,
                            ];
                            String labelFor(String id) {
                              if (id == _addGuardianOptionId) {
                                return EnrollmentStrings.addGuardian;
                              }
                              for (final o in options) {
                                if (o.id == id) return o.name;
                              }
                              return id;
                            }

                            return EnrollmentDropdown(
                              label: EnrollmentStrings.guardianLabel,
                              options: ids,
                              value: ids.contains(_guardianId)
                                  ? _guardianId
                                  : null,
                              optionLabel: labelFor,
                              onChanged: (v) async {
                                if (v != _addGuardianOptionId) {
                                  // Keep batch option cache in sync for fhir lookup.
                                  _guardianOptions = options;
                                }
                                await _onGuardianChanged(v);
                              },
                              hint: EnrollmentStrings.guardianHint,
                              isRequired: true,
                              errorText: _fieldErrors['guardian'],
                            );
                          },
                        ),
                      const SizedBox(height: 20),
                    ],

                    // ── Q9: Disability ─────────────────────────────────────
                    SizedBox(key: _key('disability'), height: 0),
                    _QuestionLabel(
                      number: 'Q9',
                      text: EnrollmentStrings.disabilityStatusLabel,
                    ),
                    const SizedBox(height: 10),
                    EnrollmentSegmentedButtons(
                      label: EnrollmentStrings.disabilityStatusLabel,
                      options: EnrollmentStrings.disabilityStatusesV2,
                      selectedValue: _disabilityStatus,
                      optionLabel: EnrollmentStrings.disabilityStatusDisplay,
                      onChanged: (v) => setState(() {
                        _disabilityStatus = v;
                        _fieldErrors.remove('disability');
                      }),
                      isRequired: true,
                      allowDeselect: false,
                      errorText: _fieldErrors['disability'],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      EnrollmentStrings.disabilityMemberInfo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
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
                    loading: _submitting,
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
