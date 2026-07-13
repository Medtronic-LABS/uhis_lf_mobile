import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/immunisation_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_theme.dart';
import '../assessment_repository.dart';
import '../triage/child_assessment_section.dart';
import 'epi_schedule_engine.dart';
import 'immunisation_dto.dart';
import 'immunisation_repository.dart';

// ── Color tokens ─────────────────────────────────────────────────────────────
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kAmber = Color(0xFFF59E0B);
const _kGrey = Color(0xFF9CA3AF);
const _kRedSurface = Color(0xFFFEF2F2);

class ImmunisationTimelineScreen extends StatefulWidget {
  const ImmunisationTimelineScreen({
    super.key,
    required this.patientId,
    this.patientName,
    this.dob,
    this.onVisitComplete,
    this.encounterId,
    this.householdMemberLocalId,
    this.memberId,
  });

  final String patientId;
  final String? patientName;
  final String? dob;

  /// When non-null, the submit bar label changes to "Done → Continue Visit"
  /// and this callback is invoked after [context.pop()] so the visit flow can
  /// advance to Step 3. Standalone access leaves this null (behaviour unchanged).
  final VoidCallback? onVisitComplete;

  /// Visit encounter ID — passed through to [_UpdateStatusSheet] so vaccine
  /// status updates can be pushed to the backend via [ImmunisationRepository].
  /// Null in standalone (patient profile) access; push is skipped in that case.
  final String? encounterId;

  /// Local DB member ID — required for [AssessmentRepository.saveAssessment]
  /// to correctly attribute the EPI child assessment to the right member row.
  /// Defaults to 0 when not supplied (standalone/profile access).
  final int? householdMemberLocalId;

  /// Backend member UUID — carried through to the assessment payload.
  final String? memberId;

  @override
  State<ImmunisationTimelineScreen> createState() =>
      _ImmunisationTimelineScreenState();
}

