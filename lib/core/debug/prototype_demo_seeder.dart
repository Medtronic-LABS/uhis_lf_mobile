import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../models/risk.dart';

/// Seeds the local SQLite database with the exact 5 prototype patients
/// defined in the Apon Sushashthya v12 design.
///
/// Only runs in kDebugMode. Safe to call repeatedly — clears DEMO-* rows
/// before re-inserting so the queue always reflects the canonical prototype.
class PrototypeDemoSeeder {
  PrototypeDemoSeeder(this._db);

  final AppDatabase _db;

  static const _demoPatientPrefix = 'DEMO-';

  Future<void> seedDemoPatients() async {
    assert(kDebugMode, 'PrototypeDemoSeeder must only run in debug builds');
    if (!kDebugMode) return;

    await _clearDemoData();

    final now = DateTime.now();
    final batch = _db.db.batch();

    // ── Nasrin Begum — ANC Visit 3 due, today ──────────────────────────────
    _insertPatient(batch, now,
      id: 'DEMO-PAT-001',
      name: 'Nasrin Begum',
      age: 24,
      gender: 'Female',
      householdId: 'DEMO-HH-007',
      houseNo: '07',
      village: 'Char Bhadra',
      band: Band.band3,
      modifier: Modifier.a,
      nextDueDays: 0,   // due today
    );
    _insertProgramme(batch, 'DEMO-PAT-001', 'anc');
    _insertFollowUp(batch, now,
      id: 'DEMO-FU-001',
      patientId: 'DEMO-PAT-001',
      kind: 'anc',
      dueDays: 0,
    );

    // ── Priya Rani Das — ANC Visit 1, first registration, today ───────────
    _insertPatient(batch, now,
      id: 'DEMO-PAT-002',
      name: 'Priya Rani Das',
      age: 20,
      gender: 'Female',
      householdId: 'DEMO-HH-006',
      houseNo: '06',
      village: 'Bhadra',
      band: Band.band3,
      modifier: Modifier.none,
      nextDueDays: 0,
    );
    _insertProgramme(batch, 'DEMO-PAT-002', 'anc');
    _insertFollowUp(batch, now,
      id: 'DEMO-FU-002',
      patientId: 'DEMO-PAT-002',
      kind: 'anc',
      dueDays: 0,
    );

    // ── Rahim Hossain — Child immunisation, overdue ────────────────────────
    _insertPatient(batch, now,
      id: 'DEMO-PAT-003',
      name: 'Rahim Hossain',
      age: 2,
      gender: 'Male',
      householdId: 'DEMO-HH-013',
      houseNo: '13',
      village: 'Char Bhadra',
      band: Band.band2,
      modifier: Modifier.b,
      nextDueDays: -14,  // 2 weeks overdue
    );
    _insertProgramme(batch, 'DEMO-PAT-003', 'imci');
    _insertFollowUp(batch, now,
      id: 'DEMO-FU-003',
      patientId: 'DEMO-PAT-003',
      kind: 'imci',
      dueDays: -14,
    );

    // ── Md. Karim Uddin — Monthly NCD check, this week ────────────────────
    _insertPatient(batch, now,
      id: 'DEMO-PAT-004',
      name: 'Md. Karim Uddin',
      age: 52,
      gender: 'Male',
      householdId: 'DEMO-HH-021',
      houseNo: '21',
      village: 'Bhadra',
      band: Band.band4,
      modifier: Modifier.none,
      nextDueDays: 3,   // this week
    );
    _insertProgramme(batch, 'DEMO-PAT-004', 'ncd');
    _insertFollowUp(batch, now,
      id: 'DEMO-FU-004',
      patientId: 'DEMO-PAT-004',
      kind: 'ncd',
      dueDays: 3,
    );

    await batch.commit(noResult: true);
    debugPrint('[PrototypeDemoSeeder] seeded 4 demo patients');
  }

  void _insertPatient(
    dynamic batch,
    DateTime now, {
    required String id,
    required String name,
    required int age,
    required String gender,
    required String householdId,
    required String houseNo,
    required String village,
    required Band band,
    required Modifier modifier,
    required int nextDueDays,
  }) {
    final dob = now.subtract(Duration(days: age * 365));
    final nextDueAt = now.add(Duration(days: nextDueDays)).millisecondsSinceEpoch;
    final lastVisitAt = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    final rank = sortRankFor(band, modifier);

    batch.insert(
      AppDatabase.tablePatients,
      {
        'id': id,
        'patient_id': id,
        'name': name,
        'gender': gender,
        'dob': dob.toIso8601String().substring(0, 10),
        'phone': '',
        'national_id': '',
        'household_id': householdId,
        'village_id': '1',
        'village_name': village,
        'is_active': 1,
        'updated_at': now.millisecondsSinceEpoch,
        'age': age,
        'risk_score': rank,
        'risk_band': band.wireTag,
        'risk_modifier': modifier.wireTag,
        'risk_reasons': '',
        'red_flag': band == Band.band1 ? 1 : 0,
        'last_visit_at': lastVisitAt,
        'next_due_at': nextDueAt,
        'missed_visit_count': nextDueDays < 0 ? 1 : 0,
      },
      conflictAlgorithm: 5, // CONFLICT_REPLACE
    );
  }

  void _insertProgramme(dynamic batch, String patientId, String programme) {
    batch.insert(
      AppDatabase.tablePatientProgrammes,
      {
        'patient_id': patientId,
        'programme': programme,
      },
      conflictAlgorithm: 5, // CONFLICT_REPLACE
    );
  }

  void _insertFollowUp(
    dynamic batch,
    DateTime now, {
    required String id,
    required String patientId,
    required String kind,
    required int dueDays,
  }) {
    final dueAt = now.add(Duration(days: dueDays)).millisecondsSinceEpoch;
    batch.insert(
      AppDatabase.tableFollowUps,
      {
        'id': id,
        'patient_id': patientId,
        'kind': kind,
        'due_at': dueAt,
        'completed_at': null,
        'attempts': 0,
        'is_lost': 0,
      },
      conflictAlgorithm: 5, // CONFLICT_REPLACE
    );
  }

  Future<void> _clearDemoData() async {
    await _db.db.delete(AppDatabase.tablePatients,
        where: "id LIKE '$_demoPatientPrefix%'");
    await _db.db.delete(AppDatabase.tablePatientProgrammes,
        where: "patient_id LIKE '$_demoPatientPrefix%'");
    await _db.db.delete(AppDatabase.tableFollowUps,
        where: "patient_id LIKE '$_demoPatientPrefix%'");
  }
}
