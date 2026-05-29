import '../dashboard/dashboard_repository.dart';
import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';

/// Health assessment data for a member.
class MemberAssessment {
  const MemberAssessment({
    required this.id,
    required this.type,
    required this.date,
    this.visitNumber,
    this.status,
    this.notes,
    this.rawJson = const {},
  });

  final String id;
  final String type; // 'ANC', 'IMCI', 'PNC', 'NCD', etc.
  final DateTime date;
  final int? visitNumber;
  final String? status;
  final String? notes;
  final Map<String, dynamic> rawJson;

  static MemberAssessment? fromJson(Map<String, dynamic> json) {
    // Support both encounterId (new API) and id (legacy)
    final id = json['encounterId']?.toString() ?? json['id']?.toString();
    if (id == null) return null;

    DateTime? date;
    // Support visitDate (new API) and other date fields
    final dateStr = json['visitDate'] ?? json['createdAt'] ?? json['startTime'] ?? json['date'];
    if (dateStr is String) {
      date = DateTime.tryParse(dateStr);
    } else if (dateStr is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateStr);
    }
    date ??= DateTime.now();

    // Support serviceProvided (new API) and assessmentName/type (legacy)
    final type = json['serviceProvided']?.toString() ??
        json['assessmentName']?.toString() ??
        json['type']?.toString() ??
        'Assessment';

    return MemberAssessment(
      id: id,
      type: _normalizeType(type),
      date: date,
      visitNumber: json['visitNumber'] is int ? json['visitNumber'] : null,
      status: json['referralStatus']?.toString() ?? json['status']?.toString(),
      notes: json['referralReason']?.toString() ?? json['clinicalNotes']?.toString(),
      rawJson: json,
    );
  }

  static String _normalizeType(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('ANC') || upper.contains('PREGNANCY')) return 'ANC';
    if (upper.contains('IMCI') || upper.contains('ICCM') || upper.contains('UNDER_FIVE') || upper.contains('UNDER_2')) return 'IMCI';
    if (upper.contains('PNC')) return 'PNC';
    if (upper.contains('NCD')) return 'NCD';
    if (upper.contains('TB')) return 'TB';
    return type;
  }
}

/// Full member health details including assessments.
class MemberHealthDetails {
  const MemberHealthDetails({
    required this.id,
    this.patientId,
    this.name,
    this.gender,
    this.age,
    this.dateOfBirth,
    this.phoneNumber,
    this.householdId,
    this.villageId,
    this.isPregnant = false,
    this.assessments = const [],
    this.rawJson = const {},
  });

  final String id;
  final String? patientId;
  final String? name;
  final String? gender;
  final int? age;
  final String? dateOfBirth;
  final String? phoneNumber;
  final String? householdId;
  final String? villageId;
  final bool isPregnant;
  final List<MemberAssessment> assessments;
  final Map<String, dynamic> rawJson;

  static MemberHealthDetails fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? age;
    final ageVal = json['age'];
    if (ageVal is int) {
      age = ageVal;
    } else if (ageVal is num) {
      age = ageVal.toInt();
    }

    // Calculate age from dateOfBirth if not available
    if (age == null) {
      final dobStr = str('dateOfBirth');
      if (dobStr != null) {
        try {
          final dob = DateTime.parse(dobStr);
          final now = DateTime.now();
          age = now.year - dob.year;
          if (now.month < dob.month ||
              (now.month == dob.month && now.day < dob.day)) {
            age = age - 1;
          }
        } catch (_) {}
      }
    }

    final assessmentsList = <MemberAssessment>[];
    if (json['assessments'] is List) {
      for (final a in json['assessments']) {
        if (a is Map<String, dynamic>) {
          final assessment = MemberAssessment.fromJson(a);
          if (assessment != null) assessmentsList.add(assessment);
        }
      }
    }

