import 'package:uuid/uuid.dart';

import '../../../core/api/api_repository.dart';
import '../../../core/api/endpoints.dart';
import 'models/household_enrollment_models.dart';

/// Submits a completed household enrollment to
/// `POST /offline-service/offline-sync/create`.
///
/// Postman-verified payload shape. All field mappings follow the canonical
/// `create-record` example in the Leapfrog postman collection.
class EnrollmentRepository extends ApiRepository {
  EnrollmentRepository(super.api);

  static const _uuid = Uuid();

  /// Build and POST the offline-sync/create payload.
  ///
  /// [household] and [head] must pass their respective validation checks before
  /// this is called. [members] may be empty (head-only enrollment).
  ///
  /// [userId] / [organizationId] come from [AuthRepository] and are stamped
  /// into every provenance block. [deviceId] is the stable per-device UUID
  /// from secure storage.
  Future<void> submit({
    required Household household,
    required HouseholdHeadInfo head,
    required List<HouseholdMember> members,
    required int userId,
    required String organizationId,
    required String deviceId,
    String appVersionName = '2.0.3',
    int appVersionCode = 10,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hhReferenceId = _uuid.v4();

    final provenance = {
      'modifiedDate': DateTime.now().toUtc().toIso8601String(),
      'organizationId': organizationId,
      'spiceUserId': userId,
      'userId': userId.toString(),
    };

    final villageId = int.tryParse(household.villageId) ?? 0;
    final subVillageId = int.tryParse(household.subVillageId ?? '') ?? 0;

    // Build member rows — head first, then additional members.
    final allMembers = <Map<String, dynamic>>[
      _memberPayload(
        member: head,
        householdReferenceId: hhReferenceId,
        isHouseholdHead: true,
        villageId: villageId,
        subVillageId: subVillageId,
        villageName: household.villageName ?? '',
        subVillageName: household.subVillageName ?? '',
        provenance: provenance,
        nowMs: nowMs,
      ),
      for (final m in members)
        _memberPayload(
          member: m,
          householdReferenceId: hhReferenceId,
          isHouseholdHead: false,
          villageId: villageId,
          subVillageId: subVillageId,
          villageName: household.villageName ?? '',
          subVillageName: household.subVillageName ?? '',
          provenance: provenance,
          nowMs: nowMs,
        ),
    ];

    final hhPayload = {
      'referenceId': hhReferenceId,
      'name': head.name,
      'householdNo': household.householdNumber,
      'householdType': household.householdType,
      'villageId': villageId,
      'subVillageId': subVillageId,
      'village': household.villageName ?? '',
      'shasthyaShebikaId': userId,
      'noOfPeople': household.numberOfMembers,
      'householdHeadOccupation': household.occupation,
      if (household.occupation.toLowerCase() == 'other')
        'otherOccupation': household.occupation,
      'monthlyIncome': _incomeToInt(household.monthlyIncome),
      'disabilityPersonsCount': household.disabilityQuestion ? 1 : 0,
      'latitude': 0.0,
      'longitude': 0.0,
      'provenance': provenance,
      'householdMembers': allMembers,
      'createdAt': nowMs,
      'updatedAt': nowMs,
    };

    final body = {
      'requestId': _uuid.v4(),
      'appVersionName': appVersionName,
      'appVersionCode': appVersionCode,
      'deviceId': deviceId,
      'appType': 'COMMUNITY',
      'syncMode': 'AutomaticSync',
      'households': [hhPayload],
      'householdMembers': <dynamic>[],
      'assessments': <dynamic>[],
      'followUps': <dynamic>[],
      'householdMemberLinks': <dynamic>[],
      'communityProfiles': <dynamic>[],
      'rxBuddies': <dynamic>[],
    };

    await postOk(Endpoints.offlineSyncCreate, data: body, action: 'Enrollment');
  }

  Map<String, dynamic> _memberPayload({
    required HouseholdMember member,
    required String householdReferenceId,
    required bool isHouseholdHead,
    required int villageId,
    required int subVillageId,
    required String villageName,
    required String subVillageName,
    required Map<String, dynamic> provenance,
    required int nowMs,
  }) {
    return {
      'referenceId': _uuid.v4(),
      'householdReferenceId': householdReferenceId,
      'name': member.name,
      'nationalId': member.idNumber ?? '',
      'idType': member.idType.toLowerCase(),
      'dateOfBirth': _normaliseDob(member.dateOfBirth),
      'gender': member.gender.toLowerCase(),
      'isHouseholdHead': isHouseholdHead,
      'isActive': true,
      'isChild': member.age < 18,
      'maritalStatus': member.maritalStatus.toLowerCase(),
      'disability': member.disabilityStatus.toLowerCase() == 'none'
          ? 'absent'
          : 'present',
      'villageId': villageId,
      'subVillageId': subVillageId,
      'village': villageName,
      'subVillage': subVillageName,
      'phoneNumber': member.mobileNumber ?? '',
      'latitude': 0.0,
      'longitude': 0.0,
      'provenance': provenance,
      'assessments': <dynamic>[],
      'rxBuddies': <dynamic>[],
      'createdAt': nowMs,
      'updatedAt': nowMs,
    };
  }

  /// Map income bracket strings to midpoint integers expected by the API.
  static int _incomeToInt(String bracket) {
    switch (bracket) {
      case '<10000':
        return 9999;
      case '10000-25000':
        return 17500;
      case '25000-50000':
        return 37500;
      case '>50000':
        return 60000;
      default:
        return int.tryParse(bracket) ?? 0;
    }
  }

  /// Ensure DOB is ISO-8601 with UTC offset suffix: "YYYY-MM-DDT00:00:00+00:00".
  static String _normaliseDob(String dob) {
    if (dob.isEmpty) return dob;
    // Already has time component — return as-is.
    if (dob.contains('T')) return dob;
    return '${dob}T00:00:00+00:00';
  }
}
