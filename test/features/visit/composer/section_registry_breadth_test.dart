/// Phase 4.5 — Section registry breadth tests for EPI, NUTRITION, PNC.
///
/// Tests:
/// 1. forProgrammes({epi}) includes epi-review.
/// 2. forProgrammes({nutrition}) includes nutrition-detail.
/// 3. forProgrammes({pnc}) includes pnc-check.
/// 4. compose([ICCM, NUTRITION]) — nutrition-detail at priority 35 appears
///    after symptom-detail (30) and before iccm-classify (40).
/// 5. All 7 programmes compose together — no crashes, no field duplicates.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/composer/form_compositor.dart';
import 'package:uhis_next/features/visit/composer/section_registry.dart';
import 'package:uhis_next/features/visit/pathway/pathway_engine.dart';

// ── Helper ──────────────────────────────────────────────────────────────────────

ActivatedPathway _pathway(Programme programme, {int priority = 10}) =>
    ActivatedPathway(
      programme: programme,
      priority: priority,
      confidence: 1.0,
      trigger: PathwayTrigger.rule,
      rationaleKey: 'test',
    );

void main() {
  // ── Test 1: EPI ────────────────────────────────────────────────────────────────
  test(
    '1 — forProgrammes({Programme.epi}) includes epi-review; '
    'excludes ICCM, ANC, NCD, TB, NUTRITION, PNC sections',
    () {
      final sections = SectionRegistry.forProgrammes({Programme.epi});
      final ids = sections.map((s) => s.sectionId).toSet();

      expect(ids, contains('epi-review'));
      expect(ids, isNot(contains('vitals')));
      expect(ids, isNot(contains('anc-vitals')));
      expect(ids, isNot(contains('ncd-htn')));
      expect(ids, isNot(contains('tb-screen-detail')));
      expect(ids, isNot(contains('nutrition-detail')));
      expect(ids, isNot(contains('pnc-check')));
    },
  );

  // ── Test 2: NUTRITION ──────────────────────────────────────────────────────────
  test(
    '2 — forProgrammes({Programme.nutrition}) includes nutrition-detail; '
    'excludes ICCM, ANC, NCD, TB, EPI, PNC sections',
    () {
      final sections =
          SectionRegistry.forProgrammes({Programme.nutrition});
      final ids = sections.map((s) => s.sectionId).toSet();

      expect(ids, contains('nutrition-detail'));
      expect(ids, isNot(contains('vitals')));
      expect(ids, isNot(contains('anc-vitals')));
      expect(ids, isNot(contains('ncd-htn')));
      expect(ids, isNot(contains('tb-screen-detail')));
      expect(ids, isNot(contains('epi-review')));
      expect(ids, isNot(contains('pnc-check')));
    },
  );

  // ── Test 3: PNC ────────────────────────────────────────────────────────────────
  test(
    '3 — forProgrammes({Programme.pnc}) includes pnc-check; '
    'excludes ICCM, ANC, NCD, TB, EPI, NUTRITION sections',
    () {
      final sections = SectionRegistry.forProgrammes({Programme.pnc});
      final ids = sections.map((s) => s.sectionId).toSet();

      expect(ids, contains('pnc-check'));
      expect(ids, isNot(contains('vitals')));
      expect(ids, isNot(contains('anc-vitals')));
      expect(ids, isNot(contains('ncd-htn')));
      expect(ids, isNot(contains('tb-screen-detail')));
      expect(ids, isNot(contains('epi-review')));
      expect(ids, isNot(contains('nutrition-detail')));
    },
  );

  // ── Test 4: ICCM + NUTRITION priority ordering ─────────────────────────────────
  test(
    '4 — compose([ICCM, NUTRITION]) → nutrition-detail (priority 35) appears '
    'after symptom-detail (30) and before iccm-classify (40)',
    () {
      final form = FormCompositor.compose([
        _pathway(Programme.imci, priority: 5),
        _pathway(Programme.nutrition, priority: 35),
      ]);

      final sectionIds = form.sections.map((s) => s.sectionId).toList();

      // Both ICCM and NUTRITION sections must be present.
      expect(sectionIds, contains('symptom-detail'),
          reason: 'ICCM symptom-detail must be included');
      expect(sectionIds, contains('iccm-classify'),
          reason: 'ICCM iccm-classify must be included');
      expect(sectionIds, contains('nutrition-detail'),
          reason: 'NUTRITION nutrition-detail must be included');

      // Priority ordering: symptom-detail (30) < nutrition-detail (35) < iccm-classify (40).
      final symptomDetailIdx = sectionIds.indexOf('symptom-detail');
      final nutritionDetailIdx = sectionIds.indexOf('nutrition-detail');
      final iccmClassifyIdx = sectionIds.indexOf('iccm-classify');

      expect(symptomDetailIdx, lessThan(nutritionDetailIdx),
          reason: 'symptom-detail (p=30) must precede nutrition-detail (p=35)');
      expect(nutritionDetailIdx, lessThan(iccmClassifyIdx),
          reason: 'nutrition-detail (p=35) must precede iccm-classify (p=40)');
    },
  );

  // ── Test 5: All 7 programmes — no crash, no field duplicates ─────────────────
  test(
    '5 — compose([ICCM, TB, ANC, NCD, EPI, NUTRITION, PNC]) — '
    'no crash, no section duplicates, no field-ownership duplicates',
    () {
      final form = FormCompositor.compose([
        _pathway(Programme.imci, priority: 5),
        _pathway(Programme.tb, priority: 20),
        _pathway(Programme.anc, priority: 5),
        _pathway(Programme.ncd, priority: 40),
        _pathway(Programme.epi, priority: 60),
        _pathway(Programme.nutrition, priority: 35),
        _pathway(Programme.pnc, priority: 46),
      ]);

      final sectionIds = form.sections.map((s) => s.sectionId).toList();

      // Each programme family must be represented.
      expect(sectionIds, contains('vitals'),
          reason: 'ICCM: vitals must be present');
      expect(sectionIds, contains('danger-signs'),
          reason: 'ICCM: danger-signs must be present');
      expect(sectionIds, contains('iccm-classify'),
          reason: 'ICCM: iccm-classify must be present');
      expect(sectionIds, contains('tb-screen-detail'),
          reason: 'TB: tb-screen-detail must be present');
      expect(sectionIds, contains('anc-vitals'),
          reason: 'ANC: anc-vitals must be present');
      expect(sectionIds, contains('anc-specific'),
          reason: 'ANC: anc-specific must be present');
      expect(sectionIds, contains('ncd-htn'),
          reason: 'NCD: ncd-htn must be present');
      expect(sectionIds, contains('ncd-dm'),
          reason: 'NCD: ncd-dm must be present');
      expect(sectionIds, contains('epi-review'),
          reason: 'EPI: epi-review must be present');
      expect(sectionIds, contains('nutrition-detail'),
          reason: 'NUTRITION: nutrition-detail must be present');
      expect(sectionIds, contains('pnc-check'),
          reason: 'PNC: pnc-check must be present');

      // No duplicate section IDs.
      expect(sectionIds.toSet().length, equals(sectionIds.length),
          reason: 'All section IDs must be unique');

      // No duplicate field ownership keys (Map already enforces this, but
      // verify via length equality to catch any compositor bug).
      final ownershipKeys = form.fieldOwnership.keys.toList();
      expect(ownershipKeys.toSet().length, equals(ownershipKeys.length),
          reason: 'All owned field IDs must be unique');

      // Sections sorted ascending by priority.
      final priorities = form.sections.map((s) => s.priority).toList();
      for (var i = 1; i < priorities.length; i++) {
        expect(priorities[i], greaterThanOrEqualTo(priorities[i - 1]),
            reason: 'Sections must be sorted ascending by priority');
      }
    },
  );
}