    return MemberHealthDetails(
      id: str('id') ?? '',
      patientId: str('patientId'),
      name: str('name') ?? str('firstName'),
      gender: str('gender'),
      age: age,
      dateOfBirth: str('dateOfBirth'),
      phoneNumber: str('phoneNumber'),
      householdId: str('householdId'),
      villageId: str('villageId'),
      isPregnant: json['isPregnant'] == true,
      assessments: assessmentsList,
      rawJson: json,
    );
  }
}

/// Repository for fetching member health details.
class MemberDetailRepository extends ApiRepository {
  MemberDetailRepository(super.api, this._authRepo);
  
  final AuthRepository _authRepo;
  List<int>? _cachedSubVillageIds;

  /// Fetch member details by ID from the member list endpoint.
  Future<MemberHealthDetails?> getMemberById(String memberId) async {
    // ignore: avoid_print
    print('[MemberDetailRepository] getMemberById: $memberId');
    try {
      _cachedSubVillageIds ??= await _authRepo.subVillageIds();
      final villageIds = _cachedSubVillageIds!;
      // ignore: avoid_print
      print('[MemberDetailRepository] villageIds=$villageIds');
      
      // First try to get from member list with the ID
      final body = await postOk(
        Endpoints.householdMemberList,
        data: {
          'skip': 0,
          'limit': 500,
          'tenantId': api.tenantIdAsNum,
          if (villageIds.isNotEmpty) 'villageIds': villageIds,
        },
        action: 'Member list',
      );
      
      // ignore: avoid_print
      print('[MemberDetailRepository] Response body type: ${body.runtimeType}');

      final list = extractList(body);
      // ignore: avoid_print
      print('[MemberDetailRepository] Found ${list.length} members, looking for $memberId');
      for (final item in list) {
        if (item is Map<String, dynamic> && item['id']?.toString() == memberId) {
          // ignore: avoid_print
          print('[MemberDetailRepository] Found member: ${item['name']}');
          return MemberHealthDetails.fromJson(item);
        }
      }
      // ignore: avoid_print
      print('[MemberDetailRepository] Member not found');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching member: $e');
      return null;
    }
  }

  /// Fetch assessment history for a member.
  /// If [villageId] is provided, uses the villageIds-based endpoint for better results.
  /// For demo/test patients, filters by patient profile (age, gender, isPregnant).
  Future<List<MemberAssessment>> getMemberAssessments(
    String memberId, {
    String? villageId,
    int? patientAge,
    String? patientGender,
    bool? isPregnant,
  }) async {
    // ignore: avoid_print
    print('[MemberDetailRepository] getMemberAssessments: memberId=$memberId, villageId=$villageId, age=$patientAge, gender=$patientGender, isPregnant=$isPregnant');
    try {
      List<dynamic> list = [];

      // If we have a villageId, use the villageIds-based endpoint
      if (villageId != null) {
        final villageIdNum = int.tryParse(villageId);
        if (villageIdNum != null) {
          // ignore: avoid_print
          print('[MemberDetailRepository] Using villageIds endpoint with villageId=$villageIdNum');
          final body = await postOk(
            Endpoints.patientMemberAssessmentHistory,
            data: {
              'villageIds': [villageIdNum],
              'tenantId': api.tenantIdAsNum,
              'skip': 0,
              'limit': 100,
            },
            action: 'Member assessment history by village',
          );
          list = extractList(body);
          // ignore: avoid_print
          print('[MemberDetailRepository] Got ${list.length} assessments from villageId=$villageIdNum');
          // Filter to only this member's assessments if memberId is a numeric ID
          final isNumericId = int.tryParse(memberId) != null;
          if (isNumericId) {
            list = list
                .where((item) =>
                    item is Map<String, dynamic> &&
                    (item['householdMemberId']?.toString() == memberId ||
                     item['memberId']?.toString() == memberId))
                .toList();
            // ignore: avoid_print
            print('[MemberDetailRepository] Filtered to ${list.length} assessments for memberId=$memberId');
          } else {
            // For non-numeric IDs (like UUIDs from local test data), filter by patient profile
            // ignore: avoid_print
            print('[MemberDetailRepository] Non-numeric memberId, filtering by patient profile');
            list = _filterByPatientProfile(list, patientAge, patientGender, isPregnant);
            // ignore: avoid_print
            print('[MemberDetailRepository] After profile filter: ${list.length} assessments');
            if (list.length > 5) list = list.sublist(0, 5);
          }
        }
      }

      // Fallback: try legacy memberId-based request
      if (list.isEmpty) {
        // ignore: avoid_print
        print('[MemberDetailRepository] Trying legacy memberId endpoint...');
        final body = await postOk(
          Endpoints.patientMemberAssessmentHistory,
          data: {
            'memberId': memberId,
            'tenantId': api.tenantIdAsNum,
          },
          action: 'Member assessment history',
        );
        list = extractList(body);
        // ignore: avoid_print
        print('[MemberDetailRepository] Legacy endpoint returned ${list.length} assessments');
      }
      
      final assessments = <MemberAssessment>[];
      // ignore: avoid_print
      print('[MemberDetailRepository] Found ${list.length} assessments total');
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final a = MemberAssessment.fromJson(item);
          if (a != null) assessments.add(a);
        }
      }

