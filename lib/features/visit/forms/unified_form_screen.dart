import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/form_fields/radio_form_field.dart';
import 'canonical_visit_data.dart';
import 'form_config.dart';
import 'form_field_visuals.dart';
import '../../scribe/widgets/ai_scribe_banner.dart';
import 'triage_symptom_mapper.dart';
import 'unified_form_notifier.dart';
import 'unified_section_rules.dart';
import 'vitals_trend.dart';

/// JSON-driven assessment form.
///
/// Reads [FormConfig] from assets, applies [UnifiedSectionRules] to produce
/// an ordered, deduplicated section list, and renders each field using the
/// appropriate existing field widget. Delegates state to [UnifiedFormNotifier].
///
/// ## Section ordering
///
/// 1. **Vitals** — BP, weight, and other physical measurements, always first.
/// 2. **Enrolled programmes** — sections from [enrolledFormTypes] come next.
/// 3. **Recommended programmes** — new pathway-activated sections follow.
///
/// Triage symptoms selected in Step 1 are surfaced inline under each programme
/// divider (see [_ProgrammeDivider]) rather than in a single top banner, so the
/// SK sees only the symptoms relevant to the programme being assessed.
///
/// The caller wraps this widget in a [ChangeNotifierProvider<UnifiedFormNotifier>]
/// and supplies [onSubmitComplete] to handle post-submit navigation.
class UnifiedFormScreen extends StatefulWidget {
  const UnifiedFormScreen({
    super.key,
    required this.activeFormTypes,
    required this.onSubmitComplete,
    this.gestationalWeeks,
    this.enrolledFormTypes = const [],
    this.confirmedSymptoms = const [],
    this.aiPickedSymptoms = const {},
  });

  /// Ordered formType keys (e.g. `['anc', 'ncd']`) from activated pathways.
  final List<String> activeFormTypes;

  /// Called after [UnifiedFormNotifier.submit] succeeds. Navigation lives here.
  final VoidCallback onSubmitComplete;

  /// Passed to [UnifiedSectionRules] for conditional `birthPreparedness` visibility.
  final int? gestationalWeeks;

  /// FormType keys of programmes the patient is already enrolled in.
  /// These sections render after the Vitals group and before recommended ones.
  final List<String> enrolledFormTypes;

  /// Symptom codes selected in Step 1 (triage).  Displayed read-only at the
  /// top of the form and seeded into [CanonicalVisitData] so section rules can
  /// drive conditional visibility.
  final List<String> confirmedSymptoms;

  /// Subset of [confirmedSymptoms] pre-selected by the AI Scribe.
  /// Used to colour AI-sourced chips purple in the programme divider strips.
  final Set<String> aiPickedSymptoms;

  @override
  State<UnifiedFormScreen> createState() => _UnifiedFormScreenState();
}

class _UnifiedFormScreenState extends State<UnifiedFormScreen> {
  FormConfig? _config;
  bool _configLoading = true;
  Object? _configError;
  final ScrollController _scrollCtrl = ScrollController();

  // Used to suppress duplicate [Form] debug logs — only log when the section
  // count or field count actually changes between rebuilds.
  int _lastLoggedSectionCount = -1;
  int _lastLoggedFieldCount = -1;

  /// Prior ANC visit snapshots for the vitals-trend card (oldest-first).
  /// Loaded once after init; empty until then / for non-ANC visits.
  List<VisitVitals> _priorAncVisits = const [];

  /// Weight (kg) from the patient's most-recent prior visit across ALL
  /// programme types — used for the weight-delta badge.  `null` until loaded.
  double? _lastRecordedWeight;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<UnifiedFormNotifier>();

      if (widget.confirmedSymptoms.isNotEmpty) {
        // Store raw codes so section-rules can drive conditional visibility.
        notifier.updateField('_triageSymptoms', widget.confirmedSymptoms);

        // Pre-fill symptom fields derived from triage selections.
        // Done BEFORE loadDraft so that a saved draft can override these
        // suggestions (draft values win over triage-derived defaults).
        for (final ft in widget.activeFormTypes) {
          final prefills = TriageSymptomMapper.prefillsFor(
            ft,
            widget.confirmedSymptoms,
          );
          for (final entry in prefills.entries) {
            notifier.updateField(entry.key, entry.value);
          }
        }
      }

      notifier.loadDraft();

      // Load the patient's most-recent weight from ANY prior visit so the
      // weight-delta badge shows "Last: X kg" regardless of programme type.
      notifier.lastRecordedWeight().then((w) {
        if (mounted && w != null) setState(() => _lastRecordedWeight = w);
      });