class _ImmunisationTimelineScreenState
    extends State<ImmunisationTimelineScreen> {
  List<VaccineMilestone>? _milestones;
  Patient? _patient;
  bool _loading = true;
  String? _error;
  ChildAssessmentData _childAssessmentData = ChildAssessmentData();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final immunisationDao = context.read<ImmunisationDao>();
    final immunisationRepo = context.read<ImmunisationRepository>();
    final patientDao = context.read<PatientDao>();

    final patient = await patientDao.byId(widget.patientId);

    DateTime? dob;
    final dobStr = widget.dob ?? patient?.dob;
    if (dobStr != null && dobStr.isNotEmpty) {
      dob = DateTime.tryParse(dobStr);
    }
    if (dob == null) {
      setState(() {
        _patient = patient;
        _error = EpiStrings.noDobError;
        _loading = false;
      });
      return;
    }

    try {
      // Try backend first — matches Android SPICE app behaviour.
      // On success the response is the authoritative schedule + statuses.
      final dtos = await immunisationRepo
          .fetchSchedule(
            patientId: widget.patientId,
            patientReference: widget.patientId,
            birthDate: dobStr!.substring(0, 10),
          )
          .timeout(const Duration(seconds: 5));

      if (dtos.isNotEmpty) {
        final milestones = _dtosToMilestones(dtos);
        if (mounted) {
          setState(() {
            _patient = patient;
            _milestones = milestones;
            _loading = false;
          });
        }
        return;
      }
    } on Object {
      // Offline or timeout — fall through to local DB.
    }

    // Offline fallback: static EPI schedule + locally recorded given dates.
    try {
      final rowMap = await immunisationDao.forMany([widget.patientId]);
      final rows = rowMap[widget.patientId] ?? [];
      final milestones = await EpiScheduleEngine.build(dob: dob, rows: rows);
      if (mounted) {
        setState(() {
          _patient = patient;
          _milestones = milestones;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _patient = patient;
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Converts backend [VaccinationDetailDto] list → [VaccineMilestone] list.
  /// Mirrors how the Android SPICE ImmunisationViewModel builds its timeline.
  List<VaccineMilestone> _dtosToMilestones(List<VaccinationDetailDto> dtos) {
    final now = DateTime.now();

    // Group by (type, value) — same milestone bucket.
    final groups = <String, List<VaccinationDetailDto>>{};
    for (final dto in dtos) {
      (groups['${dto.type}_${dto.value}'] ??= []).add(dto);
    }

    // Sort groups by scheduled date ascending.
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final aDate = DateTime.tryParse(groups[a]!.first.scheduledDate);
        final bDate = DateTime.tryParse(groups[b]!.first.scheduledDate);
        if (aDate == null || bDate == null) return 0;
        return aDate.compareTo(bDate);
      });

    final milestones = <VaccineMilestone>[];
    bool priorGroupComplete = true;

    for (final key in sortedKeys) {
      final groupDtos = groups[key]!;
      final first = groupDtos.first;
      final scheduledDate = DateTime.tryParse(first.scheduledDate) ?? now;

      final vaccines = groupDtos.asMap().entries.map((e) {
        final dto = e.value;
        final VaccineStatus status;
        if (dto.status == 'Vaccinated') {
          status = VaccineStatus.completed;
        } else if (!priorGroupComplete) {
          status = VaccineStatus.locked;
        } else {
          final days = scheduledDate.difference(now).inDays;
          if (days <= 0) {
            status = VaccineStatus.dueNow;
          } else if (days <= 28) {
            status = VaccineStatus.upcoming;
          } else {
            status = VaccineStatus.notYetDue;
          }
        }
        return VaccineEntry(
          code: dto.vaccineName,
          display: dto.vaccineName,
          category: dto.category,
          description: '',
          route: '',
          cardGroup: dto.vaccineOrder,
          scheduledDate: scheduledDate,
          givenDate: dto.vaccinatedDate != null
              ? DateTime.tryParse(dto.vaccinatedDate!)
              : null,
          status: status,
        );
      }).toList();

      final milestone = VaccineMilestone(
        label: _milestoneLabel(first.type, first.value),
        scheduledDate: scheduledDate,
        vaccines: vaccines,
        offsetType: first.type.toLowerCase(),
        offsetValue: first.value,
      );
      milestones.add(milestone);
      priorGroupComplete = milestone.allCompleted;
    }

    return milestones;
  }

  static String _milestoneLabel(String type, int value) {
    if (value == 0) return 'At Birth';
    switch (type.toUpperCase()) {
      case 'WEEK':
        return '$value ${value == 1 ? 'Week' : 'Weeks'}';
      case 'MONTH':
        return '$value ${value == 1 ? 'Month' : 'Months'}';
      default:
        return '$value ${value == 1 ? 'Day' : 'Days'}';
    }
  }

  String _ageLabel(Patient? p) {
    if (p == null) return '';
    final dob = (p.dob != null && p.dob!.isNotEmpty)
        ? DateTime.tryParse(p.dob!)
        : null;
    if (dob != null) {
      final months = (DateTime.now().difference(dob).inDays / 30.44).floor();
      if (months < 1) {
        final days = DateTime.now().difference(dob).inDays;
        return '$days ${days == 1 ? 'day' : 'days'}';
      }
      if (months < 24) return '$months ${months == 1 ? 'month' : 'months'}';
      final years = months ~/ 12;
      return '$years ${years == 1 ? 'year' : 'years'}';
    }
    if (p.age != null) return '${p.age} years';
    return '';
  }

  String _subtitle(Patient? p) {
    final parts = <String>[];
    final age = _ageLabel(p);
    if (age.isNotEmpty) parts.add(age);
    if (p?.gender != null) {
      final g = p!.gender!.toUpperCase();
      if (g == 'M' || g == 'MALE') parts.add('Male');
      if (g == 'F' || g == 'FEMALE') parts.add('Female');
    }
    if (p?.villageName != null && p!.villageName!.isNotEmpty) {
      parts.add(p.villageName!);
    }
    return parts.join(' · ');
  }

  List<VaccineMilestone> get _overdueMilestones =>
      (_milestones ?? []).where((m) => m.hasDueNow).toList();

  String _overdueBannerDetail() {
    final due = _overdueMilestones;
    if (due.isEmpty) return '';
    final label = due.map((m) => m.label).join(', ');
    final vaccines = due.expand((m) => m.vaccines
        .where((v) => v.status == VaccineStatus.dueNow)
        .map((v) => v.display)).toList();
    final vaccineText = vaccines.take(4).join(', ') +
        (vaccines.length > 4 ? '…' : '');
    return '$label doses ($vaccineText) are due now.';
  }

  int get _totalOverdueCount =>
      (_milestones ?? [])
          .expand((m) => m.vaccines)
          .where((v) => v.status == VaccineStatus.dueNow)
          .length;

  @override
  Widget build(BuildContext context) {
    final name = widget.patientName ?? _patient?.name ?? EpiStrings.screenTitle;

    // When embedded in the visit flow (onVisitComplete set), the _VisitFlowHeader
    // above already shows the patient name + step indicator — suppress our AppBar.
    final embedded = widget.onVisitComplete != null;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: embedded
          ? null
          : AppBar(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  Text(
                    _subtitle(_patient),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.textMuted)),
                  ),
                )
              : _buildContent(name),
    );
  }

  Widget _buildContent(String patientName) {
    final milestones = _milestones!;
    final overdueCount = _totalOverdueCount;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              // Overdue banner
              if (overdueCount > 0)
                _OverdueBanner(
                  count: overdueCount,
                  detail: _overdueBannerDetail(),
                ),

              // Timeline
              _Timeline(
                milestones: milestones,
                patientName: patientName,
                ageLabel: _ageLabel(_patient),
                onUpdateStatus: (milestone) =>
                    _showUpdateSheet(milestone, patientName),
              ),

              // Child health programme questions — always visible on vaccination screen
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ChildAssessmentSection(
                  data: _childAssessmentData,
                  onChanged: (updated) =>
                      setState(() => _childAssessmentData = updated),
                ),
              ),
            ],
          ),
        ),

        // Bottom Submit bar
        _SubmitBar(
          label: widget.onVisitComplete != null
              ? EpiStrings.doneVisitCta
              : EpiStrings.submitCta,
          onSubmit: () async {
            final assessmentRepo = context.read<AssessmentRepository>();
            final details = <String, dynamic>{
              if (_childAssessmentData.congenitalDefect != null)
                'congenitalDefect': _childAssessmentData.congenitalDefect,
              if (_childAssessmentData.weightKg != null)
                'weightKg': _childAssessmentData.weightKg,
              if (_childAssessmentData.isBreastfeeding != null)
                'isBreastfeeding': _childAssessmentData.isBreastfeeding,
              if (_childAssessmentData.additionalFoodLast24h != null)
                'additionalFoodLast24h':
                    _childAssessmentData.additionalFoodLast24h,
              if (_childAssessmentData.vaccinesReceived != null)
                'vaccinesReceived': _childAssessmentData.vaccinesReceived,
              if (_childAssessmentData.dewormingTaken != null)
                'dewormingTaken': _childAssessmentData.dewormingTaken,
              if (_childAssessmentData.anyIllness != null)
                'anyIllness': _childAssessmentData.anyIllness,
              if (_childAssessmentData.complications.isNotEmpty)
                'complications': _childAssessmentData.complications,
              if (_childAssessmentData.referralMade != null)
                'referralMade': _childAssessmentData.referralMade,
              if (_childAssessmentData.referralPlace != null)
                'referralPlace': _childAssessmentData.referralPlace,
            };
            debugPrint(
              '[ImmunisationTimeline] saving EPI child assessment '
              '(householdMemberLocalId=${widget.householdMemberLocalId ?? 0}): '
              '$details',
            );
            if (widget.householdMemberLocalId == null) {
              debugPrint(
                '[ImmunisationTimeline] WARNING: householdMemberLocalId not '
                'supplied — assessment saved with localId=0. Pass it via the '
                'immunisation route extra to fix attribution.',
              );
            }
            try {
              await assessmentRepo.saveAssessment(
                assessmentType: 'EPI',
                assessmentDetails: details,
                householdMemberLocalId: widget.householdMemberLocalId ?? 0,
                memberId: widget.memberId,
                patientId: widget.patientId,
                villageId: _patient?.villageId,
                encounterId: widget.encounterId,
                isReferred: _childAssessmentData.referralMade ?? false,
                referredReasons:
                    _childAssessmentData.referralMade == true &&
                            _childAssessmentData.referralPlace != null
                        ? [_childAssessmentData.referralPlace!]
                        : null,
              );
              debugPrint(
                '[ImmunisationTimeline] EPI assessment queued for sync',
              );
              debugPrint(
                '[ImmunisationTimeline] triggering syncPendingAssessments',
              );
              unawaited(
                assessmentRepo.syncPendingAssessments().then(
                  (n) => debugPrint(
                    '[ImmunisationTimeline] syncPendingAssessments → synced $n',
                  ),
                  onError: (e) => debugPrint(
                    '[ImmunisationTimeline] syncPendingAssessments ✗ $e',
                  ),
                ),
              );
            } on Object catch (e) {
              debugPrint(
                '[ImmunisationTimeline] EPI assessment save error: $e',
              );
            }
            final onComplete = widget.onVisitComplete;
            if (mounted) context.pop();
            onComplete?.call();
          },
        ),
      ],
    );
  }

  Future<void> _showUpdateSheet(
      VaccineMilestone milestone, String patientName) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _UpdateStatusSheet(
        milestone: milestone,
        patientId: widget.patientId,
        patient: _patient,
        patientName: patientName,
        ageLabel: _ageLabel(_patient),
        locationLabel: _patient?.villageName ?? '',
        encounterId: widget.encounterId,
        onRecorded: () {
          setState(() => _loading = true);
          _load();
        },
      ),
    );
  }
}

