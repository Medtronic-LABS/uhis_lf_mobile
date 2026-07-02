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
      // Backend villageId = sub-village ID (what fetch-synced-data filters on).
      // hierarchy.villages = unions (id=40), hierarchy.subVillages = actual villages (id=262).
      'villageId': subVillageId.toString(),
      'subVillageId': villageId.toString(),
      'village': household.subVillageName ?? household.villageName ?? '',
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
    final normDob = _normaliseDob(member.dateOfBirth);
    return {
      'referenceId': _uuid.v4(),
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
      'villageId': subVillageId,
      'subVillageId': villageId,
      'village': subVillageName.isNotEmpty ? subVillageName : villageName,
      'subVillage': villageName,
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

  /// Normalize DOB to "YYYY-MM-DDT00:00:00+00:00".
  ///
  /// Handles:
  /// - Already ISO with time component → return as-is
  /// - "YYYY-MM-DD" → append time suffix
  /// - "DD Mon YYYY" (NID OCR output, including common OCR variants like "Noy"→Nov) → parse and convert
  /// - Unparseable → return empty string (never send garbage to the backend)
  static String _normaliseDob(String dob) {
    if (dob.isEmpty) return dob;
    if (dob.contains('T')) return dob;

    // YYYY-MM-DD
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob.trim())) {
      return '${dob.trim()}T00:00:00+00:00';
    }

    // "DD Mon YYYY" — NID card format, possibly with OCR typos
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

  /// Map month abbreviations to month numbers, including common OCR variants
  /// from Bangladeshi NID cards (e.g. "Noy" for November).
  static int? _parseMonth(String abbr) {
    const map = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,
      'may': 5, 'jun': 6, 'jul': 7, 'aug': 8,
      'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      // OCR variants
      'noy': 11, 'nob': 11, 'okt': 10, 'agt': 8,
      'jao': 1,  'fob': 2,  'mao': 3,
    };
    return map[abbr.toLowerCase()];
  }

  /// Determine isChild from age if known, otherwise derive from normalised DOB.
  static bool _isChild(int age, String normDob) {
    if (age > 0) return age < 18;
    if (normDob.isEmpty) return false;
    final parsed = DateTime.tryParse(normDob);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inDays < 18 * 365;
  }

  /// Normalize idType to backend-expected values: 'nid' or 'brn'.
  static String _normalizeIdType(String raw) {
    final s = raw.toLowerCase().replaceAll(' ', '');
    return s == 'nationalid' ? 'nid' : s;
  }

  /// Convert internal disabilityStatus to the API "absent"/"present" string.
  /// Internal defaults to 'Absent'; also accepts 'None' for compatibility.
  static String _disabilityValue(String status) {
    final s = status.toLowerCase();
    return (s == 'none' || s == 'absent') ? 'absent' : 'present';
  }
}
