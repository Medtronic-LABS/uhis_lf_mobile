/// Referral model + state enum for the SK Referral SLA dashboard.
///
/// Owns the device-side `referrals` table (schema v3, see `AppDatabase`).
/// Spec: `leapfrog-setup/designs/referral-sla-engine.md`.
///
/// The server contract is sparse — `ReferralTicketDTO` carries only id /
/// referredBy / referredTo / patientStatus / referredReason / dates and a
/// 4-value status enum. The device extends with the full 14-state lifecycle
/// + SLA bookkeeping locally; richer states ride in `referral_status_events`
/// + `referrals.state` until the server contract grows (OQ #1).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Tier of the referral, which drives the SLA windows in [SlaEvaluator].
///
/// Tier is a property of the referral itself (set at creation from the
/// clinical category / diagnosis), not derived from the score.
enum SlaTier {
  emergency,
  urgent,
  routine;

  String get wireTag {
    switch (this) {
      case SlaTier.emergency:
        return 'emergency';
      case SlaTier.urgent:
        return 'urgent';
      case SlaTier.routine:
        return 'routine';
    }
  }

  static SlaTier fromWireTag(String? tag) {
    switch ((tag ?? '').toLowerCase()) {
      case 'emergency':
      case 'emer':
        return SlaTier.emergency;
      case 'urgent':
      case 'asap':
        return SlaTier.urgent;
      default:
        return SlaTier.routine;
    }
  }
}

/// Referral lifecycle state. Eight lifecycle values + six exception values.
///
/// The legacy server contract (`uhis-platform/spice-service/.../ReferralStatus`)
/// has only four values: `Referred`, `OnTreatment`, `Recovered`, `Died`. These
/// map to [ReferralStatus.fromWireTag] → `created`, `treatmentStarted`,
/// `closedRecovered`, `closedDeceased` respectively. Every other state in the
/// 14-value enum is **device-side only** until the server contract extends
/// (OQ #1 in `designs/referral-sla-engine.md`).
enum ReferralStatus {
  // ── Lifecycle (8) ───────────────────────────────────────────────────────
  created,
  acknowledged,
  inTransit,
  arrived,
  treatmentStarted,
  closedRecovered,
  closedDeceased,
  paused,

  // ── Exception (6) ───────────────────────────────────────────────────────
  refused,
  targetUnreachable,
  duplicate,
  transportDeclined,
  diverted,
  breachedArrival;

  String get wireTag {
    switch (this) {
      case ReferralStatus.created:
        return 'created';
      case ReferralStatus.acknowledged:
        return 'acknowledged';
      case ReferralStatus.inTransit:
        return 'inTransit';
      case ReferralStatus.arrived:
        return 'arrived';
      case ReferralStatus.treatmentStarted:
        return 'treatmentStarted';
      case ReferralStatus.closedRecovered:
        return 'closedRecovered';
      case ReferralStatus.closedDeceased:
        return 'closedDeceased';
      case ReferralStatus.paused:
        return 'paused';
      case ReferralStatus.refused:
        return 'refused';
      case ReferralStatus.targetUnreachable:
        return 'targetUnreachable';
      case ReferralStatus.duplicate:
        return 'duplicate';
      case ReferralStatus.transportDeclined:
        return 'transportDeclined';
      case ReferralStatus.diverted:
        return 'diverted';
      case ReferralStatus.breachedArrival:
        return 'breachedArrival';
    }
  }