      // Sort by date descending (newest first)
      assessments.sort((a, b) => b.date.compareTo(a.date));
      return assessments;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching assessments: $e');
      return [];
    }
  }

  /// Filter assessments by patient profile for demo/test data.
  /// - ANC for pregnant women or females of childbearing age (15-49)
  /// - IMCI for children under 5
  /// - NCD/TB for adults
  List<dynamic> _filterByPatientProfile(
    List<dynamic> list,
    int? patientAge,
    String? patientGender,
    bool? isPregnant,
  ) {
    if (list.isEmpty) return list;

    // Determine which assessment types are relevant
    final relevantTypes = <String>{};
    
    final isFemale = patientGender?.toLowerCase() == 'female' || 
                     patientGender?.toLowerCase() == 'f';
    final isChild = patientAge != null && patientAge < 5;
    final isChildUnder2 = patientAge != null && patientAge < 2;
    final isChildBearingAge = isFemale && patientAge != null && patientAge >= 15 && patientAge <= 49;
    
    if (isPregnant == true || isChildBearingAge) {
      relevantTypes.add('ANC');
      relevantTypes.add('PNC');
    }
    
    if (isChild || isChildUnder2) {
      relevantTypes.add('IMCI');
      relevantTypes.add('ICCM');
      relevantTypes.add('UNDER_FIVE');
      relevantTypes.add('UNDER_2');
    }
    
    // Adults get NCD/TB
    if (patientAge != null && patientAge >= 18) {
      relevantTypes.add('NCD');
      relevantTypes.add('TB');
    }
    
    // If no specific types identified, show all
    if (relevantTypes.isEmpty) {
      return list;
    }
    
    // Filter by encounter type
    return list.where((item) {
      if (item is! Map<String, dynamic>) return false;
      final encounterType = item['encounterType']?.toString().toUpperCase() ?? '';
      final serviceProvided = item['serviceProvided']?.toString().toUpperCase() ?? '';
      
      for (final type in relevantTypes) {
        if (encounterType.contains(type) || serviceProvided.contains(type)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  /// Fetch member with their assessments.
  Future<MemberHealthDetails?> getMemberWithAssessments(String memberId) async {
    final member = await getMemberById(memberId);
    if (member == null) return null;

    // Pass the member's villageId and profile to get assessments via villageIds endpoint
    final assessments = await getMemberAssessments(
      memberId,
      villageId: member.villageId,
      patientAge: member.age,
      patientGender: member.gender,
      isPregnant: member.isPregnant,
    );
    
    return MemberHealthDetails(
      id: member.id,
      patientId: member.patientId,
      name: member.name,
      gender: member.gender,
      age: member.age,
      dateOfBirth: member.dateOfBirth,
      phoneNumber: member.phoneNumber,
      householdId: member.householdId,
      villageId: member.villageId,
      isPregnant: member.isPregnant,
      assessments: assessments,
      rawJson: member.rawJson,
    );
  }
}
