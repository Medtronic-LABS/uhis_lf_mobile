/// Referral card composite widget — [FieldKind.referralCard].
///
/// Urgency (3-option traffic-light pill selector) + Facility dropdown + Reason
/// multi-line text field.
/// Value shape: `{"urgency": "urgent", "facility": "PHC Rampur", "reason": "..."}`.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../models/field_schema.dart';
import '../_shared/field_label.dart';
import '../_shared/status_badge.dart';
import '../basic/dropdown_widget.dart';

class ReferralCardWidget extends StatefulWidget {
  const ReferralCardWidget({
    super.key,
    required this.schema,
    required this.onChanged,
    this.value,
    this.readOnly = false,
  });

  final FieldSchema schema;
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<ReferralCardWidget> createState() => _ReferralCardWidgetState();
}

class _ReferralCardWidgetState extends State<ReferralCardWidget> {
  static const _urgencies = [
    (ComposerStrings.referralRoutine,   AppColors.rangeNormal,   AppColors.rangeNormalSurface),
    (ComposerStrings.referralUrgent,    AppColors.rangeElevated, AppColors.rangeElevatedSurface),
    (ComposerStrings.referralEmergency, AppColors.rangeCritical, AppColors.rangeCriticalSurface),
  ];

  String? _urgency;
  String? _facility;
  late final TextEditingController _reasonCtrl;

  @override
  void initState() {
    super.initState();
    final v = widget.value ?? {};
    _urgency  = v['urgency']?.toString();
    _facility = v['facility']?.toString();
    _reasonCtrl = TextEditingController(text: v['reason']?.toString() ?? '');
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged({
      if (_urgency != null) 'urgency': _urgency,
      if (_facility != null) 'facility': _facility,
      if (_reasonCtrl.text.isNotEmpty) 'reason': _reasonCtrl.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SdkFieldLabel(
          schema: widget.schema,
          fallback: ComposerStrings.referralUrgencyLabel,
          trailing: _urgency != null ? _urgencyBadge(_urgency!) : null,
        ),
        const SizedBox(height: 4),
        // Urgency pills
        Row(
          children: [
            for (int i = 0; i < _urgencies.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _UrgencyPill(
                  label: _urgencies[i].$1,
                  color: _urgencies[i].$2,
                  surfaceColor: _urgencies[i].$3,
                  selected: _urgency == _urgencies[i].$1.toLowerCase(),
                  readOnly: widget.readOnly,
                  onTap: () => setState(() {
                    _urgency = _urgencies[i].$1.toLowerCase();
                    _emit();
                  }),
                ),
              ),
            ],
          ],
        ),
        if (widget.schema.options.isNotEmpty) ...[
          const SizedBox(height: 10),
          DropdownWidget(
            schema: FieldSchema(
              fieldId: 'referralFacility',
              label: ComposerStrings.fieldReferPlace,
              kind: widget.schema.kind,
              options: widget.schema.options,
            ),
            value: _facility,
            readOnly: widget.readOnly,
            onChanged: (v) => setState(() {
              _facility = v;
              _emit();
            }),
          ),
        ],
        const SizedBox(height: 10),
        TextFormField(
          controller: _reasonCtrl,
          readOnly: widget.readOnly,
          maxLines: 3,
          style: const TextStyle(
            fontFamily: 'NunitoSans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          decoration: const InputDecoration(
            labelText: 'Reason for referral',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => _emit(),
        ),
      ],
    );
  }

  static Widget _urgencyBadge(String urgencyValue) {
    final match = _urgencies.firstWhere(
      (u) => u.$1.toLowerCase() == urgencyValue,
      orElse: () => (urgencyValue, AppColors.textMuted, AppColors.border),
    );
    return SdkStatusBadge(
      label: match.$1,
      textColor: match.$2,
      surfaceColor: match.$3,
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  const _UrgencyPill({
    required this.label,
    required this.color,
    required this.surfaceColor,
    required this.selected,
    required this.readOnly,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color surfaceColor;
  final bool selected;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: readOnly ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: selected ? surfaceColor : AppColors.cardSurface,
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'NunitoSans',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? color : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