  /// Map a server wire tag into a device-side state. The server only knows
  /// four values; everything else is device-local.
  static ReferralStatus fromWireTag(String? tag) {
    switch ((tag ?? '').trim()) {
      // Device-side 14 states (direct match).
      case 'created':
        return ReferralStatus.created;
      case 'acknowledged':
        return ReferralStatus.acknowledged;
      case 'inTransit':
        return ReferralStatus.inTransit;
      case 'arrived':
        return ReferralStatus.arrived;
      case 'treatmentStarted':
        return ReferralStatus.treatmentStarted;
      case 'closedRecovered':
        return ReferralStatus.closedRecovered;
      case 'closedDeceased':
        return ReferralStatus.closedDeceased;
      case 'paused':
        return ReferralStatus.paused;
      case 'refused':
        return ReferralStatus.refused;
      case 'targetUnreachable':
        return ReferralStatus.targetUnreachable;
      case 'duplicate':
        return ReferralStatus.duplicate;
      case 'transportDeclined':
        return ReferralStatus.transportDeclined;
      case 'diverted':
        return ReferralStatus.diverted;
      case 'breachedArrival':
        return ReferralStatus.breachedArrival;
      // Legacy 4-state server enum mapping (case-sensitive on the wire).
      case 'Referred':
        return ReferralStatus.created;
      case 'OnTreatment':
        return ReferralStatus.treatmentStarted;
      case 'Recovered':
        return ReferralStatus.closedRecovered;
      case 'Died':
        return ReferralStatus.closedDeceased;
      default:
        return ReferralStatus.created;
    }
  }

  bool get isClosed =>
      this == ReferralStatus.closedRecovered ||
      this == ReferralStatus.closedDeceased ||
      this == ReferralStatus.duplicate;

  bool get isException =>
      index >= ReferralStatus.refused.index &&
      index <= ReferralStatus.breachedArrival.index;
}

/// Single referral row, mirrored across the device's `referrals` table.
///
/// Construction: prefer [Referral.draft] for SK-side creation (sets sane
/// defaults + `now` timestamps); use [Referral.fromDb] for read-back; use
/// [Referral.fromMapperPayload] when ingesting from `/fhir-mapper-service/
/// patient/referral-tickets/...`.
class Referral {
  const Referral({
    required this.id,
    required this.patientId,
    required this.slaTier,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.householdId,
    this.villageId,
    this.diagnosisCode,
    this.diagnosisLabel,
    this.priorityScore,
    this.priorityLevel,
    this.priorityDrivers = const <String>[],
    this.rationaleJson,
    this.dueArrivalAt,
    this.dueTreatmentAt,
    this.breachedSince,
    this.escalationLevel = 0,
    this.closedAt,
    this.rawJson,
  });

  final String id;
  final String patientId;
  final String? householdId;
  final String? villageId;
  final SlaTier slaTier;
  final String? diagnosisCode;
  final String? diagnosisLabel;
  final ReferralStatus state;
  final int? priorityScore;
  final String? priorityLevel; // SlaPriority.wireTag
  final List<String> priorityDrivers;
  final String? rationaleJson; // RiskRationale.toJson() encoded
  final int? dueArrivalAt; // epoch ms
  final int? dueTreatmentAt;
  final int? breachedSince;
  final int escalationLevel; // 0=sk,1=supervisor,2=facility,3=district
  final int createdAt;
  final int updatedAt;
  final int? closedAt;
  final String? rawJson;

