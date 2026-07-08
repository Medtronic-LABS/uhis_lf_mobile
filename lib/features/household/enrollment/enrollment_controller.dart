import 'package:flutter/foundation.dart';
import 'dart:math';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/services/location_service.dart';
import 'enrollment_repository.dart';
import 'models/household_enrollment_models.dart';

/// Controller for managing household enrollment state across all screens.
///
/// Holds the active household being enrolled, the household head info, and
/// any members being added. Provides methods to update form state, generate
/// household numbers, and submit to [EnrollmentRepository].
///
/// Use via Provider to share state across enrollment screens.
class EnrollmentController extends ChangeNotifier {
  EnrollmentController({AuthRepository? auth, ApiClient? apiClient})
      : _auth = auth,
        _repo = (auth != null && apiClient != null)
            ? EnrollmentRepository(apiClient)
            : null;

  final AuthRepository? _auth;
  final EnrollmentRepository? _repo;

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

        await repo.submit(
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

  /// Auto-generate a household number in the format HH-YYYY-XXXX.
  String _generateHouseholdNumber() {
    final year = DateTime.now().year;
    final random = Random();
    final seq = random.nextInt(10000).toString().padLeft(4, '0');
    return 'HH-$year-$seq';
  }
}
