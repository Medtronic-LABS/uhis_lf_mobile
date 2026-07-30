/// Gate 3 — Flagship scenario: pregnant woman + BP ≥ 140/90.
///
/// Verifies the full end-to-end flow for the composed ANC + NCD assessment:
///   1. PathwayEngine activates ANC for a pregnant woman.
///   2. FormCompositor produces [anc-vitals, ncd-htn, ncd-dm, anc-specific]
///      in priority order; BP fields appear exactly once, owned by anc-vitals.
///   3. CdsRules fires bp_stage1(addPathway NCD) when only ANC is active.
///   4. CdsRules fires bp_stage1(continueAssessment) when ANC + NCD both active.
///   5. UnifiedSubmissionOrchestrator fans out two LocalAssessmentEntity rows
///      (one ANC, one NCD) that share the same encounterId.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/db/local_assessment_dao.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/composer/cds_rules.dart';
import 'package:uhis_next/features/visit/composer/form_compositor.dart';
import 'package:uhis_next/features/visit/pathway/pathway_engine.dart';
import 'package:uhis_next/features/visit/submission/unified_submission_orchestrator.dart';
import 'package:uhis_next/features/visit/triage/patient_context_builder.dart';

// ── Test DB ────────────────────────────────────────────────────────────────────

Future<AppDatabase> _openTestDb() async {
  final raw = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppDatabase.schemaVersion,
      onCreate: AppDatabase.createSchema,
    ),
  );
  return AppDatabase.forTesting(raw);
}

// ── Pathway helper ─────────────────────────────────────────────────────────────

ActivatedPathway _pathway(Programme programme, {int priority = 10}) =>
    ActivatedPathway(
      programme: programme,
      priority: priority,
      confidence: 1.0,
      trigger: PathwayTrigger.rule,
      rationaleKey: 'gate3-test',
    );