  /// Best-effort referral target facility name, parsed from [rawJson].
  /// Tries multiple keys the server wire has used across versions.
  String? get facilityName {
    if (rawJson == null || rawJson!.isEmpty) {
      debugPrint('[ReferralFacility] Referral($id) rawJson=null → facilityName=null');
      return null;
    }
    try {
      final m = jsonDecode(rawJson!);
      if (m is! Map) return null;
      for (final k in const ['facilityName', 'referredTo', 'referredSiteName', 'referredSite']) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) {
          debugPrint('[ReferralFacility] Referral($id) key=$k → ${v.trim()}');
          return v.trim();
        }
      }
    } catch (_) {}
    debugPrint('[ReferralFacility] Referral($id) rawJson present but no facility key matched');
    return null;
  }

  Map<String, Object?> toDb() => {
        'id': id,
        'patient_id': patientId,
        'household_id': householdId,
        'village_id': villageId,
        'sla_tier': slaTier.wireTag,
        'diagnosis_code': diagnosisCode,
        'diagnosis_label': diagnosisLabel,
        'state': state.wireTag,
        'priority_score': priorityScore,
        'priority_level': priorityLevel,
        'priority_drivers': priorityDrivers.isEmpty
            ? null
            : jsonEncode(priorityDrivers),
        'rationale_json': rationaleJson,
        'due_arrival_at': dueArrivalAt,
        'due_treatment_at': dueTreatmentAt,
        'breached_since': breachedSince,
        'escalation_level': escalationLevel,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'closed_at': closedAt,
        'raw_json': rawJson,
      };

  factory Referral.fromDb(Map<String, Object?> r) {
    final driversRaw = r['priority_drivers'] as String?;
    final drivers = (driversRaw == null || driversRaw.isEmpty)
        ? const <String>[]
        : (jsonDecode(driversRaw) as List<dynamic>)
            .map((e) => e as String)
            .toList(growable: false);
    return Referral(
      id: r['id'] as String,
      patientId: r['patient_id'] as String,
      householdId: r['household_id'] as String?,
      villageId: r['village_id'] as String?,
      slaTier: SlaTier.fromWireTag(r['sla_tier'] as String?),
      diagnosisCode: r['diagnosis_code'] as String?,
      diagnosisLabel: r['diagnosis_label'] as String?,
      state: ReferralStatus.fromWireTag(r['state'] as String?),
      priorityScore: (r['priority_score'] as num?)?.toInt(),
      priorityLevel: r['priority_level'] as String?,
      priorityDrivers: drivers,
      rationaleJson: r['rationale_json'] as String?,
      dueArrivalAt: (r['due_arrival_at'] as num?)?.toInt(),
      dueTreatmentAt: (r['due_treatment_at'] as num?)?.toInt(),
      breachedSince: (r['breached_since'] as num?)?.toInt(),
      escalationLevel: (r['escalation_level'] as num?)?.toInt() ?? 0,
      createdAt: (r['created_at'] as num).toInt(),
      updatedAt: (r['updated_at'] as num).toInt(),
      closedAt: (r['closed_at'] as num?)?.toInt(),
      rawJson: r['raw_json'] as String?,
    );
  }

  /// Build a draft Referral as the SK is creating it on-device. Caller must
  /// run it through [SlaEvaluator] + [PriorityScorer] before persisting so
  /// the SLA + priority columns are populated.
  factory Referral.draft({
    required String id,
    required String patientId,
    required SlaTier slaTier,
    String? householdId,
    String? villageId,
    String? diagnosisCode,
    String? diagnosisLabel,
    String? facilityName,
    DateTime? now,
  }) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return Referral(
      id: id,
      patientId: patientId,
      householdId: householdId,
      villageId: villageId,
      slaTier: slaTier,
      diagnosisCode: diagnosisCode,
      diagnosisLabel: diagnosisLabel,
      state: ReferralStatus.created,
      createdAt: ts,
      updatedAt: ts,
      rawJson: facilityName != null ? jsonEncode({'facilityName': facilityName}) : null,
    );
  }

  /// Build from a fhir-mapper response payload (legacy
  /// `ReferralTicketDTO` shape). The wire only carries `id` / `referredBy` /
  /// `referredTo` / `patientStatus` / `referredReason` / dates — every device
  /// field beyond that is defaulted, then refined by the SLA engine.
  factory Referral.fromMapperPayload(Map<String, Object?> p) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return Referral(
      id: (p['id'] ?? '') as String,
      patientId: (p['memberId'] ?? p['patientId'] ?? '') as String,
      slaTier: _inferTier(p['referredReason'] as String?),
      diagnosisLabel: p['referredReason'] as String?,
      state: ReferralStatus.fromWireTag(p['patientStatus'] as String?),
      createdAt: _parseDateMs(p['referredDate']) ?? ts,
      updatedAt: ts,
      rawJson: jsonEncode(p),
    );
  }

  Referral copyWith({
    SlaTier? slaTier,
    ReferralStatus? state,
    int? priorityScore,
    String? priorityLevel,
    List<String>? priorityDrivers,
    String? rationaleJson,
    int? dueArrivalAt,
    int? dueTreatmentAt,
    int? breachedSince,
    int? escalationLevel,
    int? updatedAt,
    int? closedAt,
  }) =>
      Referral(
        id: id,
        patientId: patientId,
        householdId: householdId,
        villageId: villageId,
        slaTier: slaTier ?? this.slaTier,
        diagnosisCode: diagnosisCode,
        diagnosisLabel: diagnosisLabel,
        state: state ?? this.state,
        priorityScore: priorityScore ?? this.priorityScore,
        priorityLevel: priorityLevel ?? this.priorityLevel,
        priorityDrivers: priorityDrivers ?? this.priorityDrivers,
        rationaleJson: rationaleJson ?? this.rationaleJson,
        dueArrivalAt: dueArrivalAt ?? this.dueArrivalAt,
        dueTreatmentAt: dueTreatmentAt ?? this.dueTreatmentAt,
        breachedSince: breachedSince ?? this.breachedSince,
        escalationLevel: escalationLevel ?? this.escalationLevel,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        closedAt: closedAt ?? this.closedAt,
        rawJson: rawJson,
      );

  /// Heuristic: map a referral reason string into an SLA tier when the wire
  /// payload doesn't carry an explicit category. Pilot-grade — clinical lead
  /// to tune (OQ #2 in spec). Match is case-insensitive substring.
  static SlaTier _inferTier(String? reason) {
    if (reason == null || reason.isEmpty) return SlaTier.routine;
    final r = reason.toLowerCase();
    const emergencyMarkers = <String>[
      'severe',
      'convulsion',
      'eclampsia',
      'obstetric emergency',
      'dehydration',
      'shock',
    ];
    if (emergencyMarkers.any(r.contains)) return SlaTier.emergency;
    const urgentMarkers = <String>[
      'high-risk',
      'hypertensive crisis',
      'moderate pneumonia',
      'severe anemia',
      'anemia',
    ];
    if (urgentMarkers.any(r.contains)) return SlaTier.urgent;
    return SlaTier.routine;
  }

  static int? _parseDateMs(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString();
    final dt = DateTime.tryParse(s);
    return dt?.millisecondsSinceEpoch;
  }
}

