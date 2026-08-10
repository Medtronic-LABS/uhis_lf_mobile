import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/db/household_dao.dart';
import '../../../core/db/member_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/db/roster_revision.dart';
import '../../../core/models/patient.dart';
import '../../../core/services/location_service.dart';
import 'enrollment_dob.dart';
import 'enrollment_id_number.dart';
import 'enrollment_mobile_number.dart';
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

  static const _uuid = Uuid();

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
  Future<void> initializeHousehold({
    required String healthWorkerId,
    required String villageId,
    String? villageName,
    String? subVillageId,
    String? subVillageName,
  }) async {
    final householdNumber = await _generateHouseholdNumber();
    _household = Household(
      householdNumber: householdNumber,
      healthWorkerId: healthWorkerId,
      villageId: villageId,
      villageName: villageName,
      subVillageId: subVillageId,
      subVillageName: subVillageName,
      householdType: '',
      numberOfMembers: 0,
      houseNumber: '',
      occupation: '',
      monthlyIncomeRange: '',
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
    String? otherOccupation,
    String? monthlyIncomeRange,
    int? disabilityPersonsCount,
    String? villageId,
    String? villageName,
    String? subVillageId,
    String? subVillageName,
  }) {
    if (_household == null) {
      debugPrint('[EnrollmentController] updateHousehold ignored — no active '
          'household (initializeHousehold was never called, or reset() ran '
          'after it). Form input will not reach validation.');
      return;
    }

    _household = _household!.copyWith(
      healthWorkerId: healthWorkerId,
      householdType: householdType,
      numberOfMembers: numberOfMembers,
      houseNumber: houseNumber,
      occupation: occupation,
      otherOccupation: otherOccupation,
      monthlyIncomeRange: monthlyIncomeRange,
      disabilityPersonsCount: disabilityPersonsCount,
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
    required int age,
    required String gender,
    required String dateOfBirth,
    required String idType,
    String? idNumber,
    String? mobileNumber,
    String? phoneNumberCategory,
    bool? mobileAvailable,
    required String maritalStatus,
    required String disabilityStatus,
    bool? nidScanned,
  }) {
    _householdHead = HouseholdHeadInfo(
      // Stable client key so a later infant can select this head as guardian
      // before local DB ids exist (Spice uses Long member ids).
      id: _householdHead?.id ?? _uuid.v4(),
      name: name,
      age: age,
      gender: gender,
      dateOfBirth: dateOfBirth,
      idType: idType,
      idNumber: idNumber,
      mobileNumber: mobileNumber,
      phoneNumberCategory: phoneNumberCategory,
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
    final withId = (member.id == null || member.id!.isEmpty)
        ? member.copyWith(id: _uuid.v4())
        : member;
    _members.add(withId);
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
      debugPrint('[EnrollmentController] validateHouseholdForm — household is '
          'null; initializeHousehold() must run before the form is submitted');
      errors.add(EnrollmentStrings.householdNotInitializedError);
      return errors;
    }

    debugPrint('[EnrollmentController] validateHouseholdForm '
        'no=${_household!.householdNumber} '
        'type="${_household!.householdType}" '
        'members=${_household!.numberOfMembers} '
        'occupation="${_household!.occupation}" '
        'incomeRange="${_household!.monthlyIncomeRange}" '
        'village=${_household!.villageId} '
        'subVillage=${_household!.subVillageId}');

    if (_household!.numberOfMembers <= 0) {
      errors.add(EnrollmentStrings.membersCountRequiredError);
    }
    if (_household!.monthlyIncomeRange.isEmpty) {
      errors.add(EnrollmentStrings.incomeRangeRequiredError);
    }
    if (_household!.occupation == 'Other' &&
        _household!.otherOccupation.trim().isEmpty) {
      errors.add(EnrollmentStrings.occupationSpecifyRequiredError);
    }

    return errors;
  }

  /// Validate household head form (step 2).
  List<String> validateHeadForm() {
    final errors = <String>[];

    if (_householdHead == null) {
      errors.add(EnrollmentStrings.headInfoRequiredError);
      return errors;
    }

    if (_householdHead!.name.trim().isEmpty) {
      errors.add(EnrollmentStrings.headNameRequiredError);
    }
    if (_householdHead!.idType.trim().isEmpty) {
      errors.add(EnrollmentStrings.idTypeRequiredError);
    }
    // "Not Available" hides the number field in Spice, so it must not be
    // demanded here either.
    final headIdError = EnrollmentIdNumber.validate(
      _householdHead!.idType,
      _householdHead!.idNumber,
      requiredMessage: EnrollmentStrings.idNumberRequiredError,
    );
    if (headIdError != null) {
      errors.add(headIdError);
    }
    // Spice: marital status mandatory when age ≥ 14.
    if (EnrollmentDob.needsMaritalStatus(
          EnrollmentDob.parse(_householdHead!.dateOfBirth),
          ageYears: _householdHead!.age,
        ) &&
        _householdHead!.maritalStatus.isEmpty) {
      errors.add(EnrollmentStrings.maritalStatusRequiredError);
    }
    // Android member_registration.json: disability mandatory for head too.
    final headDisability = _householdHead!.disabilityStatus.trim();
    if (headDisability.isEmpty ||
        headDisability.toLowerCase() == 'none' ||
        headDisability.toLowerCase() == 'absent') {
      errors.add(EnrollmentStrings.disabilityStatusRequiredError);
    }
    if (_householdHead!.mobileAvailable) {
      final mobileError = EnrollmentMobileNumber.validate(
        _householdHead!.mobileNumber,
        required: true,
        requiredMessage: EnrollmentStrings.mobileNumberRequiredError,
      );
      if (mobileError != null) errors.add(mobileError);
    }

    return errors;
  }

  /// Validate member form (for add/edit members).
  List<String> validateMemberForm(HouseholdMember member) {
    final errors = <String>[];

    if (member.name.trim().isEmpty) {
      errors.add(EnrollmentStrings.memberNameRequiredError);
    }
    if (member.age < 0) {
      errors.add(EnrollmentStrings.ageInvalidError);
    }
    if (member.dateOfBirth.isEmpty) {
      errors.add(EnrollmentStrings.memberDobRequiredError);
    }
    final memberIdError = EnrollmentIdNumber.validate(
      member.idType,
      member.idNumber,
      requiredMessage: EnrollmentStrings.idNumberRequiredError,
    );
    if (memberIdError != null) {
      errors.add(memberIdError);
    }
    // Android member_registration.json: phone + category + disability mandatory.
    if (member.phoneNumberCategory == null ||
        member.phoneNumberCategory!.trim().isEmpty) {
      errors.add(EnrollmentStrings.phoneCategoryRequiredError);
    }
    final mobileError = EnrollmentMobileNumber.validate(
      member.mobileNumber,
      required: true,
      requiredMessage: EnrollmentStrings.mobileNumberRequiredError,
    );
    if (mobileError != null) errors.add(mobileError);
    // Spice: marital status mandatory when age ≥ 14.
    final dob = EnrollmentDob.parse(member.dateOfBirth);
    if (EnrollmentDob.needsMaritalStatus(dob, ageYears: member.age) &&
        member.maritalStatus.isEmpty) {
      errors.add(EnrollmentStrings.maritalStatusRequiredError);
    }
    final disability = member.disabilityStatus.trim().toLowerCase();
    if (disability.isEmpty ||
        disability == 'none' ||
        disability == 'absent') {
      errors.add(EnrollmentStrings.disabilityStatusRequiredError);
    }
    // Spice: guardian mandatory when age ≤ 2.
    if (EnrollmentDob.needsGuardian(dob, ageYears: member.age) &&
        (member.guardianId == null || member.guardianId!.isEmpty)) {
      errors.add(CommonStrings.required);
    }

    return errors;
  }

  /// Submit household enrollment to `POST /offline-service/offline-sync/create`.
  ///
  /// Spice order: insert local rows (autoincrement PKs) → push with
  /// `referenceId = localId` → poll status to stamp `fhir_id` on the same rows.
  Future<bool> submitHousehold() async {
    final householdErrors = validateHouseholdForm();
    final headErrors = validateHeadForm();

    if (householdErrors.isNotEmpty || headErrors.isNotEmpty) {
      _error = EnrollmentStrings.requiredFieldsMissingError;
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

        // 1) Persist first so referenceIds are stable local autoincrement PKs.
        final result = await _persistLocally(
          location: (latitude: location.latitude, longitude: location.longitude),
        );
        if (result == null) {
          _error = EnrollmentStrings.saveLocallyFailedError;
          _setLoading(false);
          return false;
        }

        // 2) Build create payload using those local ids as referenceId.
        final (:body, requestId: requestId) = repo.buildPayload(
          household: _household!,
          head: _householdHead!,
          members: _members,
          userId: userId,
          userFhirId: userFhirId,
          organizationId: orgId,
          deviceId: deviceId,
          latitude: location.latitude,
          longitude: location.longitude,
          hhReferenceId: result.hhReferenceId,
          memberReferenceIds: result.memberReferenceIds,
        );

        // 3) Push in the background, then poll status to stamp fhir_id (Spice
        // getSyncStatusForOffline). The rows are already on disk, so the
        // enrollment is done from the health worker's side — awaiting the
        // network here would only make them sit on the form through a status
        // poll, and let a failure send them back to Continue, which would
        // re-run _persistLocally and duplicate the household.
        unawaited(
          _pushEnrollment(
            repo: repo,
            body: body,
            requestId: requestId,
            deviceId: deviceId,
            userId: userId,
          ),
        );
      } else {
        debugPrint('[EnrollmentController] mock submit: ${_household?.toJson()}');
        await Future.delayed(const Duration(milliseconds: 800));
      }

      _setLoading(false);
      return true;
    } on DioException catch (e) {
      // Anticipated failure: the request never reached the server (or was
      // rejected outright). Show the generic translated fallback rather than
      // the raw exception — a stack trace / status code means nothing to an SK.
      debugPrint('[EnrollmentController] submitHousehold network error: $e');
      _error = EnrollmentStrings.enrollmentFailed;
      _setLoading(false);
      return false;
    } on SocketException catch (e) {
      // Anticipated failure: device is offline.
      debugPrint('[EnrollmentController] submitHousehold offline: $e');
      _error = EnrollmentStrings.enrollmentFailed;
      _setLoading(false);
      return false;
    } catch (e) {
      // Truly unclassified — no getter can localize an arbitrary exception
      // message, so this is the only path that still surfaces raw text.
      debugPrint('[EnrollmentController] submitHousehold unexpected error: $e');
      _error = 'Enrollment failed: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Pushes an already-persisted enrollment and stamps the returned fhir_ids.
  ///
  /// Runs detached from [submitHousehold], so it must never throw, never touch
  /// controller state, and never notify: the screen has moved on and [reset]
  /// may already have cleared the form it was built from. Rows left unstamped
  /// stay pending and are retried by Offline Sync / the reconnect trigger.
  Future<void> _pushEnrollment({
    required EnrollmentRepository repo,
    required Map<String, dynamic> body,
    required String requestId,
    required String deviceId,
    required int userId,
  }) async {
    try {
      await repo.postEnrollment(body);
      await repo.pollAndApplyFhirIds(
        requestId: requestId,
        deviceId: deviceId,
        userId: userId,
        householdDao: _householdDao,
        memberDao: _memberDao,
      );
      debugPrint('[EnrollmentController] background push done');
    } on DioException catch (e) {
      debugPrint(_isNetworkError(e)
          ? '[EnrollmentController] offline — enrollment queued for sync'
          : '[EnrollmentController] push failed (HTTP ${e.response?.statusCode})'
              ' — enrollment queued for sync');
    } on SocketException {
      debugPrint('[EnrollmentController] offline — enrollment queued for sync');
    } catch (e) {
      debugPrint('[EnrollmentController] background push error: $e');
    }
  }

  /// Persist household + members with autoincrement local PKs (Spice order).
  /// Returns the local ids used as create `referenceId`s.
  Future<EnrollmentResult?> _persistLocally({
    required ({double latitude, double longitude}) location,
  }) async {
    final householdDao = _householdDao;
    final memberDao = _memberDao;
    final patientDao = _patientDao;
    if (householdDao == null || memberDao == null || patientDao == null) {
      debugPrint('[EnrollmentController] no DAOs injected — skipping local save');
      return null;
    }

    final hh = _household!;
    final head = _householdHead!;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Keep the two levels apart on every row. spice-service resolves the
    // hierarchy from villageId + subVillageId, so collapsing them (which the
    // household row used to do) makes every later add-member send the same id
    // for both and the FHIR mapper 500s.
    final parentVillageId = hh.villageId;
    final parentVillageName = hh.villageName;
    final subVillageId = hh.subVillageId;
    final subVillageName = hh.subVillageName;

    // Patients stay scoped to the finest level available — assessment pulls
    // are filtered by sub-village (Android getAllSubVillageIds).
    final canonicalVillageId =
        subVillageId?.isNotEmpty == true ? subVillageId! : parentVillageId;
    final canonicalVillageName =
        subVillageName?.isNotEmpty == true ? subVillageName : parentVillageName;

    // Household — autoincrement id; NotSynced until status stamps fhir_id.
    final hhLocalId = await householdDao.insertLocal(
      HouseholdEntity(
        id: '0',
        householdNo: hh.householdNumber,
        name: head.name,
        village: parentVillageName,
        villageId: parentVillageId,
        subVillageId: subVillageId,
        subVillageName: subVillageName,
        memberCount: 1 + _members.length,
        latitude: location.latitude,
        longitude: location.longitude,
        createdAt: nowMs,
        updatedAt: nowMs,
        syncStatus: 'NotSynced',
      ),
    );
    // reference_id mirrors local PK (Spice push uses id as referenceId).
    await householdDao.setReferenceId(hhLocalId);

    final membersToSave = <HouseholdMember>[head, ..._members];
    final memberLocalIds = <String>[];
    // Client enrollment ids → local PKs so guardian pointers resolve like
    // Android's Long guardianId after sequential member inserts.
    final clientToLocal = <String, String>{};

    for (var i = 0; i < membersToSave.length; i++) {
      final m = membersToSave[i];
      final clientKey = (m.id != null && m.id!.isNotEmpty) ? m.id! : 'idx-$i';
      final resolvedGuardianId = m.guardianId == null || m.guardianId!.isEmpty
          ? null
          : clientToLocal[m.guardianId!];
      final memberLocalId = await memberDao.insertLocal(
        HouseholdMemberEntity(
          id: '0',
          householdId: hhLocalId,
          householdReferenceId: hhLocalId,
          referenceId: null,
          name: m.name,
          gender: m.gender,
          dob: m.dateOfBirth,
          phone: m.mobileNumber,
          phoneNumberCategory: m.phoneNumberCategory,
          nationalId: m.idNumber,
          idType: m.idType,
          villageId: parentVillageId,
          villageName: parentVillageName,
          subVillageId: subVillageId,
          subVillageName: subVillageName,
          maritalStatus: m.maritalStatus,
          disability: m.disabilityStatus.toLowerCase(),
          guardianId: resolvedGuardianId,
          guardianFhirId: m.guardianFhirId,
          isHouseholdHead: i == 0,
          isActive: true,
          isPregnant: false,
          latitude: location.latitude,
          longitude: location.longitude,
          createdAt: nowMs,
          updatedAt: nowMs,
          syncStatus: 'NotSynced',
        ),
      );
      await memberDao.setReferenceId(memberLocalId);
      memberLocalIds.add(memberLocalId);
      clientToLocal[clientKey] = memberLocalId;

      // Patient keyed by stable local member id (never swapped for FHIR).
      final patientRaw = jsonEncode({
        'id': memberLocalId,
        'name': m.name,
        'gender': m.gender,
        'dateOfBirth': m.dateOfBirth,
        'phoneNumber': m.mobileNumber,
        'nationalId': m.idNumber,
        'villageId': canonicalVillageId,
        'houseHoldId': hhLocalId,
        'isActive': true,
      });
      await patientDao.upsertMany([
        Patient(
          id: memberLocalId,
          name: m.name,
          gender: m.gender,
          dob: m.dateOfBirth,
          phone: m.mobileNumber,
          nationalId: m.idNumber,
          villageId: canonicalVillageId,
          villageName: canonicalVillageName,
          householdId: hhLocalId,
          isActive: true,
          updatedAt: nowMs,
          rawJson: patientRaw,
        ),
      ]);
    }

    // Rewrite in-memory guardian ids to local PKs for the create payload.
    for (var i = 0; i < _members.length; i++) {
      final m = _members[i];
      final resolvedGuardian = m.guardianId == null || m.guardianId!.isEmpty
          ? null
          : clientToLocal[m.guardianId!];
      // Reconstruct so a failed resolve clears the client-uuid guardian pointer
      // (copyWith cannot assign null over a non-null field).
      _members[i] = HouseholdMember(
        id: memberLocalIds[i + 1],
        name: m.name,
        age: m.age,
        gender: m.gender,
        dateOfBirth: m.dateOfBirth,
        idType: m.idType,
        idNumber: m.idNumber,
        mobileNumber: m.mobileNumber,
        phoneNumberCategory: m.phoneNumberCategory,
        mobileAvailable: m.mobileAvailable,
        maritalStatus: m.maritalStatus,
        disabilityStatus: m.disabilityStatus,
        relationshipToHead: m.relationshipToHead,
        villageId: m.villageId,
        nidScanned: m.nidScanned,
        guardianId: resolvedGuardian,
        guardianFhirId: m.guardianFhirId,
      );
    }

    debugPrint('[EnrollmentController] locally saved: '
        'household=$hhLocalId members=${memberLocalIds.length}');

    // Tell any mounted roster screen to re-query; enrollment leaves via
    // go('/home'), so the Patients tab gets no navigation event of its own.
    bumpRosterRevision();

    return EnrollmentResult(
      hhReferenceId: hhLocalId,
      memberReferenceIds: memberLocalIds,
    );
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
  /// Matches Android's HouseRegistrationViewModel.generateHouseholdNumber():
  ///   val householdNumber = "HH${currentHouseholdsCount + 1}"
  Future<String> _generateHouseholdNumber() async {
    final count = await _householdDao?.count() ?? 0;
    return 'HH${count + 1}';
  }

  static bool _isNetworkError(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout;
}