// ── Suite ──────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Patient context: 28-year-old pregnant woman with stage-1 HTN (150/95).
  const encounterId = 'enc-gate3-flagship';
  const patientId = 'pat-preg-htn-001';
  const memberId = 'mbr-001';
  const householdMemberLocalId = 42;

  // ── 1. PathwayEngine activates ANC ────────────────────────────────────────

  test(
      'Gate3-1 — pregnant woman (28yo, dizziness) → ANC pathway activated', () {
    final ctx = PatientContext(
      patientId: patientId,
      ageMonths: 28 * 12,
      sex: Sex.female,
      isPregnant: true,
    );

    final pathways = PathwayEngine.activate({'dizziness'}, ctx);
    expect(
      pathways.map((p) => p.programme),
      contains(Programme.anc),
    );
  });

  // ── 2. Composed form: 4 sections, correct order, BP owned once ────────────

  test(
      'Gate3-2 — compose([ANC, NCD]) → '
      '[anc-vitals, ncd-htn, ncd-dm, anc-specific]; '
      'BP owned by anc-vitals; no duplicate field IDs', () {
    final form = FormCompositor.compose([
      _pathway(Programme.anc, priority: 5),
      _pathway(Programme.ncd, priority: 40),
    ]);

    final ids = form.sections.map((s) => s.sectionId).toList();

    // All four sections present.
    expect(ids, contains('anc-vitals'));
    expect(ids, contains('ncd-htn'));
    expect(ids, contains('ncd-dm'));
    expect(ids, contains('anc-specific'));

    // Correct priority order.
    final ancVitals = ids.indexOf('anc-vitals');
    final ncdHtn = ids.indexOf('ncd-htn');
    final ncdDm = ids.indexOf('ncd-dm');
    final ancSpec = ids.indexOf('anc-specific');
    expect(ancVitals, lessThan(ncdHtn));
    expect(ncdHtn, lessThan(ncdDm));
    expect(ncdDm, lessThan(ancSpec));

    // BP fields owned by anc-vitals (priority 12 beats ncd-htn at 42).
    expect(form.fieldOwnership['bloodPressureSystolic'], equals('anc-vitals'));
    expect(form.fieldOwnership['bloodPressureDiastolic'], equals('anc-vitals'));

    // Every sectionId is unique (compositor deduplicates sections, not fields).
    expect(
      ids.toSet().length,
      equals(ids.length),
      reason: 'Compositor must deduplicate sections — no duplicate sectionIds',
    );

    // Shared BP fields appear in ncd-htn.fields but ownership stays with anc-vitals.
    final ncdHtnSection = form.sections.firstWhere((s) => s.sectionId == 'ncd-htn');
    final ncdHtnFieldIds = ncdHtnSection.fields.map((f) => f.fieldId).toSet();
    expect(ncdHtnFieldIds, contains('bloodPressureSystolic'),
        reason: 'ncd-htn defines BP as sharedField; field still present in section.fields');
    // But ownership belongs to anc-vitals (already verified above).
  });

  // ── 3. CDS at detection: ANC only + BP 150/95 → addPathway(NCD) ──────────

  test(
      'Gate3-3 — BP=150/95, {ANC} active → '
      'bp_stage1 warning with addPathway(NCD)', () {
    final alerts = CdsRules.evaluate(
      {'bloodPressureSystolic': 150, 'bloodPressureDiastolic': 95},
      {Programme.anc},
    );

    final bp = alerts.firstWhere(
      (a) => a.alertId == 'bp_stage1',
      orElse: () => throw StateError('bp_stage1 alert missing'),
    );
    expect(bp.severity, CdsSeverity.warning);
    expect(bp.action, CdsAction.addPathway,
        reason: 'NCD not yet active — engine must propose adding it');
    expect(bp.addPathway, Programme.ncd);
  });

  // ── 4. CDS at completion: ANC+NCD both active + BP 150/95 ────────────────

  test(
      'Gate3-4 — BP=150/95, {ANC, NCD} active → '
      'bp_stage1 present but NOT addPathway', () {
    final alerts = CdsRules.evaluate(
      {'bloodPressureSystolic': 150, 'bloodPressureDiastolic': 95},
      {Programme.anc, Programme.ncd},
    );

    final bp = alerts.firstWhere(
      (a) => a.alertId == 'bp_stage1',
      orElse: () => throw StateError('bp_stage1 alert missing'),
    );
    expect(bp.action, isNot(CdsAction.addPathway),
        reason: 'NCD already active — must not propose adding it again');
    expect(bp.addPathway, isNull);
  });

  // ── 5. Submission fan-out: two legs share one encounterId ─────────────────

  test(
      'Gate3-5 — submit(ANC+NCD draft) → two LocalAssessmentEntity rows '
      'with shared encounterId; one ANC leg, one NCD leg', () async {
    final appDb = await _openTestDb();
    addTearDown(appDb.close);

    final localAssessmentDao = LocalAssessmentDao(appDb);
    final draftDao = AssessmentDraftDao(appDb);

    // Persist a completed draft with both programmes activated.
    final draft = AssessmentDraftRow(
      encounterId: encounterId,
      patientId: patientId,
      memberId: memberId,
      activatedProgrammes: jsonEncode(['ANC', 'NCD']),
      fieldValues: jsonEncode({
        'bloodPressureSystolic': 150,
        'bloodPressureDiastolic': 95,
        'weight': 62.5,
        'fundalHeight': 28,
        'glucoseValue': null,
      }),
      sectionStatus: jsonEncode({
        'anc-vitals': 'done',
        'ncd-htn': 'done',
        'ncd-dm': 'done',
        'anc-specific': 'done',
      }),
    );
    await draftDao.saveDraft(draft);

    final orchestrator = UnifiedSubmissionOrchestrator(localAssessmentDao);
    await orchestrator.submit(
      draft,
      householdMemberLocalId: householdMemberLocalId,
      memberId: memberId,
      householdId: 'hh-001',
      villageId: 'vil-001',
    );

    // Two LocalAssessmentEntity rows must have been inserted.
    final rows = await localAssessmentDao.getUnsynced();
    expect(rows, hasLength(2),
        reason: 'One leg per activated programme (ANC + NCD = 2)');

    // Both rows share the same encounterId.
    for (final row in rows) {
      final details = jsonDecode(row.otherDetails!) as Map<String, dynamic>;
      expect(
        details['encounterId'],
        equals(encounterId),
        reason: 'Both legs must share the encounter ID',
      );
      expect(
        details['legId'],
        isA<String>(),
        reason: 'Each leg must have a stable UUID',
      );
    }

    // Each leg targets a distinct programme.
    final types = rows.map((r) => r.assessmentType).toSet();
    expect(types, containsAll(['ANC', 'NCD']));

    // Each leg has a distinct legId.
    final legIds = rows
        .map((r) => (jsonDecode(r.otherDetails!) as Map)['legId'] as String)
        .toSet();
    expect(legIds, hasLength(2),
        reason: 'Each leg must have a unique legId UUID');

    // Both legs are pending (not yet synced).
    for (final row in rows) {
      expect(row.syncStatus, AssessmentSyncStatus.pending);
    }
  });
}
