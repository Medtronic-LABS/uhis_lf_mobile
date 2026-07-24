import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_repository.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/provance_dto.dart';
import 'models/household_enrollment_models.dart';

/// IDs generated during enrollment — returned from [EnrollmentRepository.submit]
/// so the controller can persist the household locally without a round-trip.
class EnrollmentResult {
  const EnrollmentResult({
    required this.hhReferenceId,
    required this.memberReferenceIds,
  });

  /// UUID assigned to the household in the sync payload.
  final String hhReferenceId;

  /// UUID assigned to each member (head first, then additional members).
  final List<String> memberReferenceIds;
}

/// Result from [EnrollmentRepository.submitStandaloneMember].
class StandaloneMemberResult {
  const StandaloneMemberResult({required this.memberReferenceId});

  /// UUID assigned to the new member in the sync payload.
  final String memberReferenceId;
}

/// Submits a completed household enrollment to
/// `POST /offline-service/offline-sync/create`.
///
/// Postman-verified payload shape. All field mappings follow the canonical
/// `create-record` example in the Leapfrog postman collection.
/// Matches Android's HouseHoldRepository.submitHousehold pattern.
class EnrollmentRepository extends ApiRepository {
  EnrollmentRepository(super.api);

  static const _uuid = Uuid();
  static const _skRole = 'SHASTIYA_KORMI';

