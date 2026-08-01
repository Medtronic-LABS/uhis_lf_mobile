import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_repository.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/provance_dto.dart';
import 'models/household_enrollment_models.dart';

/// IDs generated during enrollment — local autoincrement PKs used as
/// create `referenceId`s (Spice parity).
class EnrollmentResult {
  const EnrollmentResult({
    required this.hhReferenceId,
    required this.memberReferenceIds,
  });

  /// Local households.id used as create referenceId.
  final String hhReferenceId;

  /// Local members.id values (head first, then additional members).
  final List<String> memberReferenceIds;
}

/// Result from [EnrollmentRepository.submitStandaloneMember].
class StandaloneMemberResult {
  const StandaloneMemberResult({
    required this.memberReferenceId,
    required this.requestId,
  });

  /// Local member PK sent as the create `referenceId`.
  final String memberReferenceId;

  /// Id of the create request — needed to poll `offline-sync/status` and stamp
  /// the returned `fhir_id` back onto the local row.
  final String requestId;
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
  ///
  /// [hhReferenceId] / [memberReferenceIds] must be the local autoincrement
  /// PKs already inserted (Spice: referenceId = local id).
  ({Map<String, dynamic> body, String requestId}) buildPayload({
    required Household household,
    required HouseholdHeadInfo head,
    required List<HouseholdMember> members,
    required int userId,
    required String userFhirId,
    required String organizationId,
    required String deviceId,
    required String hhReferenceId,
    required List<String> memberReferenceIds,
    double latitude = 0.0,
    double longitude = 0.0,
    String appVersionName = AppConfig.appVersionName,
    int appVersionCode = AppConfig.appVersionCode,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final headRefId = memberReferenceIds.first;
    final extraRefIds = memberReferenceIds.length > 1
        ? memberReferenceIds.sublist(1)
        : <String>[];

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
        'otherOccupation': household.otherOccupation,
      // Android's HouseHold model carries both: the form only ever writes the
      // range, and `monthlyIncome` stays a legacy numeric mirror.
      'monthlyIncomeRange': household.monthlyIncomeRange,
      'monthlyIncome': _incomeMidpoint(household.monthlyIncomeRange),
      'disabilityPersonsCount': household.disabilityPersonsCount,
      'latitude': latitude,
      'longitude': longitude,
      'provenance': provenance.toJson(),
      'householdMembers': allMembers,
      'createdAt': nowMs,
      'updatedAt': nowMs,
    };

    final requestId = _uuid.v4();
    final body = {
      'requestId': requestId,
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

    return (body: body, requestId: requestId);
  }

  /// POST a pre-built payload to offline-sync/create.
  Future<void> postEnrollment(Map<String, dynamic> body) async {
    if (kDebugMode) {
      debugPrint('[EnrollmentRepository] offline-sync/create payload:\n'
          '${const JsonEncoder.withIndent('  ').convert(body)}');
    }
    await postOk(Endpoints.offlineSyncCreate, data: body, action: 'Enrollment');
  }

  /// Poll `/offline-sync/status` and stamp `fhir_id` onto local rows.
  ///
  /// Mirrors Spice `OfflineSyncRepository.getSyncStatusForOffline` +
  /// `RoomHelper.updateFhirId`. Same row keeps its local PK.
  Future<void> pollAndApplyFhirIds({
    required String requestId,
    required String deviceId,
    required int userId,
    HouseholdDao? householdDao,
    MemberDao? memberDao,
    int maxAttempts = 4,
    Duration delayBetween = const Duration(seconds: 10),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) await Future<void>.delayed(delayBetween);

      final body = <String, dynamic>{
        'requestId': requestId,
        'dataRequired': false,
        'userId': userId,
        'appVersionName': AppConfig.appVersionName,
        'appVersionCode': AppConfig.appVersionCode,
        if (deviceId.isNotEmpty) 'deviceId': deviceId,
      };

      try {
        final data = await postOk(
          Endpoints.offlineSyncStatus,
          data: body,
          action: 'Enrollment status',
        );
        final entities = data is Map ? data['entityList'] : null;
        debugPrint('[EnrollmentRepository] status poll $attempt/$maxAttempts '
            'entities=${entities is List ? entities.length : 0}');

        if (entities is! List || entities.isEmpty) continue;

        var anyInProgress = false;
        for (final raw in entities) {
          if (raw is! Map) continue;
          final type = raw['type']?.toString() ?? '';
          final status = raw['status']?.toString() ?? '';
          final refId = raw['referenceId']?.toString();
          final fhirId = raw['fhirId']?.toString();

          if (status == 'InProgress') {
            anyInProgress = true;
            continue;
          }
          if (refId == null || refId.isEmpty) continue;
          if (status != 'Success' && status != 'Failed') continue;

          final typeLower = type.toLowerCase();
          if (typeLower.contains('household') &&
              !typeLower.contains('member') &&
              householdDao != null) {
            await householdDao.updateFhirId(
              localId: refId,
              fhirId: status == 'Success' ? fhirId : null,
              syncStatus: status,
            );
          } else if (typeLower.contains('member') && memberDao != null) {
            await memberDao.updateFhirId(
              localId: refId,
              fhirId: status == 'Success' ? fhirId : null,
              syncStatus: status,
            );
          }
        }

        if (!anyInProgress) {
          debugPrint('[EnrollmentRepository] status terminal — fhir ids stamped');
          return;
        }
      } catch (e) {
        debugPrint('[EnrollmentRepository] status poll error: $e');
      }
    }
    debugPrint('[EnrollmentRepository] status poll exhausted — warm sync '
        'will merge by fhir_id');
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
        'otherOccupation': household.otherOccupation,
      // Android's HouseHold model carries both: the form only ever writes the
      // range, and `monthlyIncome` stays a legacy numeric mirror.
      'monthlyIncomeRange': household.monthlyIncomeRange,
      'monthlyIncome': _incomeMidpoint(household.monthlyIncomeRange),
      'disabilityPersonsCount': household.disabilityPersonsCount,
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
    String? memberReferenceId,
    double latitude = 0.0,
    double longitude = 0.0,
    String appVersionName = AppConfig.appVersionName,
    int appVersionCode = AppConfig.appVersionCode,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final memberRefId = memberReferenceId ?? _uuid.v4();

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

    final normDob = wireDateOfBirth(member.dateOfBirth, age: member.age);

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
      'gender': _genderValue(member.gender),
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
      'phoneNumberCategory':
          EnrollmentStrings.phoneCategoryIds[member.phoneNumberCategory] ?? '',
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

    final requestId = _uuid.v4();
    final body = {
      'requestId': requestId,
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

    return StandaloneMemberResult(
      memberReferenceId: memberRefId,
      requestId: requestId,
    );
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
    final normDob = wireDateOfBirth(member.dateOfBirth, age: member.age);
    return {
      'referenceId': referenceId,
      'householdReferenceId': householdReferenceId,
      'name': member.name,
      'nationalId': member.idNumber ?? '',
      'idType': _normalizeIdType(member.idType),
      'dateOfBirth': normDob,
      'gender': _genderValue(member.gender),
      'isHouseholdHead': isHouseholdHead,
      'isActive': true,
      'isChild': _isChild(member.age, normDob),
      'maritalStatus': member.maritalStatus.toLowerCase(),
      'disability': _disabilityValue(member.disabilityStatus),
      'villageId': villageId,
      'subVillageId': subVillageId,
      'village': villageName,
      'phoneNumber': member.mobileNumber ?? '',
      'phoneNumberCategory':
          EnrollmentStrings.phoneCategoryIds[member.phoneNumberCategory] ?? '',
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

  /// Midpoint of a Spice `monthlyIncomeRange` id, for the legacy numeric
  /// `monthlyIncome` column. Mirrors the brackets in
  /// `HouseHoldRegistration.rangeFromExactValue`.
  static int _incomeMidpoint(String range) {
    switch (range) {
      case '<5000':
        return 5000;
      case '5001–10000':
        return 7500;
      case '10001–15000':
        return 12500;
      case '15001–20000':
        return 17500;
      case '20001–30000':
        return 25000;
      case '30001–40000':
        return 35000;
      case '40001–70000':
        return 55000;
      case '>70000':
        return 70000;
      default:
        return int.tryParse(range) ?? 0;
    }
  }

  /// Android `HouseHoldMember.dateOfBirth` is a non-null `String`. An empty or
  /// omitted value becomes JSON `null` on the fetch-synced-data round-trip and
  /// crashes Android `toHouseholdMemberEntity` (`dateOfBirth is null`). Always
  /// emit a concrete UTC timestamp — parse common UI formats, else derive from
  /// [age] (1 Jan of birth year).
  @visibleForTesting
  static String wireDateOfBirth(String dob, {int age = 0}) {
    final normalised = _normaliseDob(dob);
    if (normalised.isNotEmpty) return normalised;
    if (age > 0) return _dobFromAge(age);
    // Last resort so the field is never empty/null on the wire.
    return '1970-01-01T00:00:00+00:00';
  }

  static String _dobFromAge(int age) {
    final year = DateTime.now().toUtc().year - age;
    final y = year.toString().padLeft(4, '0');
    return '$y-01-01T00:00:00+00:00';
  }

  static String _normaliseDob(String dob) {
    if (dob.isEmpty) return '';
    final trimmed = dob.trim();
    if (trimmed.contains('T')) return trimmed;

    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      return '${trimmed}T00:00:00+00:00';
    }

    // UI hint is DD/MM/YYYY — previously unparsed → '' → server null → Android NPE.
    final dmy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$')
        .firstMatch(trimmed);
    if (dmy != null) {
      final day = int.tryParse(dmy.group(1)!);
      final month = int.tryParse(dmy.group(2)!);
      final year = int.tryParse(dmy.group(3)!);
      if (day != null &&
          month != null &&
          year != null &&
          month >= 1 &&
          month <= 12 &&
          day >= 1 &&
          day <= 31) {
        final mm = month.toString().padLeft(2, '0');
        final dd = day.toString().padLeft(2, '0');
        return '$year-$mm-${dd}T00:00:00+00:00';
      }
    }

    final match =
        RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,4})\s+(\d{4})$').firstMatch(trimmed);
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

  /// Spice `id_type` option ids: nid | brn | na.
  static String _normalizeIdType(String raw) {
    final s = raw.toLowerCase().replaceAll(' ', '');
    return switch (s) {
      'nationalid' => 'nid',
      'notavailable' => 'na',
      _ => s,
    };
  }

  static String _disabilityValue(String status) {
    final s = status.toLowerCase();
    return (s == 'none' || s == 'absent' || s == 'no') ? 'absent' : 'present';
  }

  /// Spice `gender` option ids are lowercase for male/female but capitalised
  /// for Other; match that exactly so the server sees familiar values.
  static String _genderValue(String raw) {
    final s = raw.toLowerCase();
    return (s == 'male' || s == 'female') ? s : 'Other';
  }
}
