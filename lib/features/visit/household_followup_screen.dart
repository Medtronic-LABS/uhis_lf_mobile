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
import '../../core/db/patient_programmes_dao.dart';
import '../../core/models/patient.dart';
import '../../core/models/programme.dart';
import '../../core/models/risk.dart';
import '../../core/theme/app_theme.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

typedef _MemberEntry = ({Patient patient, Set<Programme> programmes});

String _programmeLabel(Programme p) => switch (p) {
      Programme.anc => 'ANC Check',
      Programme.pnc => 'PNC Visit',
      Programme.ncd => 'NCD Check',
      Programme.imci => 'Child Health',
      Programme.tb => 'TB Follow-up',
      Programme.epi => 'Immunisation',
      Programme.nutrition => 'Nutrition',
      Programme.familyPlanning => 'Family Planning',
      Programme.cataract => 'Cataract',
      Programme.eyeCare => 'Eye Care',
      _ => p.wireTag,
    };

// ── Screen ────────────────────────────────────────────────────────────────────

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
  List<_MemberEntry>? _entries;

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

    final progMap = await progDao.programmesForMany(
      members.map((p) => p.id).toList(),
    );

    final entries = members
        .map((p) => (patient: p, programmes: progMap[p.id] ?? <Programme>{}))
        .toList()
      ..sort(_byUrgency);

    if (mounted) setState(() => _entries = entries);
  }

  static int _byUrgency(_MemberEntry a, _MemberEntry b) {
    final bandA = a.patient.riskBand?.index ?? Band.band4.index;
    final bandB = b.patient.riskBand?.index ?? Band.band4.index;
    if (bandA != bandB) return bandA.compareTo(bandB);
    final dueA = a.patient.nextDueAt ?? double.maxFinite.toInt();
    final dueB = b.patient.nextDueAt ?? double.maxFinite.toInt();
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
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _MemberCard(
                          entry: entries[i],
                          onView: () =>
                              widget.onViewPatient(entries[i].patient.id),
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

// ── Member card ───────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.entry, required this.onView});
  final _MemberEntry entry;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final patient = entry.patient;
    final programmes = entry.programmes
        .where((p) => p != Programme.unknown)
        .toList();
    final urgencyChip = _urgencyChip(patient);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: tokens.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + name/age/urgency + CTA
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    _bandColor(patient.riskBand).withValues(alpha: 0.15),
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
              TextButton(
                onPressed: onView,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text(
                  HouseholdFollowUpStrings.viewPatient,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),

          // Programme pills — shown when the patient has enrolled programmes
          if (programmes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: programmes
                  .map((p) => _ProgrammePill(programme: p))
                  .toList(),
            ),
          ],
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
    } else if (due != null &&
        due < now + const Duration(days: 1).inMilliseconds) {
      label = HouseholdFollowUpStrings.dueToday;
      bg = AppColors.navy.withValues(alpha: 0.10);
      fg = AppColors.navy;
    } else if (due != null &&
        due < now + const Duration(days: 7).inMilliseconds) {
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
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ── Programme pill ────────────────────────────────────────────────────────────

class _ProgrammePill extends StatelessWidget {
  const _ProgrammePill({required this.programme});
  final Programme programme;

  Color _pillColor(Programme p) => switch (p) {
        Programme.anc || Programme.pnc => AppColors.ancHeader,
        Programme.ncd => AppColors.ncdHeader,
        Programme.imci => AppColors.imciHeader,
        Programme.tb => AppColors.tbHeader,
        _ => AppColors.navy,
      };

  @override
  Widget build(BuildContext context) {
    final color = _pillColor(programme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _programmeLabel(programme),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