/// Single status transition for a referral. Append-only.
class ReferralStatusEventRow {
  const ReferralStatusEventRow({
    required this.id,
    required this.referralId,
    this.fromState,
    required this.toState,
    required this.occurredAt,
    this.actor,
    this.reason,
    this.rawJson,
  });

  final String id;
  final String referralId;
  final ReferralStatus? fromState;
  final ReferralStatus toState;
  final int occurredAt;
  final String? actor;
  final String? reason;
  final String? rawJson;

  Map<String, Object?> toDb() => {
        'id': id,
        'referral_id': referralId,
        'from_state': fromState?.wireTag,
        'to_state': toState.wireTag,
        'occurred_at': occurredAt,
        'actor': actor,
        'reason': reason,
        'raw_json': rawJson,
      };

  factory ReferralStatusEventRow.fromDb(Map<String, Object?> r) =>
      ReferralStatusEventRow(
        id: r['id'] as String,
        referralId: r['referral_id'] as String,
        fromState: r['from_state'] == null
            ? null
            : ReferralStatus.fromWireTag(r['from_state'] as String?),
        toState: ReferralStatus.fromWireTag(r['to_state'] as String?),
        occurredAt: (r['occurred_at'] as num).toInt(),
        actor: r['actor'] as String?,
        reason: r['reason'] as String?,
        rawJson: r['raw_json'] as String?,
      );
}

/// One row per scheduled (and re-scheduled) notification. Used by
/// [RepeatScheduler.rehydrateOnBoot] to restore pending alarms after a
/// device reboot.
class NotificationLogRow {
  const NotificationLogRow({
    required this.id,
    required this.referralId,
    required this.channel,
    required this.firedAt,
    this.nextRepeatAt,
    this.payloadJson,
  });

  final String id;
  final String referralId;
  final String channel; // 'critical' | 'warning' | 'completion'
  final int firedAt;
  final int? nextRepeatAt;
  final String? payloadJson;

  Map<String, Object?> toDb() => {
        'id': id,
        'referral_id': referralId,
        'channel': channel,
        'fired_at': firedAt,
        'next_repeat_at': nextRepeatAt,
        'payload_json': payloadJson,
      };

  factory NotificationLogRow.fromDb(Map<String, Object?> r) =>
      NotificationLogRow(
        id: r['id'] as String,
        referralId: r['referral_id'] as String,
        channel: r['channel'] as String,
        firedAt: (r['fired_at'] as num).toInt(),
        nextRepeatAt: (r['next_repeat_at'] as num?)?.toInt(),
        payloadJson: r['payload_json'] as String?,
      );
}
