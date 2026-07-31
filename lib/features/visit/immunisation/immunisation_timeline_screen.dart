import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/db/assessment_dao.dart';
import '../../../core/db/immunisation_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_theme.dart';
import '../../patient/member_detail_repository.dart';
import '../assessment_repository.dart';
import '../triage/child_assessment_section.dart';
import 'child_immunization_dto.dart';
import 'epi_schedule_engine.dart';
import 'immunisation_dto.dart';
import 'immunisation_repository.dart';

// ── Color tokens ─────────────────────────────────────────────────────────────
// v16 mockup s20 exact hexes — completed dot ring #059669, due/overdue
// #EF4444. "Referred" (below) uses the mockup's separate #DC2626 chip
// convention, not this same #EF4444, so the two states stay visually
// distinct on the same timeline.
const _kGreen = Color(0xFF059669);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
// Two shades darker than the mockup's own grey (#9CA3AF) — on-device
// testing found the mockup-exact value, and one step darker after that,
// still too faint against the white/canvas background for "not yet due"
// content; this is a deliberate legibility deviation, not a mockup value.
const _kGrey = Color(0xFF4B5563);
// Matches the "Referred" chip convention used elsewhere in the v16 mockup
// (the ANC screen's referral chip) — a different red from this screen's own
// due-now/overdue #EF4444, so a referred dot still reads distinctly from a
// still-due one on the same timeline.
const _kReferred = Color(0xFFDC2626);
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
    this.showChildAssessment = true,
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

  /// Whether to show the Child Assessment section below the vaccine timeline.
  /// False when SK selected Vaccination-only (no Child Health card) so the
  /// IMCI questions don't appear inside a vaccination-only visit.
  final bool showChildAssessment;

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
    debugPrint('[_ImmunisationTimelineScreenState] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    debugPrint('[_ImmunisationTimelineScreenState] _load');
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

    final rowMap = await immunisationDao.forMany([widget.patientId]);
    final localRows = rowMap[widget.patientId] ?? [];
    final history = await _fetchHistoricalOutcomes(patient);

    // History fills gaps the backend/schedule doesn't know about yet;
    // same-session local rows always win on conflict. For the offline
    // engine path, prepend history as synthetic rows so build()'s own
    // last-write-wins map assignment resolves priority correctly (local
    // rows are appended after, so they overwrite on the same vaccine name).
    final historyRows = history
        .map((h) => ImmunisationRow(
              id: 'history_${widget.patientId}_${h.vaccineName}',
              patientId: widget.patientId,
              vaccineCode: h.vaccineName,
              givenAt: h.givenAtMs,
              status: h.status,
              missedReason: h.reason,
              referralFacility: h.facility,
              rawJson: '{}',
            ))
        .toList();
    final mergedRows = [...historyRows, ...localRows];

    // Same priority, as name-keyed maps for the backend-dto path below
    // (VaccinationDetailDto has no facility field, so that path needs a
    // post-build overlay rather than a per-row merge).
    final historyGivenByName = <String, String>{};
    final historyMissedByName = <String, String>{};
    final historyFacilityByName = <String, String>{};
    for (final h in history) {
      if (h.status == 'Vaccinated' && h.givenAtMs != null) {
        historyGivenByName[h.vaccineName] =
            DateTime.fromMillisecondsSinceEpoch(h.givenAtMs!)
                .toIso8601String()
                .substring(0, 10);
      } else if (h.status == 'Missed') {
        historyMissedByName[h.vaccineName] = h.reason ?? '';
        if (h.facility != null && h.facility!.isNotEmpty) {
          historyFacilityByName[h.vaccineName] = h.facility!;
        }
      }
    }
    for (final r in localRows) {
      if (r.vaccineCode == null) continue;
      if (r.givenAt != null) {
        historyGivenByName[r.vaccineCode!] =
            DateTime.fromMillisecondsSinceEpoch(r.givenAt!)
                .toIso8601String()
                .substring(0, 10);
      } else if (r.status == 'Missed') {
        historyMissedByName[r.vaccineCode!] = r.missedReason ?? '';
        if (r.referralFacility != null && r.referralFacility!.isNotEmpty) {
          historyFacilityByName[r.vaccineCode!] = r.referralFacility!;
        }
      }
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
        // Merge local + history outcomes to handle backend eventual
        // consistency — a vaccine recorded elsewhere (given, or explicitly
        // Missed) but not yet reflected in the backend response must still
        // show that outcome so it doesn't look reverted, and so subsequent
        // milestones unlock.
        final effectiveDtos = dtos.map((dto) {
          final knownDate = historyGivenByName[dto.vaccineName];
          if (knownDate != null && dto.status != 'Vaccinated') {
            return VaccinationDetailDto(
              id: dto.id,
              type: dto.type,
              value: dto.value,
              status: 'Vaccinated',
              vaccineName: dto.vaccineName,
              scheduledDate: dto.scheduledDate,
              vaccinatedDate: knownDate,
              doseClosureWeeks: dto.doseClosureWeeks,
              reason: dto.reason,
              displayOrder: dto.displayOrder,
              category: dto.category,
              vaccineOrder: dto.vaccineOrder,
            );
          }
          final knownReason = historyMissedByName[dto.vaccineName];
          if (knownReason != null &&
              dto.status != 'Vaccinated' &&
              dto.status != 'Missed') {
            return VaccinationDetailDto(
              id: dto.id,
              type: dto.type,
              value: dto.value,
              status: 'Missed',
              vaccineName: dto.vaccineName,
              scheduledDate: dto.scheduledDate,
              doseClosureWeeks: dto.doseClosureWeeks,
              reason: knownReason,
              displayOrder: dto.displayOrder,
              category: dto.category,
              vaccineOrder: dto.vaccineOrder,
            );
          }
          return dto;
        }).toList();
        var milestones = _dtosToMilestones(effectiveDtos);
        milestones =
            _overlayReferralFacility(milestones, historyFacilityByName);
        milestones = EpiScheduleEngine.applySequencing(milestones);
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

    // Offline fallback: static EPI schedule + locally recorded/historical outcomes.
    try {
      var milestones = await EpiScheduleEngine.build(dob: dob, rows: mergedRows);
      milestones = EpiScheduleEngine.applySequencing(milestones);
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

  /// Best-effort pull of this patient's CHILD_IMMUNIZATION assessment
  /// history — network first (fresh, mirrors [ImmunisationRepository
  /// .fetchSchedule]'s own timeout convention), falling back to the local
  /// [AssessmentDao] cache the general sync flow already keeps populated.
  /// Returns an empty list rather than throwing on any failure — this is a
  /// read-side enrichment, never a hard requirement for the timeline to
  /// render.
  Future<List<HistoryOutcome>> _fetchHistoricalOutcomes(
      Patient? patient) async {
    // Resolve both repos up front — reading context.read() after an await
    // trips use_build_context_synchronously, and neither lookup needs to
    // be deferred.
    final memberDetailRepo = context.read<MemberDetailRepository>();
    final assessmentDao = context.read<AssessmentDao>();

    try {
      final assessments = await memberDetailRepo
          .getMemberAssessments(
            widget.memberId ?? widget.patientId,
            villageId: patient?.villageId,
          )
          .timeout(const Duration(seconds: 5));
      final rawJsons = assessments
          .where((a) => a.type.toUpperCase().contains('IMMUNIZATION'))
          .map((a) => a.rawJson)
          .toList();
      final outcomes = EpiScheduleEngine.outcomesFromRawJsonList(rawJsons);
      if (outcomes.isNotEmpty) return outcomes;
    } on Object catch (e) {
      debugPrint('[ImmunisationTimeline] history network fetch failed: $e');
    }

    try {
      final rowMap = await assessmentDao.forMany([widget.patientId]);
      final rows = (rowMap[widget.patientId] ?? []).where(
          (r) => (r.kind ?? '').toUpperCase().contains('IMMUNIZATION'));
      final rawJsons = <Map<String, dynamic>>[];
      for (final r in rows) {
        try {
          rawJsons.add(jsonDecode(r.rawJson) as Map<String, dynamic>);
        } on Object {
          // malformed cache row — skip.
        }
      }
      return EpiScheduleEngine.outcomesFromRawJsonList(rawJsons);
    } on Object catch (e) {
      debugPrint('[ImmunisationTimeline] history local cache read failed: $e');
      return const [];
    }
  }

  /// Overlays a name-keyed referral facility map onto already-built
  /// milestones — used for the backend-dto path, whose [VaccinationDetailDto]
  /// has no facility field to carry it through [_dtosToMilestones].
  List<VaccineMilestone> _overlayReferralFacility(
      List<VaccineMilestone> milestones, Map<String, String> facilityByName) {
    if (facilityByName.isEmpty) return milestones;
    return milestones.map((m) {
      final vaccines = m.vaccines.map((v) {
        if (v.referralFacility != null) return v;
        final facility = facilityByName[v.display];
        if (facility == null) return v;
        return VaccineEntry(
          code: v.code,
          display: v.display,
          category: v.category,
          description: v.description,
          route: v.route,
          cardGroup: v.cardGroup,
          scheduledDate: v.scheduledDate,
          givenDate: v.givenDate,
          status: v.status,
          missedReason: v.missedReason,
          referralFacility: facility,
        );
      }).toList();
      return VaccineMilestone(
        label: m.label,
        scheduledDate: m.scheduledDate,
        vaccines: vaccines,
        offsetType: m.offsetType,
        offsetValue: m.offsetValue,
        actionEnabled: m.actionEnabled,
      );
    }).toList();
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

    // Each vaccine's status is computed strictly from its own scheduled
    // date / recorded outcome, independent of every other milestone -- no
    // cross-milestone "prior must be complete first" gate. See the matching
    // comment in EpiScheduleEngine.build() for the bug this fixes.
    for (final key in sortedKeys) {
      final groupDtos = groups[key]!;
      final first = groupDtos.first;
      final scheduledDate = DateTime.tryParse(first.scheduledDate) ?? now;

      final vaccines = groupDtos.asMap().entries.map((e) {
        final dto = e.value;
        final VaccineStatus status;
        if (dto.status == 'Vaccinated') {
          status = VaccineStatus.completed;
        } else if (dto.status == 'Missed') {
          status = VaccineStatus.missed;
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
          missedReason: dto.reason,
        );
      }).toList();

      milestones.add(VaccineMilestone(
        label: _milestoneLabel(first.type, first.value),
        scheduledDate: scheduledDate,
        vaccines: vaccines,
        offsetType: first.type.toLowerCase(),
        offsetValue: first.value,
      ));
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
              // v16 mockup's s20 (this screen) header — same maroon already
              // used by the embedded visit-flow header for every programme
              // (visit_flow_header.dart's headerColor), so standalone access
              // now matches embedded access too.
              backgroundColor: AppColors.ancHeader,
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
              if (overdueCount > 0) _OverdueBanner(count: overdueCount),

              // Timeline
              _Timeline(
                milestones: milestones,
                patientName: patientName,
                ageLabel: _ageLabel(_patient),
                onUpdateStatus: (milestone) =>
                    _showUpdateSheet(milestone, patientName),
              ),

              // Child health programme questions — only when Child Health was
              // selected alongside Vaccination. Hidden for vaccination-only visits.
              if (widget.showChildAssessment)
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
      builder: (ctx) {
        DateTime? patientDob;
        final dobStr = _patient?.dob ?? widget.dob;
        if (dobStr != null && dobStr.isNotEmpty) {
          patientDob = DateTime.tryParse(dobStr);
        }
        return _UpdateStatusSheet(
          milestone: milestone,
          patientId: widget.patientId,
          patient: _patient,
          patientName: patientName,
          ageLabel: _ageLabel(_patient),
          locationLabel: _patient?.villageName ?? '',
          encounterId: widget.encounterId,
          memberId: widget.memberId,
          householdId: _patient?.householdId,
          householdMemberLocalId: widget.householdMemberLocalId,
          dob: patientDob,
          onRecorded: () {
            setState(() => _loading = true);
            _load();
          },
        );
      },
    );
  }
}

// ── Overdue banner ────────────────────────────────────────────────────────────

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    // v16 mockup's banner is a single line — no per-milestone breakdown.
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: _kRedSurface,
        border: Border(left: BorderSide(color: _kRed, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kRed, size: 18),
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

  /// Fully not-yet-due (no action, no upcoming window, not completed) —
  /// mockup dims the entire row to 50% opacity in this state.
  bool get _isFullyNotYetDue =>
      !milestone.allCompleted &&
      !milestone.hasDueNow &&
      !milestone.hasMissed &&
      !milestone.hasUpcoming;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _isFullyNotYetDue ? 0.5 : 1.0,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Center: dot + dashed line — the mockup has no separate
            // far-left label column; the milestone label appears once,
            // inside _MilestoneContent's header row.
            Column(
              children: [
                _StatusDot(milestone: milestone),
                // v16 mockup's connector is always this mint-green, not
                // state-dependent.
                if (!isLast)
                  const Expanded(
                    child: _DashedLine(color: Color(0xFFA7F3D0)),
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
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.milestone});
  final VaccineMilestone milestone;

  // Mockup dot: 18x18, a canvas-colored border creating a cutout ring
  // effect, plus a colored outer ring (its box-shadow). Approximated here
  // with a fixed-width border (the cutout) + a BoxShadow with spreadRadius
  // and no blur (the solid outer ring).
  static const _kDotCanvasBorder = Color(0xFFF0F2F8);

  Widget _dot({required Color fill, required Color ring, required Widget icon}) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: _kDotCanvasBorder, width: 2),
        boxShadow: [BoxShadow(color: ring, spreadRadius: 2)],
      ),
      child: Center(child: icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (milestone.allCompleted) {
      return _dot(
        fill: _kGreen,
        ring: _kGreen,
        icon: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
      );
    }
    if (milestone.hasDueNow) {
      final dot = _dot(
        fill: _kRed,
        ring: _kRed,
        icon: const Icon(Icons.priority_high_rounded,
            size: 10, color: Colors.white),
      );
      // Mockup blinks only the currently-actionable dot — the one whose
      // Update-status button is actually enabled, not every overdue
      // milestone at once (later ones are blocked by sequencing).
      return milestone.actionEnabled ? _BlinkingDot(child: dot) : dot;
    }
    if (milestone.hasMissed) {
      return _dot(
        fill: _kReferred,
        ring: _kReferred,
        icon: const Icon(Icons.event_busy_rounded, size: 10, color: Colors.white),
      );
    }
    if (milestone.hasUpcoming) {
      return _dot(
        fill: _kAmber,
        ring: _kAmber,
        icon: const Icon(Icons.schedule_rounded, size: 10, color: Colors.white),
      );
    }
    // Not-yet-due: solid grey fill with a white icon — inverted from the
    // other states, matching the mockup exactly (not just a lighter
    // version of the same treatment). #D1D5DB is the mockup's exact fill;
    // the row itself is already dimmed to 50% opacity in this state.
    return _dot(
      fill: const Color(0xFFD1D5DB),
      ring: const Color(0xFFD1D5DB),
      icon: const Icon(Icons.lock_outline_rounded, size: 10, color: Colors.white),
    );
  }
}

/// Reproduces the mockup's `@keyframes blink { 0%,100%{opacity:1;}
/// 50%{opacity:0.2;} }` / `animation: blink 1.4s infinite` applied directly
/// to the status dot — a 1.4s round trip is a 700ms fade out + 700ms fade
/// back in, which `repeat(reverse: true)` gives for free.
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot({required this.child});
  final Widget child;

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  ).drive(Tween<double>(begin: 1.0, end: 0.2));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
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

  // Note: VaccineStatus.missed is handled separately in build() via a
  // two-color Text.rich (red bullet + standard dark name), so it never
  // reaches this method.
  // Every state reads in the same standard dark tone — status is already
  // conveyed by the dot/badge/button, not by tinting the vaccine name text.
  Color _vaccineColor(VaccineEntry v) => const Color(0xFF374151);

  @override
  Widget build(BuildContext context) {
    final monthsUntil =
        milestone.scheduledDate.difference(DateTime.now()).inDays ~/ 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: label [+ Referred badge] — spacer — status badge / update button.
        // The label is no longer Expanded so a "Referred" badge can sit
        // immediately next to it (e.g. "14 Weeks Referred") instead of
        // being pushed to the row's far edge with the button.
        Row(
          children: [
            Text(
              milestone.label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: milestone.allCompleted ||
                        milestone.hasDueNow ||
                        milestone.hasMissed ||
                        milestone.hasUpcoming
                    ? AppColors.navy
                    : _kGrey,
              ),
            ),
            if (milestone.hasMissed) ...[
              const SizedBox(width: 6),
              // +15% size, extra bold — "referred" is an important
              // indicator and reads best when it stands out from the
              // other plain badges.
              _StatusBadge(
                  label: EpiStrings.statusReferred,
                  color: _kReferred,
                  icon: Icons.event_busy_rounded,
                  plain: true,
                  fontSize: 11.5,
                  iconSize: 12.5,
                  fontWeight: FontWeight.w900),
            ],
            const Spacer(),
            if (milestone.allCompleted)
              // +25% size on top of the earlier +10% bump.
              _StatusBadge(
                  label: EpiStrings.statusCompleted,
                  color: _kGreen,
                  icon: Icons.check_rounded,
                  plain: true,
                  fontSize: 12.5,
                  iconSize: 14),
            if (milestone.hasDueNow)
              _UpdateCtaButton(
                  onTap: onUpdateStatus,
                  color: _kRed,
                  enabled: milestone.actionEnabled),
            if (!milestone.hasDueNow && milestone.hasMissed)
              _UpdateCtaButton(
                  onTap: onUpdateStatus, color: _kReferred, enabled: true),
            if (milestone.hasUpcoming &&
                !milestone.hasDueNow &&
                !milestone.hasMissed)
              _StatusBadge(
                  label: EpiStrings.statusUpcoming,
                  color: _kAmber,
                  icon: Icons.schedule_rounded,
                  bgColor: const Color(0xFFFEF3C7),
                  textColor: const Color(0xFF92400E)),
            if (!milestone.allCompleted &&
                !milestone.hasDueNow &&
                !milestone.hasMissed &&
                !milestone.hasUpcoming)
              _StatusBadge(
                  label: EpiStrings.statusNotYetDue,
                  color: _kGrey,
                  icon: Icons.lock_outline_rounded,
                  plain: true),
          ],
        ),

        const SizedBox(height: 6),

        // Vaccine list — plain bullet points. Facility/Reason are NOT
        // repeated here even for a referred vaccine — one Refer action
        // always applies the same facility/reason to every vaccine in the
        // milestone as a batch, so they're shown once for the whole block
        // below instead of once per vaccine.
        ...milestone.vaccines.map(
          (v) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: v.status == VaccineStatus.missed
                // Only the bullet marker carries the "referred" color —
                // the vaccine name itself reads in the same standard dark
                // tone every other state's vaccine name uses. No "—
                // Referred" suffix: the button/dot color and the bottom
                // summary line already say so.
                ? Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '• ',
                          style: TextStyle(
                            fontSize: 12,
                            color: _kReferred,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: v.display,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    '• ${v.display}',
                    style: TextStyle(
                      fontSize: 12,
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
            !milestone.hasMissed &&
            monthsUntil > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Due in ~$monthsUntil ${monthsUntil == 1 ? 'month' : 'months'}',
            style: const TextStyle(fontSize: 12, color: _kAmber),
          ),
        ] else if (!milestone.allCompleted &&
            !milestone.hasDueNow &&
            !milestone.hasUpcoming &&
            !milestone.hasMissed &&
            monthsUntil > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Due in ~$monthsUntil ${monthsUntil == 1 ? 'month' : 'months'}',
            style: const TextStyle(fontSize: 12, color: _kGrey),
          ),
        ],

        // Facility/Reason, once for the whole block, at the very bottom —
        // a single Refer action always applies the same facility/reason to
        // every vaccine in the milestone, so this isn't repeated per vaccine.
        if (milestone.hasMissed) ..._referralDetails(),
      ],
    );
  }

  List<Widget> _referralDetails() {
    final referred = milestone.vaccines.firstWhere(
      (v) => v.status == VaccineStatus.missed,
      orElse: () => milestone.vaccines.first,
    );
    final widgets = <Widget>[];
    if (referred.referralFacility != null &&
        referred.referralFacility!.isNotEmpty) {
      // "Referred" + "Facility" merged into one line — the standalone
      // "Referred" footnote is gone, so this is now the single place the
      // block announces its status.
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${EpiStrings.referredToFacilityLabel}: ${referred.referralFacility}',
          style: const TextStyle(
            fontSize: 11.5,
            color: _kReferred,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
    } else {
      // No facility on record (e.g. a history-derived row where the id→
      // label lookup missed) — still say *something*, don't go silent.
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          EpiStrings.statusReferred,
          style: const TextStyle(
            fontSize: 11.5,
            color: _kReferred,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
    }
    if (referred.missedReason != null && referred.missedReason!.isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${EpiStrings.missedReasonInlineLabel}: ${referred.missedReason}',
          style: const TextStyle(
            fontSize: 11.5,
            color: _kReferred,
            fontStyle: FontStyle.italic,
          ),
        ),
      ));
    }
    return widgets;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.icon,
    this.bgColor,
    this.textColor,
    this.plain = false,
    this.fontSize,
    this.iconSize,
    this.fontWeight,
  });
  final String label;
  final Color color;
  final IconData icon;

  /// Optional exact overrides — when omitted, derived from [color] as
  /// before. Used to pixel-match the v16 mockup's exact badge hex values
  /// where they differ from the alpha-derived approximation.
  final Color? bgColor;
  final Color? textColor;

  /// Mockup's Completed/Not-yet-due badges are plain small text with no
  /// pill background at all (e.g. "✓ Completed", "🔒 Not yet due") — only
  /// Upcoming keeps the pill treatment. Set true for the plain variant.
  final bool plain;

  /// Plain-variant overrides — the three plain badges (Completed, Referred,
  /// Not-yet-due) each ended up needing their own size/weight after
  /// readability feedback, rather than staying uniform.
  final double? fontSize;
  final double? iconSize;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final text = textColor ?? color;
    if (plain) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize ?? 11, color: text),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize ?? 10,
              fontWeight: fontWeight ?? FontWeight.w700,
              color: text,
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor ?? color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCtaButton extends StatelessWidget {
  const _UpdateCtaButton({
    required this.onTap,
    this.color = _kRed,
    this.enabled = true,
  });
  final VoidCallback onTap;
  final Color color;

  /// When false, the button still renders (so the SK always sees the
  /// milestone has an action) but is greyed out and does nothing on tap —
  /// it isn't this milestone's turn yet in the sequence.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        // A further +25% on top of the earlier +10% bump — on-device
        // testing found that still not comfortably readable; a deliberate
        // usability deviation from strict mockup pixel-parity.
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: enabled ? color : _kGrey.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          EpiStrings.updateStatusCta,
          style: TextStyle(
            color: enabled ? Colors.white : _kGrey,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
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
            // v16 mockup's submit button is pink, not navy.
            backgroundColor: const Color(0xFFEC4899),
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
    this.memberId,
    this.householdId,
    this.householdMemberLocalId,
    this.dob,
  });

  final VaccineMilestone milestone;
  final String patientId;

  /// Full patient record — provides [Patient.villageId] for the
  /// CHILD_IMMUNIZATION assessment payload.
  final Patient? patient;
  final String patientName;
  final String ageLabel;
  final String locationLabel;
  final VoidCallback onRecorded;

  /// Visit encounter ID, carried through to the assessment payload's summary.
  final String? encounterId;
  final String? memberId;
  final String? householdId;

  /// Required by [AssessmentRepository.saveAssessment] to attribute the
  /// assessment to the right household member row. Defaults to 0 (matches
  /// the EPI child-assessment save a few hundred lines above).
  final int? householdMemberLocalId;

  /// Patient date of birth — used as the earliest selectable date administered.
  final DateTime? dob;

  @override
  State<_UpdateStatusSheet> createState() => _UpdateStatusSheetState();
}

