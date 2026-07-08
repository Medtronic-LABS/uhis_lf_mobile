import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/db/household_dao.dart';
import '../../../core/db/member_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/patient.dart';
import '../../../core/services/location_service.dart';
import 'enrollment_repository.dart';
import 'models/household_enrollment_models.dart';

/// Controller for managing household enrollment state across all screens.
///
/// Holds the active household being enrolled, the household head info, and
/// any members being added. Provides methods to update form state, generate
/// household numbers, and submit to [EnrollmentRepository].
///
/// After a successful server POST, immediately persists the household + members
/// to local SQLite (offline-first, matching Android's insertHouseHoldEntity /
/// registerMember pattern) so the new records appear instantly without waiting
/// for the backend to process the async queue and a subsequent warm-sync.
///
/// Use via Provider to share state across enrollment screens.
class EnrollmentController extends ChangeNotifier {
  EnrollmentController({
    AuthRepository? auth,
    ApiClient? apiClient,
    HouseholdDao? householdDao,
    MemberDao? memberDao,
    PatientDao? patientDao,
  })  : _auth = auth,
        _repo = (auth != null && apiClient != null)
            ? EnrollmentRepository(apiClient)
            : null,
        _householdDao = householdDao,
        _memberDao = memberDao,
        _patientDao = patientDao;

  final AuthRepository? _auth;
  final EnrollmentRepository? _repo;
  final HouseholdDao? _householdDao;
  final MemberDao? _memberDao;
  final PatientDao? _patientDao;

  Household? _household;
  HouseholdHeadInfo? _householdHead;
  final List<HouseholdMember> _members = [];
  bool _loading = false;
  String? _error;

  Household? get household => _household;
  HouseholdHeadInfo? get householdHead => _householdHead;
  List<HouseholdMember> get members => List.unmodifiable(_members);
  bool get loading => _loading;
  String? get error => _error;

  int get totalMembers => (_members.length) + (_householdHead != null ? 1 : 0);

  /// Initialize a new household enrollment with auto-generated household number.
  void initializeHousehold({
    required String healthWorkerId,
    required String villageId,
    String? villageName,
    String? subVillageId,
    String? subVillageName,
  }) {
    final householdNumber = _generateHouseholdNumber();
    _household = Household(
      householdNumber: householdNumber,
      healthWorkerId: healthWorkerId,
      villageId: villageId,
      villageName: villageName,
      subVillageId: subVillageId,
      subVillageName: subVillageName,
      householdType: 'Single-family',
      numberOfMembers: 0,
      houseNumber: '',
      occupation: '',
      monthlyIncome: '<10000',
      disabilityQuestion: false,
    );
    _error = null;
    notifyListeners();
  }

  /// Update household information (step 1).
  void updateHousehold({
    String? healthWorkerId,
    String? householdType,
    int? numberOfMembers,
    String? houseNumber,
    String? occupation,
    String? monthlyIncome,
    bool? disabilityQuestion,
    String? disabilityDetails,
    String? villageId,
    String? villageName,
    String? subVillageId,
    String? subVillageName,
  }) {
    if (_household == null) return;

    _household = _household!.copyWith(
      healthWorkerId: healthWorkerId,
      householdType: householdType,
      numberOfMembers: numberOfMembers,
      houseNumber: houseNumber,
      occupation: occupation,
      monthlyIncome: monthlyIncome,
      disabilityQuestion: disabilityQuestion,
      disabilityDetails: disabilityDetails,
      villageId: villageId,
      villageName: villageName,
      subVillageId: subVillageId,
      subVillageName: subVillageName,
    );
    notifyListeners();
  }

  /// Update household head information (step 2).
  void updateHead({
    required String name,
    String? fatherName,
    String? motherName,
    required int age,
    required String gender,
    required String dateOfBirth,
    required String idType,
    String? idNumber,
    String? mobileNumber,
    bool? mobileAvailable,
    required String maritalStatus,
    required String disabilityStatus,
    bool? nidScanned,
  }) {
    _householdHead = HouseholdHeadInfo(
      name: name,
      fatherName: fatherName,
      motherName: motherName,
      age: age,
      gender: gender,
      dateOfBirth: dateOfBirth,
      idType: idType,
      idNumber: idNumber,
      mobileNumber: mobileNumber,
      mobileAvailable: mobileAvailable ?? true,
      maritalStatus: maritalStatus,
      disabilityStatus: disabilityStatus,
      nidScanned: nidScanned ?? false,
    );
    notifyListeners();
  }

