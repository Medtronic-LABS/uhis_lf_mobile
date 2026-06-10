/// Golden tests for [CdsRules.evaluate].
///
/// All 16 test cases are deterministic — no clock, no I/O.
/// Each case validates alert IDs, severity, action, and the conflict-
/// precedence rule.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/composer/cds_rules.dart';

void main() {
  group('CdsRules.evaluate — golden cases', () {
    // ── Helper ─────────────────────────────────────────────────────────────────

    List<CdsAlert> eval(
      Map<String, dynamic> fields, [
      Set<Programme> pathways = const {},
    ]) =>
        CdsRules.evaluate(fields, pathways);

    // ── Case 1: Severe HTN ─────────────────────────────────────────────────────
    test('1 — systolic=165, diastolic=100 → bp_severe (urgent, referNow)', () {
      final alerts = eval(
        {'bloodPressureSystolic': 165, 'bloodPressureDiastolic': 100},
        {Programme.anc},
      );

      final bp = alerts.firstWhere((a) => a.alertId == 'bp_severe',
          orElse: () => throw StateError('bp_severe missing'));
      expect(bp.severity, CdsSeverity.urgent);
      expect(bp.action, CdsAction.referNow);
    });

    // ── Case 2: Stage-1 HTN, NCD not active → addPathway ──────────────────────
    test('2 — systolic=145, diastolic=88, NCD inactive → bp_stage1 (warning, addPathway NCD)', () {
      final alerts = eval(
        {'bloodPressureSystolic': 145, 'bloodPressureDiastolic': 88},
        {Programme.anc},
      );

      final bp = alerts.firstWhere((a) => a.alertId == 'bp_stage1',
          orElse: () => throw StateError('bp_stage1 missing'));
      expect(bp.severity, CdsSeverity.warning);
      expect(bp.action, CdsAction.addPathway);
      expect(bp.addPathway, Programme.ncd);
    });

    // ── Case 3: Stage-1 HTN, NCD already active → no addPathway ───────────────
    test('3 — systolic=145, diastolic=88, NCD active → bp_stage1 with continueAssessment', () {
      final alerts = eval(
        {'bloodPressureSystolic': 145, 'bloodPressureDiastolic': 88},
        {Programme.anc, Programme.ncd},
      );

      final bp = alerts.firstWhere((a) => a.alertId == 'bp_stage1',
          orElse: () => throw StateError('bp_stage1 missing'));
      // NCD is already active → action should NOT be addPathway
      expect(bp.action, isNot(CdsAction.addPathway));
      expect(bp.addPathway, isNull);
    });

    // ── Case 4: Danger sign ────────────────────────────────────────────────────
    test('4 — hasConvulsions=true → danger_sign_present (urgent, referNow)', () {
      final alerts = eval(
        {'hasConvulsions': true},
        {Programme.imci},
      );

      final ds = alerts.firstWhere((a) => a.alertId == 'danger_sign_present',
          orElse: () => throw StateError('danger_sign_present missing'));
      expect(ds.severity, CdsSeverity.urgent);
      expect(ds.action, CdsAction.referNow);
    });

    // ── Case 5: Chest indrawing + fast breathing → severe_pneumonia only ───────
    test('5 — hasChestIndrawing=true, hasFastBreathing=true → severe_pneumonia only', () {
      final alerts = eval(
        {'hasChestIndrawing': true, 'hasFastBreathing': true},
        {Programme.imci},
      );

      final ids = alerts.map((a) => a.alertId).toList();
      expect(ids, contains('severe_pneumonia'));
      expect(ids, isNot(contains('pneumonia')),
          reason: 'chest indrawing takes precedence — pneumonia must not fire');
    });

    // ── Case 6: Fast breathing, no indrawing → pneumonia ──────────────────────
    test('6 — hasFastBreathing=true, hasChestIndrawing=false → pneumonia (warning, referNow)', () {
      final alerts = eval(
        {'hasFastBreathing': true, 'hasChestIndrawing': false},
        {Programme.imci},
      );

      final p = alerts.firstWhere((a) => a.alertId == 'pneumonia',
          orElse: () => throw StateError('pneumonia missing'));
      expect(p.severity, CdsSeverity.warning);
      expect(p.action, CdsAction.referNow);
    });

    // ── Case 7: SAM ───────────────────────────────────────────────────────────
    test('7 — muacCm=11.2 → sam (urgent, referNow)', () {
      final alerts = eval({'muacCm': 11.2}, {Programme.imci});

      final sam = alerts.firstWhere((a) => a.alertId == 'sam',
          orElse: () => throw StateError('sam missing'));
      expect(sam.severity, CdsSeverity.urgent);
      expect(sam.action, CdsAction.referNow);
    });

    // ── Case 8: MAM ───────────────────────────────────────────────────────────
    test('8 — muacCm=12.0 → mam (warning, treatAtCommunity)', () {
      final alerts = eval({'muacCm': 12.0}, {Programme.imci});

      final mam = alerts.firstWhere((a) => a.alertId == 'mam',
          orElse: () => throw StateError('mam missing'));
      expect(mam.severity, CdsSeverity.warning);
      expect(mam.action, CdsAction.treatAtCommunity);
    });

    // ── Case 9: Severe anemia ─────────────────────────────────────────────────
    test('9 — hemoglobin=6.5 → severe_anemia (urgent, referNow)', () {
      final alerts = eval({'hemoglobin': 6.5}, {Programme.anc});

      final a = alerts.firstWhere((a) => a.alertId == 'severe_anemia',
          orElse: () => throw StateError('severe_anemia missing'));
      expect(a.severity, CdsSeverity.urgent);
      expect(a.action, CdsAction.referNow);
    });

    // ── Case 10: Mild anemia ──────────────────────────────────────────────────
    test('10 — hemoglobin=9.0 → anemia (warning, treatAtCommunity)', () {
      final alerts = eval({'hemoglobin': 9.0}, {Programme.anc});

      final a = alerts.firstWhere((a) => a.alertId == 'anemia',
          orElse: () => throw StateError('anemia missing'));
      expect(a.severity, CdsSeverity.warning);
      expect(a.action, CdsAction.treatAtCommunity);
    });

    // ── Case 11: High glucose, NCD active → no addPathway ────────────────────
    test('11 — glucoseValue=210, random, NCD active → glucose_high with no addPathway', () {
      final alerts = eval(
        {'glucoseValue': 210.0, 'glucoseType': 'random'},
        {Programme.ncd},
      );

      final g = alerts.firstWhere((a) => a.alertId == 'glucose_high',
          orElse: () => throw StateError('glucose_high missing'));
      expect(g.action, isNot(CdsAction.addPathway));
      expect(g.addPathway, isNull);
    });

    // ── Case 12: High glucose, NCD inactive → addPathway NCD_DM ──────────────
    test('12 — glucoseValue=210, random, no pathways → glucose_high with addPathway NCD', () {
      final alerts = eval(
        {'glucoseValue': 210.0, 'glucoseType': 'random'},
      );

      final g = alerts.firstWhere((a) => a.alertId == 'glucose_high',
          orElse: () => throw StateError('glucose_high missing'));
      expect(g.action, CdsAction.addPathway);
      expect(g.addPathway, Programme.ncd);
    });

    // ── Case 13: Long cough, TB inactive → tb_screen_add ─────────────────────
    test('13 — coughDays=15, no pathways → tb_screen_add (info, addPathway TB)', () {
      final alerts = eval({'coughDays': 15});

      final t = alerts.firstWhere((a) => a.alertId == 'tb_screen_add',
          orElse: () => throw StateError('tb_screen_add missing'));
      expect(t.severity, CdsSeverity.info);
      expect(t.action, CdsAction.addPathway);
      expect(t.addPathway, Programme.tb);
    });

    // ── Case 14: Long cough, TB already active → no tb_screen_add ─────────────
    test('14 — coughDays=15, TB already active → no tb_screen_add', () {
      final alerts = eval({'coughDays': 15}, {Programme.tb});

      expect(
        alerts.any((a) => a.alertId == 'tb_screen_add'),
        isFalse,
        reason: 'TB already active — tb_screen_add must not fire',
      );
    });

    // ── Case 15: Conflict — SAM + pneumonia → treatAtCommunity suppressed ─────
    test(
        '15 — muacCm=11.2, hasFastBreathing=true, hasChestIndrawing=false → '
        'sam(urgent,referNow) + pneumonia(warning,referNow); no treatAtCommunity', () {
      final alerts = eval(
        {
          'muacCm': 11.2,
          'hasFastBreathing': true,
          'hasChestIndrawing': false,
        },
        {Programme.imci},
      );

      final ids = alerts.map((a) => a.alertId).toList();
      expect(ids, contains('sam'));
      expect(ids, contains('pneumonia'));

      // No treatAtCommunity alert must survive the conflict rule.
      expect(
        alerts.any((a) => a.action == CdsAction.treatAtCommunity),
        isFalse,
        reason: 'Conflict rule: treatAtCommunity must be suppressed when referNow present',
      );
    });

    // ── Case 16: Conflict — SAM(urgent) + MAM suppressed ─────────────────────
    // muacCm=12.0 → mam (treatAtCommunity); hemoglobin=6.5 → severe_anemia (referNow).
    // Conflict rule: mam must be suppressed; first referNow gets conflict rationale.
    test(
        '16 — muacCm=12.0, hemoglobin=6.5 → severe_anemia(urgent,referNow) + '
        'mam SUPPRESSED; first referNow annotated with conflict rationale', () {
      final alerts = eval(
        {'muacCm': 12.0, 'hemoglobin': 6.5},
        {Programme.imci, Programme.anc},
      );

      // severe_anemia must be present.
      expect(alerts.any((a) => a.alertId == 'severe_anemia'), isTrue);

      // mam must be gone.
      expect(
        alerts.any((a) => a.alertId == 'mam'),
        isFalse,
        reason: 'Conflict rule: mam (treatAtCommunity) must be suppressed',
      );

      // No treatAtCommunity alert must survive.
      expect(
        alerts.any((a) => a.action == CdsAction.treatAtCommunity),
        isFalse,
      );

      // The first referNow alert must carry the conflict rationale key.
      final firstRefer =
          alerts.firstWhere((a) => a.action == CdsAction.referNow);
      expect(
        firstRefer.rationaleKey,
        equals(CdsStrings.conflictReferralOverridesKey),
        reason: 'First referNow alert must carry the conflict override rationale',
      );
    });

    // ── Ordering invariant ────────────────────────────────────────────────────
    test('Alerts are ordered urgent → warning → info', () {
      final alerts = eval(
        {
          'coughDays': 15,               // info
          'hemoglobin': 9.0,             // warning
          'bloodPressureSystolic': 165,  // urgent
        },
        {},
      );

      expect(alerts, isNotEmpty);
      int prevRank = -1;
      for (final a in alerts) {
        final rank = switch (a.severity) {
          CdsSeverity.urgent => 0,
          CdsSeverity.warning => 1,
          CdsSeverity.info => 2,
        };
        expect(rank, greaterThanOrEqualTo(prevRank),
            reason: '${a.alertId} out of order');
        prevRank = rank;
      }
    });
  });
}
