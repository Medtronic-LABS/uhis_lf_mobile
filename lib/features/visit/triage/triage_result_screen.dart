/// Step 2 of the 3-step visit flow: AI triage result screen.
///
/// Shows:
///   - The highest-urgency alert derived from activated pathways.
///   - 3 measurement instruction cards tailored to the primary programme.
///   - "Programme identified" banner.
///   - CTA → Step 3 (SectionedAssessmentScreen via VisitFormScreen).
///
/// Engineering Design Standards:
///   - Widget only — no I/O, no business logic.
///   - All strings from [TriageResultStrings].
///   - PatientContext is read-only; no mutations.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';
import '../pathway/pathway_engine.dart';
import 'visit_step_header.dart';

class TriageResultScreen extends StatelessWidget {
  const TriageResultScreen({
    super.key,
    required this.encounterId,
    required this.patientId,
    required this.patientLabel,
    required this.pathways,
    this.memberId,
    this.householdId,
    this.patientAge,
  });

  final String encounterId;
  final String patientId;
  final String patientLabel;
  final List<ActivatedPathway> pathways;
  final String? memberId;
  final String? householdId;
  final int? patientAge;

  // ── Derived urgency ──────────────────────────────────────────────────────────

  /// Primary pathway — the highest priority (lowest priority number).
  ActivatedPathway? get _primaryPathway =>
      pathways.isEmpty ? null : pathways.reduce(
        (a, b) => a.priority <= b.priority ? a : b,
      );

  bool get _isUrgent {
    final p = _primaryPathway;
    if (p == null) return false;
    return p.programme == Programme.imci &&
        (p.triggerSymptoms.contains('chest_indrawing') ||
         p.triggerSymptoms.contains('convulsions') ||
         p.triggerSymptoms.contains('stridor') ||
         p.triggerSymptoms.contains('unconscious'));
  }

  String get _urgencyTitle {
    if (pathways.isEmpty) return TriageResultStrings.infoTitle;
    if (_isUrgent) return TriageResultStrings.urgentTitle;
    return TriageResultStrings.warningTitle;
  }

  Color get _urgencyColor {
    if (pathways.isEmpty) return const Color(0xFF1E40AF);
    if (_isUrgent) return const Color(0xFFDC2626); // red-600
    return const Color(0xFFD97706); // amber-600
  }

  Color get _urgencyBgColor {
    if (pathways.isEmpty) return const Color(0xFFEFF6FF);
    if (_isUrgent) return const Color(0xFFFEF2F2);
    return const Color(0xFFFFFBEB);
  }

  String get _urgencySummary {
    final p = _primaryPathway;
    if (p == null) return 'No symptoms selected — starting routine visit.';
    final symptoms = p.triggerSymptoms.take(3).join(', ').replaceAll('_', ' ');
    return 'Symptoms reported: $symptoms. Check the items below now.';
  }

  // ── Measurement cards by programme ──────────────────────────────────────────

  List<_MeasureItem> _measureItems() {
    final p = _primaryPathway;
    if (p == null) return [];
    switch (p.programme) {
      case Programme.imci:
        return [
          const _MeasureItem('🌡️', TriageResultStrings.measureTempLabel, TriageResultStrings.measureTempHint),
          const _MeasureItem('🫁', TriageResultStrings.measureBreathLabel, TriageResultStrings.measureBreathHint),
          const _MeasureItem('👁️', TriageResultStrings.measureChestLabel, TriageResultStrings.measureChestHint),
        ];
      case Programme.ncd:
        return [
          const _MeasureItem('💊', TriageResultStrings.measureBpLabel, TriageResultStrings.measureBpHint),
          const _MeasureItem('⚖️', TriageResultStrings.measureWeightLabel, TriageResultStrings.measureWeightHint),
        ];
      case Programme.anc:
      case Programme.pnc:
        return [
          const _MeasureItem('💊', TriageResultStrings.measureBpLabel, TriageResultStrings.measureBpHint),
          const _MeasureItem('⚖️', TriageResultStrings.measureWeightLabel, TriageResultStrings.measureWeightHint),
          const _MeasureItem('📏', TriageResultStrings.measureFundalLabel, TriageResultStrings.measureFundalHint),
        ];
      case Programme.tb:
        return [
          const _MeasureItem('🌡️', TriageResultStrings.measureTempLabel, TriageResultStrings.measureTempHint),
          const _MeasureItem('🫁', TriageResultStrings.measureBreathLabel, TriageResultStrings.measureBreathHint),
        ];
      case Programme.familyPlanning:
        return [
          const _MeasureItem('⚖️', TriageResultStrings.measureWeightLabel, TriageResultStrings.measureWeightHint),
          const _MeasureItem('💊', TriageResultStrings.measureBpLabel, TriageResultStrings.measureBpHint),
        ];
      case Programme.cataract:
      case Programme.eyeCare:
        return [
          const _MeasureItem('👁️', 'Visual acuity', 'Test each eye separately'),
          const _MeasureItem('💊', TriageResultStrings.measureBpLabel, TriageResultStrings.measureBpHint),
        ];
      default:
        return [
          const _MeasureItem('💊', TriageResultStrings.measureBpLabel, TriageResultStrings.measureBpHint),
          const _MeasureItem('⚖️', TriageResultStrings.measureWeightLabel, TriageResultStrings.measureWeightHint),
        ];
    }
  }

