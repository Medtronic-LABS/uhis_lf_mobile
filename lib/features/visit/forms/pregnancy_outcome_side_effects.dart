import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/member_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/patient.dart';
import 'canonical_visit_data.dart';

/// Post-submit side effects for pregnancy outcome — mirrors Android
/// `AssessmentViewModel.savePregnancyOutcomeDetails`:
/// 1. Register live babies as household members
/// 2. Mark mother inactive when maternal death is recorded
class PregnancyOutcomeSideEffects {
  PregnancyOutcomeSideEffects({
    required MemberDao memberDao,
    required PatientDao patientDao,
  })  : _members = memberDao,
        _patients = patientDao;

  final MemberDao _members;
  final PatientDao _patients;

  /// Runs after a successful pregnancy-outcome assessment save.
  ///
  /// Returns wire-ready household-member maps for any newly created babies so
  /// the caller can attach them to the next `offline-sync/create` push.
  Future<List<Map<String, dynamic>>> apply({
    required CanonicalVisitData data,
    required String? motherMemberId,
    required String? motherPatientId,
    required String? householdId,
    Map<String, dynamic>? provenance,
  }) async {
    final wireBabies = <Map<String, dynamic>>[];

    // Spice: deactivate mother when maternalDeath.timeOfDeath is present.
    final timeOfDeath = data.getValue('timeOfDeath')?.toString().trim();
    if (timeOfDeath != null &&
        timeOfDeath.isNotEmpty &&
        timeOfDeath.toLowerCase() != 'null') {
      await _markMotherInactive(
        motherMemberId: motherMemberId,
        motherPatientId: motherPatientId,
      );
    }

    // Spice registers babies whenever newbornDetails + dateOfDelivery exist
    // (including maternal death with delivery outcomes / liveBirthNumbers).
    final deliveryDate = data.getValue('dateOfDelivery')?.toString().trim();
    if (deliveryDate == null || deliveryDate.isEmpty) return wireBabies;

    final newborns = data.getValue('newbornDetails');
    if (newborns is! List || newborns.isEmpty) return wireBabies;

    final mother = await _resolveMother(
      memberId: motherMemberId,
      patientId: motherPatientId,
    );
    if (mother == null) {
      debugPrint(
          '[PregnancyOutcome] baby registration skipped — mother not found');
      return wireBabies;
    }

    final motherName = mother.name?.trim().isNotEmpty == true
        ? mother.name!.trim()
        : 'Mother';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (var index = 0; index < newborns.length; index++) {
      final raw = newborns[index];
      if (raw is! Map) continue;
      final alive = raw['isBabyAlive']?.toString().toLowerCase();
      if (alive != 'yes') continue;

      final sex = raw['sex']?.toString().trim().toLowerCase() ?? '';
      final babyRef = const Uuid().v4();
      // Spice names by newbornDetails index (1-based), not live-only count.
      final babyName = 'Baby ${index + 1} of $motherName';
      final dobWire = _dateWire(deliveryDate);

      final entity = HouseholdMemberEntity(
        id: babyRef,
        referenceId: babyRef,
        householdId: householdId ?? mother.householdId,
        householdReferenceId: mother.householdReferenceId,
        name: babyName,
        gender: sex,
        dob: dobWire,
        patientId: null,
        villageId: mother.villageId,
        villageName: mother.villageName,
        subVillageId: mother.subVillageId,
        subVillageName: mother.subVillageName,
        shasthyaShebikaId: mother.shasthyaShebikaId,
        isActive: true,
        isHouseholdHead: false,
        motherReferenceId: mother.referenceId ?? mother.id,
        motherPatientId: mother.patientId ?? motherPatientId,
        guardianId: mother.referenceId ?? mother.id,
        guardianFhirId: mother.fhirId ?? mother.id,
        latitude: mother.latitude,
        longitude: mother.longitude,
        createdAt: nowMs,
        updatedAt: nowMs,
        syncStatus: 'NotSynced',
      );

      await _members.upsertMany([entity]);

      // Bridge into patients so worklist / household UI can see the baby.
      final patient = Patient(
        id: babyRef,
        patientId: null,
        name: babyName,
        gender: sex,
        dob: dobWire,
        householdId: householdId ?? mother.householdId,
        villageId: mother.subVillageId ?? mother.villageId,
        villageName: mother.subVillageName ?? mother.villageName,
        isActive: true,
        updatedAt: nowMs,
        rawJson: '{}',
        age: 0,
      );
      await _patients.upsertMany([patient]);

      wireBabies.add(_babyWirePayload(
        entity: entity,
        mother: mother,
        provenance: provenance,
        nowMs: nowMs,
      ));

      debugPrint(
          '[PregnancyOutcome] registered baby "$babyName" ref=$babyRef');
    }

    return wireBabies;
  }

