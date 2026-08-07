/// CCE loader — lists open fetch **REFERRED** follow-ups and projects them
/// into [CceAlert] cards. Patient identity / phone are resolved via
/// follow-up `memberId` → `members.fhir_id` (not `patient_id`).
///
/// For NCD cards, Facility / Treatment are advanced from synced assessment
/// history (`medicalreviewvisit` / `ncdmedicalreview`) dated on/after the
/// community NCD visit (`encounterDate` / matching `encounterId`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/db/assessment_dao.dart';
import '../../core/db/follow_up_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/referral.dart';
import '../../features/patient/followup_call_service.dart';
import 'cce_alert.dart';

class CceRepository {
  CceRepository({
    required FollowUpDao followUps,
    required MemberDao members,
    AssessmentDao? assessments,
    HouseholdDao? households,
    DateTime Function()? clock,
    this.retryAttempts = FollowUpCallService.cceRetryAttempts,
  })  : _followUps = followUps,
        _members = members,
        _assessments = assessments,
        _households = households,
        _clock = clock ?? DateTime.now;

  final FollowUpDao _followUps;
  final MemberDao _members;
  final AssessmentDao? _assessments;
  final HouseholdDao? _households;
  final DateTime Function() _clock;

  /// CCE referred-call retry limit (matches call logging).
  final int retryAttempts;

  /// Notifies when callers ask the UI to refresh after a call.
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  Listenable get changes => _tick;

  void notifyChanged() => _tick.value++;

  /// Load CCE alerts from fetch-origin open **REFERRED** follow-ups only.
  ///
  /// Mirrors Android `getReferredFollowUpPatientListLiveData`:
  /// `FollowUp INNER JOIN HouseholdMember ON memberId = fhir_id` with
  /// `isActive = 1`. Rows without an active local member are dropped — that
  /// is why CCE can flicker when the member roster has not landed yet.
  Future<List<CceAlert>> loadAlerts({int limit = 200}) async {
    final eligible = await _followUps.openReferredFetched(limit: limit);
    if (eligible.isEmpty) return const <CceAlert>[];

    // Resolve members by follow-up memberId → members.fhir_id (batched).
    final memberIds = <String>{};
    for (final fu in eligible) {
      final mid = _memberIdFrom(fu);
      if (mid != null) memberIds.add(mid);
    }
    final membersByFhirId = <String, HouseholdMemberEntity>{};
    for (final mid in memberIds) {
      final m = await _members.getByFhirId(mid);
      if (m != null) membersByFhirId[mid] = m;
    }

    final households = <String, HouseholdEntity>{};
    if (_households != null) {
      final all = await _households.getAll(limit: 1000);
      for (final h in all) {
        households[h.id] = h;
        if (h.fhirId != null && h.fhirId!.isNotEmpty) {
          households[h.fhirId!] = h;
        }
      }
    }

    // Assessment history may be keyed by FHIR patient id, member fhir id, or
    // member local id depending on sync remap — query all candidates.
    final assessmentKeySet = <String>{};
    for (final m in membersByFhirId.values) {
      assessmentKeySet.addAll(_assessmentLookupKeys(m));
    }
    final assessmentsByKey = _assessments == null || assessmentKeySet.isEmpty
        ? const <String, List<AssessmentRow>>{}
        : await _assessments.forMany(assessmentKeySet.toList());

    final now = _clock();
    final alerts = <CceAlert>[];
    for (final fu in eligible) {
      final memberId = _memberIdFrom(fu);
      final member = memberId == null ? null : membersByFhirId[memberId];
      // Android INNER JOIN — no member / inactive member ⇒ not listed.
      if (memberId == null || member == null || !member.isActive) {
        continue;
      }

      final patient = _patientFromMember(member);
      final h = (member.householdId != null
              ? households[member.householdId!]
              : null) ??
          (member.householdFhirId != null
              ? households[member.householdFhirId!]
              : null);

      alerts.add(CceAlert.fromFollowUp(
        fu,
        patient: patient,
        latitude: member.latitude ?? h?.latitude,
        longitude: member.longitude ?? h?.longitude,
        landmark: h?.landmark,
        now: now,
        retryAttempts: retryAttempts,
        assessments: _signalsForMember(member, assessmentsByKey),
      ));
    }

    final sorted = [...alerts]..sort(_compare);
    // Dedupe by member/patient identity — prefer memberId when present.
    final seen = <String>{};
    return sorted.where((a) {
      final key = a.patientId;
      return seen.add(key);
    }).toList(growable: false);
  }

