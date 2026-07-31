import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/patient.dart';
import 'package:uhis_next/core/models/referral.dart';
import 'package:uhis_next/features/cce/cce_alert.dart';

/// Unit tests for the CCE derivation — the pure mapping from a 14-state
/// [ReferralStatus] + SLA bookkeeping onto the wireframe's severity / journey /
/// badge / status-line. No Flutter, no DB.
void main() {
  final now = DateTime(2026, 7, 13, 12, 0);
  int ms(Duration fromNow) => now.add(fromNow).millisecondsSinceEpoch;

  Referral referral({
    required ReferralStatus state,
    required SlaTier tier,
    Duration created = const Duration(days: -5),
    Duration? dueArrival,
    Duration? dueTreatment,
    Duration? breachedSince,
    Duration? updated,
    Duration? closed,
    String? priorityLevel,
    int priorityScore = 0,
    int escalationLevel = 0,
    String? diagnosisLabel = 'Severe pneumonia',
    String? rawJson,
  }) {
    return Referral(
      id: 'ref-test',
      patientId: 'pat-1',
      slaTier: tier,
      state: state,
      diagnosisLabel: diagnosisLabel,
      priorityScore: priorityScore,
      priorityLevel: priorityLevel,
      escalationLevel: escalationLevel,
      dueArrivalAt: dueArrival == null ? null : ms(dueArrival),
      dueTreatmentAt: dueTreatment == null ? null : ms(dueTreatment),
      breachedSince: breachedSince == null ? null : ms(breachedSince),
      createdAt: ms(created),
      updatedAt: ms(updated ?? created),
      closedAt: closed == null ? null : ms(closed),
      rawJson: rawJson,
    );
  }

  final patient = Patient(
    id: 'pat-1',
    name: 'Nasrin Begum',
    gender: 'female',
    phone: '+8801700000000',
    age: 24,
    villageName: 'Manikganj',
    rawJson: '{}',
  );

  CceAlert build(Referral r, {Patient? p}) =>
      CceAlert.fromReferral(r, patient: p, now: now);

  group('severity', () {
    test('breached when SLA window is breached and still open', () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.emergency,
        created: const Duration(days: -10),
        dueArrival: const Duration(days: -7),
        breachedSince: const Duration(days: -7),
      ));
      expect(a.severity, CceSeverity.breached);
      expect(a.slaBadge, contains('BREACHED'));
      expect(a.statusLine, contains('Not arrived'));
    });

    test('warning when arrived but treatment due soon', () {
      final a = build(referral(
        state: ReferralStatus.arrived,
        tier: SlaTier.urgent,
        created: const Duration(days: -5),
        dueTreatment: const Duration(days: 1),
        updated: const Duration(days: -2),
      ));
      expect(a.severity, CceSeverity.warning);
      expect(a.slaBadge, contains('left'));
      expect(a.intelTags, contains('At facility'));
    });

    test('warning when a critical case is still waiting even with clock room',
        () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.urgent,
        dueArrival: const Duration(days: 5),
        priorityLevel: 'critical',
      ));
      expect(a.severity, CceSeverity.warning);
    });

    test('onTrack when open, not breached, deadline comfortably ahead', () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.routine,
        created: const Duration(hours: -1),
        dueArrival: const Duration(days: 3),
        priorityLevel: 'low',
      ));
      expect(a.severity, CceSeverity.onTrack);
    });

    test('completed when the referral is closed', () {
      final a = build(referral(
        state: ReferralStatus.closedRecovered,
        tier: SlaTier.urgent,
        closed: const Duration(days: -1),
      ));
      expect(a.severity, CceSeverity.completed);
      expect(a.slaBadge, 'Completed');
      expect(a.statusLine, contains('Discharged'));
    });
  });

  group('journey', () {
    test('breached + not arrived marks the facility node missed', () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.emergency,
        created: const Duration(days: -10),
        dueArrival: const Duration(days: -7),
        breachedSince: const Duration(days: -7),
      ));
      expect(a.journey, hasLength(4));
      expect(a.journey[0].state, CceStepState.done); // SK visit
      expect(a.journey[1].state, CceStepState.done); // referred
      expect(a.journey[2].state, CceStepState.missed); // facility
      expect(a.journey[3].state, CceStepState.pending); // treatment
    });

    test('discharged marks every node done', () {
      final a = build(referral(
        state: ReferralStatus.closedRecovered,
        tier: SlaTier.urgent,
        closed: const Duration(days: -1),
      ));
      expect(a.journey.map((s) => s.state),
          everyElement(CceStepState.done));
      expect(a.journey.last.sublabel, 'Discharged');
    });

    test('arrived marks facility done, treatment pending', () {
      final a = build(referral(
        state: ReferralStatus.arrived,
        tier: SlaTier.urgent,
        dueTreatment: const Duration(days: 1),
      ));
      expect(a.journey[2].state, CceStepState.done);
      expect(a.journey[3].state, CceStepState.pending);
    });
  });

  group('patient identity', () {
    test('name / age / gender / phone flow through from the joined patient',
        () {
      final a = build(
        referral(state: ReferralStatus.created, tier: SlaTier.routine),
        p: patient,
      );
      expect(a.patientName, 'Nasrin Begum');
      expect(a.patientAge, 24);
      expect(a.patientGender, 'female');
      expect(a.hasPhone, isTrue);
      expect(a.villageName, 'Manikganj');
    });

    test('falls back to a placeholder name when patient is missing', () {
      final a = build(referral(state: ReferralStatus.created, tier: SlaTier.routine));
      expect(a.patientName, 'Patient');
      expect(a.hasPhone, isFalse);
    });
  });

  group('intel tags', () {
    test('escalation surfaces a tag', () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.emergency,
        dueArrival: const Duration(days: -1),
        breachedSince: const Duration(days: -1),
        escalationLevel: 2,
      ));
      expect(a.intelTags, contains('Not checked in'));
      expect(a.intelTags, contains('Escalated L2'));
    });

    test('transport-declined surfaces the barrier prompt', () {
      final a = build(referral(
        state: ReferralStatus.transportDeclined,
        tier: SlaTier.urgent,
      ));
      expect(a.intelTags, contains('Transport barrier?'));
    });
  });

  group('severity.needsAction', () {
    test('only breached and warning count as needing action', () {
      expect(CceSeverity.breached.needsAction, isTrue);
      expect(CceSeverity.warning.needsAction, isTrue);
      expect(CceSeverity.onTrack.needsAction, isFalse);
      expect(CceSeverity.completed.needsAction, isFalse);
    });
  });

  group('facility name', () {
    test('parsed from rawJson appears in referredMeta', () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.emergency,
        rawJson: jsonEncode({'facilityName': 'UHC Manikganj'}),
      ));
      expect(a.facilityName, 'UHC Manikganj');
      expect(a.referredMeta, contains('UHC Manikganj'));
    });

    test('tolerates alternate wire keys (referredTo)', () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.emergency,
        rawJson: jsonEncode({'referredTo': 'District Hospital'}),
      ));
      expect(a.facilityName, 'District Hospital');
    });

    test('absent facility leaves referredMeta as date · reason', () {
      final a = build(referral(
        state: ReferralStatus.created,
        tier: SlaTier.emergency,
        diagnosisLabel: 'Severe pneumonia',
      ));
      expect(a.facilityName, isNull);
      expect(a.referredMeta, contains('Severe pneumonia'));
      expect(a.referredMeta.split('·').length, 2);
    });
  });

  group('locate geo', () {
    test('hasGeo true when household coordinates are joined', () {
      final a = CceAlert.fromReferral(
        referral(state: ReferralStatus.created, tier: SlaTier.urgent),
        latitude: 23.8,
        longitude: 90.4,
        landmark: 'Near mosque',
        now: now,
      );
      expect(a.hasGeo, isTrue);
      expect(a.latitude, 23.8);
      expect(a.landmark, 'Near mosque');
    });

    test('hasGeo false without coordinates', () {
      final a = build(referral(
          state: ReferralStatus.created, tier: SlaTier.urgent));
      expect(a.hasGeo, isFalse);
    });
  });
}
