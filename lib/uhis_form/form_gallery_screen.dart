/// Form Gallery — browses the full form-SDK widget catalog grouped into
/// Vitals, Symptoms, and per-programme form views.
///
/// Accessible as a persistent bottom-nav tab (/gallery) and via the legacy
/// debug route (/dev/form-gallery).
library;

import 'package:flutter/material.dart';

import '../core/constants/app_strings.dart';
import '../core/theme/app_theme.dart';
import 'controller/condition_evaluator.dart';
import 'form_data_service.dart';
import 'models/field_kind.dart';
import 'models/field_schema.dart';
import 'models/form_schema.dart';
import 'widgets/field_renderer.dart';

class FormGalleryScreen extends StatefulWidget {
  const FormGalleryScreen({super.key});

  @override
  State<FormGalleryScreen> createState() => _FormGalleryScreenState();
}

class _FormGalleryScreenState extends State<FormGalleryScreen>
    with TickerProviderStateMixin {
  late final TabController _outerTabs;

  @override
  void initState() {
    super.initState();
    _outerTabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _outerTabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(FormGalleryStrings.screenTitle),
        centerTitle: false,
        bottom: TabBar(
          controller: _outerTabs,
          tabs: const [
            Tab(text: FormGalleryStrings.vitalsTab),
            Tab(text: FormGalleryStrings.symptomsTab),
            Tab(text: FormGalleryStrings.programmesTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _outerTabs,
        children: const [
          _VitalsTab(),
          _SymptomsTab(),
          _ProgrammesTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 1: Vitals
// ═══════════════════════════════════════════════════════════════════════════════

const _vitalsWidgets = [
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'vitalsBundle',
      label: 'Vitals Bundle',
      kind: FieldKind.vitalsBundle,
    ),
    initialValue: {
      'temperature': '37.2',
      'pulse': '78',
      'breathsPerMinute': '18',
      'spo2': '98',
    },
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'bloodPressure',
      label: 'Blood Pressure',
      kind: FieldKind.bloodPressure,
    ),
    initialValue: {'systolicBP': '120', 'diastolicBP': '80'},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'anthropometry',
      label: 'Anthropometry',
      kind: FieldKind.anthropometry,
    ),
    initialValue: {'height': '162', 'weight': '58'},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'bloodGlucose',
      label: 'Blood Glucose',
      kind: FieldKind.bloodGlucose,
    ),
    initialValue: {'glucoseType': 'random', 'glucoseValue': '5.4'},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'muac',
      label: 'MUAC',
      kind: FieldKind.muac,
      unit: 'cm',
    ),
    initialValue: 22.5,
  ),
];

class _VitalsTab extends StatelessWidget {
  const _VitalsTab();

  @override
  Widget build(BuildContext context) {
    return _StaticWidgetList(entries: _vitalsWidgets);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 2: Symptoms
// ═══════════════════════════════════════════════════════════════════════════════

const _symptomsWidgets = [
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'dangerSigns',
      label: 'Danger Signs',
      kind: FieldKind.dangerSigns,
    ),
    initialValue: ['heavyBleeding'],
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'obstetricHistory',
      label: 'Obstetric History',
      kind: FieldKind.obstetricHistory,
    ),
    initialValue: {'gravida': 2, 'parity': 1, 'livingChildren': 1},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'urineTest',
      label: 'Urine Test',
      kind: FieldKind.urineTest,
    ),
    initialValue: {'albumin': '+1', 'sugar': 'nil', 'bilirubin': 'nil'},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'pregnancyProfile',
      label: 'Pregnancy Profile',
      kind: FieldKind.pregnancyProfile,
    ),
    initialValue: {'lmp': '2026-01-15'},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'labResult',
      label: 'Lab Result',
      kind: FieldKind.labResult,
      unit: 'g/dL',
    ),
    initialValue: {'value': 12.5, 'unit': 'g/dL'},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'supplyPair',
      label: 'Supply Pair — Iron–Folic Acid',
      kind: FieldKind.supplyPair,
    ),
    initialValue: {'consumed': 2, 'provided': 3},
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'glassPrescription',
      label: 'Glass Prescription',
      kind: FieldKind.glassPrescription,
    ),
    initialValue: null,
  ),
  _GalleryEntry(
    schema: FieldSchema(
      fieldId: 'referralCard',
      label: 'Referral Card',
      kind: FieldKind.referralCard,
    ),
    initialValue: {
      'urgency': 'urgent',
      'facility': 'District Hospital',
      'reason': 'Pre-eclampsia',
    },
  ),
];

