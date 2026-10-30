/// Renders a Shukhee consultation's clinical summary (diagnosis, medicines,
/// follow-up) from [ShukheeClinicalData] -- Shukhee's own `appointment.
/// clinicalData`, added per their 2026-09-22 API update. Shared by
/// `TeleconsultScreen`'s wrap-up view (a just-completed live call) and
/// `TeleconsultCallDetailScreen` (a historical call synced in from Frappe) --
/// pulled out of `teleconsult_screen.dart` into its own file (and made
/// public) so both can render the identical card without duplicating it.
library;

import 'package:flutter/material.dart';
import 'package:shukhee_sdk/shukhee_sdk.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';

class ClinicalDataCard extends StatelessWidget {
  const ClinicalDataCard({super.key, required this.data});

  final ShukheeClinicalData data;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget?>[
      _bulletSection(TeleconsultStrings.chiefComplaintsLabel, data.chiefComplaints),
      _bulletSection(TeleconsultStrings.diagnosisLabel, data.diagnosis),
      _bulletSection(TeleconsultStrings.labTestsLabel, data.labTest),
      _bulletSection(TeleconsultStrings.adviceLabel, data.advice),
      _bulletSection(TeleconsultStrings.drugHistoryLabel, data.drugHistory),
      _medicineSection(),
      _mealInstructionSection(),
      _lastVitalSection(),
      _followUpSection(),
    ].whereType<Widget>().toList();

    if (sections.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TeleconsultStrings.clinicalSummaryTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final section in sections) ...[section, const SizedBox(height: AppSpacing.sm)],
        ],
      ),
    );
  }

  Widget? _bulletSection(String label, List<String> items) {
    if (items.isEmpty) return null;
    return _LabeledSection(label: label, child: Text(items.join(', ')));
  }

  Widget? _medicineSection() {
    if (data.medicine.isEmpty) return null;
    return _LabeledSection(
      label: TeleconsultStrings.medicinesLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.medicine.map((m) {
          final name = m.brandName ?? m.genericName ?? '';
          final details = [m.strength, m.dosage, m.frequency, m.instruction]
              .where((v) => v != null && v.isNotEmpty)
              .join(' · ');
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(details.isEmpty ? name : '$name — $details'),
          );
        }).toList(),
      ),
    );
  }

  Widget? _mealInstructionSection() {
    if (data.mealInstruction.isEmpty) return null;
    return _LabeledSection(
      label: TeleconsultStrings.mealInstructionsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.mealInstruction.map((m) {
          final label = [m.mealType, m.instruction].where((v) => v != null && v.isNotEmpty).join(': ');
          return Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(label));
        }).toList(),
      ),
    );
  }

  Widget? _lastVitalSection() {
    final vital = data.lastVital;
    if (vital == null) return null;
    final parts = <String>[
      if (vital.temperature != null) '${vital.temperature}°',
      if (vital.pulseRate != null) '${vital.pulseRate} bpm',
      if (vital.bloodPressure != null) '${vital.bloodPressure} mmHg',
      if (vital.spo2 != null) 'SpO₂ ${vital.spo2}%',
    ];
    if (parts.isEmpty) return null;
    return _LabeledSection(label: TeleconsultStrings.lastVitalsLabel, child: Text(parts.join(' · ')));
  }

  Widget? _followUpSection() {
    final parts = <String>[
      if (data.followUpComment != null && data.followUpComment!.isNotEmpty) data.followUpComment!,
      if (data.followUpDay != null && data.followUpDay!.isNotEmpty) '${data.followUpDay} days',
      if (data.followUpDate != null && data.followUpDate!.isNotEmpty) data.followUpDate!,
    ];
    if (parts.isEmpty) return null;
    return _LabeledSection(label: TeleconsultStrings.followUpLabel, child: Text(parts.join(' · ')));
  }
}

class _LabeledSection extends StatelessWidget {
  const _LabeledSection({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: child),
      ],
    );
  }
}
