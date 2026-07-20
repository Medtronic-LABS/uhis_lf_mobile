import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class ChildAssessmentData {
  ChildAssessmentData({
    this.congenitalDefect,
    this.weightKg,
    this.isBreastfeeding,
    this.additionalFoodLast24h,
    this.vaccinesReceived,
    this.dewormingTaken,
    this.anyIllness,
    List<String>? complications,
    this.referralMade,
    this.referralPlace,
  }) : complications = complications ?? const [];

  bool? congenitalDefect;
  double? weightKg;
  bool? isBreastfeeding;
  bool? additionalFoodLast24h;
  bool? vaccinesReceived;
  bool? dewormingTaken;
  bool? anyIllness;
  List<String> complications;
  bool? referralMade;
  String? referralPlace;

  ChildAssessmentData copyWith({
    bool? congenitalDefect,
    double? weightKg,
    bool? isBreastfeeding,
    bool? additionalFoodLast24h,
    bool? vaccinesReceived,
    bool? dewormingTaken,
    bool? anyIllness,
    List<String>? complications,
    bool? referralMade,
    String? referralPlace,
    bool clearReferralPlace = false,
  }) =>
      ChildAssessmentData(
        congenitalDefect: congenitalDefect ?? this.congenitalDefect,
        weightKg: weightKg ?? this.weightKg,
        isBreastfeeding: isBreastfeeding ?? this.isBreastfeeding,
        additionalFoodLast24h:
            additionalFoodLast24h ?? this.additionalFoodLast24h,
        vaccinesReceived: vaccinesReceived ?? this.vaccinesReceived,
        dewormingTaken: dewormingTaken ?? this.dewormingTaken,
        anyIllness: anyIllness ?? this.anyIllness,
        complications: complications ?? this.complications,
        referralMade: referralMade ?? this.referralMade,
        referralPlace: clearReferralPlace ? null : (referralPlace ?? this.referralPlace),
      );

  Map<String, dynamic> toJson() => {
        if (congenitalDefect != null) 'congenitalDefect': congenitalDefect,
        if (weightKg != null) 'weightKg': weightKg,
        if (isBreastfeeding != null) 'isBreastfeeding': isBreastfeeding,
        if (additionalFoodLast24h != null)
          'additionalFoodLast24h': additionalFoodLast24h,
        if (vaccinesReceived != null) 'vaccinesReceived': vaccinesReceived,
        if (dewormingTaken != null) 'dewormingTaken': dewormingTaken,
        if (anyIllness != null) 'anyIllness': anyIllness,
        if (complications.isNotEmpty) 'complications': complications,
        if (referralMade != null) 'referralMade': referralMade,
        if (referralPlace != null) 'referralPlace': referralPlace,
      };
}

// ── Widget ────────────────────────────────────────────────────────────────────

/// Child-specific assessment questions (Q6–Q15) shown in Step 1 of the visit
/// flow when the patient is under 5 and at least one symptom has been selected.
///
/// Mirrors screens s23 / s24 of the Apon Sushashthya v13 prototype.
class ChildAssessmentSection extends StatefulWidget {
  const ChildAssessmentSection({
    super.key,
    required this.data,
    required this.onChanged,
  });

  final ChildAssessmentData data;
  final ValueChanged<ChildAssessmentData> onChanged;

  @override
  State<ChildAssessmentSection> createState() => _ChildAssessmentSectionState();
}