      // Load prior ANC visits for the vitals-trend card (ANC visits only).
      if (widget.activeFormTypes.contains('anc') ||
          widget.enrolledFormTypes.contains('anc')) {
        notifier.ancVitalsHistory().then((history) {
          if (mounted && history.isNotEmpty) {
            setState(() => _priorAncVisits = history);
          }
        });
        // Load LMP/EDD from patient raw JSON for the gestational-age card.
        notifier.loadPregnancyData();
      }
    });
  }

  /// Builds a snapshot of the current visit's live vitals from the form data,
  /// for the last ("Today") column of the trend card.

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await FormConfig.load(rootBundle);
      if (mounted) setState(() { _config = cfg; _configLoading = false; });
    } catch (e, st) {
      debugPrint('[UnifiedForm] FormConfig.load failed: $e\n$st');
      if (mounted) setState(() { _configError = e; _configLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_configLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_configError != null || _config == null) {
      return Center(
        child: Text(
          UnifiedFormStrings.configLoadError,
          style: AppTextStyles.body,
        ),
      );
    }

    return Consumer<UnifiedFormNotifier>(
      builder: (ctx, notifier, _) {
        final annotated = UnifiedSectionRules.activeSections(
          config: _config!,
          activeFormTypes: widget.activeFormTypes,
          currentData: notifier.data,
          gestationalWeeks: widget.gestationalWeeks,
          enrolledFormTypes: widget.enrolledFormTypes,
        );

        // Only emit the [Form] debug summary when the section/field count
        // changes — suppresses per-keystroke log spam during form filling.
        final totalFields = annotated.fold<int>(
          0, (sum, a) => sum + a.section.fieldRefs.length);
        if (annotated.length != _lastLoggedSectionCount ||
            totalFields != _lastLoggedFieldCount) {
          final isFirstLoad = _lastLoggedSectionCount == -1;
          _lastLoggedSectionCount = annotated.length;
          _lastLoggedFieldCount = totalFields;
          if (isFirstLoad) {
            // Collect all field IDs across sections to report merged groups.
            final allIds = <String>{};
            for (final a in annotated) {
              for (final r in a.section.fieldRefs) {
                allIds.add(r.id);
              }
            }
            final merged = UnifiedSectionRules.mergedGroupDescriptions(allIds);
            // ignore: avoid_print
            print('[Form] ── section order (${widget.activeFormTypes.join('+')} · '
                '${annotated.length} sections · $totalFields fields) ──────────');
            if (merged.isNotEmpty) {
              // ignore: avoid_print
              print('[Form]   merged (captured once): ${merged.join(', ')}');
            }
            for (var i = 0; i < annotated.length; i++) {
              final a = annotated[i];
              final fieldIds = a.section.fieldRefs.map((r) => r.id).join(' · ');
              // ignore: avoid_print
              print('[Form]   ${i + 1}. [${a.section.sectionId}] '
                  '${a.section.title} → $fieldIds');
            }
            // ignore: avoid_print
            print('[Form] ────────────────────────────────────────────────────');
          }
          UnifiedSectionRules.debugLogSections(annotated, totalFields);
        }

        // Build the list items: programme-name dividers (with inline per-
        // programme symptom chips) + section cards.
        // ANC-specific cards are pinned to fixed positions:
        //   • Gestational age card → first item (below the AI Scribe banner)
        //   • Vitals trend card    → last item before submit
        final items = <Widget>[];
        final isAnc = widget.activeFormTypes.contains('anc');

        // ── Gestational age card (ANC) — top of scroll area ────────────────
        if (isAnc) {
          items.add(_GestationalAgeCard(
            lmpDate: notifier.lmpDate,
            eddDate: notifier.eddDate,
            gestationalWeeks: notifier.gestationalWeeks,
          ));
        }

        String? lastFormType;
        for (final annotatedSection in annotated) {
          final ft = annotatedSection.section.formType;
          if (ft != lastFormType) {
            lastFormType = ft;
            if (annotatedSection.group != SectionGroup.vitals) {
              final label = UnifiedFormStrings.programmeBadgeLabel(ft) ??
                  ft.toUpperCase();
              items.add(_ProgrammeDivider(
                label: label,
                relevantSymptomCodes: TriageSymptomMapper.relevantCodes(
                    ft, widget.confirmedSymptoms),
                aiPickedSymptomCodes: widget.aiPickedSymptoms,
              ));
            }
          }
          items.add(_SectionCard(
            section: annotatedSection.section,
            config: _config!,
            data: notifier.data,
            validationErrors: notifier.validationErrors,
            onFieldChanged: notifier.updateField,
            previousWeight: _lastRecordedWeight,
            gestationalWeeks: widget.gestationalWeeks,
          ));
        }

        // ── Vitals trend card (ANC) — bottom of scroll area ────────────────
        if (isAnc && _priorAncVisits.isNotEmpty) {
          items.add(_VitalsTrendCard(priorVisits: _priorAncVisits));
        }

        // Submit button lives inside the scroll view so it appears after the
        // last form field — not pinned to the screen bottom.
        items.add(_SubmitBar(
          submitting: notifier.submitting,
          onSubmit: () => _onSubmit(ctx, notifier, annotated),
        ));

        return Column(
          children: [
            // ── Step 2 AI Scribe banner — same widget as Step 1 ────────────
            // Horizontally inset to match the ListView's content alignment.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxxl, AppSpacing.xl, AppSpacing.xxxl, 0),
              child: AiScribeBanner(
                encounterId: notifier.encounterId,
                patientId: notifier.patientId,
                isFemale: widget.activeFormTypes.contains('anc') ||
                    widget.activeFormTypes.contains('pnc'),
                // VisitFormScreen watches ScribeController state and auto-opens
                // the SOAP review sheet when reviewReady — no action needed here.
                onReviewReady: (_) {},
              ),
            ),
            // ── Assessment form sections + submit button ────────────────────
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxxl, AppSpacing.md, AppSpacing.xxxl, AppSpacing.xxxl),
                children: items,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onSubmit(
    BuildContext ctx,
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) async {
    if (_config == null) return;

    // Validate mandatory fields before submitting.
    final errors = _computeValidationErrors(notifier, annotated);
    if (errors.isNotEmpty) {
      notifier.setValidationErrors(errors);
      // Scroll to top so the SK sees the highlighted fields.
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            UnifiedFormStrings.validationFieldsRequired(errors.length),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
      return;
    }

    // Clear any previous errors before submitting.
    notifier.setValidationErrors(const {});

    try {
      await notifier.submit();
      widget.onSubmitComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(VisitFormStrings.saveFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  /// Returns the set of mandatory field IDs that have no value in [notifier].
  Set<String> _computeValidationErrors(
    UnifiedFormNotifier notifier,
    List<AnnotatedFormSection> annotated,
  ) {
    final errors = <String>{};
    for (final a in annotated) {
      for (final ref in a.section.fieldRefs) {
        final def = _config!.fields[ref.id];
        if (def == null) continue;
        final mandatory = def.isMandatory || ref.isMandatory;
        if (!mandatory) continue;
        final v = notifier.data.getValue(ref.id);
        final empty = v == null ||
            (v is String && v.trim().isEmpty) ||
            (v is List && v.isEmpty);
        if (empty) errors.add(ref.id);
      }
    }
    return errors;
  }
}

// ── Programme divider ─────────────────────────────────────────────────────────

/// Labelled horizontal divider shown when the formType changes in the section
/// list.  The label is the programme name ("ANC", "NCD", "PNC", …) or
/// "Vitals" for the shared vitals group.
///
/// When [relevantSymptomCodes] is non-empty a collapsible chip row is shown
/// below the divider line, listing the triage symptoms that were reported and
/// are relevant to this programme.  Collapsed to the first 3 chips by default;
/// tap "N more" to reveal the rest.
class _ProgrammeDivider extends StatefulWidget {
  const _ProgrammeDivider({
    required this.label,
    this.relevantSymptomCodes = const [],
    this.aiPickedSymptomCodes = const {},
  });

  final String label;
  final List<String> relevantSymptomCodes;
  /// Codes from Step 1 that were pre-selected by the AI Scribe.
  /// Chips for these codes render with the purple AI palette.
  final Set<String> aiPickedSymptomCodes;

  @override
  State<_ProgrammeDivider> createState() => _ProgrammeDividerState();
}

class _ProgrammeDividerState extends State<_ProgrammeDivider> {
  /// Controls whether the symptom chip list is visible.
  bool _symptomsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codes = widget.relevantSymptomCodes;
    final hasChips = codes.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppSpacing.sm,
        top: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Divider row — label left-aligned, AI badge on right ────────
          Row(
            children: [
              Text(
                widget.label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Divider(color: AppColors.border, height: 1)),
            ],
          ),
          // ── Collapsible symptom strip ─────────────────────────────────
          if (hasChips) ...[
            const SizedBox(height: 6),
            // Tappable toggle row
            GestureDetector(
              onTap: () =>
                  setState(() => _symptomsExpanded = !_symptomsExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 11,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    UnifiedFormStrings.triageSymptomsCount(codes.length),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _symptomsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Chip list — revealed when expanded
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: codes
                      .map(
                        (c) => _TriageChip(
                          code: c,
                          isAi: widget.aiPickedSymptomCodes.contains(c),
                        ),
                      )
                      .toList(),
                ),
              ),
              crossFadeState: _symptomsExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// A single read-only triage symptom pill used inside programme dividers and
/// the collapsible banner.
///
/// When [isAi] is true the chip uses the purple AI palette (matching Step 1's
/// AI-ticked chip style) to signal that this symptom was pre-selected by the
/// AI Scribe.  Otherwise the amber warning palette is used for manually-selected
/// symptoms.
/// Read-only symptom chip shown in the Step 2 "Symptoms from Step 1" accordion.
///
/// Visually identical to [_PickerChip] in its **selected-AI** state so the SK
/// immediately recognises the same chips they confirmed in Step 1.
class _TriageChip extends StatelessWidget {
  const _TriageChip({required this.code, this.isAi = false});

  final String code;
  final bool isAi;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color borderColor;
    final Color textColor;
    if (isAi) {
      // Mirror _PickerChip's selected-AI colours exactly.
      bg = AppColors.aiSurfaceStart;
      borderColor = AppColors.aiBorder;
      textColor = AppColors.aiPurple;
    } else {
      bg = AppColors.statusWarningSurface;
      borderColor = AppColors.statusWarning.withValues(alpha: 0.30);
      textColor = AppColors.statusWarningText;
    }

    return Container(
      // Same padding as _PickerChip selected state.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isAi ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sparkle icon — same size (13) and spacing (4) as _PickerChip.
          Icon(
            isAi ? Icons.auto_awesome : Icons.circle,
            size: 13,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            TriageStrings.symptomLabel(code),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vitals-trend card ─────────────────────────────────────────────────────────

/// Collapsible amber accordion showing systolic / diastolic / weight / urine
/// protein across the last few ANC visits, with a 📈 marker on rising metrics.
///
/// Computes [VitalsTrendResult] internally on every build by watching
/// [UnifiedFormNotifier] directly — this guarantees the "Today" column
/// updates on every field keystroke without depending on a prop-chain through
/// the parent Consumer.  [priorVisits] is stable (loaded once in initState).
class _VitalsTrendCard extends StatefulWidget {
  const _VitalsTrendCard({required this.priorVisits});

  final List<VisitVitals> priorVisits;

  @override
  State<_VitalsTrendCard> createState() => _VitalsTrendCardState();
}

class _VitalsTrendCardState extends State<_VitalsTrendCard> {
  bool _expanded = true;

  static const _rising = '📈';
  static const _flat = '·';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watch notifier directly — rebuilds on every updateField() call so
    // "Today" column reflects the latest typed value in real-time.
    final notifier = context.watch<UnifiedFormNotifier>();
    final data = notifier.data;
    final today = VisitVitals(
      systolic: () {
        final v = data.getValue('systolic');
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      }(),
      diastolic: () {
        final v = data.getValue('diastolic');
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v);
        return null;
      }(),
      weight: () {
        final v = data.getValue('weight');
        if (v is double) return v;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }(),
      urineProtein: () {
        final v = data.getValue('urinaryAlbumin');
        if (v == null) return null;
        return v is String ? v : v.toString();
      }(),
    );
    final result = VitalsTrendAnalyzer.analyze(
      priorVisits: widget.priorVisits,
      today: today,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.catChildSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.statusWarningBorder, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Accordion header — always visible, tappable ─────────────────
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 17,
                      color: AppColors.fieldKindAmber,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        UnifiedFormStrings.trendCardTitle(result.columns.length),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.statusWarningText,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.fieldKindAmber,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Accordion body — collapsed by default ───────────────────────
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 1,
                      color: AppColors.statusWarningBorder,
                      margin: const EdgeInsets.only(bottom: 10),
                    ),
                    _buildTable(theme, result),
                    const SizedBox(height: 9),
                    Text(
                      result.show
                          ? UnifiedFormStrings.trendFooter
                          : UnifiedFormStrings.trendFooterStable,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.statusWarningText,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(ThemeData theme, VitalsTrendResult result) {
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.statusWarningText,
      fontWeight: FontWeight.w700,
      fontSize: 11,
    );
    final subStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.statusWarningText,
      fontWeight: FontWeight.w500,
      fontSize: 9.5,
    );

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: AppColors.statusWarningBorder.withValues(alpha: 0.7),
        ),
      ),
      columnWidths: const {0: FlexColumnWidth(2.2)},
      children: [
        // Header row
        TableRow(
          children: [
            const SizedBox.shrink(),
            for (final col in result.columns)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      col.isToday
                          ? UnifiedFormStrings.trendTodayColumn
                          : UnifiedFormStrings.trendVisitColumn(
                              col.visitNumber ?? 0),
                      textAlign: TextAlign.center,
                      style: headerStyle,
                    ),
                    if (!col.isToday && col.daysAgo != null)
                      Text(
                        UnifiedFormStrings.trendWeeksAgo(col.daysAgo!),
                        textAlign: TextAlign.center,
                        style: subStyle,
                      ),
                  ],
                ),
              ),
            Center(child: Text('↗', style: headerStyle)),
          ],
        ),
        // Metric rows
        for (final metric in result.metrics) _metricRow(theme, metric),
      ],
    );
  }

  TableRow _metricRow(ThemeData theme, VitalMetricTrend metric) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.statusWarningText,
      fontWeight: FontWeight.w600,
      fontSize: 11,
    );
    final priorStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.textMuted,
      fontSize: 11,
    );
    final todayStyle = theme.textTheme.labelSmall?.copyWith(
      color: AppColors.fieldKindAmber,
      fontWeight: FontWeight.w800,
      fontSize: 11.5,
    );

    final lastIndex = metric.values.length - 1;
    // For the weight row, deltas are computed from the earliest recorded reading.
    final weightBaseline = metric.metric == VitalMetric.weight
        ? metric.values.whereType<num>().firstOrNull
        : null;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(_metricLabel(metric.metric), style: labelStyle),
        ),
        for (var i = 0; i < metric.values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              _formatValue(metric.metric, metric.values[i],
                  weightBaseline: weightBaseline),
              textAlign: TextAlign.center,
              style: i == lastIndex ? todayStyle : priorStyle,
            ),
          ),
        Center(
          child: Text(
            metric.rising ? _rising : _flat,
            style: TextStyle(fontSize: metric.rising ? 12 : 13,
                color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  String _metricLabel(VitalMetric metric) {
    switch (metric) {
      case VitalMetric.systolic:
        return UnifiedFormStrings.trendSystolic;
      case VitalMetric.diastolic:
        return UnifiedFormStrings.trendDiastolic;
      case VitalMetric.weight:
        return UnifiedFormStrings.trendWeightGain;
      case VitalMetric.urineProtein:
        return UnifiedFormStrings.trendUrineProtein;
    }
  }

  String _formatValue(VitalMetric metric, num? value, {num? weightBaseline}) {
    if (value == null) return UnifiedFormStrings.trendMissingValue;
    switch (metric) {
      case VitalMetric.systolic:
      case VitalMetric.diastolic:
        return value.toInt().toString();
      case VitalMetric.weight:
        if (weightBaseline == null) return value.toStringAsFixed(1);
        final delta = value.toDouble() - weightBaseline.toDouble();
        return delta >= 0
            ? '+${delta.toStringAsFixed(1)}'
            : delta.toStringAsFixed(1);
      case VitalMetric.urineProtein:
        switch (value.toInt()) {
          case 0:
            return UnifiedFormStrings.trendUrineAbsent;
          case 1:
            return UnifiedFormStrings.trendUrineTrace;
          case 2:
            return UnifiedFormStrings.trendUrinePresent;
          default:
            return UnifiedFormStrings.trendMissingValue;
        }
    }
  }
}

// ── Gestational age card ──────────────────────────────────────────────────────

/// Navy-gradient card shown at the top of the ANC section displaying the
/// patient's gestational age, LMP, and EDD loaded from patient rawJson.
class _GestationalAgeCard extends StatelessWidget {
  const _GestationalAgeCard({
    required this.lmpDate,
    required this.eddDate,
    required this.gestationalWeeks,
  });

  final DateTime? lmpDate;
  final DateTime? eddDate;
  final int? gestationalWeeks;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmt(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _pinkAccent = Color(0xFF9D174D);
  static const _navy = Color(0xFF1B2B5E);
  static const _unitGrey = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final lmpStr = lmpDate != null ? _fmt(lmpDate!) : null;
    final eddStr = eddDate != null ? _fmt(eddDate!) : null;

    int? weeks;
    int? days;
    if (lmpDate != null) {
      final total = DateTime.now().difference(lmpDate!).inDays;
      weeks = total ~/ 7;
      days = total % 7;
    } else if (gestationalWeeks != null) {
      weeks = gestationalWeeks;
      days = 0;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDF2F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF9A8D4)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero row: circle avatar + label + number
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text('🤰', style: TextStyle(fontSize: 19)),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ComposerStrings.gestationalAgeLabel.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _pinkAccent,
                        letterSpacing: 0.6,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          color: _navy,
                          height: 1,
                        ),
                        children: weeks != null
                            ? [
                                TextSpan(
                                  text: '$weeks ',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: ComposerStrings.gestationalAgeWeeks,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _unitGrey,
                                  ),
                                ),
                                if (days != null && days > 0) ...[
                                  TextSpan(
                                    text: ' $days ',
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      color: _navy,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ComposerStrings.gestationalAgeDays,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _unitGrey,
                                    ),
                                  ),
                                ],
                              ]
                            : [
                                TextSpan(
                                  text: '— ',
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: ComposerStrings.gestationalAgeWeeks,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _unitGrey,
                                  ),
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // LMP + EDD row
            Row(
              children: [
                Expanded(
                  child: _DateSubBox(
                    emoji: '📅',
                    label: ComposerStrings.pregnancyOverviewLmp,
                    value: lmpStr,
                    valueColor: _navy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateSubBox(
                    emoji: '🍼',
                    label: ComposerStrings.pregnancyOverviewEdd,
                    value: eddStr,
                    valueColor: const Color(0xFFDB2777),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateSubBox extends StatelessWidget {
  const _DateSubBox({
    required this.emoji,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String emoji;
  final String label;
  final String? value;
  final Color valueColor;

  static const _pinkAccent = Color(0xFF9D174D);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _pinkAccent,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          Text(
            value ?? '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.config,
    required this.data,
    required this.validationErrors,
    required this.onFieldChanged,
    this.previousWeight,
    this.gestationalWeeks,
  });

  final FormSection section;
  final FormConfig config;
  final CanonicalVisitData data;
  final Set<String> validationErrors;
  final void Function(String fieldId, dynamic value) onFieldChanged;

  /// Weight (kg) from the patient's most-recent prior ANC visit — used to
  /// compute the weight-delta badge.  `null` when unavailable.
  final double? previousWeight;

  /// Patient's current gestational age in weeks — used to compute the
  /// fundal-height expected value and lag/ahead badge.  `null` when unknown.
  final int? gestationalWeeks;

  // ── Supplement pair detection ─────────────────────────────────────────────
  // Maps each "consumed" field id → (set of possible "provided" field ids,
  // outer card label, Bengali sub-label, emoji).
  static const Map<String, ({Set<String> providedIds, String label, String subLabel, String emoji})>
      _supplementConsumedMap = {
    'folicAcidTotalConsumed': (
      providedIds: {'folicAcidProvided', 'folicAcidTablets'},
      label: UnifiedFormStrings.folatePairLabel,
      subLabel: UnifiedFormStrings.folatePairSubLabel,
      emoji: '💊',
    ),
    'folicAcidTablets': (
      providedIds: {'folicAcidProvided'},
      label: UnifiedFormStrings.folatePairLabel,
      subLabel: UnifiedFormStrings.folatePairSubLabel,
      emoji: '💊',
    ),
    'ifaTotalConsumed': (
      providedIds: {'ifaProvided', 'ifaTabletsProvided'},
      label: UnifiedFormStrings.ifaPairLabel,
      subLabel: UnifiedFormStrings.ifaPairSubLabel,
      emoji: '🩸',
    ),
    'ifaTabletsConsumed': (
      providedIds: {'ifaProvided', 'ifaTabletsProvided'},
      label: UnifiedFormStrings.ifaPairLabel,
      subLabel: UnifiedFormStrings.ifaPairSubLabel,
      emoji: '🩸',
    ),
    'ifaTablets': (
      providedIds: {'ifaProvided', 'ifaTabletsProvided'},
      label: UnifiedFormStrings.ifaPairLabel,
      subLabel: UnifiedFormStrings.ifaPairSubLabel,
      emoji: '🩸',
    ),
    'calciumTotalConsumed': (
      providedIds: {'calciumProvided', 'calciumTabletsProvided'},
      label: UnifiedFormStrings.calciumPairLabel,
      subLabel: UnifiedFormStrings.calciumPairSubLabel,
      emoji: '🦴',
    ),
    'calciumTabletsConsumed': (
      providedIds: {'calciumProvided', 'calciumTabletsProvided'},
      label: UnifiedFormStrings.calciumPairLabel,
      subLabel: UnifiedFormStrings.calciumPairSubLabel,
      emoji: '🦴',
    ),
    'calciumTablets': (
      providedIds: {'calciumProvided', 'calciumTabletsProvided'},
      label: UnifiedFormStrings.calciumPairLabel,
      subLabel: UnifiedFormStrings.calciumPairSubLabel,
      emoji: '🦴',
    ),
  };

  @override
  Widget build(BuildContext context) {
    // Pre-compute the set of ref IDs in this section so all pair detectors
    // work regardless of field ordering.
    final sectionIds = section.fieldRefs.map((r) => r.id).toSet();

    final hasBpPair = sectionIds.contains('systolic') &&
        sectionIds.contains('diastolic');

    final hasBpPulseTriple = hasBpPair && sectionIds.contains('pulse');

    // Blood-glucose pair: fasting + random shown side-by-side.
    final hasGlucosePair = sectionIds.contains('fastingBloodSugar') &&
        sectionIds.contains('randomBloodSugar');

    // Height + weight pair: physical measurements shown side-by-side.
    final hasHeightWeightPair = sectionIds.contains('height') &&
        sectionIds.contains('weight');

    // For each supplement consumed field, find which provided field (if any) is
    // present in the same section, so we can render a combined pair card.
    final Map<String, String?> supplementConsumedToProvidedRef = {};
    for (final entry in _supplementConsumedMap.entries) {
      if (sectionIds.contains(entry.key)) {
        final matchedProvided = entry.value.providedIds
            .cast<String?>()
            .firstWhere(sectionIds.contains, orElse: () => null);
        supplementConsumedToProvidedRef[entry.key] = matchedProvided;
      }
    }

    // IDs absorbed into a composite widget — skip when encountered individually.
    final consumedIds = <String>{
      // When a combined BP card is rendered, skip the standalone fields.
      if (hasBpPair) ...const {'bloodPressure', 'diastolic'},
      // When pulse is in the same section, absorb it into the BP card.
      if (hasBpPulseTriple) 'pulse',
      // Combined glucose pair — skip the random field (fasting card drives).
      if (hasGlucosePair) 'randomBloodSugar',
      // Combined height+weight pair — skip weight (height card drives).
      if (hasHeightWeightPair) 'weight',
      // For each supplement pair, skip the "provided" counterpart field —
      // it will be rendered inline inside the consumed field's pair card.
      for (final p in supplementConsumedToProvidedRef.values) ?p,
    };

    bool bpPairEmitted = false;
    bool glucosePairEmitted = false;
    bool heightWeightPairEmitted = false;

    final fieldWidgets = <Widget>[];
    for (final ref in section.fieldRefs) {
      if (consumedIds.contains(ref.id)) continue;

      final def = config.fields[ref.id];
      if (def == null) continue;

      Widget child;
      if (ref.id == 'systolic' && hasBpPair) {
        // Emit the combined BP card once (with optional pulse).
        if (!bpPairEmitted) {
          bpPairEmitted = true;
          final diaRef = section.fieldRefs.firstWhere((r) => r.id == 'diastolic');
          final diaDef = config.fields['diastolic'];
          if (diaDef != null) {
            final pulseRef = hasBpPulseTriple
                ? section.fieldRefs.cast<FieldRef?>().firstWhere(
                    (r) => r?.id == 'pulse', orElse: () => null)
                : null;
            final pulseDef = pulseRef != null ? config.fields['pulse'] : null;
            child = _bpPairCard(
              context, def, ref, diaDef, diaRef,
              pulseDef: pulseDef, pulseRef: pulseRef,
            );
          } else {
            child = _fieldRow(context, def, ref);
          }
        } else {
          continue;
        }
      } else if (ref.id == 'fastingBloodSugar' && hasGlucosePair) {
        // Emit the combined glucose pair card once (fasting drives, random follows).
        if (!glucosePairEmitted) {
          glucosePairEmitted = true;
          final randomRef = section.fieldRefs.firstWhere((r) => r.id == 'randomBloodSugar');
          final randomDef = config.fields['randomBloodSugar'];
          if (randomDef != null) {
            child = _glucosePairCard(context, def, ref, randomDef, randomRef);
          } else {
            child = _fieldRow(context, def, ref);
          }
        } else {
          continue;
        }
      } else if (ref.id == 'height' && hasHeightWeightPair) {
        // Emit the combined height + weight pair card once.
        if (!heightWeightPairEmitted) {
          heightWeightPairEmitted = true;
          final weightRef = section.fieldRefs.firstWhere((r) => r.id == 'weight');
          final weightDef = config.fields['weight'];
          if (weightDef != null) {
            child = _heightWeightPairCard(context, def, ref, weightDef, weightRef);
          } else {
            child = _fieldRow(context, def, ref);
          }
        } else {
          continue;
        }
      } else if (_supplementConsumedMap.containsKey(ref.id) &&
          supplementConsumedToProvidedRef.containsKey(ref.id)) {
        // Emit supplement pair card (consumed + provided side-by-side).
        final meta = _supplementConsumedMap[ref.id]!;
        final providedId = supplementConsumedToProvidedRef[ref.id];
        if (providedId != null) {
          final providedDef = config.fields[providedId];
          if (providedDef != null) {
            child = _supplementPairCard(context, def, ref, providedDef, providedId, meta);
          } else {
            child = _fieldRow(context, def, ref);
          }
        } else {
          child = _fieldRow(context, def, ref);
        }
      } else {
        child = _fieldRow(context, def, ref);
      }

      fieldWidgets.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: child,
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Text(
              section.title.toUpperCase(),
              style: AppTextStyles.sectionLabel,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          ...fieldWidgets,
        ],
      ),
    );
  }

  /// Renders a combined Blood Pressure card with systolic / diastolic inputs
  /// side-by-side in one [_FieldShell].  When [pulseDef] / [pulseRef] are
  /// supplied the pulse input is appended in the same row after diastolic.
  Widget _bpPairCard(
    BuildContext context,
    FieldDef sysDef,
    FieldRef sysRef,
    FieldDef diaDef,
    FieldRef diaRef, {
    FieldDef? pulseDef,
    FieldRef? pulseRef,
  }) {
    final hasError = validationErrors.contains(sysRef.id) ||
        validationErrors.contains(diaRef.id) ||
        (pulseRef != null && validationErrors.contains(pulseRef.id));
    final isMandatory = sysDef.isMandatory ||
        sysRef.isMandatory ||
        diaDef.isMandatory ||
        diaRef.isMandatory ||
        (pulseDef?.isMandatory ?? false) ||
        (pulseRef?.isMandatory ?? false);
    final bpStatus = _VitalStatusEval.bloodPressure(
      _VitalStatusEval.asInt(data.getValue('systolic')),
      _VitalStatusEval.asInt(data.getValue('diastolic')),
    );

    final subLabel = pulseDef != null
        ? '${UnifiedFormStrings.bpCardSubLabel} · ${UnifiedFormStrings.bpUnit}  ·  pulse bpm'
        : '${UnifiedFormStrings.bpCardSubLabel} · ${UnifiedFormStrings.bpUnit}';

    return _FieldShell(
      label: UnifiedFormStrings.bpCardLabel,
      subLabel: subLabel,
      emoji: '🩺',
      emojiBg: const Color(0xFFEEF0FF),
      isMandatory: isMandatory,
      hasError: hasError,
      statusBadge: bpStatus != null
          ? _VitalBadge(label: bpStatus.label, color: bpStatus.color)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _NumericField(
              key: const Key('unified_form_systolic_input'),
              isDecimal: false,
              hint: UnifiedFormStrings.bpSystolicLabel,
              initialValue: data.getValue('systolic')?.toString(),
              onChanged: (v) {
                if (v == null || v.isEmpty) {
                  onFieldChanged('systolic', null);
                } else {
                  onFieldChanged('systolic', int.tryParse(v) ?? double.tryParse(v) ?? v);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 6, right: 6),
            child: Text(
              '/',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: _NumericField(
              key: const Key('unified_form_diastolic_input'),
              isDecimal: false,
              hint: UnifiedFormStrings.bpDiastolicLabel,
              initialValue: data.getValue('diastolic')?.toString(),
              onChanged: (v) {
                if (v == null || v.isEmpty) {
                  onFieldChanged('diastolic', null);
                } else {
                  onFieldChanged('diastolic', int.tryParse(v) ?? double.tryParse(v) ?? v);
                }
              },
            ),
          ),
          if (pulseDef != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 6, right: 6),
              child: Text(
                '·',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Expanded(
              child: _NumericField(
                key: const Key('unified_form_pulse_input'),
                isDecimal: false,
                hint: 'Pulse',
                initialValue: data.getValue('pulse')?.toString(),
                onChanged: (v) {
                  if (v == null || v.isEmpty) {
                    onFieldChanged('pulse', null);
                  } else {
                    onFieldChanged('pulse', int.tryParse(v) ?? double.tryParse(v) ?? v);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Renders a supplement pair card — outer [_FieldShell] with the supplement
  /// name and Bengali label, containing "consumed" and "provided" inputs
  /// side-by-side.
  Widget _supplementPairCard(
    BuildContext context,
    FieldDef consumedDef,
    FieldRef consumedRef,
    FieldDef providedDef,
    String providedId,
    ({Set<String> providedIds, String label, String subLabel, String emoji}) meta,
  ) {
    final hasError = validationErrors.contains(consumedRef.id) ||
        validationErrors.contains(providedId);
    final isMandatory = consumedDef.isMandatory ||
        consumedRef.isMandatory ||
        providedDef.isMandatory;
    return _FieldShell(
      label: meta.label,
      subLabel: meta.subLabel,
      emoji: meta.emoji,
      emojiBg: const Color(0xFFF0FDF4),
      isMandatory: isMandatory,
      hasError: hasError,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.supplementConsumedLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${consumedRef.id}_input'),
                  isDecimal: false,
                  hint: consumedDef.hintText,
                  initialValue: data.getValue(consumedRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(consumedRef.id, null);
                    } else {
                      onFieldChanged(consumedRef.id, int.tryParse(v) ?? v);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.supplementProvidedLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${providedId}_input'),
                  isDecimal: false,
                  hint: providedDef.hintText,
                  initialValue: data.getValue(providedId)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(providedId, null);
                    } else {
                      onFieldChanged(providedId, int.tryParse(v) ?? v);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders a combined Blood Glucose card — fasting and random inputs
  /// side-by-side under a shared header, with a rule-based elevation badge
  /// and an inline GDM / diabetes warning when values are high.
  Widget _glucosePairCard(
    BuildContext context,
    FieldDef fastingDef,
    FieldRef fastingRef,
    FieldDef randomDef,
    FieldRef randomRef,
  ) {
    final fastingVal = _VitalStatusEval.asDouble(data.getValue(fastingRef.id));
    final randomVal  = _VitalStatusEval.asDouble(data.getValue(randomRef.id));
    final glucoseStatus = _VitalStatusEval.bloodGlucose(fastingVal, randomVal);
    final hasError = validationErrors.contains(fastingRef.id) ||
        validationErrors.contains(randomRef.id);
    final isMandatory = fastingDef.isMandatory || fastingRef.isMandatory ||
        randomDef.isMandatory || randomRef.isMandatory;
    return _FieldShell(
      label: UnifiedFormStrings.glucosePairLabel,
      subLabel: UnifiedFormStrings.glucosePairSubLabel,
      emoji: '🩸',
      emojiBg: const Color(0xFFFFF1F2),
      isMandatory: isMandatory,
      hasError: hasError,
      statusBadge: glucoseStatus != null
          ? _VitalBadge(label: glucoseStatus.label, color: glucoseStatus.color)
          : null,
      inlineWarning: glucoseStatus?.warning,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.glucoseFastingLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${fastingRef.id}_input'),
                  isDecimal: true,
                  unit: 'mmol/L',
                  initialValue: data.getValue(fastingRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(fastingRef.id, null);
                    } else {
                      onFieldChanged(fastingRef.id, double.tryParse(v) ?? v);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.glucoseRandomLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${randomRef.id}_input'),
                  isDecimal: true,
                  unit: 'mmol/L',
                  initialValue: data.getValue(randomRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(randomRef.id, null);
                    } else {
                      onFieldChanged(randomRef.id, double.tryParse(v) ?? v);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders a combined Height + Weight card — both numeric inputs side-by-side
  /// under a single header.  The weight-delta badge and "Last: X kg" sub-info
  /// are shown in the header when prior weight data is available.
  Widget _heightWeightPairCard(
    BuildContext context,
    FieldDef heightDef,
    FieldRef heightRef,
    FieldDef weightDef,
    FieldRef weightRef,
  ) {
    final hasError = validationErrors.contains(heightRef.id) ||
        validationErrors.contains(weightRef.id);
    final isMandatory = heightDef.isMandatory || heightRef.isMandatory ||
        weightDef.isMandatory || weightRef.isMandatory;
    final currentWeight = _VitalStatusEval.asDouble(data.getValue(weightRef.id));
    final weightStatus = _VitalStatusEval.weight(currentWeight, previousWeight);
    // Sub-label: last weight info when available.
    final subParts = <String>[UnifiedFormStrings.heightWeightPairSubLabel];
    if (previousWeight != null) {
      subParts.add(UnifiedFormStrings.vsLastWeight(previousWeight!));
    }
    return _FieldShell(
      label: UnifiedFormStrings.heightWeightPairLabel,
      subLabel: subParts.join(' · '),
      emoji: '📐',
      emojiBg: const Color(0xFFEEF2FF),
      isMandatory: isMandatory,
      hasError: hasError,
      statusBadge: weightStatus != null
          ? _VitalBadge(label: weightStatus.label, color: weightStatus.color)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.heightSubLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${heightRef.id}_input'),
                  isDecimal: true,
                  unit: 'cm',
                  initialValue: data.getValue(heightRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(heightRef.id, null);
                    } else {
                      onFieldChanged(heightRef.id, double.tryParse(v) ?? v);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UnifiedFormStrings.weightSubLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                _NumericField(
                  key: Key('unified_form_${weightRef.id}_input'),
                  isDecimal: true,
                  unit: 'kg',
                  initialValue: data.getValue(weightRef.id)?.toString(),
                  onChanged: (v) {
                    if (v == null || v.isEmpty) {
                      onFieldChanged(weightRef.id, null);
                    } else {
                      onFieldChanged(weightRef.id, double.tryParse(v) ?? v);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds one field row: self-contained fields (info / text label) render
  /// bare; [dialogCheckbox] renders fully standalone (owns its own label +
  /// option list).  Every other editable field is wrapped in [_FieldShell].
  ///
  /// For the handful of vital-sign fields that have clinical rules (weight,
  /// fundal height, urine albumin, haemoglobin), a [_VitalBadge] and optional
  /// inline warning are computed from the current field value and appended.
  Widget _fieldRow(BuildContext context, FieldDef def, FieldRef ref) {
    final currentValue = data.getValue(ref.id);
    final control = _buildField(context, def, ref, currentValue);
    switch (def.widgetHint) {
      case WidgetHint.infoLabel:
        // For BMI, enrich the read-only display with a WHO classification badge.
        if (ref.id == 'bmi') {
          final bmiStatus = _VitalStatusEval.bmi(
            _VitalStatusEval.asDouble(currentValue),
          );
          return _InfoLabelField(
            key: Key('unified_form_${def.id}_info'),
            label: def.label,
            value: currentValue?.toString(),
            statusBadge: bmiStatus != null
                ? _VitalBadge(label: bmiStatus.label, color: bmiStatus.color)
                : null,
          );
        }
        return control;
      case WidgetHint.textLabel:
        return control;
      // dialogCheckbox renders as a self-contained inline list with its own
      // label header — wrapping it in a _FieldShell would double the label.
      case WidgetHint.dialogCheckbox:
        return control;
      // bloodGlucoseEntry is self-contained: it wraps its own _FieldShell and
      // manages both glucoseType + glucose inline, so skip the outer shell.
      case WidgetHint.bloodGlucoseEntry:
        return control;
      default:
        final glyph = FormFieldVisuals.forField(def.id);
        final unit = def.unitMeasurement;

        // ── Vital-status enrichment (per-field rules) ─────────────────────
        _VitalStatus? vitalStatus;
        List<String> subParts = [
          if (def.labelCulture != null && def.labelCulture!.isNotEmpty)
            def.labelCulture!,
          if (unit != null && unit.isNotEmpty) unit,
        ];

        switch (ref.id) {
          case 'weight':
            final w = _VitalStatusEval.asDouble(currentValue);
            vitalStatus = _VitalStatusEval.weight(w, previousWeight);
            if (previousWeight != null) {
              subParts = [
                if (def.labelCulture != null && def.labelCulture!.isNotEmpty)
                  def.labelCulture!,
                if (unit != null && unit.isNotEmpty) unit,
                UnifiedFormStrings.vsLastWeight(previousWeight!),
              ];
            }

          case 'fundalHeight':
            final fh = _VitalStatusEval.asDouble(currentValue);
            vitalStatus = _VitalStatusEval.fundalHeight(fh, gestationalWeeks);
            if (gestationalWeeks != null) {
              subParts = [
                if (def.labelCulture != null && def.labelCulture!.isNotEmpty)
                  def.labelCulture!,
                if (unit != null && unit.isNotEmpty) unit,
                UnifiedFormStrings.vsFhExpectedSubLabel(gestationalWeeks!),
              ];
            }

          case 'urinaryAlbumin':
            vitalStatus =
                _VitalStatusEval.urinaryAlbumin(currentValue as String?);

          case 'hemoglobin':
            vitalStatus =
                _VitalStatusEval.hemoglobin(_VitalStatusEval.asDouble(currentValue));

          case 'fastingBloodSugar':
            vitalStatus = _VitalStatusEval.bloodGlucose(
              _VitalStatusEval.asDouble(currentValue),
              null,
            );

          case 'randomBloodSugar':
            vitalStatus = _VitalStatusEval.bloodGlucose(
              null,
              _VitalStatusEval.asDouble(currentValue),
            );
        }

        return _FieldShell(
          label: def.label,
          subLabel: subParts.isEmpty ? null : subParts.join(' · '),
          emoji: glyph?.emoji,
          emojiBg: glyph?.background,
          isMandatory: def.isMandatory || ref.isMandatory,
          hasError: validationErrors.contains(ref.id),
          statusBadge: vitalStatus != null
              ? _VitalBadge(label: vitalStatus.label, color: vitalStatus.color)
              : null,
          inlineWarning: vitalStatus?.warning,
          child: control,
        );
    }
  }

  Widget _buildField(
    BuildContext context,
    FieldDef def,
    FieldRef ref,
    dynamic currentValue,
  ) {
    switch (def.widgetHint) {
      case WidgetHint.radioGroup:
        // Canonical store uses option id; RadioFormField works with display names.
        // Translate: stored id → display name for render, selected name → id on change.
        final storedId = currentValue as String?;
        final displayName = def.options
            .cast<FieldOption?>()
            .firstWhere(
              (o) => o!.id == storedId || o.name == storedId,
              orElse: () => null,
            )
            ?.name;
        return RadioFormField(
          key: Key('unified_form_${def.id}_input'),
          options: def.options.map((o) => o.name).toList(),
          currentValue: displayName,
          onChanged: (name) {
            if (name == null) {
              // Toggle-deselect: tapping the active pill clears the value.
              onFieldChanged(def.id, null);
              return;
            }
            final id = def.options
                .cast<FieldOption?>()
                .firstWhere((o) => o!.name == name, orElse: () => null)
                ?.id ?? name;
            onFieldChanged(def.id, id);
          },
        );

      case WidgetHint.dialogCheckbox:
        // Canonical store uses list of option ids; inline list works with display names.
        final storedIds = (currentValue is List)
            ? currentValue.cast<String>()
            : <String>[];
        final displayNames = storedIds.map((sid) {
          return def.options
                  .cast<FieldOption?>()
                  .firstWhere(
                    (o) => o!.id == sid || o.name == sid,
                    orElse: () => null,
                  )
                  ?.name ??
              sid;
        }).toList();
        final subParts = <String>[
          if (def.labelCulture != null && def.labelCulture!.isNotEmpty)
            def.labelCulture!,
        ];
        return _InlineListSelectField(
          key: Key('unified_form_${def.id}_input'),
          label: def.label,
          subLabel: subParts.isEmpty ? null : subParts.first,
          isMandatory: def.isMandatory || ref.isMandatory,
          hasError: validationErrors.contains(ref.id),
          options: def.options.map((o) => o.name).toList(),
          selectedValues: displayNames,
          onChanged: (names) {
            final ids = names.map((n) {
              return def.options
                      .cast<FieldOption?>()
                      .firstWhere((o) => o!.name == n, orElse: () => null)
                      ?.id ??
                  n;
            }).toList();
            onFieldChanged(def.id, ids);
          },
        );

      case WidgetHint.spinner:
        return _SpinnerField(
          key: Key('unified_form_${def.id}_input'),
          options: def.options,
          currentValue: currentValue as String?,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.bloodGlucoseEntry:
        // Renders FBS/RBS type toggle + numeric value input in one card.
        // glucoseType (def.id) stores the selected type; 'glucose' stores the
        // numeric value.  Both are written to CanonicalVisitData individually.
        return _BloodGlucoseEntryField(
          key: Key('unified_form_${def.id}_bge'),
          options: def.options,
          glucoseType: currentValue as String?,
          glucoseValue: data.getValue('glucose'),
          isMandatory: def.isMandatory || ref.isMandatory,
          hasError: validationErrors.contains(ref.id),
          onTypeChanged: (type) => onFieldChanged(def.id, type),
          onValueChanged: (val) => onFieldChanged('glucose', val),
        );

      case WidgetHint.numeric:
      case WidgetHint.bloodGlucose:
        // inputType 2 = numberDecimal; "decimal" string (from EditText fields) is
        // also treated as decimal — use isDecimal flag.
        final isDecimal = ref.inputType == 2 ||
            (currentValue is double) ||
            (def.unitMeasurement != null &&
                !def.unitMeasurement!.contains('whole'));
        return _NumericField(
          key: Key('unified_form_${def.id}_input'),
          isDecimal: isDecimal,
          unit: def.unitMeasurement,
          hint: def.hintText,
          initialValue: currentValue?.toString(),
          onChanged: (v) {
            if (v == null || v.isEmpty) {
              onFieldChanged(def.id, null);
            } else {
              final parsed = isDecimal
                  ? double.tryParse(v)
                  : int.tryParse(v) ?? double.tryParse(v);
              onFieldChanged(def.id, parsed ?? v);
            }
          },
        );

      case WidgetHint.dateField:
        return _DateField(
          key: Key('unified_form_${def.id}_input'),
          currentValue: currentValue as String?,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.infoLabel:
        // Computed read-only value (e.g. BMI, CVD risk). Show value when
        // available; otherwise show a muted placeholder.
        return _InfoLabelField(
          key: Key('unified_form_${def.id}_info'),
          label: def.label,
          value: currentValue?.toString(),
        );

      case WidgetHint.textLabel:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(def.label, style: AppTextStyles.subText),
        );

      case WidgetHint.bpField:
        // Render a systolic / diastolic pair. Stores value as a list of
        // reading maps to match Android's bpLogDetails wire format.
        final readings = (currentValue is List)
            ? currentValue.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        return _BpReadingField(
          key: Key('unified_form_${def.id}_bp'),
          readings: readings,
          onChanged: (v) => onFieldChanged(def.id, v),
        );

      case WidgetHint.ageYmd:
      case WidgetHint.pregnancyProfile:
      case WidgetHint.unknown:
        // Complex fields delegated to specialised widgets in Section overrides.
        // Fall back to a numeric text field so data is never silently dropped.
        return _NumericField(
          key: Key('unified_form_${def.id}_input'),
          isDecimal: true,
          initialValue: currentValue?.toString(),
          onChanged: (v) => onFieldChanged(def.id, v),
        );
    }
  }
}

// ── Vital status evaluation ────────────────────────────────────────────────────

/// Compact value object returned by [_VitalStatusEval] methods.
///
/// [label] is the display text for the badge pill.
/// [color] drives the badge's background tint and text color.
/// [warning] is optional inline text rendered below the field control.
class _VitalStatus {
  const _VitalStatus({
    required this.label,
    required this.color,
    this.warning,
  });

  final String label;
  final Color color;
  final String? warning;
}

/// Pure rule-based evaluator — no ML, fully explainable.
///
/// Each method returns `null` when the input is absent or out of the
/// evaluable range so the caller can simply skip the badge.
abstract final class _VitalStatusEval {
  _VitalStatusEval._();

  // ── Blood pressure ───────────────────────────────────────────────────────
  // Thresholds from the ANC / NCD clinical spec in CLAUDE.md.
  static _VitalStatus? bloodPressure(int? sys, int? dia) {
    if (sys == null && dia == null) return null;
    final s = sys ?? 0;
    final d = dia ?? 0;
    if (s >= 160 || d >= 110) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpSevere,
        color: AppColors.statusCritical,
      );
    }
    if (s >= 140 || d >= 90) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpHigh,
        color: AppColors.statusCritical,
      );
    }
    if (s >= 130 || d >= 85) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpSlightlyElevated,
        color: AppColors.statusWarning,
      );
    }
    if (s >= 120) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpElevated,
        color: AppColors.statusWarning,
      );
    }
    if (s > 0 || d > 0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBpNormal,
        color: AppColors.statusSuccess,
      );
    }
    return null;
  }

  // ── Weight delta ─────────────────────────────────────────────────────────
  static _VitalStatus? weight(double? current, double? previous) {
    if (current == null || previous == null) return null;
    final delta = current - previous;
    final abs = delta.abs();
    // Colour by gain magnitude (ANC context — 0.5–2 kg/4 wks is normal).
    Color color;
    if (delta >= 0 && abs <= 2.0) {
      color = AppColors.statusSuccess;
    } else if (abs <= 3.5) {
      color = AppColors.statusWarning;
    } else {
      color = AppColors.statusCritical;
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsWeightDelta(delta),
      color: color,
    );
  }

  // ── Fundal height ────────────────────────────────────────────────────────
  // Bartholomew's rule: FH (cm) ≈ gestational age (weeks).
  static _VitalStatus? fundalHeight(double? measured, int? gestWeeks) {
    if (measured == null || gestWeeks == null || gestWeeks <= 0) return null;
    final diff = (measured - gestWeeks).round();
    if (diff <= -2) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsFhLag(diff.abs()),
        color: AppColors.statusWarning,
      );
    }
    if (diff >= 2) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsFhAhead(diff),
        color: AppColors.navy,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsFhExpected,
      color: AppColors.statusSuccess,
    );
  }

  // ── Urinary albumin / urine protein ─────────────────────────────────────
  static _VitalStatus? urinaryAlbumin(String? value) {
    if (value == null || value.isEmpty) return null;
    final v = value.toLowerCase();
    if (v.contains('absent') || v.contains('neg')) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsUrineAbsent,
        color: AppColors.statusSuccess,
      );
    }
    if (v.contains('trace')) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsUrineTrace,
        color: AppColors.statusWarning,
      );
    }
    if (v.contains('present') || v.contains('pos')) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsUrinePresent,
        color: AppColors.statusCritical,
      );
    }
    return null;
  }

  // ── Haemoglobin ──────────────────────────────────────────────────────────
  // WHO thresholds for pregnant women (≥11 g/dL = normal).
  static _VitalStatus? hemoglobin(double? value) {
    if (value == null) return null;
    if (value < 7.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsHbSevere,
        color: AppColors.statusCritical,
        warning: UnifiedFormStrings.vsHbWarningLong,
      );
    }
    if (value < 10.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsHbModerate,
        color: AppColors.statusCritical,
        warning: UnifiedFormStrings.vsHbWarningLong,
      );
    }
    if (value < 11.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsHbMild,
        color: AppColors.statusWarning,
        warning: UnifiedFormStrings.vsHbWarningLong,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsHbNormal,
      color: AppColors.statusSuccess,
    );
  }

  // ── Blood glucose ────────────────────────────────────────────────────────
  // Uses the higher of fasting / random to determine severity.
  // ADA / GDM thresholds: fasting ≥5.1 = GDM risk; fasting ≥7.0 = DM;
  // random ≥7.8 = elevated; random ≥11.1 = DM.
  static _VitalStatus? bloodGlucose(double? fasting, double? random) {
    if (fasting == null && random == null) return null;
    // High (diabetes level): fasting ≥7.0 OR random ≥11.1
    final isHigh =
        (fasting != null && fasting >= 7.0) ||
        (random  != null && random  >= 11.1);
    if (isHigh) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsGlucoseHigh,
        color: AppColors.statusCritical,
        warning: UnifiedFormStrings.vsGlucoseWarningHigh,
      );
    }
    // Elevated: fasting ≥5.1 OR random ≥7.8
    final isElevated =
        (fasting != null && fasting >= 5.1) ||
        (random  != null && random  >= 7.8);
    if (isElevated) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsGlucoseElevated,
        color: AppColors.statusWarning,
        warning: UnifiedFormStrings.vsGlucoseWarningElevated,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsGlucoseNormal,
      color: AppColors.statusSuccess,
    );
  }

  // ── BMI ──────────────────────────────────────────────────────────────────
  // WHO adult classification thresholds.
  static _VitalStatus? bmi(double? value) {
    if (value == null) return null;
    if (value < 18.5) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBmiUnderweight,
        color: AppColors.navy,
      );
    }
    if (value < 25.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBmiNormal,
        color: AppColors.statusSuccess,
      );
    }
    if (value < 30.0) {
      return _VitalStatus(
        label: UnifiedFormStrings.vsBmiOverweight,
        color: AppColors.statusWarning,
      );
    }
    return _VitalStatus(
      label: UnifiedFormStrings.vsBmiObese,
      color: AppColors.statusCritical,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static double? asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// Small coloured pill that shows a vital-status label.
///
/// Uses a translucent background tinted from [color] so it works over both
/// white field cards and the dark card borders.
class _VitalBadge extends StatelessWidget {
  const _VitalBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}

// ── Field chrome (v13 visual system) ─────────────────────────────────────────

/// Local visual constants for the Step 2 form, mirroring the `apon_sushashthya`
/// v13 mockup's form styling.  Kept private to this screen so the shared global
/// theme is untouched; all colours still come from [AppColors] tokens.
const double _kFieldCardRadius = AppRadius.button; // 12 — white field card
const double _kControlRadius = AppRadius.field; // 10 — filled input control
const double _kControlBorderWidth = 1.5;

/// Filled input decoration shared by every text / number / date / select
/// control so their fill, border, radius, and padding are pixel-consistent
/// with the v13 mockup (`#F8F9FC` fill, `1.5px #E5E7EB` border, radius 10).
InputDecoration _filledInputDecoration({
  String? hintText,
  String? suffixText,
  Widget? suffixIcon,
}) {
  final enabled = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_kControlRadius),
    borderSide: const BorderSide(
      color: AppColors.border,
      width: _kControlBorderWidth,
    ),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: AppColors.cardSurfaceMuted,
    hintText: hintText,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
    border: enabled,
    enabledBorder: enabled,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kControlRadius),
      borderSide: const BorderSide(
        color: AppColors.navy,
        width: _kControlBorderWidth,
      ),
    ),
  );
}

/// The label line shown above every field: bold dark text with a red `*` when
/// the field is mandatory (matches the v13 `.field-label` styling).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.isMandatory = false});

  final String label;
  final bool isMandatory;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.25,
        );
    return Text.rich(
      TextSpan(
        text: label,
        style: base,
        children: isMandatory
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppColors.statusCritical,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]
            : const [],
      ),
    );
  }
}