  /// Build and POST the offline-sync/create payload matching Android.
  ///
  /// [household] and [head] must pass their respective validation checks before
  /// this is called. [members] may be empty (head-only enrollment).
  ///
  /// [userId] / [organizationId] come from [AuthRepository] and are stamped
  /// into every provenance block. [deviceId] is the stable per-device UUID
  /// from secure storage.
  ///
  /// Returns [EnrollmentResult] with the generated reference IDs so the caller
  /// can persist the data locally immediately (offline-first pattern matching
  /// Android's HouseHoldRepository.insertHouseHoldEntity / registerMember).
  /// Build the offline-sync/create payload without making a network call.
  /// Returns the body map and the pre-generated reference IDs so the caller
  /// can persist locally before attempting the POST.
  ({Map<String, dynamic> body, EnrollmentResult result}) buildPayload({
    required Household household,
    required HouseholdHeadInfo head,
    required List<HouseholdMember> members,
    required int userId,
    required String userFhirId,
    required String organizationId,
    required String deviceId,
    double latitude = 0.0,
    double longitude = 0.0,
    String appVersionName = AppConfig.appVersionName,
    int appVersionCode = AppConfig.appVersionCode,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hhReferenceId = _uuid.v4();

    final provenance = ProvanceDto.fromMap({
      'modifiedDate': DateTime.now().toUtc().toIso8601String(),
      'organizationId': organizationId,
      'spiceUserId': userId,
      'userId': userFhirId,
      'spiceRole': _skRole,
    });

    final villageId = int.tryParse(household.villageId) ?? 0;
    final subVillageId = int.tryParse(household.subVillageId ?? '') ?? 0;
    final ssWorkerId = int.tryParse(household.healthWorkerId) ?? userId;

    final headRefId = _uuid.v4();
    final extraRefIds = [for (final _ in members) _uuid.v4()];

    final allMembers = <Map<String, dynamic>>[
      _memberPayload(
        referenceId: headRefId,
        member: head,
        householdReferenceId: hhReferenceId,
        isHouseholdHead: true,
        villageId: villageId,
        subVillageId: subVillageId,
        villageName: household.villageName ?? '',
        provenance: provenance,
        nowMs: nowMs,
        skUserId: userId,
        ssWorkerId: ssWorkerId,
        latitude: latitude,
        longitude: longitude,
      ),
      for (var i = 0; i < members.length; i++)
        _memberPayload(
          referenceId: extraRefIds[i],
          member: members[i],
          householdReferenceId: hhReferenceId,
          isHouseholdHead: false,
          villageId: villageId,
          subVillageId: subVillageId,
          villageName: household.villageName ?? '',
          provenance: provenance,
          nowMs: nowMs,
          skUserId: userId,
          ssWorkerId: ssWorkerId,
          latitude: latitude,
          longitude: longitude,
        ),
    ];

    final householdNo = int.tryParse(household.householdNumber) ?? nowMs;

    final hhPayload = {
      'referenceId': hhReferenceId,
      'name': head.name,
      'householdNo': householdNo,
      'householdType': household.householdType,
      'villageId': villageId,
      'subVillageId': subVillageId,
      'village': household.villageName ?? '',
      'shasthyaShebikaId': ssWorkerId,
      'noOfPeople': household.numberOfMembers,
      'householdHeadOccupation': household.occupation,
      if (household.occupation.toLowerCase() == 'other')
        'otherOccupation': household.occupation,
      'monthlyIncome': _incomeToInt(household.monthlyIncome),
      'disabilityPersonsCount': household.disabilityQuestion ? 1 : 0,
      'latitude': latitude,
      'longitude': longitude,
      'provenance': provenance.toJson(),
      'householdMembers': allMembers,
      'createdAt': nowMs,
      'updatedAt': nowMs,
    };

    final body = {
      'requestId': _uuid.v4(),
      'appVersionName': appVersionName,
      'appVersionCode': appVersionCode,
      'deviceId': deviceId,
      'appType': AppConfig.appType,
      'syncMode': 'AutomaticSync',
      'households': [hhPayload],
      'householdMembers': <dynamic>[],
      'assessments': <dynamic>[],
      'followUps': <dynamic>[],
      'householdMemberLinks': <dynamic>[],
      'communityProfiles': <dynamic>[],
      'rxBuddies': <dynamic>[],
    };

    return (
      body: body,
      result: EnrollmentResult(
        hhReferenceId: hhReferenceId,
        memberReferenceIds: [headRefId, ...extraRefIds],
      ),
    );
  }

  /// POST a pre-built payload to offline-sync/create.
  Future<void> postEnrollment(Map<String, dynamic> body) async {
    if (kDebugMode) {
      debugPrint('[EnrollmentRepository] offline-sync/create payload:\n'
          '${const JsonEncoder.withIndent('  ').convert(body)}');
    }
    await postOk(Endpoints.offlineSyncCreate, data: body, action: 'Enrollment');
  }

  Future<EnrollmentResult> submit({
    required Household household,
    required HouseholdHeadInfo head,
    required List<HouseholdMember> members,
    required int userId,
    required String userFhirId,
    required String organizationId,
    required String deviceId,
    double latitude = 0.0,
    double longitude = 0.0,
    String appVersionName = AppConfig.appVersionName,
    int appVersionCode = AppConfig.appVersionCode,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hhReferenceId = _uuid.v4();

    final provenance = ProvanceDto.fromMap({
      'modifiedDate': DateTime.now().toUtc().toIso8601String(),
      'organizationId': organizationId,
      'spiceUserId': userId,
      'userId': userFhirId,
      'spiceRole': _skRole,
    });

    final villageId = int.tryParse(household.villageId) ?? 0;
    final subVillageId = int.tryParse(household.subVillageId ?? '') ?? 0;
    // SS worker assigned to the household — distinct from the SK (logged-in user).
    final ssWorkerId = int.tryParse(household.healthWorkerId) ?? userId;

    // Pre-generate member reference IDs so they can be returned for local save.
    final headRefId = _uuid.v4();
    final extraRefIds = [for (final _ in members) _uuid.v4()];

    // Build member rows — head first, then additional members.
    final allMembers = <Map<String, dynamic>>[
      _memberPayload(
        referenceId: headRefId,
        member: head,
        householdReferenceId: hhReferenceId,
        isHouseholdHead: true,
        villageId: villageId,
        subVillageId: subVillageId,
        villageName: household.villageName ?? '',
        provenance: provenance,
        nowMs: nowMs,
        skUserId: userId,
        ssWorkerId: ssWorkerId,
        latitude: latitude,
        longitude: longitude,
      ),
      for (var i = 0; i < members.length; i++)
        _memberPayload(
          referenceId: extraRefIds[i],
          member: members[i],
          householdReferenceId: hhReferenceId,
          isHouseholdHead: false,
          villageId: villageId,
          subVillageId: subVillageId,
          villageName: household.villageName ?? '',
          provenance: provenance,
          nowMs: nowMs,
          skUserId: userId,
          ssWorkerId: ssWorkerId,
          latitude: latitude,
          longitude: longitude,
        ),
    ];

    // Use the household number generated by the controller (numeric epoch-ms
    // string, matching Android's "HH${System.currentTimeMillis()}" fallback but
    // sent as a JSON number, not a string, per SPICE backend expectations).
    final householdNo = int.tryParse(household.householdNumber) ?? nowMs;

    final hhPayload = {
      'referenceId': hhReferenceId,
      'name': head.name,
      'householdNo': householdNo,
      'householdType': household.householdType,
      'villageId': villageId,
      'subVillageId': subVillageId,
      'village': household.villageName ?? '',
      'shasthyaShebikaId': ssWorkerId,
      'noOfPeople': household.numberOfMembers,
      'householdHeadOccupation': household.occupation,
      if (household.occupation.toLowerCase() == 'other')
        'otherOccupation': household.occupation,
      'monthlyIncome': _incomeToInt(household.monthlyIncome),
      'disabilityPersonsCount': household.disabilityQuestion ? 1 : 0,
      'latitude': latitude,
      'longitude': longitude,
      'provenance': provenance.toJson(),
      'householdMembers': allMembers,
      'createdAt': nowMs,
      'updatedAt': nowMs,
    };

    final body = {
      'requestId': _uuid.v4(),
      'appVersionName': appVersionName,
      'appVersionCode': appVersionCode,
      'deviceId': deviceId,
      'appType': AppConfig.appType,
      'syncMode': 'AutomaticSync',
      'households': [hhPayload],
      'householdMembers': <dynamic>[],
      'assessments': <dynamic>[],
      'followUps': <dynamic>[],
      'householdMemberLinks': <dynamic>[],
      'communityProfiles': <dynamic>[],
      'rxBuddies': <dynamic>[],
    };

    if (kDebugMode) {
      debugPrint('[EnrollmentRepository] offline-sync/create payload:\n'
          '${const JsonEncoder.withIndent('  ').convert(body)}');
    }
    await postOk(Endpoints.offlineSyncCreate, data: body, action: 'Enrollment');

    return EnrollmentResult(
      hhReferenceId: hhReferenceId,
      memberReferenceIds: [headRefId, ...extraRefIds],
    );
  }

  /// Submit a **single member** to an **already-synced household**.
  ///
  /// Matches Android's OfflineSyncRepository path:
  ///   request["households"]       = []
  ///   request["householdMembers"] = [HouseHoldMember(householdId=fhirId, ...)]
  ///
  /// [householdId] is the household's FHIR/server ID (HouseholdEntity.fhirId).
  /// [householdReferenceId] is the household's local reference ID (HouseholdEntity.id).
  ///
  /// Returns a [StandaloneMemberResult] containing the UUID that was assigned
  /// to the new member so the controller can persist it locally immediately.
  Future<StandaloneMemberResult> submitStandaloneMember({
    required HouseholdMember member,
    required String householdId,
    required String householdReferenceId,
    required String villageName,
    required String villageId,
    String? subVillageId,
    String? subVillageName,
    required int userId,
    required String userFhirId,
    required String organizationId,
    required String deviceId,
    double latitude = 0.0,
    double longitude = 0.0,
    String appVersionName = AppConfig.appVersionName,
    int appVersionCode = AppConfig.appVersionCode,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final memberRefId = _uuid.v4();

    final provenance = ProvanceDto.fromMap({
      'modifiedDate': DateTime.now().toUtc().toIso8601String(),
      'organizationId': organizationId,
      'spiceUserId': userId,
      'userId': userFhirId,
      'spiceRole': _skRole,
    });

    final vId = int.tryParse(villageId) ?? 0;
    final svId = int.tryParse(subVillageId ?? '') ?? 0;
    final ssWorkerId = userId;

    final normDob = _normaliseDob(member.dateOfBirth);

    // Member payload mirroring Android HouseHoldMember DTO when household
    // already has a fhirId (server has already processed the household).
    final memberPayload = {
      'referenceId': memberRefId,
      'householdId': householdId,           // FHIR ID of the existing household
      'householdReferenceId': householdReferenceId, // local UUID / ref
      'name': member.name,
      'nationalId': member.idNumber ?? '',
      'idType': _normalizeIdType(member.idType),
      'dateOfBirth': normDob,
      'gender': member.gender.toLowerCase(),
      'isHouseholdHead': false,
      'isActive': true,
      'isChild': _isChild(member.age, normDob),
      'maritalStatus': member.maritalStatus.toLowerCase(),
      'disability': _disabilityValue(member.disabilityStatus),
      'villageId': vId,
      if (svId > 0) 'subVillageId': svId,
      if (subVillageName?.isNotEmpty == true) 'subVillage': subVillageName,
      'village': villageName,
      'phoneNumber': member.mobileNumber ?? '',
      'phoneNumberCategory': '',
      'shasthyaShebikaId': ssWorkerId,
      'shasthyaKormiId': userId,
      'createdByRoleName': _skRole,
      'createdBySpiceUserId': userId,
      'assignHousehold': false,
      'isPregnant': false,
      'hasTbContactTracing': false,
      'children': <dynamic>[],
      'latitude': latitude,
      'longitude': longitude,
      'provenance': provenance.toJson(),
      'assessments': <dynamic>[],
      'rxBuddies': <dynamic>[],
      'createdAt': nowMs,
      'updatedAt': nowMs,
    };

    final body = {
      'requestId': _uuid.v4(),
      'appVersionName': appVersionName,
      'appVersionCode': appVersionCode,
      'deviceId': deviceId,
      'appType': AppConfig.appType,
      'syncMode': 'AutomaticSync',
      'households': <dynamic>[],
      'householdMembers': [memberPayload],
      'assessments': <dynamic>[],
      'followUps': <dynamic>[],
      'householdMemberLinks': <dynamic>[],
      'communityProfiles': <dynamic>[],
      'rxBuddies': <dynamic>[],
    };

    if (kDebugMode) {
      debugPrint('[EnrollmentRepository] standalone member payload:\n'
          '${const JsonEncoder.withIndent('  ').convert(body)}');
    }
    await postOk(Endpoints.offlineSyncCreate,
        data: body, action: 'LinkMemberToHousehold');

    return StandaloneMemberResult(memberReferenceId: memberRefId);
  }

  Map<String, dynamic> _memberPayload({
    required String referenceId,
    required HouseholdMember member,
    required String householdReferenceId,
    required bool isHouseholdHead,
    required int villageId,
    required int subVillageId,
    required String villageName,
    required ProvanceDto provenance,
    required int nowMs,
    required int skUserId,
    required int ssWorkerId,
    double latitude = 0.0,
    double longitude = 0.0,
  }) {
    final normDob = _normaliseDob(member.dateOfBirth);
    return {
      'referenceId': referenceId,
      'householdReferenceId': householdReferenceId,
      'name': member.name,
      'nationalId': member.idNumber ?? '',
      'idType': _normalizeIdType(member.idType),
      'dateOfBirth': normDob,
      'gender': member.gender.toLowerCase(),
      'isHouseholdHead': isHouseholdHead,
      'isActive': true,
      'isChild': _isChild(member.age, normDob),
      'maritalStatus': member.maritalStatus.toLowerCase(),
      'disability': _disabilityValue(member.disabilityStatus),
      'villageId': villageId,
      'subVillageId': subVillageId,
      'village': villageName,
      'phoneNumber': member.mobileNumber ?? '',
      'phoneNumberCategory': '',
      'shasthyaShebikaId': ssWorkerId,
      'shasthyaKormiId': skUserId,
      'createdByRoleName': _skRole,
      'createdBySpiceUserId': skUserId,
      'assignHousehold': false,
      'isPregnant': false,
      'hasTbContactTracing': false,
      'initial': '',
      'signature': '',
      'memberId': '',
      'patientReference': '',
      'householdHeadRelationship': isHouseholdHead ? 'Self' : '',
      'motherMemberId': '',
      'children': <dynamic>[],
      'latitude': latitude,
      'longitude': longitude,
      'provenance': provenance.toJson(),
      'assessments': <dynamic>[],
      'rxBuddies': <dynamic>[],
      'createdAt': nowMs,
      'updatedAt': nowMs,
    };
  }

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

  static String _normaliseDob(String dob) {
    if (dob.isEmpty) return dob;
    if (dob.contains('T')) return dob;

    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob.trim())) {
      return '${dob.trim()}T00:00:00+00:00';
    }

    final match =
        RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,4})\s+(\d{4})$').firstMatch(dob.trim());
    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final month = _parseMonth(match.group(2)!);
      final year = int.tryParse(match.group(3)!);
      if (day != null && month != null && year != null) {
        final d = DateTime.utc(year, month, day);
        final iso = d.toIso8601String().split('T')[0];
        return '${iso}T00:00:00+00:00';
      }
    }

    return '';
  }

  static int? _parseMonth(String abbr) {
    const map = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
      'may': 5, 'jun': 6, 'jul': 7, 'aug': 8,
      'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      'noy': 11, 'nob': 11, 'okt': 10, 'agt': 8,
      'jao': 1,  'fob': 2,  'mao': 3,
    };
    return map[abbr.toLowerCase()];
  }

  static bool _isChild(int age, String normDob) {
    if (age > 0) return age < 18;
    if (normDob.isEmpty) return false;
    final parsed = DateTime.tryParse(normDob);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inDays < 18 * 365;
  }

  static String _normalizeIdType(String raw) {
    final s = raw.toLowerCase().replaceAll(' ', '');
    return s == 'nationalid' ? 'nid' : s;
  }

  static String _disabilityValue(String status) {
    final s = status.toLowerCase();
    return (s == 'none' || s == 'absent') ? 'absent' : 'present';
  }
}