class _ChildAssessmentSectionState extends State<ChildAssessmentSection> {
  final _weightCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.data.weightKg != null) {
      _weightCtrl.text = widget.data.weightKg!.toString();
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  void _emit(ChildAssessmentData updated) => widget.onChanged(updated);

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.childSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.childBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              const Text('📋', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                ChildAssessmentStrings.sectionTitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Q6: Congenital defect
          _YesNoQuestion(
            label: ChildAssessmentStrings.q6Label,
            value: d.congenitalDefect,
            onChanged: (v) => _emit(d.copyWith(congenitalDefect: v)),
          ),
          const SizedBox(height: 14),

          // Q7: Weight
          _WeightField(
            controller: _weightCtrl,
            onChanged: (v) {
              final parsed = double.tryParse(v);
              _emit(d.copyWith(weightKg: parsed));
            },
          ),
          const SizedBox(height: 14),

          // Q8: Breastfeeding
          _YesNoQuestion(
            label: ChildAssessmentStrings.q8Label,
            value: d.isBreastfeeding,
            onChanged: (v) => _emit(d.copyWith(isBreastfeeding: v)),
          ),
          const SizedBox(height: 14),

          // Q9: Additional food last 24h
          _YesNoQuestion(
            label: ChildAssessmentStrings.q9Label,
            value: d.additionalFoodLast24h,
            onChanged: (v) => _emit(d.copyWith(additionalFoodLast24h: v)),
          ),
          const SizedBox(height: 14),

          // Q10: Received vaccines
          _YesNoQuestion(
            label: ChildAssessmentStrings.q10Label,
            value: d.vaccinesReceived,
            onChanged: (v) => _emit(d.copyWith(vaccinesReceived: v)),
          ),
          const SizedBox(height: 14),

          // Q11: Deworming
          _YesNoQuestion(
            label: ChildAssessmentStrings.q11Label,
            value: d.dewormingTaken,
            onChanged: (v) => _emit(d.copyWith(dewormingTaken: v)),
          ),
          const SizedBox(height: 14),

          // Q12: Any illness/complications
          _YesNoQuestion(
            label: ChildAssessmentStrings.q12Label,
            value: d.anyIllness,
            onChanged: (v) => _emit(
              d.copyWith(
                anyIllness: v,
                complications: v == true ? d.complications : [],
              ),
            ),
          ),

          // Q13: Complication chips — conditional on Q12 = Yes
          if (d.anyIllness == true) ...[
            const SizedBox(height: 14),
            _ComplicationPicker(
              selected: d.complications,
              onChanged: (chips) => _emit(d.copyWith(complications: chips)),
            ),
          ],
          const SizedBox(height: 14),

          // Q14: Referral made
          _YesNoQuestion(
            label: ChildAssessmentStrings.q14Label,
            value: d.referralMade,
            onChanged: (v) => _emit(
              d.copyWith(
                referralMade: v,
                clearReferralPlace: v == false,
              ),
            ),
          ),

          // Q15: Referral place — conditional on Q14 = Yes
          if (d.referralMade == true) ...[
            const SizedBox(height: 14),
            _ReferralPlacePicker(
              value: d.referralPlace,
              onChanged: (place) => _emit(d.copyWith(referralPlace: place)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _YesNoQuestion extends StatelessWidget {
  const _YesNoQuestion({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _ToggleChip(
                label: ChildAssessmentStrings.yesOption,
                selected: value == true,
                onTap: () => onChanged(true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ToggleChip(
                label: ChildAssessmentStrings.noOption,
                selected: value == false,
                onTap: () => onChanged(false),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? AppColors.navy : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1.5,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF9CA3AF),
          ),
        ),
      ),
    );
  }
}

class _WeightField extends StatelessWidget {
  const _WeightField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: ChildAssessmentStrings.q7Label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
              ],
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: ChildAssessmentStrings.q7Hint,
                hintStyle: const TextStyle(
                    fontSize: 13, color: Color(0xFF9CA3AF)),
                contentPadding: const EdgeInsets.fromLTRB(12, 10, 40, 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.navy),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Text(
                ChildAssessmentStrings.q7Unit,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ComplicationPicker extends StatelessWidget {
  const _ComplicationPicker({
    required this.selected,
    required this.onChanged,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: ChildAssessmentStrings.q13Label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          ChildAssessmentStrings.q13SelectAll,
          style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: ChildAssessmentStrings.complicationOptions.map((option) {
            final active = selected.contains(option);
            return GestureDetector(
              onTap: () {
                final next = List<String>.from(selected);
                if (active) {
                  next.remove(option);
                } else {
                  next.add(option);
                }
                onChanged(next);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFEEF0FF) : Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF6B63D4)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Text(
                  option,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? const Color(0xFF3D3599)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ReferralPlacePicker extends StatelessWidget {
  const _ReferralPlacePicker({
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: ChildAssessmentStrings.q15Label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: value,
          hint: const Text(
            'Select…',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
          onChanged: onChanged,
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.navy),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          items: ChildAssessmentStrings.referralPlaces
              .map((place) => DropdownMenuItem(value: place, child: Text(place)))
              .toList(),
        ),
      ],
    );
  }
}