class _SymptomsTab extends StatelessWidget {
  const _SymptomsTab();

  @override
  Widget build(BuildContext context) {
    return _StaticWidgetList(entries: _symptomsWidgets);
  }
}

// ─── Shared static widget list ────────────────────────────────────────────────

class _GalleryEntry {
  const _GalleryEntry({
    required this.schema,
    required this.initialValue,
  });

  final FieldSchema schema;
  final dynamic initialValue;
}

class _StaticWidgetListState extends State<_StaticWidgetList>
    with AutomaticKeepAliveClientMixin {
  late final Map<String, dynamic> _values;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final e in widget.entries)
        if (e.initialValue != null) e.schema.fieldId: e.initialValue,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: widget.entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final entry = widget.entries[i];
        return _GalleryWidgetCard(
          kind: entry.schema.kind,
          child: FieldRenderer(
            key: ValueKey(entry.schema.fieldId),
            schema: entry.schema,
            value: _values[entry.schema.fieldId],
            onChanged: (v) => setState(() {
              if (v == null) {
                _values.remove(entry.schema.fieldId);
              } else {
                _values[entry.schema.fieldId] = v;
              }
            }),
          ),
        );
      },
    );
  }
}

class _StaticWidgetList extends StatefulWidget {
  const _StaticWidgetList({required this.entries});

  final List<_GalleryEntry> entries;

  @override
  State<_StaticWidgetList> createState() => _StaticWidgetListState();
}

// ─── Compact widget card used in Vitals/Symptoms tabs ─────────────────────────

class _GalleryWidgetCard extends StatelessWidget {
  const _GalleryWidgetCard({
    required this.kind,
    required this.child,
  });

  final FieldKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: AppShadows.statBox,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: _KindChip(kind: kind),
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 3: Programmes
// ═══════════════════════════════════════════════════════════════════════════════

class _ProgrammesTab extends StatefulWidget {
  const _ProgrammesTab();

  @override
  State<_ProgrammesTab> createState() => _ProgrammesTabState();
}

class _ProgrammesTabState extends State<_ProgrammesTab>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<FormSchema>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = FormDataService().allSchemas();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<FormSchema>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || !snap.hasData) {
          return Center(
            child: Text(
              snap.error?.toString() ?? 'Failed to load forms',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        final schemas = snap.data!;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: schemas.length,
          itemBuilder: (context, i) =>
              _ProgrammeExpansionTile(schema: schemas[i]),
        );
      },
    );
  }
}

// ─── Programme colour tokens ──────────────────────────────────────────────────

({Color surface, Color border, Color text}) _programmeTokens(String formType) {
  return switch (formType) {
    'anc' ||
    'pncMother' ||
    'pncNeonatal' ||
    'pncChild' ||
    'pwProfile' ||
    'pregnancyOutcome' =>
      (
        surface: AppColors.ancSurface,
        border: AppColors.ancBorder,
        text: AppColors.ancText,
      ),
    'ncd' || 'family_planning' => (
        surface: AppColors.ncdSurface,
        border: AppColors.ncdBorder,
        text: AppColors.ncdText,
      ),
    'cataract' || 'eye_care' => (
        surface: AppColors.pncSurface,
        border: AppColors.pncBorder,
        text: AppColors.pncText,
      ),
    _ => (
        surface: AppColors.tagBlueSurface,
        border: AppColors.border,
        text: AppColors.navy,
      ),
  };
}

class _ProgrammeExpansionTile extends StatelessWidget {
  const _ProgrammeExpansionTile({required this.schema});

  final FormSchema schema;

