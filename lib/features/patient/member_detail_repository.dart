import '../../core/api/api_repository.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/db/member_dao.dart';

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
  MemberDetailRepository(super.api, this._authRepo, {MemberDao? members})
      : _memberDao = members;
  
  final AuthRepository _authRepo;
  final MemberDao? _memberDao;

  /// Fetch member details by ID from local SQLite (populated by offline sync).
  Future<MemberHealthDetails?> getMemberById(String memberId) async {
    // ignore: avoid_print
    print('[MemberDetailRepository] getMemberById: $memberId');
    try {
      if (_memberDao != null) {
        HouseholdMemberEntity? entity = await _memberDao!.getById(memberId);
        entity ??= await _memberDao!.getByPatientId(memberId);
        if (entity != null) {
          // ignore: avoid_print
          print('[MemberDetailRepository] Found in local DB: ${entity.name}');
          return _entityToDetails(entity);
        }
      }
      // ignore: avoid_print
      print('[MemberDetailRepository] Member not found in local DB');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching member: $e');
      return null;
    }
  }

  MemberHealthDetails _entityToDetails(HouseholdMemberEntity m) {
    int? age;
    if (m.dob != null) {
      final dob = DateTime.tryParse(m.dob!);
      if (dob != null) {
        final now = DateTime.now();
        age = now.year - dob.year;
        if (now.month < dob.month ||
            (now.month == dob.month && now.day < dob.day)) {
          age = age - 1;
        }
      }
    }
    return MemberHealthDetails(
      id: m.id,
      patientId: m.patientId,
      name: m.name,
      gender: m.gender,
      age: age,
      dateOfBirth: m.dob,
      phoneNumber: m.phone,
      householdId: m.householdId,
      villageId: m.villageId,
      isPregnant: m.isPregnant,
    );
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

  /// Fetch patient details with embedded vitals using the same endpoint as Android.
  /// 
  /// This mirrors Android's approach: calling `/spice-service/patient/patientDetails`
  /// which returns patient data with embedded vitals (avgBloodPressure, glucoseValue, etc.)
  /// and visit counts (pregnancyDetails.ancVisitMedicalReview, etc.).
  /// 
  /// Request body: {patientId, id, assessmentType, type}
  /// Response: PatientListRespModel with vitals and visit counts embedded.
  Future<PatientDetailsWithVitals?> getPatientDetailsWithVitals(
    String patientId, {
    String? assessmentType,
    String? origin,
  }) async {
    // ignore: avoid_print
    print('[MemberDetailRepository] ========== getPatientDetailsWithVitals START ==========');
    print('[MemberDetailRepository] patientId=$patientId, assessmentType=$assessmentType, origin=$origin');

    try {
      final requestData = {
        'patientId': patientId,
        'id': patientId,
        if (assessmentType != null) 'assessmentType': assessmentType,
        if (origin != null) 'type': origin,
        'tenantId': api.tenantIdAsNum,
      };
      // ignore: avoid_print
      print('[MemberDetailRepository] Calling ${Endpoints.patientDetails}');
      print('[MemberDetailRepository] Request: $requestData');

      final body = await postOk(
        Endpoints.patientDetails,
        data: requestData,
        action: 'Patient details with vitals',
      );

      // ignore: avoid_print
      print('[MemberDetailRepository] Response type: ${body.runtimeType}');

      if (body is Map<String, dynamic>) {
        final details = PatientDetailsWithVitals.fromJson(body);
        // ignore: avoid_print
        print('[MemberDetailRepository] Parsed details:');
        print('  - avgBloodPressure: ${details?.avgBloodPressure}');
        print('  - glucoseValue: ${details?.glucoseValue}');
        print('  - height: ${details?.height}');
        print('  - weight: ${details?.weight}');
        print('  - ancVisitMedicalReview: ${details?.ancVisitMedicalReview}');
        print('  - totalVisitCount: ${details?.totalVisitCount}');
        print('[MemberDetailRepository] ========== getPatientDetailsWithVitals END ==========');
        return details;
      }
      // ignore: avoid_print
      print('[MemberDetailRepository] Response was not a Map: $body');
      print('[MemberDetailRepository] ========== getPatientDetailsWithVitals END ==========');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching patient details: $e');
      print('[MemberDetailRepository] ========== getPatientDetailsWithVitals END ==========');
      return null;
    }
  }

  /// Fetch recent patient visits from /spice-service/patientvisit/list.
  /// Also tries /spice-service/medical-review/history as fallback.
  /// Finally tries FHIR Encounter search by household Group if available.
  /// Returns up to [limit] most recent visits.
  Future<List<PatientVisit>> getRecentVisits(
    String patientId, {
    String? memberReference,
    String? householdId,
    int limit = 5,
  }) async {
    // ignore: avoid_print
    print('[MemberDetailRepository] ========== getRecentVisits START ==========');
    print('[MemberDetailRepository] patientId=$patientId, memberRef=$memberReference, limit=$limit');
    final visits = <PatientVisit>[];

    // Try patientvisit/list endpoint first
    try {
      // Build patient reference in FHIR format if not already
      String patientRef = patientId;
      if (!patientId.startsWith('Patient/')) {
        patientRef = 'Patient/$patientId';
      }

      final requestData = {
        'patientReference': patientRef,
        if (memberReference != null) 'memberReference': memberReference,
        'tenantId': api.tenantIdAsNum,
        'skip': 0,
        'limit': limit,
      };
      // ignore: avoid_print
      print('[MemberDetailRepository] Calling ${Endpoints.patientVisitList}');
      print('[MemberDetailRepository] Request: $requestData');

      final body = await postOk(
        Endpoints.patientVisitList,
        data: requestData,
        action: 'Patient visits list',
      );

      // ignore: avoid_print
      print('[MemberDetailRepository] Response body type: ${body.runtimeType}');
      print('[MemberDetailRepository] Response: $body');

      final list = extractList(body);
      // ignore: avoid_print
      print('[MemberDetailRepository] patientVisitList returned ${list.length} visits');
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          // ignore: avoid_print
          print('[MemberDetailRepository] Visit item: $item');
          final visit = PatientVisit.fromJson(item);
          if (visit != null) visits.add(visit);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] patientVisitList failed: $e');
    }

    // Fallback: try medical-review/history endpoint
    if (visits.isEmpty) {
      // ignore: avoid_print
      print('[MemberDetailRepository] No visits from patientVisitList, trying medicalReviewHistory...');
      try {
        String patientRef = patientId;
        if (!patientId.startsWith('Patient/')) {
          patientRef = 'Patient/$patientId';
        }

        final requestData = {
          'patientReference': patientRef,
          'tenantId': api.tenantIdAsNum,
          'skip': 0,
          'limit': limit,
        };
        // ignore: avoid_print
        print('[MemberDetailRepository] Calling ${Endpoints.medicalReviewHistory}');
        print('[MemberDetailRepository] Request: $requestData');

        final body = await postOk(
          Endpoints.medicalReviewHistory,
          data: requestData,
          action: 'Medical review history',
        );

        // ignore: avoid_print
        print('[MemberDetailRepository] Response body type: ${body.runtimeType}');
        print('[MemberDetailRepository] Response: $body');

        final list = extractList(body);
        // ignore: avoid_print
        print('[MemberDetailRepository] medicalReviewHistory returned ${list.length} reviews');
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            // ignore: avoid_print
            print('[MemberDetailRepository] Review item: $item');
            final visit = PatientVisit.fromMedicalReview(item);
            if (visit != null) visits.add(visit);
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[MemberDetailRepository] medicalReviewHistory failed: $e');
      }
    }

    // Final fallback: try FHIR server for Encounters by household Group
    if (visits.isEmpty && householdId != null) {
      // ignore: avoid_print
      print('[MemberDetailRepository] No visits from spice-service, trying FHIR Encounters...');
      print('[MemberDetailRepository] householdId=$householdId');
      try {
        // FHIR encounters are linked to Groups (households)
        // Build the FHIR search URL
        final fhirUrl = '${Endpoints.fhirServerBase}/Encounter?subject=Group/$householdId&_count=$limit&_sort=-date';
        // ignore: avoid_print
        print('[MemberDetailRepository] Calling FHIR: $fhirUrl');

        final body = await getOk(
          fhirUrl,
          action: 'FHIR Encounters',
        );

        // ignore: avoid_print
        print('[MemberDetailRepository] FHIR response type: ${body.runtimeType}');

        // FHIR returns a Bundle with entries
        if (body is Map<String, dynamic>) {
          final entries = body['entry'] as List?;
          // ignore: avoid_print
          print('[MemberDetailRepository] FHIR bundle has ${entries?.length ?? 0} entries');
          if (entries != null) {
            for (final entry in entries) {
              if (entry is Map<String, dynamic>) {
                final resource = entry['resource'] as Map<String, dynamic>?;
                if (resource != null && resource['resourceType'] == 'Encounter') {
                  // ignore: avoid_print
                  print('[MemberDetailRepository] FHIR Encounter: ${resource['id']}');
                  final visit = PatientVisit.fromFhirEncounter(resource);
                  if (visit != null) visits.add(visit);
                }
              }
            }
          }
        }
        // ignore: avoid_print
        print('[MemberDetailRepository] Got ${visits.length} visits from FHIR');
      } catch (e) {
        // ignore: avoid_print
        print('[MemberDetailRepository] FHIR Encounters failed: $e');
      }
    }

    // Also try FHIR by Patient reference if we have fewer visits than limit
    if (visits.length < limit) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Also trying FHIR Encounters by Patient...');
      print('[MemberDetailRepository] patientId=$patientId');
      try {
        // Try to search by Patient ID
        final fhirUrl = '${Endpoints.fhirServerBase}/Encounter?subject=Patient/$patientId&_count=$limit&_sort=-date';
        // ignore: avoid_print
        print('[MemberDetailRepository] Calling FHIR by Patient: $fhirUrl');

        final body = await getOk(
          fhirUrl,
          action: 'FHIR Encounters by Patient',
        );

        if (body is Map<String, dynamic>) {
          final entries = body['entry'] as List?;
          // ignore: avoid_print
          print('[MemberDetailRepository] FHIR Patient bundle has ${entries?.length ?? 0} entries');
          if (entries != null) {
            for (final entry in entries) {
              if (entry is Map<String, dynamic>) {
                final resource = entry['resource'] as Map<String, dynamic>?;
                if (resource != null && resource['resourceType'] == 'Encounter') {
                  final encounterId = resource['id']?.toString();
                  // Check if we already have this encounter
                  final alreadyHave = visits.any((v) => v.id == encounterId);
                  if (!alreadyHave) {
                    // ignore: avoid_print
                    print('[MemberDetailRepository] FHIR Patient Encounter: $encounterId');
                    final visit = PatientVisit.fromFhirEncounter(resource);
                    if (visit != null) visits.add(visit);
                  }
                }
              }
            }
          }
        }
        // ignore: avoid_print
        print('[MemberDetailRepository] Total visits after Patient search: ${visits.length}');
      } catch (e) {
        // ignore: avoid_print
        print('[MemberDetailRepository] FHIR Encounters by Patient failed: $e');
      }
    }

    // ignore: avoid_print
    print('[MemberDetailRepository] Final visits count: ${visits.length}');
    print('[MemberDetailRepository] ========== getRecentVisits END ==========');

    // Sort by date descending
    visits.sort((a, b) => b.visitDate.compareTo(a.visitDate));
    return visits.take(limit).toList();
  }

  /// Fetch detailed visit information using medical-review/history endpoint.
  /// This matches Android's approach of calling `/spice-service/medical-review/history`
  /// with encounterId to get full review details including diagnosis, vitals, etc.
  Future<VisitDetails?> getVisitDetails(
    String encounterId, {
    String? patientReference,
    String? memberReference,
    String? type,
  }) async {
    // ignore: avoid_print
    print('[MemberDetailRepository] ========== getVisitDetails START ==========');
    print('[MemberDetailRepository] encounterId=$encounterId, patientRef=$patientReference, memberRef=$memberReference, type=$type');

    try {
      final requestData = {
        'encounterId': encounterId,
        if (patientReference != null) 'patientReference': patientReference,
        if (type != null) 'type': type,
        'tenantId': api.tenantIdAsNum,
      };
      // ignore: avoid_print
      print('[MemberDetailRepository] Calling ${Endpoints.medicalReviewHistory}');
      print('[MemberDetailRepository] Request: $requestData');

      final body = await postOk(
        Endpoints.medicalReviewHistory,
        data: requestData,
        action: 'Medical review details',
      );

      // ignore: avoid_print
      print('[MemberDetailRepository] Response type: ${body.runtimeType}');
      print('[MemberDetailRepository] Response: $body');

      if (body is Map<String, dynamic>) {
        // Extract entity from wrapped response
        final entity = body['entity'] as Map<String, dynamic>? ?? body;
        // ignore: avoid_print
        print('[MemberDetailRepository] Entity: $entity');
        print('[MemberDetailRepository] Entity reviewDetails: ${entity['reviewDetails']}');
        print('[MemberDetailRepository] Entity history: ${entity['history']}');
        
        var details = VisitDetails.fromJson(entity);
        // ignore: avoid_print
        print('[MemberDetailRepository] Parsed visit details:');
        print('  - id: ${details?.id}');
        print('  - type: ${details?.type}');
        print('  - dateOfReview: ${details?.dateOfReview}');
        print('  - patientReference: ${details?.patientReference}');
        print('  - visitNumber: ${details?.reviewDetails?.visitNumber}');
        print('  - diagnosis: ${details?.reviewDetails?.diagnosis?.length ?? 0} items');
        print('  - history: ${details?.history?.length ?? 0} items');
        
        // If history has only 1 item (current encounter), fetch full history using patientReference
        if (details != null && 
            details.patientReference != null && 
            (details.history == null || details.history!.length <= 1)) {
          print('[MemberDetailRepository] History has ${details.history?.length ?? 0} items, fetching full history...');
          final fullHistory = await _fetchFullPatientHistory(details.patientReference!);
          if (fullHistory != null && fullHistory.isNotEmpty) {
            print('[MemberDetailRepository] Got ${fullHistory.length} items in full history');
            details = VisitDetails(
              id: details.id,
              patientReference: details.patientReference,
              dateOfReview: details.dateOfReview,
              type: details.type,
              reviewDetails: details.reviewDetails,
              history: fullHistory,
              typeSpecificDetails: details.typeSpecificDetails,
              rawJson: details.rawJson,
            );
          }
        }
        
        // Fetch type-specific details if we have a visit type
        if (details != null && details.visitType != null) {
          print('[MemberDetailRepository] Fetching type-specific details for type=${details.visitType}');
          final typeDetails = await _fetchTypeSpecificDetails(
            encounterId,
            details.visitType!,
            details.patientReference,
            memberReference,
          );
          if (typeDetails != null && typeDetails.isNotEmpty) {
            print('[MemberDetailRepository] Got type-specific details: ${typeDetails.keys}');
            details = VisitDetails(
              id: details.id,
              patientReference: details.patientReference,
              dateOfReview: details.dateOfReview,
              type: details.type,
              reviewDetails: details.reviewDetails,
              history: details.history,
              typeSpecificDetails: typeDetails,
              rawJson: details.rawJson,
            );
          }
        }
        
        print('[MemberDetailRepository] ========== getVisitDetails END ==========');
        return details;
      }
      // ignore: avoid_print
      print('[MemberDetailRepository] Response was not a Map');
      print('[MemberDetailRepository] ========== getVisitDetails END ==========');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching visit details: $e');
      print('[MemberDetailRepository] ========== getVisitDetails END ==========');
      return null;
    }
  }

  /// Fetch full patient visit history using patientReference.
  Future<List<Map<String, dynamic>>?> _fetchFullPatientHistory(String patientReference) async {
    try {
      final requestData = {
        'patientReference': patientReference,
        'tenantId': api.tenantIdAsNum,
      };
      // ignore: avoid_print
      print('[MemberDetailRepository] Fetching full history with patientReference=$patientReference');

      final body = await postOk(
        Endpoints.medicalReviewHistory,
        data: requestData,
        action: 'Full patient history',
      );

      if (body is Map<String, dynamic>) {
        final entity = body['entity'] as Map<String, dynamic>? ?? body;
        final history = entity['history'] as List?;
        if (history != null) {
          return history.whereType<Map<String, dynamic>>().toList();
        }
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching full history: $e');
      return null;
    }
  }

  /// Fetch type-specific visit details based on visit type.
  /// Different visit types use different detail endpoints (NCD, ANC, PNC, Mental Health, etc.)
  Future<Map<String, dynamic>?> _fetchTypeSpecificDetails(
    String encounterId,
    String visitType,
    String? patientReference,
    String? memberReference,
  ) async {
    // Determine the endpoint based on visit type
    late String endpoint;
    bool isMentalHealth = false;
    
    switch (visitType.toUpperCase()) {
      case 'NCD':
        endpoint = Endpoints.medicalReviewNcdDetails;
        break;
      case 'CATARACT':
      case 'EYE_CARE':
      case 'MENTAL_HEALTH':
        endpoint = Endpoints.mentalHealthDetails;
        isMentalHealth = true;
        break;
      case 'ANC':
      case 'ANC_PREGNANCY':
        endpoint = Endpoints.medicalReviewAncDetails;
        break;
      case 'PNC':
        endpoint = Endpoints.medicalReviewPncDetails;
        break;
      case 'ICCM':
      case 'ICCM_GENERAL':
        endpoint = Endpoints.medicalReviewIccmDetails;
        break;
      case 'ICCM_UNDER_2_MONTHS':
        endpoint = Endpoints.medicalReviewIccmUnder2MonthsDetails;
        break;
      case 'ICCM_UNDER_5_YEARS':
        endpoint = Endpoints.medicalReviewIccmUnder5YearsDetails;
        break;
      case 'LABOUR':
      case 'DELIVERY':
      case 'LABOUR_DELIVERY':
        endpoint = Endpoints.medicalReviewLabourDetails;
        break;
      default:
        // Try NCD as a fallback for unknown types
        // ignore: avoid_print
        print('[MemberDetailRepository] Unknown visit type: $visitType, trying NCD details');
        endpoint = Endpoints.medicalReviewNcdDetails;
    }

    try {
      Map<String, dynamic> requestData;
      
      if (isMentalHealth) {
        // Mental health endpoints use memberReference and type (per Android NCDMentalHealthMedicalReviewDetails)
        final memberRef = memberReference ?? patientReference;
        if (memberRef == null) {
          print('[MemberDetailRepository] No memberReference for mental health endpoint, skipping');
          return null;
        }
        requestData = {
          'memberReference': memberRef,
          'type': visitType.toUpperCase(),
        };
      } else {
        // NCD and other endpoints - match Postman collection format
        // Uses both encounterId and encounterReference, plus latestRequired flag
        requestData = {
          'encounterId': encounterId.toString(),
          'encounterReference': encounterId.toString(),
          if (patientReference != null) 'patientReference': patientReference.toString(),
          if (memberReference != null) 'memberReference': memberReference.toString(),
          'patientVisitId': encounterId.toString(),
          'latestRequired': false,
        };
      }
      
      // ignore: avoid_print
      print('[MemberDetailRepository] Fetching $visitType details from $endpoint');
      print('[MemberDetailRepository] Request: $requestData');

      final body = await postOk(
        endpoint,
        data: requestData,
        action: '$visitType details',
      );

      // ignore: avoid_print
      print('[MemberDetailRepository] $visitType details response: $body');

      if (body is Map<String, dynamic>) {
        final entity = body['entity'] as Map<String, dynamic>? ?? body;
        return entity;
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[MemberDetailRepository] Error fetching $visitType details: $e');
      return null;
    }
  }
}

/// Detailed visit information from medical-review/history endpoint.
/// Mirrors Android's MedicalReviewHistory model.
class VisitDetails {
  const VisitDetails({
    this.id,
    this.patientReference,
    this.dateOfReview,
    this.type,
    this.reviewDetails,
    this.history,
    this.typeSpecificDetails,
    this.rawJson = const {},
  });

  final String? id;
  final String? patientReference;
  final String? dateOfReview;
  final String? type;
  final ReviewDetails? reviewDetails;
  final List<Map<String, dynamic>>? history;
  /// Type-specific details from NCD, Mental Health, ANC, PNC, etc. endpoints
  final Map<String, dynamic>? typeSpecificDetails;
  final Map<String, dynamic> rawJson;

  /// Get the visit type - either from top level or from first history item
  String? get visitType {
    if (type != null && type!.isNotEmpty) return type;
    if (history != null && history!.isNotEmpty) {
      final firstHistory = history![0];
      final historyType = firstHistory['type']?.toString();
      if (historyType != null && historyType.isNotEmpty) return historyType;
    }
    return null;
  }

  /// Get the medicalReview sub-object from type-specific details
  Map<String, dynamic>? get _medicalReview {
    if (typeSpecificDetails == null) return null;
    final mr = typeSpecificDetails!['medicalReview'];
    if (mr is Map<String, dynamic>) return mr;
    // If no nested medicalReview, use typeSpecificDetails directly
    return typeSpecificDetails;
  }

  /// Get complaints from type-specific details
  List<String> get complaints {
    final mr = _medicalReview;
    if (mr == null) return [];
    final c = mr['complaints'];
    if (c is List) return c.whereType<String>().toList();
    return [];
  }

  /// Get physical exams from type-specific details
  List<String> get physicalExams {
    final mr = _medicalReview;
    if (mr == null) return [];
    final p = mr['physicalExams'];
    if (p is List) return p.whereType<String>().toList();
    return [];
  }

  /// Get clinical notes from type-specific details
  String? get clinicalNote {
    final mr = _medicalReview;
    if (mr == null) return null;
    // Check for 'notes' array or 'clinicalNote' string
    final notes = mr['notes'];
    if (notes is List && notes.isNotEmpty) {
      return notes.whereType<String>().join('\n');
    }
    return mr['clinicalNote']?.toString();
  }

  /// Get comorbidities from type-specific details
  List<String> get comorbidities {
    final mr = _medicalReview;
    if (mr == null) return [];
    final c = mr['comorbidities'];
    if (c is List) return c.whereType<String>().toList();
    return [];
  }

  /// Get complications from type-specific details
  List<String> get complications {
    final mr = _medicalReview;
    if (mr == null) return [];
    final c = mr['complications'];
    if (c is List) return c.whereType<String>().toList();
    return [];
  }

  /// Get prescriptions from type-specific details
  List<Map<String, dynamic>> get prescriptions {
    final mr = _medicalReview;
    if (mr == null) return [];
    final p = mr['prescriptions'];
    if (p is List) return p.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  /// Get investigations from type-specific details
  List<String> get investigations {
    final mr = _medicalReview;
    if (mr == null) return [];
    final i = mr['investigations'];
    if (i is List) return i.whereType<String>().toList();
    return [];
  }

  /// Check if type-specific details have been loaded
  bool get hasTypeSpecificDetails {
    if (typeSpecificDetails == null || typeSpecificDetails!.isEmpty) return false;
    // Check if there's actual content in medicalReview
    final mr = _medicalReview;
    if (mr == null) return false;
    return mr.values.any((v) => v is List && v.isNotEmpty);
  }

  static VisitDetails? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // Parse reviewDetails
    ReviewDetails? reviewDetails;
    if (json['reviewDetails'] is Map<String, dynamic>) {
      reviewDetails = ReviewDetails.fromJson(json['reviewDetails']);
    }

    // Parse history list
    List<Map<String, dynamic>>? history;
    if (json['history'] is List) {
      history = (json['history'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    // Try to get type from history if not at top level
    String? resolvedType = str('type');
    if ((resolvedType == null || resolvedType.isEmpty) && 
        history != null && history.isNotEmpty) {
      resolvedType = history[0]['type']?.toString();
    }

    return VisitDetails(
      id: str('id'),
      patientReference: str('patientReference'),
      dateOfReview: str('dateOfReview'),
      type: resolvedType,
      reviewDetails: reviewDetails,
      history: history,
      rawJson: json,
    );
  }
}

/// Review details from medical-review/history endpoint.
/// Mirrors Android's ReviewDetails model.
class ReviewDetails {
  const ReviewDetails({
    this.id,
    this.visitNumber,
    this.patientReference,
    this.patientStatus,
    this.diagnosis,
    this.presentingComplaints,
    this.presentingComplaintsNotes,
    this.systemicExaminations,
    this.systemicExaminationsNotes,
    this.obstetricExaminations,
    this.obstetricExaminationsNotes,
    this.clinicalNotes,
    this.isMotherAlive,
    this.breastCondition,
    this.breastConditionNotes,
    this.involutionsOfTheUterus,
    this.involutionsOfTheUterusNotes,
    this.neonateOutcome,
    this.stateOfBaby,
    this.birthWeight,
    this.signs,
    this.labourDTO,
    this.rawJson = const {},
  });

  final String? id;
  final int? visitNumber;
  final String? patientReference;
  final String? patientStatus;
  final List<DiagnosisInfo>? diagnosis;
  final List<String>? presentingComplaints;
  final String? presentingComplaintsNotes;
  final List<String>? systemicExaminations;
  final String? systemicExaminationsNotes;
  final List<String>? obstetricExaminations;
  final String? obstetricExaminationsNotes;
  final String? clinicalNotes;
  final bool? isMotherAlive;
  final String? breastCondition;
  final String? breastConditionNotes;
  final String? involutionsOfTheUterus;
  final String? involutionsOfTheUterusNotes;
  final String? neonateOutcome;
  final String? stateOfBaby;
  final String? birthWeight;
  final List<String>? signs;
  final LabourDetails? labourDTO;
  final Map<String, dynamic> rawJson;

  static ReviewDetails? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? intVal(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    List<String>? strList(dynamic v) {
      if (v == null) return null;
      if (v is List) {
        return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
      return null;
    }

    // Parse diagnosis list
    List<DiagnosisInfo>? diagnosis;
    if (json['diagnosis'] is List) {
      diagnosis = (json['diagnosis'] as List)
          .whereType<Map<String, dynamic>>()
          .map((d) => DiagnosisInfo.fromJson(d))
          .whereType<DiagnosisInfo>()
          .toList();
    }

    // Parse labour details
    LabourDetails? labourDTO;
    if (json['labourDTO'] is Map<String, dynamic>) {
      labourDTO = LabourDetails.fromJson(json['labourDTO']);
    }

    return ReviewDetails(
      id: str('id'),
      visitNumber: intVal(json['visitNumber']),
      patientReference: str('patientReference'),
      patientStatus: str('patientStatus'),
      diagnosis: diagnosis,
      presentingComplaints: strList(json['presentingComplaints']),
      presentingComplaintsNotes: str('presentingComplaintsNotes'),
      systemicExaminations: strList(json['systemicExaminations']) ?? strList(json['systemicExamination']),
      systemicExaminationsNotes: str('systemicExaminationsNotes') ?? str('systemicExaminationNotes'),
      obstetricExaminations: strList(json['obstetricExaminations']),
      obstetricExaminationsNotes: str('obstetricExaminationsNotes') ?? str('obstetricExaminationNotes'),
      clinicalNotes: str('clinicalNotes'),
      isMotherAlive: json['isMotherAlive'] as bool?,
      breastCondition: str('breastCondition'),
      breastConditionNotes: str('breastConditionNotes'),
      involutionsOfTheUterus: str('involutionsOfTheUterus'),
      involutionsOfTheUterusNotes: str('involutionsOfTheUterusNotes'),
      neonateOutcome: str('neonateOutcome'),
      stateOfBaby: str('stateOfBaby'),
      birthWeight: str('birthWeight'),
      signs: strList(json['signs']),
      labourDTO: labourDTO,
      rawJson: json,
    );
  }
}

/// Diagnosis information from review details.
class DiagnosisInfo {
  const DiagnosisInfo({
    this.diseaseCategoryId,
    this.diseaseConditionId,
    this.diseaseCategory,
    this.diseaseCondition,
    this.notes,
    this.type,
  });

  final int? diseaseCategoryId;
  final int? diseaseConditionId;
  final String? diseaseCategory;
  final String? diseaseCondition;
  final String? notes;
  final String? type;

  static DiagnosisInfo? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? intVal(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    return DiagnosisInfo(
      diseaseCategoryId: intVal(json['diseaseCategoryId']),
      diseaseConditionId: intVal(json['diseaseConditionId']),
      diseaseCategory: str('diseaseCategory'),
      diseaseCondition: str('diseaseCondition'),
      notes: str('notes'),
      type: str('type'),
    );
  }

  @override
  String toString() => diseaseCondition ?? diseaseCategory ?? 'Unknown';
}

/// Labour/delivery details.
class LabourDetails {
  const LabourDetails({
    this.dateAndTimeOfDelivery,
    this.dateAndTimeOfLabourOnset,
    this.deliveryType,
    this.deliveryBy,
    this.deliveryAt,
    this.deliveryStatus,
  });

  final String? dateAndTimeOfDelivery;
  final String? dateAndTimeOfLabourOnset;
  final String? deliveryType;
  final String? deliveryBy;
  final String? deliveryAt;
  final String? deliveryStatus;

  static LabourDetails? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return LabourDetails(
      dateAndTimeOfDelivery: str('dateAndTimeOfDelivery'),
      dateAndTimeOfLabourOnset: str('dateAndTimeOfLabourOnset'),
      deliveryType: str('deliveryType'),
      deliveryBy: str('deliveryBy'),
      deliveryAt: str('deliveryAt'),
      deliveryStatus: str('deliveryStatus'),
    );
  }
}

/// Patient visit data from /spice-service/patientvisit/list.
class PatientVisit {
  const PatientVisit({
    required this.id,
    required this.visitDate,
    this.visitNumber,
    this.encounterType,
    this.serviceProvided,
    this.status,
    this.providerName,
    this.notes,
    this.rawJson = const {},
  });

  final String id;
  final DateTime visitDate;
  final int? visitNumber;
  final String? encounterType;
  final String? serviceProvided;
  final String? status;
  final String? providerName;
  final String? notes;
  final Map<String, dynamic> rawJson;

  static PatientVisit? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ??
        json['visitId']?.toString() ??
        json['encounterReference']?.toString();
    if (id == null) return null;

    DateTime? date;
    final dateVal = json['visitDate'] ??
        json['createdAt'] ??
        json['startTime'] ??
        json['date'];
    if (dateVal is String) {
      date = DateTime.tryParse(dateVal);
    } else if (dateVal is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateVal);
    }
    date ??= DateTime.now();

    return PatientVisit(
      id: id,
      visitDate: date,
      visitNumber: json['visitNumber'] is int ? json['visitNumber'] : null,
      encounterType: json['encounterType']?.toString(),
      serviceProvided: json['serviceProvided']?.toString(),
      status: json['status']?.toString(),
      providerName: json['providerName']?.toString() ??
          json['createdByName']?.toString(),
      notes: json['clinicalNotes']?.toString() ?? json['notes']?.toString(),
      rawJson: json,
    );
  }

  static PatientVisit? fromMedicalReview(Map<String, dynamic> json) {
    final id = json['encounterId']?.toString() ??
        json['id']?.toString() ??
        json['encounterReference']?.toString();
    if (id == null) return null;

    DateTime? date;
    final dateVal = json['reviewDate'] ??
        json['visitDate'] ??
        json['createdAt'] ??
        json['date'];
    if (dateVal is String) {
      date = DateTime.tryParse(dateVal);
    } else if (dateVal is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateVal);
    }
    date ??= DateTime.now();

    return PatientVisit(
      id: id,
      visitDate: date,
      visitNumber: json['visitNumber'] is int ? json['visitNumber'] : null,
      encounterType: 'Medical Review',
      serviceProvided: json['reviewType']?.toString() ??
          json['serviceProvided']?.toString(),
      status: json['status']?.toString(),
      providerName: json['reviewerName']?.toString() ??
          json['createdByName']?.toString(),
      notes: json['summary']?.toString() ?? json['clinicalNotes']?.toString(),
      rawJson: json,
    );
  }

  /// Parse a FHIR Encounter resource into a PatientVisit.
  /// FHIR Encounter structure: https://www.hl7.org/fhir/encounter.html
  static PatientVisit? fromFhirEncounter(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    if (id == null) return null;

    // Parse period.start for the visit date
    DateTime? date;
    final period = json['period'] as Map<String, dynamic>?;
    if (period != null) {
      final startStr = period['start']?.toString();
      if (startStr != null) {
        date = DateTime.tryParse(startStr);
      }
    }
    // Fallback to meta.lastUpdated
    if (date == null) {
      final meta = json['meta'] as Map<String, dynamic>?;
      final lastUpdated = meta?['lastUpdated']?.toString();
      if (lastUpdated != null) {
        date = DateTime.tryParse(lastUpdated);
      }
    }
    date ??= DateTime.now();

    // Extract encounter type from type[0].coding[0].display or text
    String? encounterType;
    final types = json['type'] as List?;
    if (types != null && types.isNotEmpty) {
      final firstType = types[0] as Map<String, dynamic>?;
      if (firstType != null) {
        encounterType = firstType['text']?.toString();
        if (encounterType == null) {
          final codings = firstType['coding'] as List?;
          if (codings != null && codings.isNotEmpty) {
            final coding = codings[0] as Map<String, dynamic>?;
            encounterType = coding?['display']?.toString() ?? coding?['code']?.toString();
          }
        }
      }
    }

    // Extract service type from serviceType.coding[0].display
    String? serviceProvided;
    final serviceType = json['serviceType'] as Map<String, dynamic>?;
    if (serviceType != null) {
      serviceProvided = serviceType['text']?.toString();
      if (serviceProvided == null) {
        final codings = serviceType['coding'] as List?;
        if (codings != null && codings.isNotEmpty) {
          final coding = codings[0] as Map<String, dynamic>?;
          serviceProvided = coding?['display']?.toString() ?? coding?['code']?.toString();
        }
      }
    }

    // Extract status
    final status = json['status']?.toString();

    return PatientVisit(
      id: id,
      visitDate: date,
      encounterType: encounterType ?? 'Encounter',
      serviceProvided: serviceProvided,
      status: status,
      rawJson: json,
    );
  }
}

/// Patient details with embedded vitals data.
/// Mirrors Android's `PatientListRespModel` from `/spice-service/patient/patientDetails`.
class PatientDetailsWithVitals {
  const PatientDetailsWithVitals({
    this.id,
    this.patientId,
    this.memberId,
    this.name,
    this.gender,
    this.age,
    this.dateOfBirth,
    this.phoneNumber,
    this.householdId,
    this.villageId,
    this.encounterId,
    // Vitals - embedded in response
    this.avgBloodPressure,
    this.glucoseValue,
    this.glucoseUnit,
    this.height,
    this.weight,
    this.bmi,
    // Visit counts from pregnancyDetails
    this.ancVisitMedicalReview,
    this.pncVisitMedicalReview,
    this.ancVisitAssessment,
    this.pncVisitAssessment,
    this.isPregnant = false,
    this.pregnancyDetails = const {},
    this.rawJson = const {},
  });

  final String? id;
  final String? patientId;
  final String? memberId;
  final String? name;
  final String? gender;
  final int? age;
  final String? dateOfBirth;
  final String? phoneNumber;
  final String? householdId;
  final String? villageId;
  final String? encounterId;
  
  // Recent vitals (like Android's PatientListRespModel)
  final String? avgBloodPressure;
  final String? glucoseValue;
  final String? glucoseUnit;
  final double? height;
  final double? weight;
  final double? bmi;
  
  // Visit counts (from pregnancyDetails)
  final int? ancVisitMedicalReview;
  final int? pncVisitMedicalReview;
  final int? ancVisitAssessment;
  final int? pncVisitAssessment;
  final bool isPregnant;
  final Map<String, dynamic> pregnancyDetails;
  final Map<String, dynamic> rawJson;

  /// Total visits count (ANC + PNC assessments and medical reviews).
  int get totalVisitCount {
    return (ancVisitMedicalReview ?? 0) +
        (pncVisitMedicalReview ?? 0) +
        (ancVisitAssessment ?? 0).toInt() +
        (pncVisitAssessment ?? 0).toInt();
  }

  /// Check if we have any vitals data.
  bool get hasVitals =>
      avgBloodPressure != null ||
      glucoseValue != null ||
      height != null ||
      weight != null;

  /// Parse from API response (matches Android's PatientListRespModel).
  static PatientDetailsWithVitals? fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    double? dbl(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int? intVal(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    // Parse pregnancyDetails sub-object
    final pregnancyDetails = json['pregnancyDetails'] as Map<String, dynamic>? ?? {};

    return PatientDetailsWithVitals(
      id: str('id') ?? str('fhirUrl'),
      patientId: str('patientId'),
      memberId: str('memberId'),
      name: str('name') ?? str('firstName'),
      gender: str('gender'),
      age: intVal(json['age']),
      dateOfBirth: str('dateOfBirth') ?? str('birthDate'),
      phoneNumber: str('phoneNumber'),
      householdId: str('houseHoldId') ?? str('householdId'),
      villageId: str('villageId'),
      encounterId: str('encounterId'),
      // Vitals from response
      avgBloodPressure: str('avgBloodPressure'),
      glucoseValue: str('glucoseValue'),
      glucoseUnit: str('glucoseUnit'),
      height: dbl(json['height']),
      weight: dbl(json['weight']),
      bmi: dbl(json['bmi']),
      // Visit counts from pregnancyDetails
      ancVisitMedicalReview: intVal(pregnancyDetails['ancVisitMedicalReview']),
      pncVisitMedicalReview: intVal(pregnancyDetails['pncVisitMedicalReview']),
      ancVisitAssessment: intVal(pregnancyDetails['ancVisitAssessment']),
      pncVisitAssessment: intVal(pregnancyDetails['pncVisitAssessment']),
      isPregnant: json['isPregnant'] == true,
      pregnancyDetails: pregnancyDetails,
      rawJson: json,
    );
  }
}
