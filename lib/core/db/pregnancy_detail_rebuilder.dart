import 'dart:convert';

import 'member_assessment_history_dao.dart';

/// Spice [PregnancyDetailRebuilder] — folds MAH into one row per pregnancy episode.
abstract final class PregnancyDetailRebuilder {
  static const motherServiceTypes = [
    'pwprofile',
    'anc',
    'pnc_mother',
    'pregnancyoutcome',
  ];

  static List<PregnancyDetailRow> rebuildMotherEpisodes({
    required int householdMemberLocalId,
    required String? householdMemberFhirId,
    required List<MemberAssessmentHistoryRow> history,
  }) {
    final motherRows = history.where((r) {
      final s = r.serviceProvided?.toLowerCase();
      if (s == null) return false;
      return motherServiceTypes.any((t) => s == t);
    }).toList();
    return _groupByEpisode(motherRows)
        .entries
        .map(
          (e) => _foldMotherEpisode(
            householdMemberLocalId: householdMemberLocalId,
            householdMemberFhirId: householdMemberFhirId,
            episodeId: e.key,
            rows: e.value,
          ),
        )
        .toList();
  }

  static Map<String, List<MemberAssessmentHistoryRow>> _groupByEpisode(
    List<MemberAssessmentHistoryRow> rows,
  ) {
    final out = <String, List<MemberAssessmentHistoryRow>>{};
    for (final row in rows) {
      final obs = _obsMap(row.observationsJson);
      final episodeId = obs['pregnancyEpisodeId']?.toString().trim();
      if (episodeId == null || episodeId.isEmpty) continue;
      out.putIfAbsent(episodeId, () => []).add(row);
    }
    return out;
  }

  static PregnancyDetailRow _foldMotherEpisode({
    required int householdMemberLocalId,
    required String? householdMemberFhirId,
    required String episodeId,
    required List<MemberAssessmentHistoryRow> rows,
  }) {
    final sorted = [...rows]..sort((a, b) {
        final vd = a.visitDate.compareTo(b.visitDate);
        if (vd != 0) return vd;
        return (a.id ?? 0).compareTo(b.id ?? 0);
      });

    MemberAssessmentHistoryRow? firstWhereType(String type) {
      for (final r in sorted) {
        if (r.serviceProvided?.toLowerCase() == type) return r;
      }
      return null;
    }

    MemberAssessmentHistoryRow? lastWhereType(String type) {
      MemberAssessmentHistoryRow? last;
      for (final r in sorted) {
        if (r.serviceProvided?.toLowerCase() == type) last = r;
      }
      return last;
    }

    final pwProfile = firstWhereType('pwprofile');
    final ancRows =
        sorted.where((r) => r.serviceProvided?.toLowerCase() == 'anc').toList();
    final pncRows = sorted
        .where((r) => r.serviceProvided?.toLowerCase() == 'pnc_mother')
        .toList();
    final outcome = lastWhereType('pregnancyoutcome');

    final pwObs = _obsMap(pwProfile?.observationsJson);
    final firstPncObs = _obsMap(pncRows.firstOrNull?.observationsJson);
    final latestAncObs = _obsMap(ancRows.lastOrNull?.observationsJson);
    final outcomeObs = _obsMap(outcome?.observationsJson);

    return PregnancyDetailRow(
      householdMemberLocalId: householdMemberLocalId,
      householdMemberFhirId: householdMemberFhirId,
      pregnancyEpisodeId: episodeId,
      lastMenstrualPeriod: _stringObs(pwObs, const [
        'lastMenstrualPeriod',
        'lastMenstrualPeriodDate',
      ]),
      estimatedDeliveryDate: _stringObs(pwObs, const ['estimatedDeliveryDate']),
      dateOfDelivery: _stringObs(outcomeObs, const ['dateOfDelivery']),
      startAt: sorted.first.visitDate,
      endAt: sorted.last.visitDate,
      ancVisitNo: ancRows.isEmpty ? null : ancRows.length,
      gravida: _intObs(pwObs, const ['gravida']),
      parity: _intObs(pwObs, const ['parity']) ??
          _intObs(firstPncObs, const ['parity']),
      pregnantWomanExistingIllness:
          latestAncObs['pregnantWomanExistingIllness']?.toString(),
      highRiskPregnantWoman: _riskObs(latestAncObs, 'highRiskPregnantWoman'),
      gapsInAnc: latestAncObs['gapsInAnc']?.toString(),
      typeOfAbortion: _stringObs(outcomeObs, const ['typeOfAbortion']),
    );
  }