  /// Add a member to the household.
  void addMember(HouseholdMember member) {
    if (_household == null) return;
    _members.add(member);
    notifyListeners();
  }

  /// Remove a member by index.
  void removeMember(int index) {
    if (index >= 0 && index < _members.length) {
      _members.removeAt(index);
      notifyListeners();
    }
  }

  /// Update an existing member.
  void updateMember(int index, HouseholdMember member) {
    if (index >= 0 && index < _members.length) {
      _members[index] = member;
      notifyListeners();
    }
  }

  /// Validate household form (step 1).
  List<String> validateHouseholdForm() {
    final errors = <String>[];

    if (_household == null) {
      errors.add('Household not initialized');
      return errors;
    }

    if (_household!.householdType.isEmpty) {
      errors.add('Household type is required');
    }
    if (_household!.numberOfMembers <= 0) {
      errors.add('Number of members must be greater than 0');
    }
    if (_household!.houseNumber.trim().isEmpty) {
      errors.add('House number is required');
    }
    if (_household!.disabilityQuestion &&
        (_household!.disabilityDetails?.trim().isEmpty ?? true)) {
      errors.add('Please specify disability details');
    }

    return errors;
  }

  /// Validate household head form (step 2).
  List<String> validateHeadForm() {
    final errors = <String>[];

    if (_householdHead == null) {
      errors.add('Head information not provided');
      return errors;
    }

    if (_householdHead!.name.trim().isEmpty) {
      errors.add('Head name is required');
    }
    if (_householdHead!.idNumber?.trim().isEmpty ?? true) {
      errors.add('ID number is required');
    }
    if (_householdHead!.maritalStatus.isEmpty) {
      errors.add('Marital status is required');
    }

    return errors;
  }

  /// Validate member form (for add/edit members).
  List<String> validateMemberForm(HouseholdMember member) {
    final errors = <String>[];

    if (member.name.trim().isEmpty) {
      errors.add('Member name is required');
    }
    if (member.age < 0) {
      errors.add('Age must be valid');
    }
    if (member.dateOfBirth.isEmpty) {
      errors.add('Date of birth is required');
    }
    if (member.idNumber?.trim().isEmpty ?? true) {
      errors.add('ID number is required');
    }
    if (!member.mobileAvailable &&
        (member.mobileNumber?.trim().isEmpty ?? true)) {
      errors.add('Mobile number is required or mark as not available');
    }
    if (member.maritalStatus.isEmpty) {
      errors.add('Marital status is required');
    }

    return errors;
  }