// ── Overdue banner ────────────────────────────────────────────────────────────

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({required this.count, required this.detail});
  final int count;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: _kRedSurface,
        border: Border(left: BorderSide(color: _kRed, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: _kRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  EpiStrings.overdueBanner(count),
                  style: const TextStyle(
                    color: _kRed,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                detail,
                style: const TextStyle(
                  color: _kRed,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Vertical timeline ─────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.milestones,
    required this.patientName,
    required this.ageLabel,
    required this.onUpdateStatus,
  });

  final List<VaccineMilestone> milestones;
  final String patientName;
  final String ageLabel;
  final void Function(VaccineMilestone) onUpdateStatus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (int i = 0; i < milestones.length; i++)
            _MilestoneRow(
              milestone: milestones[i],
              isLast: i == milestones.length - 1,
              patientName: patientName,
              ageLabel: ageLabel,
              onUpdateStatus: () => onUpdateStatus(milestones[i]),
            ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.milestone,
    required this.isLast,
    required this.patientName,
    required this.ageLabel,
    required this.onUpdateStatus,
  });

  final VaccineMilestone milestone;
  final bool isLast;
  final String patientName;
  final String ageLabel;
  final VoidCallback onUpdateStatus;

  Color get _labelColor {
    if (milestone.allCompleted) return _kGreen;
    if (milestone.hasDueNow) return _kRed;
    if (milestone.hasUpcoming) return _kAmber;
    return _kGrey;
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Far left: age label
          SizedBox(
            width: 58,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                milestone.label,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _labelColor,
                  height: 1.3,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Center: dot + dashed line
          Column(
            children: [
              _StatusDot(milestone: milestone),
              if (!isLast)
                Expanded(
                  child: _DashedLine(
                    color: milestone.allCompleted
                        ? _kGreen.withValues(alpha: 0.5)
                        : const Color(0xFFD1D5DB),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Right: milestone content (no card container)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _MilestoneContent(
                milestone: milestone,
                patientName: patientName,
                ageLabel: ageLabel,
                onUpdateStatus: onUpdateStatus,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.milestone});
  final VaccineMilestone milestone;

  @override
  Widget build(BuildContext context) {
    if (milestone.allCompleted) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: _kGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
      );
    }
    if (milestone.hasDueNow) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(color: _kRed, shape: BoxShape.circle),
        child: const Icon(Icons.priority_high_rounded,
            size: 16, color: Colors.white),
      );
    }
    if (milestone.hasUpcoming) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _kAmber.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: _kAmber, width: 2),
        ),
        child: const Icon(Icons.schedule_rounded, size: 14, color: _kAmber),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _kGrey, width: 2),
      ),
      child: const Icon(Icons.lock_outline_rounded, size: 12, color: _kGrey),
    );
  }
}