/// The consistent chrome around every editable field: a white rounded card with
/// a `1.5px` border (red when [hasError]).  The header row mirrors the v13
/// mockup's vitals cards — an optional pastel [emoji] tile, the bold English
/// [label] + mandatory `*`, and a muted bilingual [subLabel] (Bengali · unit) —
/// with the control [child] below.
class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.label,
    required this.child,
    this.subLabel,
    this.emoji,
    this.emojiBg,
    this.isMandatory = false,
    this.hasError = false,
    this.statusBadge,
    this.inlineWarning,
  });

  final String label;
  final Widget child;

  /// Muted second line under the label (e.g. `"রক্তচাপ · mmHg"`).
  final String? subLabel;

  /// Optional decorative emoji shown in a pastel tile to the left of the label.
  final String? emoji;
  final Color? emojiBg;

  final bool isMandatory;
  final bool hasError;

  /// Optional status pill rendered at the far right of the header row.
  /// Typically a [_VitalBadge] instance.
  final Widget? statusBadge;

  /// Optional inline warning shown below the field control (⚠ text).
  final String? inlineWarning;

  @override
  Widget build(BuildContext context) {
    final hasSubLabel = subLabel != null && subLabel!.isNotEmpty;
    final hasWarning  = inlineWarning != null && inlineWarning!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(_kFieldCardRadius),
        border: Border.all(
          color: hasError ? AppColors.statusCritical : AppColors.border,
          width: _kControlBorderWidth,
        ),
        boxShadow: AppShadows.statBox,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (emoji != null) ...[
                  _EmojiTile(emoji: emoji!, background: emojiBg),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FieldLabel(label: label, isMandatory: isMandatory),
                      if (hasSubLabel) ...[
                        const SizedBox(height: 2),
                        Text(
                          subLabel!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMuted,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (statusBadge != null) ...[
                  const SizedBox(width: 6),
                  statusBadge!,
                ],
              ],
            ),
            const SizedBox(height: 9),
          ],
          child,
          if (hasWarning) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    inlineWarning!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.statusWarningText,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Rounded pastel tile holding a single decorative emoji, matching the v13
/// mockup's `30x30` vitals-card icon tile.
class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, this.background});

  final String emoji;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? AppColors.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 15)),
    );
  }
}

