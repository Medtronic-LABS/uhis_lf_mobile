/// Household follow-up prompt shown after accepting the Step 3 care plan.
///
/// Lets the SK check whether other household members need care while they
/// are already at the household. Uses [WorklistCard] — same card widget as
/// the main worklist — so the UI is immediately familiar.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/programme.dart';
import '../../core/models/risk.dart';
import '../../core/models/worklist_entry.dart';
import '../../core/theme/app_theme.dart';
import '../worklist/widgets/worklist_card.dart';

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
  List<WorklistEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final patientDao = context.read<PatientDao>();
    final progDao = context.read<PatientProgrammesDao>();

    final rows = await patientDao.getByHouseholdId(widget.householdId);
    final members = rows
        .map(Patient.fromDb)
        .where((p) => p.id != widget.excludePatientId)
        .where((p) => p.isActive != false)
        .toList();

    final ids = members.map((p) => p.id).toList();
    final progMap = await progDao.programmesForMany(ids);

    final entries = members.map((p) {
      final progs = progMap[p.id] ?? <Programme>{};
      final due = p.nextDueAt != null
          ? DateTime.fromMillisecondsSinceEpoch(p.nextDueAt!)
          : null;
      final last = p.lastVisitAt != null
          ? DateTime.fromMillisecondsSinceEpoch(p.lastVisitAt!)
          : null;
      return WorklistEntry(
        patientId: p.id,
        displayName: p.name ?? '—',
        age: p.age,
        householdNo: p.householdId,
        programmes: progs,
        band: p.riskBand ?? Band.band4,
        modifier: p.riskModifier ?? Modifier.none,
        reasons: p.riskReasons,
        nextDueAt: due,
        lastVisitAt: last,
      );
    }).toList()
      ..sort(_byUrgency);

    if (mounted) setState(() => _entries = entries);
  }

  static int _byUrgency(WorklistEntry a, WorklistEntry b) {
    final bandCmp = a.band.index.compareTo(b.band.index);
    if (bandCmp != 0) return bandCmp;
    final dueA = a.nextDueAt?.millisecondsSinceEpoch ?? double.maxFinite.toInt();
    final dueB = b.nextDueAt?.millisecondsSinceEpoch ?? double.maxFinite.toInt();
    return dueA.compareTo(dueB);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

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
            child: entries == null
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? _EmptyState(onDone: widget.onDone)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => WorklistCard(
                          entry: entries[i],
                          onTap: () => widget.onViewPatient(entries[i].patientId),
                        ),
                      ),
          ),

          // Done footer
          if (entries != null && entries.isNotEmpty)
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
