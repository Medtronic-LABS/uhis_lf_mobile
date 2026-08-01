import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../mission/mission_pregnancy_facts.dart';
import 'app_database.dart';

/// Per-patient pregnancy episode snapshot (`patient_pregnancy_snapshot`).
///
/// Mirrors the Spice Android `PregnancyDetail` fields needed for ANC
/// show/hide, visit continuity, and mission dashboard flags. Gestational
/// weeks are **not** stored — they are always computed from [lmpDate].
///
/// One row per patient — sync merges with [mergePreservingDates] so a
/// server pull cannot wipe locally-captured obstetric fields.
class PregnancySnapshotRow {
  const PregnancySnapshotRow({
    required this.patientId,
    required this.facts,
    this.updatedAt,
    this.eddDate,
    this.lmpDate,
    this.deliveryDateMillis,
    this.ancVisitNo,
    this.pncVisitNo,
    this.gravida,
    this.parity,
    this.livingChildren,
    this.ageOfLastChild,
    this.pregnancyTest,
    this.previousPregnancyComplications,
    this.existingIllness,
    this.onTreatment,
    this.ttTdCompleted,
    this.facilityIdentifiedForDelivery,
    this.ancWeight,
    this.lastAncVisitDateMs,
  });

  final String patientId;
  final PregnancyFacts facts;
  final int? updatedAt;

  /// EDD as epoch milliseconds.
  final int? eddDate;

  /// LMP as epoch milliseconds — source of truth for gestational age.
  final int? lmpDate;

  /// Delivery date as epoch milliseconds (post pregnancy-outcome).
  final int? deliveryDateMillis;

  /// Completed ANC visit count (Spice `PregnancyDetail.ancVisitNo`).
  final int? ancVisitNo;

  /// Completed PNC mother visit count (Spice `PregnancyDetail.pncVisitNo`).
  final int? pncVisitNo;

  /// Spice `PregnancyDetail.gravida` — PW registration / PW profile.
  final int? gravida;

  /// Spice `PregnancyDetail.parity`.
  final int? parity;

  /// Spice `PregnancyDetail.numberOfLivingChildren`.
  final int? livingChildren;

  /// Spice `PregnancyDetail.ageOfLastChild` (ISO date or free text).
  final String? ageOfLastChild;

  /// Spice `PregnancyDetail.pregnancyTest`.
  final String? pregnancyTest;

  /// JSON list string — Spice `previousPregnancyComplications`.
  final String? previousPregnancyComplications;

  /// JSON list string — Spice `pregnantWomanExistingIllness`.
  final String? existingIllness;

  /// JSON list string — Spice `pregnantWomanOnTreatment`.
  final String? onTreatment;

  /// Spice `ttTdCompleted` (string / option id).
  final String? ttTdCompleted;

  /// Spice facility identified for delivery.
  final String? facilityIdentifiedForDelivery;

  /// Last ANC weight (kg) — Spice `ancWeight` for visit-2+ gain check.
  final double? ancWeight;

  /// Last ANC visit date as epoch ms — Spice `ancVisitDate`.
  final int? lastAncVisitDateMs;

