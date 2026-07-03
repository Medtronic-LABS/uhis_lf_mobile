/// Household follow-up prompt shown after accepting the Step 3 care plan.
///
/// Lets the SK check whether other household members need care while they
/// are already at the household. Shows a purpose-built [_HouseholdMemberCard]
/// for each member — not the full worklist card — since the context here is
/// "while you're at this household" rather than a ranked mission queue.
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

  /// Called with the selected [patientId] when the SK taps a member card.
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

    debugPrint(
      '[HouseholdFollowUp] householdId=${widget.householdId} '
      'members=${members.length} '
      'ids=${members.map((p) => p.id).join(',')}',
    );

    final ids = members.map((p) => p.id).toList();
    final progMap = await progDao.programmesForMany(ids);

    debugPrint(
      '[HouseholdFollowUp] progMap entries: '
      '${progMap.entries.map((e) => "${e.key}:${e.value.map((p) => p.wireTag).join(",")}").join(" | ")}',
    );

    final entries = members.map((p) {
      // If no programme data synced for this member, show "Scheduled Visit"
      // so the card always has a visit-type label rather than being blank.
      final progs = progMap[p.id]?.isNotEmpty == true
          ? progMap[p.id]!
          : <Programme>{Programme.unknown};
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
      backgroundColor: const Color(0xFFF4F6FA),
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
                        padding: const EdgeInsets.only(top: 12, bottom: 8),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => _HouseholdMemberCard(
                          entry: entries[i],
                          onTap: () => widget.onViewPatient(entries[i].patientId),
                        ),
                      ),
          ),

          // Done footer
          if (entries != null && entries.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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

// ── Member card ───────────────────────────────────────────────────────────────

class _HouseholdMemberCard extends StatelessWidget {
  const _HouseholdMemberCard({required this.entry, required this.onTap});

  final WorklistEntry entry;
  final VoidCallback onTap;

  static (Color bg, Color fg, IconData icon) _programmeStyle(Programme p) {
    switch (p) {
      case Programme.anc:
        return (AppColors.ancSurface, AppColors.ancText, Icons.pregnant_woman_rounded);
      case Programme.pnc:
        return (AppColors.pncSurface, AppColors.pncText, Icons.pregnant_woman_rounded);
      case Programme.ncd:
        return (AppColors.ncdSurface, AppColors.ncdText, Icons.monitor_heart_outlined);
      case Programme.imci:
        return (AppColors.imciSurface, AppColors.imciText, Icons.child_care_rounded);
      case Programme.tb:
        return (AppColors.tbSurface, AppColors.tbText, Icons.sick_outlined);
      case Programme.epi:
        return (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), Icons.vaccines_rounded);
      case Programme.nutrition:
        return (const Color(0xFFF0FDF4), const Color(0xFF15803D), Icons.restaurant_rounded);
      case Programme.familyPlanning:
        return (AppColors.pncSurface, AppColors.pncText, Icons.family_restroom_rounded);
      default:
        return (const Color(0xFFF1F5F9), const Color(0xFF475569), Icons.calendar_today_rounded);
    }
  }

  static String _visitLabel(Programme p) {
    switch (p) {
      case Programme.anc:           return 'ANC Visit needed';
      case Programme.pnc:           return 'PNC Visit needed';
      case Programme.ncd:           return 'NCD Check needed';
      case Programme.imci:          return 'Child Visit needed';
      case Programme.tb:            return 'TB Check needed';
      case Programme.epi:           return 'Vaccination due';
      case Programme.nutrition:     return 'Nutrition check';
      case Programme.familyPlanning: return 'FP visit needed';
      default:                       return 'Visit scheduled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final programme = entry.programmes.firstOrNull ?? Programme.unknown;
    final (bg, fg, icon) = _programmeStyle(programme);
    final visitLabel = _visitLabel(programme);

    final now = DateTime.now();
    final due = entry.nextDueAt;
    final overdueDays = due != null ? now.difference(due).inDays : -1;
    final isDueToday = due != null &&
        overdueDays <= 0 &&
        due.year == now.year &&
        due.month == now.month &&
        due.day == now.day;
    final daysUntilDue = due != null && !isDueToday && overdueDays < 0
        ? due.difference(now).inDays + 1
        : -1;

    final ageParts = <String>[];
    if (entry.age != null) ageParts.add('${entry.age} yrs');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left programme accent stripe
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: fg,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(13),
                        bottomLeft: Radius.circular(13),
                      ),
                    ),
                  ),

                  // Card content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: programme badge + due chip
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Programme badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: 12, color: fg),
                                    const SizedBox(width: 4),
                                    Text(
                                      visitLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: fg,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // Due / overdue chip
                              if (overdueDays > 0)
                                _DueChip(
                                  label: overdueDays == 1
                                      ? 'Overdue 1d'
                                      : 'Overdue ${overdueDays}d',
                                  level: overdueDays > 7 ? _DueLevel.critical : _DueLevel.warning,
                                )
                              else if (isDueToday)
                                const _DueChip(
                                  label: 'Due today',
                                  level: _DueLevel.warning,
                                )
                              else if (daysUntilDue >= 0 && daysUntilDue <= 7)
                                _DueChip(
                                  label: 'Due in ${daysUntilDue}d',
                                  level: _DueLevel.info,
                                ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Patient name
                          Text(
                            entry.displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),

                          // Demographics
                          if (ageParts.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              ageParts.join(' · '),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                                height: 1.3,
                              ),
                            ),
                          ],

                          const SizedBox(height: 10),

                          // Open patient CTA — right-aligned, programme color
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                HouseholdFollowUpStrings.viewPatient,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: fg,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Due chip ─────────────────────────────────────────────────────────────────

enum _DueLevel { critical, warning, info }

class _DueChip extends StatelessWidget {
  const _DueChip({required this.label, required this.level});
  final String label;
  final _DueLevel level;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (level) {
      _DueLevel.critical => (
          const Color(0xFFFEF2F2),
          const Color(0xFFDC2626),
          Icons.warning_rounded,
        ),
      _DueLevel.warning => (
          const Color(0xFFFFFBEB),
          const Color(0xFFD97706),
          Icons.schedule_rounded,
        ),
      _DueLevel.info => (
          const Color(0xFFF0F9FF),
          const Color(0xFF0369A1),
          Icons.schedule_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.2,
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
