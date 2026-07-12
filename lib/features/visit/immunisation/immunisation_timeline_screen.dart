import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/immunisation_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/theme/app_theme.dart';
import 'epi_schedule_engine.dart';

class ImmunisationTimelineScreen extends StatefulWidget {
  const ImmunisationTimelineScreen({
    super.key,
    required this.patientId,
    this.patientName,
    this.dob,
  });

  final String patientId;
  final String? patientName;

  /// DOB as ISO-8601 string — nullable for defensive handling.
  final String? dob;

  @override
  State<ImmunisationTimelineScreen> createState() =>
      _ImmunisationTimelineScreenState();
}

class _ImmunisationTimelineScreenState
    extends State<ImmunisationTimelineScreen> {
  List<VaccineMilestone>? _milestones;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final immunisationDao = context.read<ImmunisationDao>();

    DateTime? dob;
    if (widget.dob != null && widget.dob!.isNotEmpty) {
      dob = DateTime.tryParse(widget.dob!);
    }
    if (dob == null) {
      // Try loading from patient DAO
      final patientDao = context.read<PatientDao>();
      final patient = await patientDao.byId(widget.patientId);
      if (patient?.dob != null) dob = DateTime.tryParse(patient!.dob!);
    }
    if (dob == null) {
      setState(() {
        _error = EpiStrings.noDobError;
        _loading = false;
      });
      return;
    }

    try {
      final rowMap =
          await immunisationDao.forMany([widget.patientId]);
      final rows = rowMap[widget.patientId] ?? [];
      final milestones = await EpiScheduleEngine.build(
        dob: dob,
        rows: rows,
      );
      if (mounted) {
        setState(() {
          _milestones = milestones;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int get _overdueCount =>
      (_milestones ?? [])
          .expand((m) => m.vaccines)
          .where((v) => v.isOverdue || v.status == VaccineStatus.dueNow)
          .length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(widget.patientName ?? EpiStrings.screenTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                )
              : _buildTimeline(),
    );
  }

  Widget _buildTimeline() {
    final milestones = _milestones!;
    final overdue = _overdueCount;

    return CustomScrollView(
      slivers: [
        if (overdue > 0)
          SliverToBoxAdapter(
            child: _OverdueBanner(count: overdue),
          ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _MilestoneCard(
              milestone: milestones[index],
              onUpdateStatus: (vaccine) => _showUpdateSheet(vaccine),
            ),
            childCount: milestones.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Future<void> _showUpdateSheet(VaccineEntry vaccine) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _UpdateStatusSheet(
        vaccine: vaccine,
        patientId: widget.patientId,
        onRecorded: (_) {
          // Reload after recording
          setState(() => _loading = true);
          _load();
        },
      ),
    );
  }
}

// ── Overdue banner ────────────────────────────────────────────────────────────

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              EpiStrings.overdueBanner(count),
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Milestone card ────────────────────────────────────────────────────────────

class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.milestone,
    required this.onUpdateStatus,
  });

  final VaccineMilestone milestone;
  final void Function(VaccineEntry) onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Milestone header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                _MilestoneStatusIcon(milestone: milestone),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    milestone.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                Text(
                  _formatDate(milestone.scheduledDate),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14),
          // Vaccine rows
          ...milestone.vaccines.map(
            (v) => _VaccineRow(
              vaccine: v,
              onUpdateStatus: () => onUpdateStatus(v),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_monthShort(d.month)} ${d.year}';

  String _monthShort(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

class _MilestoneStatusIcon extends StatelessWidget {
  const _MilestoneStatusIcon({required this.milestone});
  final VaccineMilestone milestone;

  @override
  Widget build(BuildContext context) {
    if (milestone.allCompleted) {
      return const CircleAvatar(
        radius: 12,
        backgroundColor: Color(0xFF16A34A),
        child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
      );
    }
    final hasOverdue = milestone.overdueCount > 0 || milestone.dueNowCount > 0;
    if (hasOverdue) {
      return const CircleAvatar(
        radius: 12,
        backgroundColor: Color(0xFFDC2626),
        child: Icon(Icons.priority_high_rounded, size: 14, color: Colors.white),
      );
    }
    return CircleAvatar(
      radius: 12,
      backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
      child: const Icon(Icons.schedule_rounded,
          size: 14, color: Color(0xFFF59E0B)),
    );
  }
}

class _VaccineRow extends StatelessWidget {
  const _VaccineRow({
    required this.vaccine,
    required this.onUpdateStatus,
  });

  final VaccineEntry vaccine;
  final VoidCallback onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = _statusStyle(vaccine.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vaccine.display,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: vaccine.status == VaccineStatus.locked
                        ? AppColors.textMuted
                        : AppColors.navy,
                  ),
                ),
                if (vaccine.givenDate != null)
                  Text(
                    '${EpiStrings.givenOn} ${_formatDate(vaccine.givenDate!)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (vaccine.status == VaccineStatus.dueNow)
            _UpdateCta(onTap: onUpdateStatus),
          if (vaccine.status != VaccineStatus.dueNow)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  (Color, IconData, String) _statusStyle(VaccineStatus s) {
    switch (s) {
      case VaccineStatus.completed:
        return (
          const Color(0xFF16A34A),
          Icons.check_circle_rounded,
          EpiStrings.statusCompleted,
        );
      case VaccineStatus.dueNow:
        return (
          const Color(0xFFDC2626),
          Icons.error_outline_rounded,
          EpiStrings.statusDueNow,
        );
      case VaccineStatus.upcoming:
        return (
          const Color(0xFFF59E0B),
          Icons.schedule_rounded,
          EpiStrings.statusUpcoming,
        );
      case VaccineStatus.notYetDue:
        return (
          AppColors.textMuted,
          Icons.radio_button_unchecked_rounded,
          EpiStrings.statusNotYetDue,
        );
      case VaccineStatus.locked:
        return (
          AppColors.textMuted,
          Icons.lock_outline_rounded,
          EpiStrings.statusLocked,
        );
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_monthShort(d.month)} ${d.year}';

  String _monthShort(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

class _UpdateCta extends StatelessWidget {
  const _UpdateCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.pink,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          EpiStrings.updateStatusCta,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Update status bottom sheet ────────────────────────────────────────────────

class _UpdateStatusSheet extends StatefulWidget {
  const _UpdateStatusSheet({
    required this.vaccine,
    required this.patientId,
    required this.onRecorded,
  });

  final VaccineEntry vaccine;
  final String patientId;
  final void Function(DateTime givenDate) onRecorded;

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  DateTime _givenDate = DateTime.now();
  bool _isMissed = false;
  bool _saving = false;
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final immunisationDao = context.read<ImmunisationDao>();
    try {
      final givenAtMs =
          _isMissed ? null : _givenDate.millisecondsSinceEpoch;
      final id = '${widget.patientId}_${widget.vaccine.code}';
      await immunisationDao.upsertMany([
        ImmunisationRow(
          id: id,
          patientId: widget.patientId,
          vaccineCode: widget.vaccine.code,
          dueAt: widget.vaccine.scheduledDate.millisecondsSinceEpoch,
          givenAt: givenAtMs,
          rawJson: _buildRaw(),
        ),
      ]);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onRecorded(_givenDate);
      }
    } on Object {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _buildRaw() {
    return '{'
        '"vaccineName":"${widget.vaccine.display}",'
        '"category":"${widget.vaccine.category}",'
        '"missed":$_isMissed'
        '${_isMissed && _reasonCtrl.text.isNotEmpty ? ',"missedReason":"${_reasonCtrl.text}"' : ''}'
        '}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.vaccine.display,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.navy,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Vaccinated / Missed toggle
          Row(
            children: [
              _ToggleChip(
                label: EpiStrings.vaccinated,
                selected: !_isMissed,
                onTap: () => setState(() => _isMissed = false),
                activeColor: const Color(0xFF16A34A),
              ),
              const SizedBox(width: 10),
              _ToggleChip(
                label: EpiStrings.missed,
                selected: _isMissed,
                onTap: () => setState(() => _isMissed = true),
                activeColor: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (!_isMissed) ...[
            Text(
              EpiStrings.dateGiven,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(_givenDate),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Text(
              EpiStrings.missedReasonLabel,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.navy),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _reasonCtrl,
              decoration: InputDecoration(
                hintText: EpiStrings.missedReasonHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 2,
            ),
          ],

          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(EpiStrings.saveStatus),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _givenDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _givenDate = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_monthShort(d.month)} ${d.year}';

  String _monthShort(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.activeColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFFD1D5DB),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textMuted,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