  /// Gestational weeks from [lmpDate] (floor days/7). Null when LMP unknown.
  int? get gestationalWeeksFromLmp {
    final ms = lmpDate;
    if (ms == null) return null;
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms))
        .inDays;
    if (days < 0) return 0;
    return days ~/ 7;
  }

  Map<String, Object?> toDb() => {
        'patient_id': patientId,
        'high_risk_pregnant_woman': facts.highRiskPregnantWoman ? 1 : 0,
        'has_gaps_in_anc': facts.hasGapsInAnc ? 1 : 0,
        'is_postpartum_window': facts.isPostpartumWindow ? 1 : 0,
        'is_near_term_anc': facts.isNearTermAnc ? 1 : 0,
        'had_delivery_complications': facts.hadDeliveryComplications ? 1 : 0,
        'has_pnc_illness': facts.hasPncIllness ? 1 : 0,
        'updated_at': updatedAt,
        'edd_date': eddDate,
        'lmp_date': lmpDate,
        'delivery_date_millis': deliveryDateMillis,
        'anc_visit_no': ancVisitNo,
        'pnc_visit_no': pncVisitNo,
        'gravida': gravida,
        'parity': parity,
        'living_children': livingChildren,
        'age_of_last_child': ageOfLastChild,
        'pregnancy_test': pregnancyTest,
        'previous_pregnancy_complications': previousPregnancyComplications,
        'existing_illness': existingIllness,
        'on_treatment': onTreatment,
        'tt_td_completed': ttTdCompleted,
        'facility_identified_for_delivery': facilityIdentifiedForDelivery,
        'anc_weight': ancWeight,
        'last_anc_visit_date_ms': lastAncVisitDateMs,
      };

  static PregnancySnapshotRow fromDb(Map<String, Object?> row) =>
      PregnancySnapshotRow(
        patientId: row['patient_id'] as String,
        facts: PregnancyFacts(
          highRiskPregnantWoman: row['high_risk_pregnant_woman'] == 1,
          hasGapsInAnc: row['has_gaps_in_anc'] == 1,
          isPostpartumWindow: row['is_postpartum_window'] == 1,
          isNearTermAnc: row['is_near_term_anc'] == 1,
          hadDeliveryComplications: row['had_delivery_complications'] == 1,
          hasPncIllness: row['has_pnc_illness'] == 1,
        ),
        updatedAt: row['updated_at'] as int?,
        eddDate: row['edd_date'] as int?,
        lmpDate: row['lmp_date'] as int?,
        deliveryDateMillis: row['delivery_date_millis'] as int?,
        ancVisitNo: row['anc_visit_no'] as int?,
        pncVisitNo: row['pnc_visit_no'] as int?,
        gravida: row['gravida'] as int?,
        parity: row['parity'] as int?,
        livingChildren: row['living_children'] as int?,
        ageOfLastChild: row['age_of_last_child'] as String?,
        pregnancyTest: row['pregnancy_test'] as String?,
        previousPregnancyComplications:
            row['previous_pregnancy_complications'] as String?,
        existingIllness: row['existing_illness'] as String?,
        onTreatment: row['on_treatment'] as String?,
        ttTdCompleted: row['tt_td_completed'] as String?,
        facilityIdentifiedForDelivery:
            row['facility_identified_for_delivery'] as String?,
        ancWeight: (row['anc_weight'] as num?)?.toDouble(),
        lastAncVisitDateMs: row['last_anc_visit_date_ms'] as int?,
      );

  /// Encode a form list/string value as a JSON list string for SQLite.
  static String? encodeJsonList(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return null;
      if (t.startsWith('[')) return t;
      return jsonEncode([t]);
    }
    if (value is List) {
      if (value.isEmpty) return null;
      return jsonEncode(value.map((e) => e.toString()).toList());
    }
    return jsonEncode([value.toString()]);
  }

  /// Decode a stored JSON list string back to `List<String>`.
  static List<String>? decodeJsonList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      return [raw];
    }
    return [raw];
  }

  static int? asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  PregnancySnapshotRow copyWith({
    String? patientId,
    PregnancyFacts? facts,
    int? updatedAt,
    int? eddDate,
    int? lmpDate,
    int? deliveryDateMillis,
    int? ancVisitNo,
    int? pncVisitNo,
    int? gravida,
    int? parity,
    int? livingChildren,
    String? ageOfLastChild,
    String? pregnancyTest,
    String? previousPregnancyComplications,
    String? existingIllness,
    String? onTreatment,
    String? ttTdCompleted,
    String? facilityIdentifiedForDelivery,
    double? ancWeight,
    int? lastAncVisitDateMs,
    bool clearAncVisitNo = false,
    bool clearPncVisitNo = false,
  }) =>
      PregnancySnapshotRow(
        patientId: patientId ?? this.patientId,
        facts: facts ?? this.facts,
        updatedAt: updatedAt ?? this.updatedAt,
        eddDate: eddDate ?? this.eddDate,
        lmpDate: lmpDate ?? this.lmpDate,
        deliveryDateMillis: deliveryDateMillis ?? this.deliveryDateMillis,
        ancVisitNo:
            clearAncVisitNo ? null : (ancVisitNo ?? this.ancVisitNo),
        pncVisitNo:
            clearPncVisitNo ? null : (pncVisitNo ?? this.pncVisitNo),
        gravida: gravida ?? this.gravida,
        parity: parity ?? this.parity,
        livingChildren: livingChildren ?? this.livingChildren,
        ageOfLastChild: ageOfLastChild ?? this.ageOfLastChild,
        pregnancyTest: pregnancyTest ?? this.pregnancyTest,
        previousPregnancyComplications: previousPregnancyComplications ??
            this.previousPregnancyComplications,
        existingIllness: existingIllness ?? this.existingIllness,
        onTreatment: onTreatment ?? this.onTreatment,
        ttTdCompleted: ttTdCompleted ?? this.ttTdCompleted,
        facilityIdentifiedForDelivery: facilityIdentifiedForDelivery ??
            this.facilityIdentifiedForDelivery,
        ancWeight: ancWeight ?? this.ancWeight,
        lastAncVisitDateMs: lastAncVisitDateMs ?? this.lastAncVisitDateMs,
      );

  /// Prefer non-null values from [patch]; keep this row's values otherwise.
  PregnancySnapshotRow mergedWith(PregnancySnapshotRow patch) =>
      PregnancySnapshotRow(
        patientId: patientId,
        facts: patch.facts,
        updatedAt: patch.updatedAt ?? updatedAt,
        eddDate: patch.eddDate ?? eddDate,
        lmpDate: patch.lmpDate ?? lmpDate,
        deliveryDateMillis: patch.deliveryDateMillis ?? deliveryDateMillis,
        ancVisitNo: PregnancySnapshotDao._preferHigherVisitNo(
          patch.ancVisitNo,
          ancVisitNo,
        ),
        pncVisitNo: PregnancySnapshotDao._preferHigherVisitNo(
          patch.pncVisitNo,
          pncVisitNo,
        ),
        gravida: patch.gravida ?? gravida,
        parity: patch.parity ?? parity,
        livingChildren: patch.livingChildren ?? livingChildren,
        ageOfLastChild: patch.ageOfLastChild ?? ageOfLastChild,
        pregnancyTest: patch.pregnancyTest ?? pregnancyTest,
        previousPregnancyComplications: patch.previousPregnancyComplications ??
            previousPregnancyComplications,
        existingIllness: patch.existingIllness ?? existingIllness,
        onTreatment: patch.onTreatment ?? onTreatment,
        ttTdCompleted: patch.ttTdCompleted ?? ttTdCompleted,
        facilityIdentifiedForDelivery: patch.facilityIdentifiedForDelivery ??
            facilityIdentifiedForDelivery,
        ancWeight: patch.ancWeight ?? ancWeight,
        lastAncVisitDateMs: patch.lastAncVisitDateMs ?? lastAncVisitDateMs,
      );
}