class _MilestoneContent extends StatelessWidget {
  const _MilestoneContent({
    required this.milestone,
    required this.patientName,
    required this.ageLabel,
    required this.onUpdateStatus,
  });

  final VaccineMilestone milestone;
  final String patientName;
  final String ageLabel;
  final VoidCallback onUpdateStatus;

  Color _vaccineColor(VaccineEntry v) {
    if (v.status == VaccineStatus.completed) return _kGreen;
    if (milestone.hasDueNow) return _kRed;
    if (milestone.hasUpcoming) return _kAmber;
    return _kGrey;
  }

  @override
  Widget build(BuildContext context) {
    final monthsUntil =
        milestone.scheduledDate.difference(DateTime.now()).inDays ~/ 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: label + status badge / update button
        Row(
          children: [
            Expanded(
              child: Text(
                milestone.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: milestone.allCompleted ||
                          milestone.hasDueNow ||
                          milestone.hasUpcoming
                      ? AppColors.navy
                      : _kGrey,
                ),
              ),
            ),
            if (milestone.allCompleted)
              _StatusBadge(
                  label: EpiStrings.statusCompleted,
                  color: _kGreen,
                  icon: Icons.check_rounded),
            if (milestone.hasDueNow)
              _UpdateCtaButton(onTap: onUpdateStatus),
            if (milestone.hasUpcoming && !milestone.hasDueNow)
              _StatusBadge(
                  label: EpiStrings.statusUpcoming,
                  color: _kAmber,
                  icon: Icons.schedule_rounded),
            if (!milestone.allCompleted &&
                !milestone.hasDueNow &&
                !milestone.hasUpcoming)
              _StatusBadge(
                  label: EpiStrings.statusNotYetDue,
                  color: _kGrey,
                  icon: Icons.lock_outline_rounded),
          ],
        ),