  int actionsNeededCount(List<CceAlert> alerts) =>
      alerts.where((a) => a.severity != CceSeverity.completed).length;

  /// Legacy SLA status update — not used for fetch-based referred CCE.
  Future<void> updateStatus({
    required String referralId,
    required ReferralStatus to,
    String? reason,
  }) async {
    debugPrint(
      '[CceRepository] updateStatus ignored for follow-up CCE '
      '(referralId=$referralId to=${to.wireTag})',
    );
  }

  static String? _memberIdFrom(FollowUpRow fu) {
    try {
      final decoded = jsonDecode(fu.rawJson);
      if (decoded is Map) {
        final v = decoded['memberId'] ?? decoded['householdMemberId'];
        if (v != null) {
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Keys under which synced assessment history may be stored for [m].
  static List<String> _assessmentLookupKeys(HouseholdMemberEntity m) {
    final keys = <String>{};
    void add(String? v) {
      final s = v?.trim();
      if (s != null && s.isNotEmpty) keys.add(s);
    }

    add(m.fhirId);
    add(m.id);
    add(m.patientId);
    return keys.toList();
  }

  static List<CceAssessmentSignal> _signalsForMember(
    HouseholdMemberEntity member,
    Map<String, List<AssessmentRow>> byKey,
  ) {
    final seen = <String>{};
    final out = <CceAssessmentSignal>[];
    for (final key in _assessmentLookupKeys(member)) {
      final rows = byKey[key];
      if (rows == null) continue;
      for (final r in rows) {
        if (!seen.add(r.id)) continue;
        out.add(CceAssessmentSignal(
          id: r.id,
          kind: r.kind,
          occurredAt: r.occurredAt,
        ));
      }
    }
    return out;
  }

  /// Project a member row into [Patient] so [CceAlert.fromFollowUp] can use
  /// name/phone/village from `members` (keyed by fhir_id).
  static Patient? _patientFromMember(HouseholdMemberEntity? m) {
    if (m == null) return null;
    final id = m.fhirId ?? m.id;
    return Patient(
      id: id,
      patientId: m.patientId,
      name: m.name,
      gender: m.gender,
      dob: m.dob,
      phone: m.phone,
      nationalId: m.nationalId,
      householdId: m.householdId ?? m.householdFhirId,
      villageId: m.villageId,
      villageName: m.villageName,
      isActive: m.isActive,
      updatedAt: m.updatedAt,
      rawJson: m.rawJson ?? '{}',
      age: _ageFromDob(m.dob),
    );
  }

  static int? _ageFromDob(String? dob) {
    if (dob == null || dob.trim().isEmpty) return null;
    final d = DateTime.tryParse(dob);
    if (d == null) return null;
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }

  static int _compare(CceAlert a, CceAlert b) {
    final s = _severityRank(a.severity).compareTo(_severityRank(b.severity));
    if (s != 0) return s;
    return b.priorityScore.compareTo(a.priorityScore);
  }

  static int _severityRank(CceSeverity s) {
    switch (s) {
      case CceSeverity.breached:
        return 0;
      case CceSeverity.warning:
        return 1;
      case CceSeverity.onTrack:
        return 2;
      case CceSeverity.completed:
        return 3;
    }
  }
}