  @override
  Widget build(BuildContext context) {
    final fieldCount = schema.allFields
        .where((f) => f.kind != FieldKind.sectionHeader)
        .length;
    final tokens = _programmeTokens(schema.formType);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: tokens.border, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        title: Text(
          _formLabel(schema.formType),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: tokens.text,
          ),
        ),
        subtitle: Text(
          '$fieldCount ${FormGalleryStrings.fields}',
          style: TextStyle(fontSize: 11, color: tokens.text.withValues(alpha: 0.6)),
        ),
        childrenPadding: EdgeInsets.zero,
        children: [_GalleryFormPage(schema: schema)],
      ),
    );
  }

  static String _formLabel(String formType) {
    const labels = {
      'anc': 'ANC',
      'ncd': 'NCD',
      'pncMother': 'PNC Mother',
      'pncNeonatal': 'PNC Neonatal',
      'pncChild': 'PNC Child',
      'pwProfile': 'Pregnant Woman Profile',
      'pregnancyOutcome': 'Pregnancy Outcome',
      'household_member_registration': 'Member Registration',
      'household_registration': 'Household Registration',
      'family_planning': 'Family Planning',
      'cataract': 'Cataract',
      'eye_care': 'Eye Care',
      'enrollment': 'Enrollment',
    };
    return labels[formType] ?? formType;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Per-form interactive page (used inside Programmes tab)
// ═══════════════════════════════════════════════════════════════════════════════

class _GalleryFormPage extends StatefulWidget {
  const _GalleryFormPage({required this.schema});

  final FormSchema schema;

  @override
  State<_GalleryFormPage> createState() => _GalleryFormPageState();
}

class _GalleryFormPageState extends State<_GalleryFormPage> {
  final Map<String, dynamic> _values = {};

  void _setValue(String fieldId, dynamic value) {
    setState(() {
      if (value == null) {
        _values.remove(fieldId);
      } else {
        _values[fieldId] = value;
      }
    });
  }

  Map<String, bool> get _visibility =>
      ConditionEvaluator.evaluate(widget.schema, _values);

  @override
  Widget build(BuildContext context) {
    final visibility = _visibility;
    final sections =
        widget.schema.sections.where((s) => s.fields.isNotEmpty).toList();
    final filledCount = _values.length;
    final visibleCount = visibility.values.where((v) => v).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatsBar(
          schema: widget.schema,
          filledCount: filledCount,
          visibleCount: visibleCount,
        ),
        ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          itemCount: sections.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final section = sections[i];
            final visibleFields = section.fields
                .where((f) =>
                    f.kind != FieldKind.sectionHeader &&
                    (visibility[f.fieldId] ?? true))
                .toList();

            return _FormSectionCard(
              title: section.title,
              fields: visibleFields,
              values: _values,
              onChanged: _setValue,
            );
          },
        ),
      ],
    );
  }
}

// ─── Compact section card for form field groups (gallery-local) ───────────────

class _FormSectionCard extends StatelessWidget {
  const _FormSectionCard({
    required this.title,
    required this.fields,
    required this.values,
    required this.onChanged,
  });