        const SizedBox(height: 6),

        // Vaccine list — plain bullet points
        ...milestone.vaccines.map(
          (v) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '• ${v.display}',
              style: TextStyle(
                fontSize: 13,
                color: _vaccineColor(v),
                fontWeight: milestone.hasDueNow
                    ? FontWeight.w500
                    : FontWeight.normal,
              ),
            ),
          ),
        ),

        // Status footnote
        if (milestone.hasDueNow) ...[
          const SizedBox(height: 4),
          Text(
            ageLabel.isNotEmpty
                ? 'Due now · $patientName is $ageLabel'
                : 'Due now',
            style: const TextStyle(
                fontSize: 12, color: _kRed, fontWeight: FontWeight.w600),
          ),
        ] else if (milestone.hasUpcoming &&
            !milestone.hasDueNow &&
            monthsUntil > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Due in ~$monthsUntil ${monthsUntil == 1 ? 'month' : 'months'}',
            style: const TextStyle(fontSize: 12, color: _kAmber),
          ),
        ] else if (!milestone.allCompleted &&
            !milestone.hasDueNow &&
            !milestone.hasUpcoming &&
            monthsUntil > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Due in ~$monthsUntil ${monthsUntil == 1 ? 'month' : 'months'}',
            style: const TextStyle(fontSize: 12, color: _kGrey),
          ),
        ],
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCtaButton extends StatelessWidget {
  const _UpdateCtaButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _kRed,
          borderRadius: BorderRadius.circular(20),
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

// ── Dashed timeline line ──────────────────────────────────────────────────────

class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2,
      child: CustomPaint(painter: _DashedLinePainter(color: color)),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dash = 5.0;
    const gap = 4.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(1, y),
        Offset(1, (y + dash).clamp(0.0, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

// ── Submit bar ────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.onSubmit, this.label});
  final Future<void> Function() onSubmit;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onSubmit,
          icon: const Text('💉', style: TextStyle(fontSize: 16)),
          label: Text(
            label ?? EpiStrings.submitCta,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

// ── Update status bottom sheet ────────────────────────────────────────────────

class _UpdateStatusSheet extends StatefulWidget {
  const _UpdateStatusSheet({
    required this.milestone,
    required this.patientId,
    required this.patientName,
    required this.ageLabel,
    required this.locationLabel,
    required this.onRecorded,
    this.patient,
    this.encounterId,
  });

  final VaccineMilestone milestone;
  final String patientId;

  /// Full patient record — provides the numeric backend [Patient.patientId]
  /// and [Patient.villageId] for the immunisation create request.
  final Patient? patient;
  final String patientName;
  final String ageLabel;
  final String locationLabel;
  final VoidCallback onRecorded;

  /// When set, vaccine status is pushed to the backend via [ImmunisationRepository]
  /// after saving locally. Null in standalone access; push skipped.
  final String? encounterId;

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  DateTime _givenDate = DateTime.now();
  final TextEditingController _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String _sheetSubtitle() {
    final parts = <String>[widget.patientName];
    if (widget.ageLabel.isNotEmpty) parts.add(widget.ageLabel);
    if (widget.locationLabel.isNotEmpty) parts.add(widget.locationLabel);
    return parts.join(' · ');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final immunisationDao = context.read<ImmunisationDao>();
    final immunisationRepo = context.read<ImmunisationRepository>();
    try {
      final givenMs = _givenDate.millisecondsSinceEpoch;
      final givenIso =
          _givenDate.toIso8601String().substring(0, 10); // "YYYY-MM-DD"
      final dueIso = widget.milestone.scheduledDate
          .toIso8601String()
          .substring(0, 10);

      // 1. Save locally first (offline-first guarantee)
      final rows = widget.milestone.vaccines.map((v) {
        return ImmunisationRow(
          id: '${widget.patientId}_${v.code}',
          patientId: widget.patientId,
          vaccineCode: v.code,
          dueAt: widget.milestone.scheduledDate.millisecondsSinceEpoch,
          givenAt: givenMs,
          rawJson: '{"vaccineName":"${v.display}"'
              ',"milestone":"${widget.milestone.label}"'
              ',"notes":"${_notesCtrl.text.replaceAll('"', '\\"')}"'
              '}',
        );
      }).toList();
      await immunisationDao.upsertMany(rows);

      // 2. Push to backend if in a visit context (best-effort)
      if (widget.encounterId != null) {
        final dtos = widget.milestone.vaccines.asMap().entries.map((e) {
          return VaccinationDetailDto(
            vaccineName: e.value.display,
            type: widget.milestone.offsetType.toUpperCase(),
            value: widget.milestone.offsetValue,
            status: 'Vaccinated',
            scheduledDate: dueIso,
            vaccinatedDate: givenIso,
            displayOrder: e.key,
            category: e.value.category,
            vaccineOrder: e.value.cardGroup,
          );
        }).toList();

        // Use the backend's numeric patient ID when available.
        // widget.patientId may be a FHIR UUID — patient.patientId holds the
        // backend integer ID that /immunisation/create actually validates.
        final numericId =
            widget.patient?.patientId ?? widget.patientId;
        await immunisationRepo.submitVaccinations(
          patientId: widget.patientId,
          numericPatientId: numericId,
          patientReference: numericId,
          vaccines: dtos,
          encounterId: widget.encounterId,
          villageId: widget.patient?.villageId,
          missedReason: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onRecorded();
      }
    } on Object {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.milestone.label} Vaccines',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sheetSubtitle(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textMuted),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Status strip
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: _kRedSurface,
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(color: _kRed, width: 3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: _kRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.ageLabel.isNotEmpty
                        ? 'Status: Due now · ${widget.patientName} is ${widget.ageLabel}'
                        : 'Status: Due now',
                    style: const TextStyle(
                      color: _kRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Vaccines section
                  _SectionLabel(EpiStrings.vaccinesDueLabel),
                  ...widget.milestone.vaccineCards.map(
                    (group) => _VaccineCard(vaccines: group),
                  ),

                  const SizedBox(height: 16),

                  // Date administered
                  _SectionLabel(EpiStrings.dateAdministered),
                  _DateField(
                    date: _givenDate,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _givenDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _givenDate = picked);
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Notes
                  _SectionLabel(EpiStrings.notesOptional),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: EpiStrings.notesHint,
                      hintStyle: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Mark as completed
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(EpiStrings.markCompleted),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Cancel
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(EpiStrings.cancel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Card for one card-group of vaccines (e.g. OPV-3 + PCV-3 together).
class _VaccineCard extends StatelessWidget {
  const _VaccineCard({required this.vaccines});
  final List<VaccineEntry> vaccines;

  @override
  Widget build(BuildContext context) {
    final title = vaccines.map((v) => v.display).join(' · ');
    final descriptions = vaccines.map((v) => v.description).join(' · ');
    final routes = vaccines.map((v) => v.route).join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            descriptions,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            routes,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap});
  final DateTime date;
  final VoidCallback onTap;

  String _format(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day / $month / ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _format(date),
                style: const TextStyle(fontSize: 15, color: AppColors.navy),
              ),
            ),
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
