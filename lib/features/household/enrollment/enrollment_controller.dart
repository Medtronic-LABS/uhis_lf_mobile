import 'package:flutter/foundation.dart';
import 'dart:math';

import 'models/household_enrollment_models.dart';

/// Controller for managing household enrollment state across all screens.
///
/// Holds the active household being enrolled, the household head info, and
/// any members being added. Provides methods to update form state, generate
/// household numbers, and handle mock NID scans.
///
/// Use via Provider to share state across enrollment screens.
class EnrollmentController extends ChangeNotifier {
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
  }) {
    final householdNumber = _generateHouseholdNumber();
    _household = Household(
      householdNumber: householdNumber,
      healthWorkerId: healthWorkerId,
      villageId: villageId,
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
    String? householdType,
    int? numberOfMembers,
    String? houseNumber,
    String? occupation,
    String? monthlyIncome,
    bool? disabilityQuestion,
    String? disabilityDetails,
  }) {
    if (_household == null) return;

    _household = _household!.copyWith(
      householdType: householdType,
      numberOfMembers: numberOfMembers,
      houseNumber: houseNumber,
      occupation: occupation,
      monthlyIncome: monthlyIncome,
      disabilityQuestion: disabilityQuestion,
      disabilityDetails: disabilityDetails,
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
    bool? mobileAvailable,
    required String maritalStatus,
    required String disabilityStatus,
    bool? nidScanned,
  }) {
    _householdHead = HouseholdHeadInfo(
      name: name,
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
    if (_household!.occupation.trim().isEmpty) {
      errors.add('Occupation is required');
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
    if (_householdHead!.age <= 0) {
      errors.add('Head age must be valid');
    }
    if (_householdHead!.dateOfBirth.isEmpty) {
      errors.add('Date of birth is required');
    }
    if (_householdHead!.idNumber?.trim().isEmpty ?? true) {
      errors.add('ID number is required');
    }
    if (!_householdHead!.mobileAvailable &&
        (_householdHead!.mobileNumber?.trim().isEmpty ?? true)) {
      errors.add('Mobile number is required');
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

  /// Submit household enrollment (mocked for now).
  /// Backend integration to come later.
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
      await Future.delayed(const Duration(milliseconds: 1200));

      // TODO: Post to backend when ready
      // For now, just log the data
      final enrollmentData = {
        'household': _household?.toJson(),
        'head': _householdHead?.toJson(),
        'members': _members.map((m) => m.toJson()).toList(),
      };
      debugPrint('Enrollment data (to be posted): $enrollmentData');

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