// ── Inline micro-widgets (no hardcoded strings, tokens only) ─────────────────

/// Combined blood-glucose card: FBS / RBS type toggle + numeric value input.
///
/// Replaces the separate `glucoseType` (Spinner) + `glucose` (EditText) pair
/// with a single self-contained card.  Both fields are still written to
/// [CanonicalVisitData] under their original IDs so the payload mapper is
/// unaffected.
class _BloodGlucoseEntryField extends StatefulWidget {
  const _BloodGlucoseEntryField({
    super.key,
    required this.options,
    required this.onTypeChanged,
    required this.onValueChanged,
    this.glucoseType,
    this.glucoseValue,
    this.isMandatory = false,
    this.hasError = false,
  });

  /// Options from the `glucoseType` field definition (FBS, RBS).
  final List<FieldOption> options;

  /// Current selected type id ('fbs' | 'rbs' | null).
  final String? glucoseType;

  /// Current glucose value (double | null).
  final dynamic glucoseValue;

  final void Function(String? type) onTypeChanged;
  final void Function(dynamic value) onValueChanged;
  final bool isMandatory;
  final bool hasError;

  @override
  State<_BloodGlucoseEntryField> createState() =>
      _BloodGlucoseEntryFieldState();
}

class _BloodGlucoseEntryFieldState extends State<_BloodGlucoseEntryField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.glucoseValue?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(_BloodGlucoseEntryField old) {
    super.didUpdateWidget(old);
    if (old.glucoseValue != widget.glucoseValue) {
      final newText = widget.glucoseValue?.toString() ?? '';
      if (_ctrl.text != newText) {
        final ctrlNum = double.tryParse(_ctrl.text);
        final newNum = double.tryParse(newText);
        final sameValue =
            ctrlNum != null && newNum != null && ctrlNum == newNum;
        if (!sameValue) {
          _ctrl.text = newText;
          _ctrl.selection =
              TextSelection.collapsed(offset: newText.length);
        }
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentType = widget.glucoseType;
    final glucoseNum = _VitalStatusEval.asDouble(widget.glucoseValue);

    // Route value to fasting vs random threshold depending on selected type.
    final fastingVal = currentType == 'fbs' ? glucoseNum : null;
    final randomVal = currentType == 'rbs' ? glucoseNum : null;
    final status = _VitalStatusEval.bloodGlucose(fastingVal, randomVal);

    return _FieldShell(
      label: UnifiedFormStrings.bloodGlucoseEntryLabel,
      subLabel: UnifiedFormStrings.bloodGlucoseEntrySubLabel,
      emoji: '🩸',
      emojiBg: const Color(0xFFFEE2E2),
      isMandatory: widget.isMandatory,
      hasError: widget.hasError,
      statusBadge: status != null
          ? _VitalBadge(label: status.label, color: status.color)
          : null,
      inlineWarning: status?.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Type toggle row ─────────────────────────────────────────────
          Row(
            children: List.generate(widget.options.length, (i) {
              final opt = widget.options[i];
              final isSelected = currentType == opt.id;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i < widget.options.length - 1 ? AppSpacing.xs : 0,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      // Tap again to deselect.
                      widget.onTypeChanged(isSelected ? null : opt.id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.navy
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.navy
                              : AppColors.border,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        opt.name,
                        style: AppTextStyles.chip.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textMuted,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          // ── Value input ─────────────────────────────────────────────────
          TextFormField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: _filledInputDecoration(
              hintText: UnifiedFormStrings.bloodGlucoseEntryHint,
              suffixText: UnifiedFormStrings.bloodGlucoseEntryUnit,
            ),
            onChanged: (v) {
              if (v.isEmpty) {
                widget.onValueChanged(null);
              } else {
                widget.onValueChanged(double.tryParse(v) ?? v);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _NumericField extends StatefulWidget {
  const _NumericField({
    super.key,
    required this.isDecimal,
    required this.onChanged,
    this.initialValue,
    this.unit,
    this.hint,
  });

  final bool isDecimal;
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final String? unit;
  final String? hint;

  @override
  State<_NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<_NumericField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void didUpdateWidget(_NumericField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue) {
      final newText = widget.initialValue ?? '';
      if (_ctrl.text != newText) {
        // Skip the update when the controller text and the incoming value
        // represent the same number but differ only in float representation
        // (e.g. "1" vs "1.0").  Without this guard, storing a parsed double
        // after every keystroke causes "120" to become "1.20": the controller
        // is reset to "1.0" after the first "1", and the next character
        // inserts at the wrong cursor position.
        final ctrlNum = double.tryParse(_ctrl.text);
        final newNum  = double.tryParse(newText);
        final sameValue = ctrlNum != null && newNum != null && ctrlNum == newNum;
        if (!sameValue) {
          _ctrl.text = newText;
          _ctrl.selection = TextSelection.collapsed(offset: newText.length);
        }
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      // Use the plain number keyboard for ALL numeric fields — even decimal
      // ones.  Some Android keyboards in currency/decimal mode auto-insert a
      // decimal point when `decimal: true` is set, causing "190" to appear
      // as "1.90" without the user intending it.  The plain number keyboard
      // never auto-inserts a point; users who need decimals (e.g. temperature
      // "36.5") can still type the "." manually since the formatter below
      // allows it.
      keyboardType: TextInputType.number,
      inputFormatters: [
        if (widget.isDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
      ],
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: _filledInputDecoration(
        hintText: widget.hint,
        suffixText: widget.unit,
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// Single-select field.  Rendered as the same chip/pill row as [RadioFormField]
/// (not a dropdown) to match the v13 mockup: ≤3 options fill a row, more options
/// wrap as chips.  The canonical store keeps the option id; the pill widget
/// works with display names, so ids are translated in both directions.
class _SpinnerField extends StatelessWidget {
  const _SpinnerField({
    super.key,
    required this.options,
    required this.onChanged,
    this.currentValue,
  });

  final List<FieldOption> options;
  final String? currentValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final displayName = options
        .cast<FieldOption?>()
        .firstWhere(
          (o) => o!.id == currentValue || o.name == currentValue,
          orElse: () => null,
        )
        ?.name;
    return RadioFormField(
      options: options.map((o) => o.name).toList(),
      currentValue: displayName,
      onChanged: (name) {
        if (name == null) {
          // Toggle-deselect.
          onChanged(null);
          return;
        }
        final id = options
                .cast<FieldOption?>()
                .firstWhere((o) => o!.name == name, orElse: () => null)
                ?.id ??
            name;
        onChanged(id);
      },
    );
  }
}

class _DateField extends StatefulWidget {
  const _DateField({
    super.key,
    required this.onChanged,
    this.currentValue,
  });

  final String? currentValue;
  final ValueChanged<String?> onChanged;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentValue ?? '');
  }

  @override
  void didUpdateWidget(_DateField old) {
    super.didUpdateWidget(old);
    if (old.currentValue != widget.currentValue) {
      _ctrl.text = widget.currentValue ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: _ctrl,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: _filledInputDecoration(
        suffixIcon: const Icon(
          Icons.calendar_today_outlined,
          size: 18,
          color: AppColors.textMuted,
        ),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          widget.onChanged(picked.toIso8601String().substring(0, 10));
        }
      },
    );
  }
}

// ── BP reading field ──────────────────────────────────────────────────────────

/// Systolic / diastolic pair that matches Android's `bpLogDetails` wire format.
///
/// Stores value as `List<Map<String, dynamic>>` with one entry per reading:
/// `[{'systolic': 120, 'diastolic': 80, 'pulse': 72}]`.
class _BpReadingField extends StatefulWidget {
  const _BpReadingField({
    super.key,
    required this.readings,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> readings;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<_BpReadingField> createState() => _BpReadingFieldState();
}

class _BpReadingFieldState extends State<_BpReadingField> {
  late TextEditingController _sys;
  late TextEditingController _dia;
  late TextEditingController _pulse;

  @override
  void initState() {
    super.initState();
    final first =
        widget.readings.isNotEmpty ? widget.readings.first : const {};
    _sys = TextEditingController(text: first['systolic']?.toString() ?? '');
    _dia = TextEditingController(text: first['diastolic']?.toString() ?? '');
    _pulse = TextEditingController(text: first['pulse']?.toString() ?? '');
  }

  @override
  void didUpdateWidget(_BpReadingField old) {
    super.didUpdateWidget(old);
    if (old.readings != widget.readings) {
      final first =
          widget.readings.isNotEmpty ? widget.readings.first : const {};
      _syncCtrl(_sys, first['systolic']?.toString() ?? '');
      _syncCtrl(_dia, first['diastolic']?.toString() ?? '');
      _syncCtrl(_pulse, first['pulse']?.toString() ?? '');
    }
  }

  void _syncCtrl(TextEditingController ctrl, String newText) {
    if (ctrl.text != newText) {
      ctrl.text = newText;
      ctrl.selection = TextSelection.collapsed(offset: newText.length);
    }
  }

  @override
  void dispose() {
    _sys.dispose();
    _dia.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _emit() {
    final sys = int.tryParse(_sys.text);
    final dia = int.tryParse(_dia.text);
    if (sys == null && dia == null) {
      widget.onChanged([]);
      return;
    }
    final reading = <String, dynamic>{};
    if (sys != null) reading['systolic'] = sys;
    if (dia != null) reading['diastolic'] = dia;
    final pulse = int.tryParse(_pulse.text);
    if (pulse != null) reading['pulse'] = pulse;
    widget.onChanged([reading]);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Systolic / diastolic pair joined by a "/" separator.
        Expanded(
          flex: 3,
          child: _bpCell(
            context,
            caption: UnifiedFormStrings.bpSystolicLabel,
            controller: _sys,
            suffixText: UnifiedFormStrings.bpUnit,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 6, right: 6),
          child: Text(
            '/',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _bpCell(
            context,
            caption: UnifiedFormStrings.bpDiastolicLabel,
            controller: _dia,
          ),
        ),
        const SizedBox(width: 10),
        // Pulse.
        Expanded(
          flex: 3,
          child: _bpCell(
            context,
            caption: UnifiedFormStrings.bpPulseLabel,
            controller: _pulse,
            suffixText: UnifiedFormStrings.bpPulseUnit,
          ),
        ),
      ],
    );
  }

  /// One captioned, filled numeric input used for systolic / diastolic / pulse.
  Widget _bpCell(
    BuildContext context, {
    required String caption,
    required TextEditingController controller,
    String? suffixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: _filledInputDecoration(suffixText: suffixText),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }
}

// ── Info label field ──────────────────────────────────────────────────────────

/// Read-only display for computed values (BMI, CVD risk score, etc.).
///
/// Accepts an optional [statusBadge] (e.g. a [_VitalBadge]) that is shown
/// to the right of the numeric value so the SK gets instant classification
/// context (e.g. "Normal", "Overweight") without reading a table.
class _InfoLabelField extends StatelessWidget {
  const _InfoLabelField({
    super.key,
    required this.label,
    this.value,
    this.statusBadge,
  });

  final String label;
  final String? value;

  /// Optional status pill rendered to the right of the displayed value.
  final Widget? statusBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurfaceMuted,
        borderRadius: BorderRadius.circular(_kControlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Uppercase caption + purple (auto) tag.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                UnifiedFormStrings.autoComputedTag,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.aiPurple,
                  fontWeight: FontWeight.w600,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                hasValue ? value! : UnifiedFormStrings.autoComputedPlaceholder,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.navy,
                ),
              ),
              if (statusBadge != null && hasValue) ...[
                const SizedBox(width: 8),
                statusBadge!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Inline list multi-select ──────────────────────────────────────────────────

/// Multi-select field rendered as an inline tappable list — one rounded row per
/// option.  Matches the "Any danger signs now?" UI in the v13 reference mockup:
/// each option is a white card-row with a leading emoji tile (if provided) and
/// the label, with a navy-filled style when selected.  The "None of these"
/// option (detected by a case-insensitive "none" prefix) deselects everything
/// else and shows a ✓ prefix.
class _InlineListSelectField extends StatelessWidget {
  const _InlineListSelectField({
    super.key,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.hasError = false,
    this.label,
    this.subLabel,
    this.isMandatory = false,
  });

  final List<String> options;
  final List<String> selectedValues;
  final ValueChanged<List<String>> onChanged;
  final bool hasError;
  final String? label;
  final String? subLabel;
  final bool isMandatory;

  static const _noneKey = 'none';

  String? get _noneOption =>
      options.cast<String?>().firstWhere(
            (o) => o!.toLowerCase().startsWith(_noneKey),
            orElse: () => null,
          );

  bool _isNone(String opt) => opt.toLowerCase().startsWith(_noneKey);

  void _toggle(String option) {
    final current = List<String>.from(selectedValues);
    if (_isNone(option)) {
      // Selecting "None" clears all other selections.
      onChanged(current.contains(option) ? [] : [option]);
      return;
    }
    // Selecting any real option clears "None" if it was active.
    if (current.contains(option)) {
      current.remove(option);
    } else {
      current.remove(_noneOption);
      current.add(option);
    }
    onChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: label + Bengali sublabel + mandatory marker.
        if (label != null && label!.isNotEmpty) ...[
          _InlineListHeader(
            label: label!,
            subLabel: subLabel,
            isMandatory: isMandatory,
            hasError: hasError,
          ),
          const SizedBox(height: 8),
        ],
        // Option rows.
        for (final option in options) ...[
          _InlineListRow(
            label: option,
            isSelected: selectedValues.contains(option),
            isNone: _isNone(option),
            onTap: () => _toggle(option),
          ),
          const SizedBox(height: 6),
        ],
        // Red error hint below the list.
        if (hasError) ...[
          const SizedBox(height: 2),
          Text(
            'Please select at least one option',
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.statusCritical,
            ),
          ),
        ],
      ],
    );
  }
}

/// Header section for [_InlineListSelectField]: bold English label + muted
/// Bengali sub-label + mandatory `*`.
class _InlineListHeader extends StatelessWidget {
  const _InlineListHeader({
    required this.label,
    this.subLabel,
    this.isMandatory = false,
    this.hasError = false,
  });

  final String label;
  final String? subLabel;
  final bool isMandatory;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: hasError
                      ? AppColors.statusCritical
                      : AppColors.textPrimary,
                  height: 1.25,
                ),
            children: isMandatory
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(
                        color: AppColors.statusCritical,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]
                : null,
          ),
        ),
        if (subLabel != null && subLabel!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subLabel!,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}

/// A single selectable row inside [_InlineListSelectField].
///
/// Unselected: white card with a `1.5px` grey border.
/// Selected (normal): navy-filled card.
/// Selected (none): light grey-filled card with ✓ prefix.
class _InlineListRow extends StatelessWidget {
  const _InlineListRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isNone = false,
  });

  final String label;
  final bool isSelected;
  final bool isNone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;

    if (isNone && isSelected) {
      bg = AppColors.cardSurfaceMuted;
      fg = AppColors.textPrimary;
      border = AppColors.border;
    } else if (isSelected) {
      bg = AppColors.navy;
      fg = AppColors.textOnNavy;
      border = AppColors.navy;
    } else {
      bg = Colors.white;
      fg = AppColors.textPrimary;
      border = AppColors.border;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(_kFieldCardRadius),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isNone && isSelected ? '✓ $label' : label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                  height: 1.3,
                ),
              ),
            ),
            if (isSelected && !isNone)
              Icon(Icons.check_circle_rounded, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}

// ── Submit bar ────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.submitting, required this.onSubmit});

  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xl,
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const Key('unified_form_submit_button'),
            onPressed: submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.pink,
              foregroundColor: AppColors.textOnNavy,
              disabledBackgroundColor: AppColors.pink.withValues(alpha: 0.5),
              disabledForegroundColor: AppColors.textOnNavy,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnNavy,
                    ),
                  )
                : const Text(UnifiedFormStrings.submitLabel),
          ),
        ),
      ),
    );
  }
}