  Future<void> _markMotherInactive({
    required String? motherMemberId,
    required String? motherPatientId,
  }) async {
    final mother = await _resolveMother(
      memberId: motherMemberId,
      patientId: motherPatientId,
    );
    if (mother == null) {
      debugPrint(
          '[PregnancyOutcome] maternal death — mother not found to deactivate');
      return;
    }
    // Keep existing sync_status — deceased mother must not enter
    // householdMembers[] create (that path is for new babies only).
    await _members.updateActiveStatus(
      mother.id,
      isActive: false,
      syncStatus: mother.syncStatus,
    );
    final patientId = mother.patientId ?? motherPatientId;
    if (patientId != null && patientId.isNotEmpty) {
      final patient = await _patients.byId(patientId);
      if (patient != null) {
        await _patients.upsertMany([
          patient.copyWithActive(false),
        ]);
      }
    }
    debugPrint(
        '[PregnancyOutcome] mother marked inactive id=${mother.id}');
  }

  Future<HouseholdMemberEntity?> _resolveMother({
    required String? memberId,
    required String? patientId,
  }) async {
    if (memberId != null && memberId.isNotEmpty) {
      final byId = await _members.getById(memberId);
      if (byId != null) return byId;
    }
    if (patientId != null && patientId.isNotEmpty) {
      return _members.getByPatientId(patientId);
    }
    return null;
  }

  static String _dateWire(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final m = parsed.month.toString().padLeft(2, '0');
    final d = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$m-${d}T00:00:00+00:00';
  }

  static Map<String, dynamic> _babyWirePayload({
    required HouseholdMemberEntity entity,
    required HouseholdMemberEntity mother,
    required Map<String, dynamic>? provenance,
    required int nowMs,
  }) {
    return toHouseholdMemberWire(
      entity: entity,
      provenance: provenance,
      villageIdFallback: mother.villageId,
      subVillageIdFallback: mother.subVillageId,
      villageNameFallback: mother.villageName,
      subVillageNameFallback: mother.subVillageName,
      nowMs: nowMs,
    );
  }

  /// Wire DTO for offline-sync/create `householdMembers[]` (Spice shape).
  static Map<String, dynamic> toHouseholdMemberWire({
    required HouseholdMemberEntity entity,
    Map<String, dynamic>? provenance,
    String? villageIdFallback,
    String? subVillageIdFallback,
    String? villageNameFallback,
    String? subVillageNameFallback,
    int? nowMs,
  }) {
    final ts = nowMs ?? entity.updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    return {
      'referenceId': entity.referenceId ?? entity.id,
      'householdId': entity.householdId,
      'householdReferenceId': entity.householdReferenceId,
      'name': entity.name,
      'nationalId': '',
      'idType': '',
      'dateOfBirth': entity.dob,
      'gender': entity.gender,
      'isHouseholdHead': false,
      'isActive': entity.isActive,
      'isChild': true,
      'maritalStatus': '',
      'disability': '',
      'villageId': int.tryParse(entity.villageId ?? '') ??
          int.tryParse(villageIdFallback ?? '') ??
          0,
      'subVillageId': int.tryParse(entity.subVillageId ?? '') ??
          int.tryParse(subVillageIdFallback ?? '') ??
          0,
      'village': entity.villageName ?? villageNameFallback ?? '',
      'subVillage': entity.subVillageName ?? subVillageNameFallback ?? '',
      'phoneNumber': '',
      'phoneNumberCategory': '',
      'shasthyaShebikaId':
          int.tryParse(entity.shasthyaShebikaId ?? '') ?? 0,
      'motherReferenceId': entity.motherReferenceId,
      'guardianFhirId': entity.guardianFhirId,
      'guardianId': entity.guardianId,
      'latitude': entity.latitude ?? 0.0,
      'longitude': entity.longitude ?? 0.0,
      if (provenance != null) 'provenance': provenance,
      'assessments': <dynamic>[],
      'rxBuddies': <dynamic>[],
      'createdAt': entity.createdAt ?? ts,
      'updatedAt': ts,
    };
  }
}
