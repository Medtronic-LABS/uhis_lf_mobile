/// CCE loader — the single seam between the referral SLA engine and the CCE
/// drawer UI.
///
/// Owns no state of its own and no new persistence: it reads open referrals
/// from [ReferralRepository], joins cached patient identity from [PatientDao],
/// and projects each row into a [CceAlert]. Status changes are delegated
/// straight back to [ReferralRepository.transition] so the SLA engine,
/// timeline audit log and notification scheduler all stay authoritative.
///
/// Because it only composes existing repositories, the CCE feature adds zero
/// backend surface — it is a pure presentation layer (see `cce_alert.dart`).
library;

import 'package:flutter/foundation.dart';

import '../../core/db/household_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/referral.dart';
import '../referral/referral_repository.dart';
import 'cce_alert.dart';

class CceRepository {
  CceRepository({
    required ReferralRepository referrals,
    required PatientDao patients,
    HouseholdDao? households,
    DateTime Function()? clock,
  })  : _referrals = referrals,
        _patients = patients,
        _households = households,
        _clock = clock ?? DateTime.now;

  final ReferralRepository _referrals;
  final PatientDao _patients;
  // Optional — supplies household lat/long/landmark for a precise "Locate".
  final HouseholdDao? _households;
  final DateTime Function() _clock;

  /// UI listens to this to refresh after any referral mutation.
  Listenable get changes => _referrals.changes;

  /// Load the CCE alert list, sorted the way the drawer renders it:
  /// breached → warning → on-track → completed, then by priority score, then
  /// by earliest breach. One patient query, joined in memory.
  Future<List<CceAlert>> loadAlerts({int limit = 200}) async {
    final referrals = await _referrals.load(limit: limit);
    if (referrals.isEmpty) return const <CceAlert>[];

    final patients = await _patients.allForVillages(const <String>[]);
    final byId = <String, Patient>{for (final p in patients) p.id: p};

    // Join household geo for a precise "Locate" (best-effort).
    final households = <String, HouseholdEntity>{};
    if (_households != null) {
      final all = await _households.getAll(limit: 1000);
      for (final h in all) {
        households[h.id] = h;
      }
    }

    final now = _clock();
    final alerts = referrals.map((r) {
      final h = r.householdId == null ? null : households[r.householdId];
      return CceAlert.fromReferral(
        r,
        patient: byId[r.patientId],
        latitude: h?.latitude,
        longitude: h?.longitude,
        landmark: h?.landmark,
        now: now,
      );
    }).toList(growable: false);

    final sorted = [...alerts]..sort(_compare);

    // One card per patient — keep the most critical referral (first after sort).
    // Patients with multiple open referrals should not appear as duplicates.
    final seen = <String>{};
    final deduped =
        sorted.where((a) => seen.add(a.patientId)).toList(growable: false);

    return deduped;
  }

  /// Total open CCE alerts — matches the number of cards the drawer renders.
  /// Excludes completed referrals (discharged / closed).
  int actionsNeededCount(List<CceAlert> alerts) =>
      alerts.where((a) => a.severity != CceSeverity.completed).length;

  /// Apply an SK status update. Delegates to the referral lifecycle owner so
  /// the transition is journaled and re-scored. [reason] carries an optional
  /// barrier tag ("Transport", "Cost", …).
  Future<void> updateStatus({
    required String referralId,
    required ReferralStatus to,
    String? reason,
  }) {
    return _referrals.transition(
      referralId: referralId,
      to: to,
      reason: reason,
    );
  }

  /// Sort comparator: worst-first by severity, then priority score desc.
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