  String _programmeName(Programme p) {
    switch (p) {
      case Programme.imci: return PathwayStrings.programmeImci;
      case Programme.anc: return PathwayStrings.programmeAnc;
      case Programme.pnc: return PathwayStrings.programmePnc;
      case Programme.ncd: return PathwayStrings.programmeNcd;
      case Programme.tb: return PathwayStrings.programmeTb;
      case Programme.epi: return PathwayStrings.programmeEpi;
      case Programme.nutrition: return PathwayStrings.programmeNutrition;
      case Programme.familyPlanning: return PathwayStrings.programmeFamilyPlanning;
      case Programme.cataract: return PathwayStrings.programmeCataract;
      case Programme.eyeCare: return PathwayStrings.programmeEyeCare;
      default: return PathwayStrings.programmeUnknown;
    }
  }

  void _proceed(BuildContext context) {
    debugPrint('[TriageResult] Proceeding to form — ${pathways.length} pathways: ${pathways.map((p) => p.programme.name).join(', ')}');
    context.go(
      '/patients/visit/$encounterId/form',
      extra: {
        'patientId': patientId,
        'memberId': memberId,
        'householdId': householdId,
        'patientAge': patientAge,
        'activatedPathways': pathways.map((p) => p.programme.name).toList(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final measures = _measureItems();
    final primary = _primaryPathway;
    final programmes = pathways.map((p) => p.programme).toSet();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F8),
      appBar: VisitStepHeader(
        step: VisitStep.triageResult,
        patientLabel: patientLabel,
        onBack: () => context.pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Urgency card ────────────────────────────────────────────────────
          _UrgencyCard(
            color: _urgencyColor,
            bgColor: _urgencyBgColor,
            title: _urgencyTitle,
            summary: _urgencySummary,
            isUrgent: _isUrgent,
          ),
          const SizedBox(height: 12),

          // ── Measurements section ────────────────────────────────────────────
          if (measures.isNotEmpty) ...[
            const Text(
              TriageResultStrings.measureSectionLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            ...measures.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MeasureCard(item: m),
            )),
            const SizedBox(height: 6),
          ],

          // ── Programme identified banner ────────────────────────────────────
          if (primary != null) ...[
            _ProgrammeBanner(
              programmes: programmes,
              nameOf: _programmeName,
            ),
            const SizedBox(height: 14),
          ],

          // ── CTA ─────────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _proceed(context),
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                primary != null
                    ? TriageResultStrings.ctaOpenChecklist
                    : TriageResultStrings.ctaNoPathways,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE8356D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _UrgencyCard extends StatelessWidget {
  const _UrgencyCard({
    required this.color,
    required this.bgColor,
    required this.title,
    required this.summary,
    required this.isUrgent,
  });
  final Color color, bgColor;
  final String title, summary;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isUrgent ? Icons.warning_amber_rounded : Icons.info_outline,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(summary,
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          height: 1.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasureItem {
  const _MeasureItem(this.emoji, this.label, this.hint);
  final String emoji, label, hint;
}

class _MeasureCard extends StatelessWidget {
  const _MeasureCard({required this.item});
  final _MeasureItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(item.emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.hint,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgrammeBanner extends StatelessWidget {
  const _ProgrammeBanner({
    required this.programmes,
    required this.nameOf,
  });
  final Set<Programme> programmes;
  final String Function(Programme) nameOf;

  @override
  Widget build(BuildContext context) {
    final names = programmes.map(nameOf).join(' + ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF0FF), Color(0xFFE8EAFF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4D8FF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF6B63D4), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${TriageResultStrings.programmeBannerPrefix}$names${TriageResultStrings.programmeBannerSuffix}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3D3599)),
                ),
                const SizedBox(height: 2),
                const Text(
                  TriageResultStrings.programmeBannerCta,
                  style: TextStyle(
                      fontSize: 11, color: Color(0xFF6B63D4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
