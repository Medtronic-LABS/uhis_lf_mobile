/// Unit tests for [FormCompositor] — pure function.
///
/// Test cases:
/// 1. ICCM only  → correct sections, no tb-screen-detail.
/// 2. TB only    → correct sections, no iccm-classify.
/// 3. ICCM + TB  → vitals deduplicated, fieldOwnership['temperature'] = 'vitals'.
/// 4. ICCM + TB  → section ordering matches priority ascending.
/// 5. Synthetic programme (ANC) → compositor includes new section without
///    code changes — proves genericity.
/// 6. projectionFor ICCM → filters to ICCM-relevant fields only.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/composer/form_compositor.dart';
import 'package:uhis_next/features/visit/composer/form_section.dart';
import 'package:uhis_next/features/visit/composer/section_registry.dart';
import 'package:uhis_next/features/visit/pathway/pathway_engine.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

ActivatedPathway _pathway(Programme programme) => ActivatedPathway(
      programme: programme,
      priority: 10,
      confidence: 1.0,
      trigger: PathwayTrigger.rule,
      rationaleKey: 'test',
    );

void main() {
  // ── Test 1: ICCM only ─────────────────────────────────────────────────────
  test(
      'compose([ICCM]) includes vitals, danger-signs, symptom-detail, '
      'iccm-classify; excludes tb-screen-detail', () {
    final form = FormCompositor.compose([_pathway(Programme.imci)]);

    final ids = form.sections.map((s) => s.sectionId).toList();

    expect(ids, contains('vitals'));
    expect(ids, contains('danger-signs'));
    expect(ids, contains('symptom-detail'));
    expect(ids, contains('iccm-classify'));
    expect(ids, isNot(contains('tb-screen-detail')));
  });

  // ── Test 2: TB only ───────────────────────────────────────────────────────
  test(
      'compose([TB]) includes vitals, danger-signs, symptom-detail, '
      'tb-screen-detail; excludes iccm-classify', () {
    final form = FormCompositor.compose([_pathway(Programme.tb)]);

    final ids = form.sections.map((s) => s.sectionId).toList();

    expect(ids, contains('vitals'));
    expect(ids, contains('danger-signs'));
    expect(ids, contains('symptom-detail'));
    expect(ids, contains('tb-screen-detail'));
    expect(ids, isNot(contains('iccm-classify')));
  });

  // ── Test 3: ICCM + TB — deduplication ─────────────────────────────────────
  test(
      'compose([ICCM, TB]) — vitals appears exactly once, '
      "fieldOwnership['temperature'] == 'vitals', tb-screen-detail present", () {
    final form = FormCompositor.compose([
      _pathway(Programme.imci),
      _pathway(Programme.tb),
    ]);

    final ids = form.sections.map((s) => s.sectionId).toList();
    final vitalsOccurrences = ids.where((id) => id == 'vitals').length;

    expect(vitalsOccurrences, equals(1), reason: 'vitals must appear exactly once');
    expect(form.fieldOwnership['temperature'], equals('vitals'));
    expect(ids, contains('tb-screen-detail'));
    expect(ids, contains('iccm-classify'));
  });

  // ── Test 4: ICCM + TB — ordering ─────────────────────────────────────────
  test(
      'compose([ICCM, TB]) — sections ordered by priority ascending: '
      'vitals(10) < danger-signs(20) < symptom-detail(30) < '
      'iccm-classify(40) < tb-screen-detail(50)', () {
    final form = FormCompositor.compose([
      _pathway(Programme.imci),
      _pathway(Programme.tb),
    ]);

    // Verify the expected priority order.
    final priorityMap = {
      for (final s in SectionRegistry.all) s.sectionId: s.priority
    };

    final sectionIds = form.sections.map((s) => s.sectionId).toList();

    // Every consecutive pair must be non-decreasing in priority.
    for (var i = 0; i < sectionIds.length - 1; i++) {
      final a = priorityMap[sectionIds[i]] ?? 0;
      final b = priorityMap[sectionIds[i + 1]] ?? 0;
      expect(a, lessThanOrEqualTo(b),
          reason:
              '${sectionIds[i]}(p=$a) must come before ${sectionIds[i + 1]}(p=$b)');
    }

    // Explicit ordering check for the 5 known sections.
    final knownOrder = [
      'vitals',
      'danger-signs',
      'symptom-detail',
      'iccm-classify',
      'tb-screen-detail',
    ];
    for (final expected in knownOrder) {
      expect(sectionIds, contains(expected));
    }

    // Positional check.
    int indexOf(String id) => sectionIds.indexOf(id);
    expect(indexOf('vitals'), lessThan(indexOf('danger-signs')));
    expect(indexOf('danger-signs'), lessThan(indexOf('symptom-detail')));
    expect(indexOf('symptom-detail'), lessThan(indexOf('iccm-classify')));
    expect(indexOf('iccm-classify'), lessThan(indexOf('tb-screen-detail')));
  });

  // ── Test 5: Synthetic programme — genericity ──────────────────────────────
  test(
      'compose([ICCM, TB, ANC]) with a synthetic ANC section registered — '
      'compositor includes it without any code change (genericity / D8)', () {
    // Register a transient test section for Programme.anc.
    final syntheticSection = FormSection(
      sectionId: 'synthetic-5',
      programmes: const {Programme.anc},
      priority: 60,
      fields: const [
        FieldDef(
          fieldId: 'gestationalWeeks',
          type: FieldType.intField,
          labelKey: 'fieldGestationalWeeks',
        ),
      ],
    );
    SectionRegistry.addTestSection(syntheticSection);

    try {
      final form = FormCompositor.compose([
        _pathway(Programme.imci),
        _pathway(Programme.tb),
        _pathway(Programme.anc),
      ]);

      final sectionIds = form.sections.map((s) => s.sectionId).toList();

      // The synthetic section must be present.
      expect(sectionIds, contains('synthetic-5'),
          reason: 'New section for a new programme must appear automatically');

      // Existing sections must still be present.
      expect(sectionIds, contains('vitals'));
      expect(sectionIds, contains('iccm-classify'));
      expect(sectionIds, contains('tb-screen-detail'));

      // Priority ordering must still hold — synthetic-5 (60) last.
      int indexOf(String id) => sectionIds.indexOf(id);
      expect(indexOf('tb-screen-detail'), lessThan(indexOf('synthetic-5')));
    } finally {
      SectionRegistry.removeTestSection('synthetic-5');
    }
  });

  // ── Test 6: projectionFor ICCM ────────────────────────────────────────────
  test(
      'projectionFor(ICCM, {...}) returns only ICCM-relevant fields, '
      'maps to API field names', () {
    const fieldValues = <String, dynamic>{
      'temperature': 37.5,
      'hasCough': true,
      'hasCoughLastedLonger': true, // TB-only field
      'hasNightSweats': false, // TB-only field
      'hasFever': false,
      'hasDiarrhea': false,
      'unableToBreastfeed': false,
    };

    final projection =
        SectionRegistry.projectionFor(Programme.imci, fieldValues);

    // ICCM sections own: temperature (vitals), hasCough (symptom-detail),
    // hasFever (symptom-detail), hasDiarrhea (symptom-detail),
    // danger-sign fields, iccm-classify fields.
    expect(projection.containsKey('temperature'), isTrue);
    expect(projection.containsKey('hasCough'), isTrue);
    expect(projection.containsKey('hasFever'), isTrue);
    expect(projection.containsKey('hasDiarrhea'), isTrue);
    expect(projection.containsKey('unableToBreastfeed'), isTrue);

    // TB-only fields must be absent.
    expect(projection.containsKey('hasCoughLastedLonger'), isFalse);
    expect(projection.containsKey('hasNightSweats'), isFalse);
  });
}
