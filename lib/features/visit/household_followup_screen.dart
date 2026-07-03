/// Household follow-up prompt shown after accepting the Step 3 care plan.
///
/// Lets the SK quickly check whether other household members need care
/// while they are already at the household. Tapping a patient card navigates
/// to [PatientContextScreen] via [onViewPatient]; the "Done" button fires
/// [onDone] which takes the SK to the dashboard or task list.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/patient_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/risk.dart';
import '../../core/theme/app_theme.dart';

class HouseholdFollowUpScreen extends StatefulWidget {
  const HouseholdFollowUpScreen({
    super.key,
    required this.householdId,
    required this.excludePatientId,
    required this.onDone,
    required this.onViewPatient,
  });

  final String householdId;
  final String excludePatientId;

  /// Called when the SK taps "Done — go to home".
  final VoidCallback onDone;

  /// Called with the selected [patientId] when the SK taps "View patient".
  final void Function(String patientId) onViewPatient;

  @override
  State<HouseholdFollowUpScreen> createState() =>
      _HouseholdFollowUpScreenState();
}

class _HouseholdFollowUpScreenState extends State<HouseholdFollowUpScreen> {
  List<Patient>? _members;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dao = context.read<PatientDao>();
    final rows = await dao.getByHouseholdId(widget.householdId);
    final members = rows
        .map(Patient.fromDb)
        .where((p) => p.id != widget.excludePatientId)
        .where((p) => p.isActive != false)
        .toList()
      ..sort(_byUrgency);
    if (mounted) setState(() => _members = members);
  }

  static int _byUrgency(Patient a, Patient b) {
    final bandA = a.riskBand?.index ?? Band.band4.index;
    final bandB = b.riskBand?.index ?? Band.band4.index;
    if (bandA != bandB) return bandA.compareTo(bandB);
    final dueA = a.nextDueAt ?? double.maxFinite.toInt();
    final dueB = b.nextDueAt ?? double.maxFinite.toInt();
    return dueA.compareTo(dueB);
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text(HouseholdFollowUpStrings.title),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: widget.onDone,
        ),
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Subtitle strip
          Container(
            color: AppColors.navy,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: const Text(
              HouseholdFollowUpStrings.subtitle,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),

          // Member list
          Expanded(
            child: members == null
                ? const Center(child: CircularProgressIndicator())
                : members.isEmpty
                    ? _EmptyState(onDone: widget.onDone)
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: members.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _MemberCard(
                          patient: members[i],
                          onView: () => widget.onViewPatient(members[i].id),
                        ),
                      ),
          ),

          // Done footer
          if (members != null && members.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: widget.onDone,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      HouseholdFollowUpStrings.doneButton,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.home_rounded, size: 56, color: AppColors.border),
          const SizedBox(height: 16),
          const Text(
            HouseholdFollowUpStrings.emptyState,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(HouseholdFollowUpStrings.doneButton),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Member card ───────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.patient, required this.onView});
  final Patient patient;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final urgencyChip = _urgencyChip(patient);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tokens.divider),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: _bandColor(patient.riskBand).withValues(alpha: 0.15),
            child: Text(
              (patient.name ?? '?').characters.first.toUpperCase(),
              style: TextStyle(
                color: _bandColor(patient.riskBand),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + age + urgency
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name ?? '—',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (patient.age != null)
                      Text(
                        '${patient.age}y',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    if (patient.age != null && urgencyChip != null)
                      const SizedBox(width: 6),
                    if (urgencyChip != null) urgencyChip,
                  ],
                ),
              ],
            ),
          ),

          // CTA
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text(
              HouseholdFollowUpStrings.viewPatient,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _bandColor(Band? band) => switch (band) {
        Band.band1 => AppColors.rangeCritical,
        Band.band2 => AppColors.statusWarning,
        Band.band3 => AppColors.navy,
        _ => AppColors.textMuted,
      };

  Widget? _urgencyChip(Patient p) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = p.nextDueAt;

    String? label;
    Color? bg;
    Color? fg;

    if (p.riskBand == Band.band1 || p.riskBand == Band.band2) {
      label = HouseholdFollowUpStrings.urgentLabel;
      bg = AppColors.rangeCritical.withValues(alpha: 0.12);
      fg = AppColors.rangeCritical;
    } else if (due != null && due < now) {
      label = HouseholdFollowUpStrings.overdue;
      bg = AppColors.statusWarning.withValues(alpha: 0.12);
      fg = AppColors.statusWarning;
    } else if (due != null && due < now + const Duration(days: 1).inMilliseconds) {
      label = HouseholdFollowUpStrings.dueToday;
      bg = AppColors.navy.withValues(alpha: 0.10);
      fg = AppColors.navy;
    } else if (due != null && due < now + const Duration(days: 7).inMilliseconds) {
      label = HouseholdFollowUpStrings.dueSoon;
      bg = AppColors.border;
      fg = AppColors.textMuted;
    }

    if (label == null || bg == null || fg == null) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