  final String title;
  final List<FieldSchema> fields;
  final Map<String, dynamic> values;
  final void Function(String fieldId, dynamic value) onChanged;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header: label in sectionLabel style
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Text(
              title.toUpperCase(),
              style: AppTextStyles.sectionLabel,
            ),
          ),
          // Fields with hairline dividers, no per-field kind chip
          ...List.generate(fields.length * 2 - 1, (idx) {
            if (idx.isOdd) {
              return const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.border,
                indent: 14,
                endIndent: 14,
              );
            }
            final f = fields[idx ~/ 2];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              child: FieldRenderer(
                key: ValueKey(f.fieldId),
                schema: f,
                value: values[f.fieldId],
                onChanged: (v) => onChanged(f.fieldId, v),
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Stats banner ──────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.schema,
    required this.filledCount,
    required this.visibleCount,
  });

  final FormSchema schema;
  final int filledCount;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    final allKinds = schema.allFields
        .where((f) => f.kind != FieldKind.sectionHeader)
        .map((f) => f.kind)
        .toList();

    final kindCounts = <FieldKind, int>{};
    for (final k in allKinds) {
      kindCounts[k] = (kindCounts[k] ?? 0) + 1;
    }

    final topKinds = kindCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = topKinds.take(5).toList();

    return Container(
      color: AppColors.navy.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatPill(
                label: 'sections',
                value: '${schema.sections.length}',
                color: AppColors.navy,
              ),
              const SizedBox(width: 6),
              _StatPill(
                label: 'fields',
                value: '${allKinds.length}',
                color: AppColors.fieldKindGreen,
              ),
              const SizedBox(width: 6),
              _StatPill(
                label: 'visible',
                value: '$visibleCount',
                color: AppColors.fieldKindPurple,
              ),
              const SizedBox(width: 6),
              _StatPill(
                label: 'filled',
                value: '$filledCount',
                color: AppColors.fieldKindOrange,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 3,
            children: shown
                .map((e) => _KindCountChip(kind: e.key, count: e.value))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(
                fontSize: 9,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindCountChip extends StatelessWidget {
  const _KindCountChip({required this.kind, required this.count});

  final FieldKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _kindColor(kind).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.flag),
      ),
      child: Text(
        '${_kindLabel(kind)} ×$count',
        style: TextStyle(
          fontSize: 10,
          color: _kindColor(kind),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Field kind badge ──────────────────────────────────────────────────────────

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final FieldKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kindColor(kind).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.flag),
      ),
      child: Text(
        _kindLabel(kind),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: _kindColor(kind),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Kind metadata ─────────────────────────────────────────────────────────────

String _kindLabel(FieldKind k) => switch (k) {
      FieldKind.textInput => 'TEXT',
      FieldKind.integerInput => 'INT',
      FieldKind.decimalInput => 'DECIMAL',
      FieldKind.datePicker => 'DATE',
      FieldKind.radioGroup => 'RADIO',
      FieldKind.dropdown => 'DROPDOWN',
      FieldKind.chipMultiSelect => 'MULTI',
      FieldKind.toggleSwitch => 'TOGGLE',
      FieldKind.qrScanner => 'QR',
      FieldKind.ageOrDob => 'AGE/DOB',
      FieldKind.ageYmd => 'AGE YMD',
      FieldKind.bloodPressure => 'BP',
      FieldKind.anthropometry => 'ANTHRO',
      FieldKind.bloodGlucose => 'GLUCOSE',
      FieldKind.vitalsBundle => 'VITALS',
      FieldKind.muac => 'MUAC',
      FieldKind.supplyPair => 'SUPPLY',
      FieldKind.dangerSigns => 'DANGER',
      FieldKind.urineTest => 'URINE',
      FieldKind.obstetricHistory => 'OBS HX',
      FieldKind.labResult => 'LAB',
      FieldKind.pregnancyProfile => 'PREG',
      FieldKind.glassPrescription => 'GLASS',
      FieldKind.referralCard => 'REFERRAL',
      FieldKind.computedLabel => 'COMPUTED',
      FieldKind.instruction => 'INFO',
      FieldKind.sectionHeader => 'HEADER',
    };

Color _kindColor(FieldKind k) => switch (k) {
      FieldKind.bloodPressure ||
      FieldKind.vitalsBundle ||
      FieldKind.anthropometry ||
      FieldKind.bloodGlucose =>
        AppColors.fieldKindBlue,
      FieldKind.dangerSigns => AppColors.fieldKindRed,
      FieldKind.supplyPair => AppColors.statusSuccessActionDark,
      FieldKind.urineTest ||
      FieldKind.obstetricHistory ||
      FieldKind.muac ||
      FieldKind.labResult ||
      FieldKind.pregnancyProfile =>
        AppColors.fieldKindViolet,
      FieldKind.glassPrescription || FieldKind.referralCard =>
        AppColors.fieldKindAmber,
      FieldKind.radioGroup ||
      FieldKind.dropdown ||
      FieldKind.chipMultiSelect =>
        AppColors.fieldKindIndigo,
      FieldKind.datePicker ||
      FieldKind.ageOrDob ||
      FieldKind.ageYmd =>
        AppColors.fieldKindTeal,
      FieldKind.computedLabel || FieldKind.instruction => AppColors.fieldKindSlate,
      _ => AppColors.navy,
    };