class _UpdateStatusSheetState extends State<_UpdateStatusSheet> {
  /// Whether the sheet is currently showing the referral flow (facility +
  /// reason) instead of the default vaccinated flow (date + notes).
  bool _referring = false;

  DateTime _givenDate = DateTime.now();
  final TextEditingController _notesCtrl = TextEditingController();

  final TextEditingController _reasonCtrl = TextEditingController();
  String? _reasonError;
  String? _selectedFacilityId;
  String? _facilityError;

  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    debugPrint('[_UpdateStatusSheetState] dispose');
    super.dispose();
  }

  String _sheetSubtitle() {
    final parts = <String>[widget.patientName];
    if (widget.ageLabel.isNotEmpty) parts.add(widget.ageLabel);
    if (widget.locationLabel.isNotEmpty) parts.add(widget.locationLabel);
    return parts.join(' · ');
  }

  /// Saves the milestone's vaccines as either Vaccinated (default flow) or
  /// Missed+referred (referral flow) — local-first, then queued for sync as
  /// a CHILD_IMMUNIZATION assessment via offline-sync/create.
  Future<void> _save() async {
    debugPrint('[_UpdateStatusSheetState] _save referring=$_referring');

    if (_referring) {
      if (_reasonCtrl.text.trim().isEmpty) {
        setState(() => _reasonError = EpiStrings.missedReasonRequired);
        return;
      }
      if (_selectedFacilityId == null) {
        setState(() => _facilityError = EpiStrings.referralFacilityRequired);
        return;
      }
    }

    setState(() => _saving = true);
    final immunisationDao = context.read<ImmunisationDao>();
    final assessmentRepo = context.read<AssessmentRepository>();

    try {
      final givenMs = _referring ? null : _givenDate.millisecondsSinceEpoch;
      final wireStatus = _referring ? 'Missed' : 'Vaccinated';
      final reasonText = _referring ? _reasonCtrl.text.trim() : null;
      final facilityLabel = _selectedFacilityId == null
          ? null
          : referralFacilityOptions
              .firstWhere((o) => o.id == _selectedFacilityId)
              .label;

      // 1. Save locally first (offline-first guarantee) — drives the
      // timeline's own status computation independent of sync.
      final rows = widget.milestone.vaccines.map((v) {
        return ImmunisationRow(
          id: '${widget.patientId}_${v.code}',
          patientId: widget.patientId,
          vaccineCode: v.code,
          dueAt: widget.milestone.scheduledDate.millisecondsSinceEpoch,
          givenAt: givenMs,
          status: wireStatus,
          missedReason: reasonText,
          referralFacility: _referring ? facilityLabel : null,
          rawJson: '{"vaccineName":"${v.display}"'
              ',"milestone":"${widget.milestone.label}"'
              '${!_referring ? ',"notes":"${_notesCtrl.text.replaceAll('"', '\\"')}"' : ''}'
              '}',
        );
      }).toList();
      await immunisationDao.upsertMany(rows);

      // 2. Queue as a CHILD_IMMUNIZATION assessment for offline-sync/create.
      final records = widget.milestone.vaccines
          .map((v) => ChildImmunizationVaccinationRecord(
                vaccineName: v.display,
                status: wireStatus,
                vaccinatedDate: _referring
                    ? null
                    : ChildImmunizationVaccinationRecord.dateWire(_givenDate),
                reason: reasonText,
              ))
          .toList();

      await assessmentRepo.saveAssessment(
        assessmentType: 'CHILD_IMMUNIZATION',
        assessmentDetails: {
          'vaccinations': records.map((r) => r.toJson()).toList(),
        },
        householdMemberLocalId: widget.householdMemberLocalId ?? 0,
        memberId: widget.memberId,
        householdId: widget.householdId,
        patientId: widget.patientId,
        villageId: widget.patient?.villageId,
        encounterId: widget.encounterId,
        isReferred: _referring,
        referredReasons: _referring && facilityLabel != null
            ? [facilityLabel]
            : null,
        otherDetails: _referring && _selectedFacilityId != null
            ? {'referralFacilityType': _selectedFacilityId}
            : null,
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

      if (mounted) {
        Navigator.of(context).pop();
        widget.onRecorded();
      }
    } on Object catch (e) {
      debugPrint('[_UpdateStatusSheetState] save error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _statusStrip() {
    final Color color;
    final Color surface;
    final IconData icon;
    final String text;
    if (widget.milestone.hasDueNow) {
      color = _kRed;
      // Mockup's exact fixed background for this state, not alpha-derived.
      surface = _kRedSurface;
      icon = Icons.warning_amber_rounded;
      text = widget.ageLabel.isNotEmpty
          ? 'Status: Due now · ${widget.patientName} is ${widget.ageLabel}'
          : 'Status: Due now';
    } else if (widget.milestone.hasMissed) {
      color = _kReferred;
      surface = color.withValues(alpha: 0.08);
      icon = Icons.event_busy_rounded;
      text = 'Status: ${EpiStrings.statusReferred}';
    } else {
      color = _kAmber;
      surface = color.withValues(alpha: 0.08);
      icon = Icons.schedule_rounded;
      text = 'Status: ${EpiStrings.statusUpcoming}';
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: surface,
        // Mockup's banner rounds only the corners away from the left
        // accent border, not all four.
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
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
          // Drag handle — mockup shows a small grey bar at the top of the sheet.
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
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
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sheetSubtitle(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
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

          _statusStrip(),

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

                  if (!_referring) ...[
                    // Date administered
                    _SectionLabel(EpiStrings.dateAdministered),
                    _DateField(
                      date: _givenDate,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _givenDate,
                          firstDate: widget.dob ?? DateTime(2020),
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
                          borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE5E7EB), width: 1.5),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Referral facility
                    _SectionLabel(EpiStrings.referralFacilityLabel),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedFacilityId,
                      hint: Text(
                        EpiStrings.referralFacilitySelectHint,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textMuted),
                      ),
                      onChanged: (id) => setState(() {
                        _selectedFacilityId = id;
                        _facilityError = null;
                      }),
                      decoration: InputDecoration(
                        errorText: _facilityError,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                      ),
                      items: referralFacilityOptions
                          .map((o) => DropdownMenuItem(
                              value: o.id, child: Text(o.label)))
                          .toList(),
                    ),

                    const SizedBox(height: 16),

                    // Missed reason
                    _SectionLabel(EpiStrings.missedReasonLabel),
                    TextField(
                      controller: _reasonCtrl,
                      maxLines: 3,
                      onChanged: (_) =>
                          setState(() => _reasonError = null),
                      decoration: InputDecoration(
                        hintText: EpiStrings.missedReasonHint,
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13),
                        errorText: _reasonError,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFD1D5DB)),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  if (!_referring) ...[
                    // Mark Complete → Refer → Cancel, all full-width and
                    // stacked — matches the mockup's stacked-button
                    // convention (it has no Refer path of its own, so this
                    // extends that convention to the extra action rather
                    // than reverting to a 2-up row).
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
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _referring = true),
                        icon: const Icon(Icons.event_busy_rounded,
                            size: 18, color: _kReferred),
                        label: Text(
                          EpiStrings.referCta,
                          style: const TextStyle(color: _kReferred),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _kReferred),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
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
                  ] else ...[
                    // Confirm referral + Back.
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
                            : const Icon(Icons.event_busy_rounded, size: 18),
                        label: Text(EpiStrings.confirmReferralCta),
                        style: FilledButton.styleFrom(
                          backgroundColor: _kReferred,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _referring = false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          side: const BorderSide(color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(EpiStrings.back),
                      ),
                    ),
                  ],
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      // v16 mockup's vaccine detail cards are flat, no border, tighter
      // padding than the previous pass used.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.chatBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < vaccines.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Text(
              vaccines[i].display,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.navy,
              ),
            ),
            if (vaccines[i].description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                vaccines[i].description,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
            if (vaccines[i].route.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                vaccines[i].route,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
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
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
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
