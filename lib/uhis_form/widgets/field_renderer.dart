/// Dispatches a [FieldSchema] to the correct widget based on [FieldKind].
///
/// Adding a new [FieldKind]:
///   1. Add the enum value in [field_kind.dart].
///   2. Create a widget in [widgets/basic/] or [widgets/healthcare/].
///   3. Add a case in [build] below.
///
/// The switch is exhaustive — a compile error surfaces any unhandled kind.
library;

import 'package:flutter/material.dart';

import '../models/field_kind.dart';
import '../models/field_schema.dart';
import 'basic/age_or_dob_widget.dart';
import 'basic/age_ymd_widget.dart';
import 'basic/chip_multi_select_widget.dart';
import 'basic/computed_label_widget.dart';
import 'basic/date_field_widget.dart';
import 'basic/dropdown_widget.dart';
import 'basic/instruction_widget.dart';
import 'basic/number_field_widget.dart';
import 'basic/radio_group_widget.dart';
import 'basic/text_field_widget.dart';
import 'basic/toggle_widget.dart';
import 'healthcare/anthropometry_widget.dart';
import 'healthcare/blood_glucose_widget.dart';
import 'healthcare/blood_pressure_widget.dart';
import 'healthcare/danger_signs_widget.dart';
import 'healthcare/obstetric_history_widget.dart';
import 'healthcare/supply_pair_widget.dart';
import 'healthcare/urine_test_widget.dart';
import 'healthcare/vitals_bundle_widget.dart';

class FieldRenderer extends StatelessWidget {
  const FieldRenderer({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.aiHint,
    this.readOnly = false,
  });

  final FieldSchema schema;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final dynamic aiHint;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final Widget field = switch (schema.kind) {
      // ── Basic ────────────────────────────────────────────────────────────
      FieldKind.textInput => TextFieldWidget(
          schema: schema,
          value: value?.toString(),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.integerInput => NumberFieldWidget(
          schema: schema,
          decimal: false,
          value: value is num ? value as num : int.tryParse(value?.toString() ?? ''),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.decimalInput => NumberFieldWidget(
          schema: schema,
          decimal: true,
          value: value is num ? value as num : double.tryParse(value?.toString() ?? ''),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.datePicker => DateFieldWidget(
          schema: schema,
          value: value?.toString(),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.radioGroup => RadioGroupWidget(
          schema: schema,
          value: value?.toString(),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.dropdown => DropdownWidget(
          schema: schema,
          value: value?.toString(),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.chipMultiSelect => ChipMultiSelectWidget(
          schema: schema,
          value: value is List ? value as List : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.toggleSwitch => ToggleWidget(
          schema: schema,
          value: value is bool ? value as bool : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.ageOrDob => AgeOrDobWidget(
          schema: schema,
          value: value?.toString(),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.ageYmd => AgeYmdWidget(
          schema: schema,
          value: value?.toString(),
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.qrScanner => _QrPlaceholder(schema: schema),

      // ── Healthcare composites ────────────────────────────────────────────
      FieldKind.bloodPressure => BloodPressureWidget(
          schema: schema,
          value: value is Map<String, dynamic> ? value as Map<String, dynamic> : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.anthropometry => AnthropometryWidget(
          schema: schema,
          value: value is Map<String, dynamic> ? value as Map<String, dynamic> : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.bloodGlucose => BloodGlucoseWidget(
          schema: schema,
          value: value is Map<String, dynamic> ? value as Map<String, dynamic> : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.vitalsBundle => VitalsBundleWidget(
          schema: schema,
          value: value is Map<String, dynamic> ? value as Map<String, dynamic> : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.supplyPair => SupplyPairWidget(
          schema: schema,
          value: value is Map<String, dynamic> ? value as Map<String, dynamic> : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.dangerSigns => DangerSignsWidget(
          schema: schema,
          value: value is List ? value as List : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.urineTest => UrineTestWidget(
          schema: schema,
          value: value is Map<String, dynamic> ? value as Map<String, dynamic> : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),
      FieldKind.obstetricHistory => ObstetricHistoryWidget(
          schema: schema,
          value: value is Map<String, dynamic> ? value as Map<String, dynamic> : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),

      // Tier-2 composites — rendered as text inputs until widgets are built
      FieldKind.muac ||
      FieldKind.labResult ||
      FieldKind.pregnancyProfile ||
      FieldKind.glassPrescription ||
      FieldKind.referralCard =>
        NumberFieldWidget(
          schema: schema,
          decimal: true,
          value: value is num ? value as num : null,
          onChanged: (v) => onChanged(v),
          readOnly: readOnly,
        ),

      // ── Display only ─────────────────────────────────────────────────────
      FieldKind.computedLabel => ComputedLabelWidget(
          schema: schema,
          value: value,
        ),
      FieldKind.instruction => InstructionWidget(schema: schema),
      FieldKind.sectionHeader => const SizedBox.shrink(),
    };

    // Wrap with AI hint badge if Scribe pre-filled this field
    if (aiHint != null) {
      return _AiHintWrapper(child: field);
    }
    return field;
  }
}

/// Temporary QR scanner placeholder — shows a tap-to-scan button.
class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder({required this.schema});

  final FieldSchema schema;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          schema.label,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.qr_code_scanner, size: 18),
          label: const Text('Scan QR code'),
        ),
      ],
    );
  }
}

/// Wraps a field with a subtle AI-pre-fill indicator.
class _AiHintWrapper extends StatelessWidget {
  const _AiHintWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF6B63D4),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
