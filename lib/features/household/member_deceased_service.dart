import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/models/patient.dart';
import '../../core/sync/offline_push_service.dart';

/// Local side effects when a household member is marked deceased — mirrors
/// Android `updateMemberDeceasedReason` + `startBackgroundOfflineSync`.
class MemberDeceasedService {
  MemberDeceasedService({
    required MemberDao memberDao,
    required PatientDao patientDao,
    required OfflinePushService pushService,
  })  : _members = memberDao,
        _patients = patientDao,
        _push = pushService;

  final MemberDao _members;
  final PatientDao _patients;
  final OfflinePushService _push;

  Future<bool> markDeceased({
    required String memberLocalId,
    required String deceasedReason,
  }) async {
    final member = await _members.getById(memberLocalId);
    if (member == null) {
      debugPrint('[MemberDeceased] member not found id=$memberLocalId');
      return false;
    }
    if (!member.isActive) {
      debugPrint('[MemberDeceased] member already inactive id=$memberLocalId');
      return false;
    }

    await _members.updateMemberDeceasedReason(
      member.id,
      isActive: false,
      deceasedReason: deceasedReason.trim().isEmpty ? null : deceasedReason.trim(),
    );

    await _deactivatePatientBridge(member);

    if (!OfflinePushService.isPushInFlight) {
      unawaited(_push.pushAll(syncMode: 'ManualSync'));
    }
    return true;
  }

  Future<void> _deactivatePatientBridge(HouseholdMemberEntity member) async {
    final candidateIds = <String>{
      if (member.patientId != null && member.patientId!.isNotEmpty)
        member.patientId!,
      member.id,
    };
    for (final pid in candidateIds) {
      final patient = await _patients.byId(pid);
      if (patient == null) continue;
      await _patients.upsertMany([
        patient.copyWithActive(false),
      ]);
    }
  }
}