class PregnancySnapshotDao {
  PregnancySnapshotDao(this._db);

  final AppDatabase _db;

  Future<void> upsertMany(List<PregnancySnapshotRow> rows) async {
    if (rows.isEmpty) return;
    final batch = _db.db.batch();
    for (final r in rows) {
      batch.insert(
        AppDatabase.tablePregnancySnapshot,
        r.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Bulk read — returns `patientId → PregnancyFacts` for *every* patient
  /// that has a stored snapshot. Callers should treat missing keys as
  /// [PregnancyFacts.empty].
  Future<Map<String, PregnancyFacts>> getAll() async {
    final rows = await getAllRows();
    return {for (final e in rows.entries) e.key: e.value.facts};
  }

  /// Full snapshot rows keyed by patient ID.
  Future<Map<String, PregnancySnapshotRow>> getAllRows() async {
    final rows = await _db.db.query(AppDatabase.tablePregnancySnapshot);
    final out = <String, PregnancySnapshotRow>{};
    for (final r in rows) {
      final row = PregnancySnapshotRow.fromDb(r);
      out[row.patientId] = row;
    }
    return out;
  }

  Future<PregnancySnapshotRow?> byPatient(String patientId) async {
    final rows = await _db.db.query(
      AppDatabase.tablePregnancySnapshot,
      where: 'patient_id = ?',
      whereArgs: [patientId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PregnancySnapshotRow.fromDb(rows.first);
  }

  /// Snapshot for [patientId], including any row sync stored under
  /// [memberId].
  ///
  /// Sync keys rows by household-member id whenever the FHIR patient map was
  /// incomplete, so a plain [byPatient] can miss a woman's entire episode and
  /// make an established pregnancy look brand new. Values recorded against
  /// the patient id win; the member row only fills gaps, and visit counters
  /// take the higher of the two.
  Future<PregnancySnapshotRow?> byPatientOrMember(
    String patientId, {
    String? memberId,
  }) async {
    final own = await byPatient(patientId);
    if (memberId == null || memberId.isEmpty || memberId == patientId) {
      return own;
    }
    final alias = await byPatient(memberId);
    if (alias == null) return own;
    if (own == null) return alias.copyWith(patientId: patientId);
    return alias.mergedWith(own).copyWith(patientId: patientId);
  }

  /// Insert or replace a single row. Prefer [mergeUpsert] when only a subset
  /// of episode fields is known so existing obstetric data is not wiped.
  Future<void> upsertOne(PregnancySnapshotRow row) async {
    await _db.db.insert(
      AppDatabase.tablePregnancySnapshot,
      row.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Merge [patch] into the existing row (or insert if none). Non-null patch
  /// fields win; null patch fields keep prior values.
  Future<void> mergeUpsert(PregnancySnapshotRow patch) async {
    final existing = await byPatient(patch.patientId);
    if (existing == null) {
      await upsertOne(patch);
      return;
    }
    await upsertOne(existing.mergedWith(patch));
  }

  /// Next visit number for a stored counter, matching Android
  /// `AssessmentViewModel.getVisitNumber`: null → 1, otherwise existing + 1.
  static int nextVisitNo(int? existing) {
    if (existing == null) return 1;
    return existing + 1;
  }

  /// Next ANC visit number for [patientId] (Spice `ancVisitNo + 1`).
  Future<int> nextAncVisitNo(String patientId, {String? memberId}) async {
    final row = await byPatientOrMember(patientId, memberId: memberId);
    return nextVisitNo(row?.ancVisitNo);
  }

  /// Next PNC visit number for [patientId] (Spice `pncVisitNo + 1`).
  Future<int> nextPncVisitNo(String patientId, {String? memberId}) async {
    final row = await byPatientOrMember(patientId, memberId: memberId);
    return nextVisitNo(row?.pncVisitNo);
  }

  /// Persist the just-completed ANC visit count (Spice writes back
  /// `pregnancyDetail.ancVisitNo` after each ANC save).
  Future<void> setAncVisitNo(String patientId, int visitNo) async {
    await _setVisitCounter(patientId, ancVisitNo: visitNo);
  }

  /// Persist the just-completed PNC visit count (Spice writes back
  /// `pregnancyDetail.pncVisitNo` after each PNC save).
  Future<void> setPncVisitNo(String patientId, int visitNo) async {
    await _setVisitCounter(patientId, pncVisitNo: visitNo);
  }

  Future<void> _setVisitCounter(
    String patientId, {
    int? ancVisitNo,
    int? pncVisitNo,
  }) async {
    final existing = await byPatient(patientId);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (existing == null) {
      await upsertOne(PregnancySnapshotRow(
        patientId: patientId,
        facts: PregnancyFacts.empty,
        updatedAt: nowMs,
        ancVisitNo: ancVisitNo,
        pncVisitNo: pncVisitNo,
      ));
      return;
    }
    await upsertOne(existing.copyWith(
      updatedAt: nowMs,
      ancVisitNo: ancVisitNo,
      pncVisitNo: pncVisitNo,
    ));
  }

  Future<void> clearAll() async {
    await _db.db.delete(AppDatabase.tablePregnancySnapshot);
  }

  /// Collapse multiple server episodes for the same patient into one row.
  static List<PregnancySnapshotRow> coalesceByPatient(
    List<PregnancySnapshotRow> rows,
  ) {
    final byId = <String, PregnancySnapshotRow>{};
    for (final row in rows) {
      final prev = byId[row.patientId];
      if (prev == null) {
        byId[row.patientId] = row;
        continue;
      }
      byId[row.patientId] = prev.mergedWith(row);
    }
    return byId.values.toList(growable: false);
  }

  /// Merge server [incoming] rows with [prior] local snapshots.
  ///
  /// - Incoming is first coalesced per patient (see [coalesceByPatient]).
  /// - Incoming facts always win.
  /// - Null clinical / date fields on incoming keep the prior value.
  /// - Visit counters take the higher of server vs local.
  /// - Prior rows for patients absent from [incoming] are kept.
  static List<PregnancySnapshotRow> mergePreservingDates({
    required List<PregnancySnapshotRow> incoming,
    required Map<String, PregnancySnapshotRow> prior,
  }) {
    final coalesced = coalesceByPatient(incoming);
    final incomingIds = <String>{};
    final merged = <PregnancySnapshotRow>[];
    for (final row in coalesced) {
      incomingIds.add(row.patientId);
      final prev = prior[row.patientId];
      if (prev == null) {
        merged.add(row);
        continue;
      }
      merged.add(PregnancySnapshotRow(
        patientId: row.patientId,
        facts: row.facts,
        updatedAt: row.updatedAt ?? prev.updatedAt,
        eddDate: row.eddDate ?? prev.eddDate,
        lmpDate: row.lmpDate ?? prev.lmpDate,
        deliveryDateMillis: row.deliveryDateMillis ?? prev.deliveryDateMillis,
        ancVisitNo: _preferHigherVisitNo(row.ancVisitNo, prev.ancVisitNo),
        pncVisitNo: _preferHigherVisitNo(row.pncVisitNo, prev.pncVisitNo),
        gravida: row.gravida ?? prev.gravida,
        parity: row.parity ?? prev.parity,
        livingChildren: row.livingChildren ?? prev.livingChildren,
        ageOfLastChild: row.ageOfLastChild ?? prev.ageOfLastChild,
        pregnancyTest: row.pregnancyTest ?? prev.pregnancyTest,
        previousPregnancyComplications: row.previousPregnancyComplications ??
            prev.previousPregnancyComplications,
        existingIllness: row.existingIllness ?? prev.existingIllness,
        onTreatment: row.onTreatment ?? prev.onTreatment,
        ttTdCompleted: row.ttTdCompleted ?? prev.ttTdCompleted,
        facilityIdentifiedForDelivery: row.facilityIdentifiedForDelivery ??
            prev.facilityIdentifiedForDelivery,
        ancWeight: row.ancWeight ?? prev.ancWeight,
        lastAncVisitDateMs: row.lastAncVisitDateMs ?? prev.lastAncVisitDateMs,
      ));
    }
    for (final entry in prior.entries) {
      if (!incomingIds.contains(entry.key)) {
        merged.add(entry.value);
      }
    }
    return merged;
  }

  static int? _preferHigherVisitNo(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a >= b ? a : b;
  }
}