  /// Spice stores [highRiskPregnantWoman] as JSON map text when present.
  static String? _riskObs(Map<String, dynamic> obs, String key) {
    final v = obs[key];
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is Map && v.isNotEmpty) {
      return jsonEncode(v);
    }
    return null;
  }

  static Map<String, dynamic> _obsMap(String? json) {
    if (json == null || json.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return {};
  }

  static String? _stringObs(Map<String, dynamic> obs, List<String> keys) {
    for (final k in keys) {
      final v = obs[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static int? _intObs(Map<String, dynamic> obs, List<String> keys) {
    for (final k in keys) {
      final v = obs[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final p = int.tryParse(v.toString().trim());
      if (p != null) return p;
    }
    return null;
  }
}

/// Local mirror of Spice [PregnancyDetail] for dashboard SQL parity.
class PregnancyDetailRow {
  const PregnancyDetailRow({
    this.id,
    required this.householdMemberLocalId,
    this.householdMemberFhirId,
    required this.pregnancyEpisodeId,
    this.lastMenstrualPeriod,
    this.estimatedDeliveryDate,
    this.dateOfDelivery,
    this.startAt,
    this.endAt,
    this.ancVisitNo,
    this.gravida,
    this.parity,
    this.pregnantWomanExistingIllness,
    this.highRiskPregnantWoman,
    this.gapsInAnc,
    this.typeOfAbortion,
  });

  final int? id;
  final int householdMemberLocalId;
  final String? householdMemberFhirId;
  final String pregnancyEpisodeId;
  final String? lastMenstrualPeriod;
  final String? estimatedDeliveryDate;
  final String? dateOfDelivery;
  final String? startAt;
  final String? endAt;
  final int? ancVisitNo;
  final int? gravida;
  final int? parity;
  final String? pregnantWomanExistingIllness;
  final String? highRiskPregnantWoman;
  final String? gapsInAnc;
  final String? typeOfAbortion;

  Map<String, Object?> toDb() => {
        if (id != null) 'id': id,
        'household_member_local_id': householdMemberLocalId,
        'household_member_fhir_id': householdMemberFhirId,
        'pregnancy_episode_id': pregnancyEpisodeId,
        'last_menstrual_period': lastMenstrualPeriod,
        'estimated_delivery_date': estimatedDeliveryDate,
        'date_of_delivery': dateOfDelivery,
        'start_at': startAt,
        'end_at': endAt,
        'anc_visit_no': ancVisitNo,
        'gravida': gravida,
        'parity': parity,
        'pregnant_woman_existing_illness': pregnantWomanExistingIllness,
        'high_risk_pregnant_woman': highRiskPregnantWoman,
        'gaps_in_anc': gapsInAnc,
        'type_of_abortion': typeOfAbortion,
      };

  static PregnancyDetailRow fromDb(Map<String, Object?> row) {
    return PregnancyDetailRow(
      id: row['id'] as int?,
      householdMemberLocalId: row['household_member_local_id'] as int,
      householdMemberFhirId: row['household_member_fhir_id'] as String?,
      pregnancyEpisodeId: row['pregnancy_episode_id'] as String,
      lastMenstrualPeriod: row['last_menstrual_period'] as String?,
      estimatedDeliveryDate: row['estimated_delivery_date'] as String?,
      dateOfDelivery: row['date_of_delivery'] as String?,
      startAt: row['start_at'] as String?,
      endAt: row['end_at'] as String?,
      ancVisitNo: row['anc_visit_no'] as int?,
      gravida: row['gravida'] as int?,
      parity: row['parity'] as int?,
      pregnantWomanExistingIllness:
          row['pregnant_woman_existing_illness'] as String?,
      highRiskPregnantWoman: row['high_risk_pregnant_woman'] as String?,
      gapsInAnc: row['gaps_in_anc'] as String?,
      typeOfAbortion: row['type_of_abortion'] as String?,
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

extension _LastOrNull<E> on List<E> {
  E? get lastOrNull => isEmpty ? null : last;
}