  /// Submit household enrollment to `POST /offline-service/offline-sync/create`.
  ///
  /// Falls back to a mock delay when the controller was constructed without
  /// auth/api deps (e.g. in widget tests).
  Future<bool> submitHousehold() async {
    final householdErrors = validateHouseholdForm();
    final headErrors = validateHeadForm();

    if (householdErrors.isNotEmpty || headErrors.isNotEmpty) {
      _error = 'Please fill all required fields';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _error = null;

    try {
      final repo = _repo;
      final auth = _auth;
      if (repo != null && auth != null) {
        final userId = await auth.userId() ?? 0;
        final userFhirId = await auth.userFhirId() ?? '';
        final orgId = await auth.organizationFhirId() ?? '';
        final deviceId = await auth.deviceId();
        final location = await LocationService.getCurrentPosition();

        final result = await repo.submit(
          household: _household!,
          head: _householdHead!,
          members: _members,
          userId: userId,
          userFhirId: userFhirId,
          organizationId: orgId,
          deviceId: deviceId,
          latitude: location.latitude,
          longitude: location.longitude,
        );

        // Mirror Android: save to local SQLite immediately so the household
        // and its members are visible without waiting for the backend queue
        // to be processed and a subsequent warm-sync to pull them back.
        await _persistLocally(
          result: result,
          location: (latitude: location.latitude, longitude: location.longitude),
        );
      } else {
        // No HTTP client injected — dev/test path.
        debugPrint('[EnrollmentController] mock submit: ${_household?.toJson()}');
        await Future.delayed(const Duration(milliseconds: 800));
      }

      _setLoading(false);
      return true;
    } catch (e) {
      _error = 'Enrollment failed: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Persist the newly enrolled household + members to local SQLite immediately.
  ///
  /// Uses the same [referenceId] UUIDs that were sent to the server so the
  /// records can be matched when the server later returns FHIR IDs via the
  /// warm-sync bundle. Uses sub-village ID as the canonical village scope to
  /// match Android's assessment-history pull request granularity.
  Future<void> _persistLocally({
    required EnrollmentResult result,
    required ({double latitude, double longitude}) location,
  }) async {
    final householdDao = _householdDao;
    final memberDao = _memberDao;
    final patientDao = _patientDao;
    if (householdDao == null || memberDao == null || patientDao == null) {
      debugPrint('[EnrollmentController] no DAOs injected — skipping local save');
      return;
    }

    final hh = _household!;
    final head = _householdHead!;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Use sub-village ID as canonical village scope (mirrors _memberToPatient fix).
    final canonicalVillageId = hh.subVillageId?.isNotEmpty == true
        ? hh.subVillageId!
        : hh.villageId;
    final canonicalVillageName = hh.subVillageName?.isNotEmpty == true
        ? hh.subVillageName
        : hh.villageName;

    // ── Household ────────────────────────────────────────────────────────────
    final hhEntity = HouseholdEntity(
      id: result.hhReferenceId,
      householdNo: hh.householdNumber,
      name: head.name,
      village: canonicalVillageName,
      villageId: canonicalVillageId,
      memberCount: 1 + _members.length,
      latitude: location.latitude,
      longitude: location.longitude,
      createdAt: nowMs,
      updatedAt: nowMs,
      syncStatus: 'Success',
    );
    await householdDao.upsertMany([hhEntity]);

    // ── Members + Patient rows ────────────────────────────────────────────────
    // HouseholdHeadInfo extends HouseholdMember, so no reconstruction needed.
    final membersToSave = <HouseholdMember>[head, ..._members];

    for (var i = 0; i < membersToSave.length; i++) {
      final m = membersToSave[i];
      final refId = result.memberReferenceIds[i];

      final memberEntity = HouseholdMemberEntity(
        id: refId,
        householdId: result.hhReferenceId,
        householdReferenceId: result.hhReferenceId,
        name: m.name,
        gender: m.gender,
        dob: m.dateOfBirth,
        phone: m.mobileNumber,
        nationalId: m.idNumber,
        idType: m.idType,
        villageId: canonicalVillageId,
        villageName: canonicalVillageName,
        subVillageId: hh.subVillageId,
        subVillageName: hh.subVillageName,
        maritalStatus: m.maritalStatus,
        disability: m.disabilityStatus.toLowerCase(),
        isHouseholdHead: i == 0,
        isActive: true,
        isPregnant: false,
        latitude: location.latitude,
        longitude: location.longitude,
        createdAt: nowMs,
        updatedAt: nowMs,
        syncStatus: 'Success',
      );
      await memberDao.upsertMany([memberEntity]);

      // Mirror patient record so PatientDao.byId(refId) resolves immediately.
      final patientRaw = jsonEncode({
        'id': refId,
        'name': m.name,
        'gender': m.gender,
        'dateOfBirth': m.dateOfBirth,
        'phoneNumber': m.mobileNumber,
        'nationalId': m.idNumber,
        'villageId': canonicalVillageId,
        'houseHoldId': result.hhReferenceId,
        'isActive': true,
      });
      final patientEntity = Patient(
        id: refId,
        name: m.name,
        gender: m.gender,
        dob: m.dateOfBirth,
        phone: m.mobileNumber,
        nationalId: m.idNumber,
        villageId: canonicalVillageId,
        villageName: canonicalVillageName,
        householdId: result.hhReferenceId,
        isActive: true,
        updatedAt: nowMs,
        rawJson: patientRaw,
      );
      await patientDao.upsertMany([patientEntity]);
    }

    debugPrint('[EnrollmentController] locally saved: '
        'household=${result.hhReferenceId} '
        'members=${result.memberReferenceIds.length}');
  }

  /// Reset the entire enrollment state.
  void reset() {
    _household = null;
    _householdHead = null;
    _members.clear();
    _loading = false;
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  /// Generate a numeric household number matching Android's fallback pattern
  /// (System.currentTimeMillis()). Android's primary path uses HH{count+1}
  /// which requires a per-sub-village DB count; without that lookup we use the
  /// timestamp as the authoritative fallback, identical to Android's:
  ///   householdEntity.householdNo = "HH${System.currentTimeMillis()}"
  /// We store it as a numeric string so it serialises as a JSON number.
  String _generateHouseholdNumber() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}
