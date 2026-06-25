import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/member_dao.dart' show MemberDao, HouseholdMemberEntity;
import '../../core/models/programme.dart';
import '../../core/models/risk.dart';
import 'member_detail_repository.dart';
import 'open_followups_section.dart';
import 'patient_actions_row.dart';
import 'patient_repository.dart';
import 'recent_vitals_section.dart';

/// Combined data type that can hold either a local patient or remote member.
class PatientOrMemberData {
  const PatientOrMemberData({
    this.localPatient,
    this.remoteMember,
    this.programmes = const {},
    this.remoteAssessments = const [],
    this.localAssessments = const [],
    this.recentVisits = const [],
    this.memberId,
  });

  final PatientWithProgrammes? localPatient;
  final MemberHealthDetails? remoteMember;
  final Set<Programme> programmes;
  final List<MemberAssessment> remoteAssessments;

  /// Locally-cached assessments — union of EncounterDao history,
  /// synced AssessmentDao rows, and sync-pending LocalAssessmentDao
  /// drafts. Surfaces records even when the remote /medical-review/history
  /// endpoint is unreachable or returns empty (offline-first §3.1).
  final List<MemberAssessment> localAssessments;
  final List<PatientVisit> recentVisits;
  final String? memberId;

  bool get hasData => localPatient != null || remoteMember != null;

  String? get name => localPatient?.patient.name ?? remoteMember?.name;
  String? get gender => localPatient?.patient.gender ?? remoteMember?.gender;
  String? get householdId =>
      localPatient?.patient.householdId ?? remoteMember?.householdId;
  String? get villageId =>
      localPatient?.patient.villageId ?? remoteMember?.villageId;
  String? get villageName => localPatient?.patient.villageName;
  String? get phoneNumber =>
      localPatient?.patient.phone ?? remoteMember?.phoneNumber;
  String? get patientId =>
      localPatient?.patient.patientId ?? remoteMember?.patientId;
  int? get age => localPatient?.patient.age ?? remoteMember?.age;
  bool get isPregnant => remoteMember?.isPregnant ?? false;
  int? get riskScore => localPatient?.patient.riskScore;
  RiskBand? get riskBand => localPatient?.patient.riskBand;
  List<String> get riskReasons => localPatient?.patient.riskReasons ?? [];
  /// Merged Recent Visits feed — locally-cached first (always available
  /// even offline), then remote-only rows the device hasn't synced yet.
  /// Deduped by [MemberAssessment.id], sorted DESC by date so newest sits
  /// at top of the section. Replaces the old remote-or-bust behavior that
  /// rendered "No assessments yet" whenever the API was offline / empty.
  List<MemberAssessment> get assessments {
    final byId = <String, MemberAssessment>{};
    void addAll(List<MemberAssessment> src) {
      for (final a in src) {
        final existing = byId[a.id];
        if (existing == null || a.date.isAfter(existing.date)) {
          byId[a.id] = a;
        }
      }
    }
    addAll(localAssessments);
    addAll(remoteAssessments);
    addAll(remoteMember?.assessments ?? const []);
    final out = byId.values.toList();
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }
  
  /// Member reference for FHIR API calls (format: RelatedPerson/xxx).
  String? get memberReference {
    final id = memberId ?? remoteMember?.id;
    if (id == null) return null;
    if (id.startsWith('RelatedPerson/')) return id;
    return 'RelatedPerson/$id';
  }
}

/// Patient/Member Context Screen — shows health details when tapping on a
/// patient from the worklist or a member from household details.
class PatientContextScreen extends StatefulWidget {
  const PatientContextScreen({
    super.key,
    required this.patientId,
    this.memberData,
    this.origin,
  });

  final String patientId;
  /// Pre-populated member data passed from household detail.
  /// If provided, skips remote lookup when local patient not found.
  final Map<String, dynamic>? memberData;
  /// Origin screen for return navigation after visit ('dashboard' or 'tasks').
  final String? origin;

  @override
  State<PatientContextScreen> createState() => _PatientContextScreenState();
}

class _PatientContextScreenState extends State<PatientContextScreen> {
  Future<PatientOrMemberData>? _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Initialize directly without setState since widget isn't mounted yet
    _future = _fetchData();
  }

  void _load() {
    final future = _fetchData();
    setState(() {
      _future = future;
    });
  }

  /// Build the local-first Recent Visits feed from three on-device sources.
  /// Spec: dashboard-prioritization-impl §Patient Detail; matches the
  /// offline-first contract (architecture.md §3.1). Returns deduped list
  /// sorted DESC by date.
  Future<List<MemberAssessment>> _localAssessmentsFor(String patientId) async {
    final stripped = patientId.contains('/')
        ? patientId.substring(patientId.lastIndexOf('/') + 1)
        : patientId;
    final encounters = context.read<EncounterDao>();
    final assessments = context.read<AssessmentDao>();
    final localDrafts = context.read<LocalAssessmentDao>();

    final out = <MemberAssessment>[];

    try {
      final encs = await encounters.recentForPatient(stripped, limit: 50);
      // ignore: avoid_print
      print('[PatientContextScreen] localAssessmentsFor in=$patientId norm=$stripped encs=${encs.length}');
      for (final e in encs) {
        final date = DateTime.fromMillisecondsSinceEpoch(
            e.completedAt ?? e.startedAt);
        out.add(MemberAssessment(
          id: e.id,
          type: e.programme.toUpperCase(),
          date: date,
          status: e.status.name,
          rawJson: <String, dynamic>{
            'programme': e.programme,
            'status': e.status.name,
            'serverVisitId': e.serverVisitId,
          },
        ));
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('[PatientContextScreen] local encounters fetch failed: $e');
    }

    try {
      final asMap = await assessments.forMany([stripped]);
      for (final row in asMap[stripped] ?? const []) {
        final date = row.occurredAt == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(row.occurredAt!);
        out.add(MemberAssessment(
          id: row.id,
          type: (row.kind ?? 'Assessment').toUpperCase(),
          date: date,
          rawJson: <String, dynamic>{'kind': row.kind, 'raw': row.rawJson},
        ));
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('[PatientContextScreen] local assessments fetch failed: $e');
    }

    try {
      final drafts = await localDrafts.getByPatientId(stripped);
      for (final d in drafts) {
        out.add(MemberAssessment(
          id: d.id.toString(),
          type: d.assessmentType.toUpperCase(),
          date: d.createdAt ?? DateTime.now(),
          status: d.syncStatus.name,
          notes: d.referredReasons,
          rawJson: <String, dynamic>{
            'isReferred': d.isReferred,
            'referralStatus': d.referralStatus,
            'syncStatus': d.syncStatus.name,
          },
        ));
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('[PatientContextScreen] local drafts fetch failed: $e');
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    // ignore: avoid_print
    print('[PatientContextScreen] localAssessmentsFor total=${out.length}');
    return out;
  }

  Future<PatientOrMemberData> _fetchData() async {
    // ignore: avoid_print
    print('[PatientContextScreen] _fetchData for patientId: ${widget.patientId}');

    final memberRepo = context.read<MemberDetailRepository>();

    // First try local patient database
    final patientRepo = context.read<PatientRepository>();
    final localPatient = await patientRepo.byId(widget.patientId);
    if (localPatient != null) {
      // ignore: avoid_print
      print('[PatientContextScreen] Found local patient: ${localPatient.patient.name}');

      // Scope history query to the patient's own village — falling back to all
      // assigned villages when villageId is null. Previously used
      // subVillageIds.first which silently excluded patients in other villages.
      // ignore: avoid_print
      print('[PatientContextScreen] Fetching assessments from remote API with villageId: ${localPatient.patient.villageId}...');
      final assessments = await memberRepo.getMemberAssessments(
        widget.patientId,
        villageId: localPatient.patient.villageId,
        patientAge: localPatient.patient.age,
        patientGender: localPatient.patient.gender,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${assessments.length} remote assessments');
      
      // Fetch recent visits
      final patientIdForVisits = localPatient.patient.patientId ?? widget.patientId;
      final memberRef = 'RelatedPerson/${widget.patientId}';
      // ignore: avoid_print
      print('[PatientContextScreen] Fetching recent visits for patient: $patientIdForVisits, member: $memberRef, householdId: ${localPatient.patient.householdId}');
      final visits = await memberRepo.getRecentVisits(
        patientIdForVisits,
        memberReference: memberRef,
        householdId: localPatient.patient.householdId,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${visits.length} recent visits');
      
      final localAssessments =
          await _localAssessmentsFor(widget.patientId);
      return PatientOrMemberData(
        localPatient: localPatient,
        programmes: localPatient.programmes,
        remoteAssessments: assessments,
        localAssessments: localAssessments,
        recentVisits: visits,
        memberId: widget.patientId,
      );
    }

    // ignore: avoid_print
    print('[PatientContextScreen] No local patient, trying remote member API');
    
    // If not found locally, try fetching member from remote API
    final member = await memberRepo.getMemberWithAssessments(widget.patientId);
    if (member != null) {
      // ignore: avoid_print
      print('[PatientContextScreen] Found remote member: ${member.name} with ${member.assessments.length} assessments');
      // Determine programmes from assessments
      final progs = <Programme>{};
      for (final a in member.assessments) {
        switch (a.type) {
          case 'ANC':
            progs.add(Programme.anc);
            break;
          case 'IMCI':
            progs.add(Programme.imci);
            break;
          case 'NCD':
            progs.add(Programme.ncd);
            break;
          case 'TB':
            progs.add(Programme.tb);
            break;
        }
      }
      
      // Fetch recent visits
      final patientIdForVisits = member.patientId ?? widget.patientId;
      final memberRef = 'RelatedPerson/${member.id}';
      // ignore: avoid_print
      print('[PatientContextScreen] Fetching recent visits for patient: $patientIdForVisits, member: $memberRef, householdId: ${member.householdId}');
      final visits = await memberRepo.getRecentVisits(
        patientIdForVisits,
        memberReference: memberRef,
        householdId: member.householdId,
      );
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${visits.length} recent visits');
      
      final localAssessments = await _localAssessmentsFor(widget.patientId);
      return PatientOrMemberData(
        remoteMember: member,
        programmes: progs,
        localAssessments: localAssessments,
        recentVisits: visits,
        memberId: member.id,
      );
    }

    // If we have pre-passed member data from household detail, use it
    if (widget.memberData != null) {
      // ignore: avoid_print
      print('[PatientContextScreen] Using pre-passed member data from household');
      final data = widget.memberData!;
      // Extract patient profile for filtering
      final age = data['age'] as int?;
      final gender = data['gender'] as String?;
      final isPregnant = data['isPregnant'] as bool? ?? false;
      final memberId = data['id']?.toString() ?? widget.patientId;
      
      // Try to fetch assessments but don't fail if API is unavailable.
      // Pass villageId: null so the call falls back to all assigned villages
      // rather than only the first one (which would miss patients in other villages).
      List<MemberAssessment> assessments = [];
      try {
        assessments = await memberRepo.getMemberAssessments(
          widget.patientId,
          patientAge: age,
          patientGender: gender,
          isPregnant: isPregnant,
        );
        // ignore: avoid_print
        print('[PatientContextScreen] Found ${assessments.length} assessments for pre-passed member');
      } catch (e) {
        // ignore: avoid_print
        print('[PatientContextScreen] Failed to fetch assessments: $e (continuing with basic info)');
      }
      
      // Determine programmes from assessments
      final progs = <Programme>{};
      for (final a in assessments) {
        switch (a.type) {
          case 'ANC':
            progs.add(Programme.anc);
            break;
          case 'IMCI':
            progs.add(Programme.imci);
            break;
          case 'NCD':
            progs.add(Programme.ncd);
            break;
          case 'TB':
            progs.add(Programme.tb);
            break;
        }
      }
      
      // Try to fetch recent visits but don't fail if API is unavailable
      List<PatientVisit> visits = [];
      try {
        final patientIdForVisits = data['patientId'] as String? ?? widget.patientId;
        final memberRef = 'RelatedPerson/$memberId';
        final householdIdForVisits = data['householdId']?.toString();
        // ignore: avoid_print
        print('[PatientContextScreen] Fetching recent visits for patient: $patientIdForVisits, member: $memberRef, householdId: $householdIdForVisits');
        visits = await memberRepo.getRecentVisits(
          patientIdForVisits,
          memberReference: memberRef,
          householdId: householdIdForVisits,
        );
        // ignore: avoid_print
        print('[PatientContextScreen] Found ${visits.length} recent visits');
      } catch (e) {
        // ignore: avoid_print
        print('[PatientContextScreen] Failed to fetch recent visits: $e (continuing with basic info)');
      }
      
      final localAssessmentsList =
          await _localAssessmentsFor(widget.patientId);
      return PatientOrMemberData(
        remoteMember: MemberHealthDetails(
          id: memberId,
          name: data['name'] as String? ?? 'Unknown',
          gender: data['gender'] as String?,
          age: data['age'] as int?,
          dateOfBirth: data['dateOfBirth'] as String?,
          phoneNumber: data['phoneNumber'] as String?,
          householdId: data['householdId']?.toString(),
          isPregnant: data['isPregnant'] as bool? ?? false,
          patientId: data['patientId'] as String?,
          assessments: assessments,
        ),
        programmes: progs,
        remoteAssessments: assessments,
        localAssessments: localAssessmentsList,
        recentVisits: visits,
        memberId: memberId,
      );
    }

    // ignore: avoid_print
    print('[PatientContextScreen] No member found either');
    return const PatientOrMemberData();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final data = await _fetchData();
      if (!mounted) return;
      setState(() => _future = Future.value(data));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PatientContextStrings.refreshDone)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(PatientContextStrings.refreshFailed)),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: FutureBuilder<PatientOrMemberData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SafeArea(
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snap.data;
          if (data == null || !data.hasData) {
            return SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_search_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        PatientContextStrings.notFound,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.tonal(
                        onPressed: _load,
                        child: const Text(CommonStrings.retry),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final isUrgent = data.riskBand == RiskBand.urgent ||
              data.riskBand == RiskBand.high;
          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                _PatientDetailHeader(
                  data: data,
                  isUrgent: isUrgent,
                  refreshing: _refreshing,
                  onBack: () => Navigator.of(context).maybePop(),
                  onRefresh: _refreshing ? null : _refresh,
                ),
                // Same-household strip per spec Phase 5
                if (data.householdId != null)
                  _SameHouseholdStrip(
                    currentPatientId: widget.patientId,
                    householdId: data.householdId!,
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
                    children: [
                      _GreetingCard(data: data),
                      const SizedBox(height: 10),
                      if (data.riskReasons.isNotEmpty)
                        _AiSummaryCard(
                          name: data.name ?? PatientContextStrings.fallbackTitle,
                          reasons: data.riskReasons,
                        ),
                      if (data.riskReasons.isNotEmpty)
                        const SizedBox(height: 10),
                      _AssessmentsSection(assessments: data.assessments),
                      const SizedBox(height: 10),
                      RecentVitalsSection(
                        patientId: data.patientId ?? widget.patientId,
                        memberReference: data.memberReference,
                      ),
                      const SizedBox(height: 10),
                      OpenFollowupsSection(
                        patientId: widget.patientId,
                        memberReference: data.memberReference,
                      ),
                      const SizedBox(height: 10),
                      PatientActionsRow(
                        patientId: widget.patientId,
                        patientName: data.name,
                        patientAge: data.age,
                        patientGender: data.gender,
                        householdId: data.householdId,
                        villageId: data.villageId,
                        programmes: data.programmes,
                        origin: widget.origin,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


/// Section showing assessment history.
class _AssessmentsSection extends StatelessWidget {
  const _AssessmentsSection({required this.assessments});

  final List<MemberAssessment> assessments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy');

    if (assessments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assignment_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    PatientContextStrings.sectionRecentVisits,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history_outlined,
                      size: 48,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No assessments yet',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  PatientContextStrings.sectionRecentVisits,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                Text(
                  '${assessments.length} total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...assessments.take(5).map((a) => _AssessmentTile(
                  assessment: a,
                  dateFormat: dateFormat,
                )),
            if (assessments.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      // TODO: Show full assessment list
                    },
                    child: Text('View all ${assessments.length} assessments'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({
    required this.assessment,
    required this.dateFormat,
  });

  final MemberAssessment assessment;
  final DateFormat dateFormat;

  void _showAssessmentDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AssessmentDetailSheet(
        assessment: assessment,
        dateFormat: dateFormat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;

    Color typeColor;
    IconData typeIcon;
    switch (assessment.type) {
      case 'ANC':
        typeColor = progColors.of(Programme.anc);
        typeIcon = Icons.pregnant_woman;
        break;
      case 'IMCI':
        typeColor = progColors.of(Programme.imci);
        typeIcon = Icons.child_care;
        break;
      case 'NCD':
        typeColor = progColors.of(Programme.ncd);
        typeIcon = Icons.monitor_heart_outlined;
        break;
      case 'TB':
        typeColor = progColors.of(Programme.tb);
        typeIcon = Icons.healing;
        break;
      default:
        typeColor = scheme.primary;
        typeIcon = Icons.assignment;
    }

    return Semantics(
      label: 'View ${assessment.type} assessment on ${dateFormat.format(assessment.date)}',
      button: true,
      child: InkWell(
      key: const Key('patient_assessment_row_tap'),
      onTap: () => _showAssessmentDetail(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(typeIcon, size: 20, color: typeColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          assessment.type,
                          style: TextStyle(
                            color: typeColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      if (assessment.visitNumber != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Visit ${assessment.visitNumber}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateFormat.format(assessment.date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
      ),
    );
  }
}

/// Bottom sheet showing assessment details.
class _AssessmentDetailSheet extends StatelessWidget {
  const _AssessmentDetailSheet({
    required this.assessment,
    required this.dateFormat,
  });

  final MemberAssessment assessment;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    final raw = assessment.rawJson;
    
    Color typeColor;
    IconData typeIcon;
    switch (assessment.type) {
      case 'ANC':
        typeColor = progColors.of(Programme.anc);
        typeIcon = Icons.pregnant_woman;
        break;
      case 'IMCI':
        typeColor = progColors.of(Programme.imci);
        typeIcon = Icons.child_care;
        break;
      case 'NCD':
        typeColor = progColors.of(Programme.ncd);
        typeIcon = Icons.monitor_heart_outlined;
        break;
      case 'TB':
        typeColor = progColors.of(Programme.tb);
        typeIcon = Icons.healing;
        break;
      default:
        typeColor = scheme.primary;
        typeIcon = Icons.assignment;
    }

    // Extract useful fields from rawJson
    final serviceProvided = raw['serviceProvided']?.toString();
    final referralStatus = raw['referralStatus']?.toString();
    final referralReason = raw['referralReason']?.toString();
    final nextFollowUpDate = raw['nextFollowUpDate']?.toString();
    final memberId = raw['householdMemberId']?.toString();
    final encounterId = raw['encounterId']?.toString();
    final latestVisit = raw['latestVisit'] == true;
    final customStatus = raw['customStatus'] as List<dynamic>?;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(typeIcon, size: 28, color: typeColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  assessment.type,
                                  style: TextStyle(
                                    color: typeColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (latestVisit) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusSuccess.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Latest',
                                    style: TextStyle(
                                      color: AppColors.statusSuccess,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Visit on ${dateFormat.format(assessment.date)}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _DetailRow(label: 'Service', value: serviceProvided ?? assessment.type),
                    if (assessment.visitNumber != null)
                      _DetailRow(label: 'Visit Number', value: '${assessment.visitNumber}'),
                    if (encounterId != null)
                      _DetailRow(label: 'Encounter ID', value: encounterId),
                    if (memberId != null)
                      _DetailRow(label: 'Member ID', value: memberId),
                    if (referralStatus != null && referralStatus.isNotEmpty)
                      _DetailRow(
                        label: 'Referral Status',
                        value: referralStatus,
                        valueColor: referralStatus.toLowerCase() == 'referred' ? AppColors.statusWarning : null,
                      ),
                    if (referralReason != null && referralReason.isNotEmpty)
                      _DetailRow(label: 'Referral Reason', value: referralReason),
                    if (nextFollowUpDate != null && nextFollowUpDate.isNotEmpty)
                      _DetailRow(label: 'Next Follow-up', value: nextFollowUpDate),
                    if (customStatus != null && customStatus.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Status Indicators',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: customStatus.map((s) => Chip(
                          label: Text(s.toString()),
                          backgroundColor: typeColor.withValues(alpha: 0.1),
                          labelStyle: TextStyle(color: typeColor, fontSize: 12),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Assessment type specific info
                    _buildTypeSpecificInfo(context, typeColor),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeSpecificInfo(BuildContext context, Color typeColor) {
    final scheme = Theme.of(context).colorScheme;
    
    switch (assessment.type) {
      case 'ANC':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pregnant_woman, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'Antenatal Care Visit',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'This visit included routine prenatal checkups, fetal monitoring, and maternal health assessment.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      case 'IMCI':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.child_care, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'Child Health Visit',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Integrated Management of Childhood Illness assessment including growth monitoring, immunization status, and illness screening.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      case 'NCD':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.monitor_heart_outlined, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'NCD Screening',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Non-communicable disease screening including blood pressure, glucose levels, and cardiovascular risk assessment.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      case 'TB':
        return Card(
          color: typeColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.healing, color: typeColor),
                    const SizedBox(width: 8),
                    Text(
                      'TB Screening',
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tuberculosis screening including symptom assessment, contact tracing, and treatment monitoring.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HTML-composition widgets for the Patient Detail screen.
// Match `Leapfrog .html` patient summary view: purple header strip, greeting
// card with bilingual prompt, AI summary card with lavender background.
// ─────────────────────────────────────────────────────────────────────────────

class _PatientDetailHeader extends StatelessWidget {
  const _PatientDetailHeader({
    required this.data,
    required this.isUrgent,
    required this.refreshing,
    required this.onBack,
    required this.onRefresh,
  });

  final PatientOrMemberData data;
  final bool isUrgent;
  final bool refreshing;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final name = data.name ?? PatientContextStrings.fallbackTitle;
    final subtitleParts = <String>[];
    if (data.age != null) subtitleParts.add('Age ${data.age}');
    if (data.gender != null) subtitleParts.add(data.gender!);
    if (data.householdId != null) subtitleParts.add('HH ${data.householdId}');
    final subtitle = subtitleParts.join(' · ');

    return Container(
      color: tokens.aiPurpleDark,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
                tooltip: PatientContextStrings.backToWorklist,
              ),
              Expanded(
                child: Text(
                  PatientContextStrings.backToWorklist,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isUrgent)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: tokens.statusCritical,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'URGENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              IconButton(
                tooltip: PatientContextStrings.refresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_download_outlined,
                        color: Colors.white),
                onPressed: onRefresh,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
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
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.data});

  final PatientOrMemberData data;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.waving_hand, size: 18, color: tokens.statusInfo),
              const SizedBox(width: 6),
              Text(
                PatientContextStrings.sayHelloFirst,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: tokens.statusInfo,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.statusInfoSurface,
              borderRadius: BorderRadius.circular(LeapfrogColors.radiusMd),
              border: Border(
                left: BorderSide(color: tokens.statusInfo, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PatientContextStrings.greetingBangla,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.brandNavy,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  PatientContextStrings.greetingEnglish,
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.statusInfo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSummaryCard extends StatelessWidget {
  const _AiSummaryCard({required this.name, required this.reasons});

  final String name;
  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tokens.aiSurfaceStart, tokens.aiSurfaceEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(LeapfrogColors.radiusLg),
        border: Border.all(color: tokens.aiBorder),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -2,
            right: -2,
            child: Text(
              '✦',
              style: TextStyle(
                fontSize: 32,
                color: tokens.aiPurple.withValues(alpha: 0.18),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.aiPurple,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '✦ AI READ HER RECORD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                PatientContextStrings.aiSummaryLead(name),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.brandNavy,
                  height: 1.5,
                ),
              ),
              if (reasons.isNotEmpty) const SizedBox(height: 8),
              if (reasons.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in reasons.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tokens.cardSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.aiBorder),
                        ),
                        child: Text(
                          '⚠ $r',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tokens.aiPurpleDark,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal chip strip showing other members of the same household.
/// Hidden when the household has only the current patient.
/// Per spec Phase 5: Household clustering = info chip strip on patient
/// detail screen, not main-list reorder.
class _SameHouseholdStrip extends StatelessWidget {
  const _SameHouseholdStrip({
    required this.currentPatientId,
    required this.householdId,
  });

  final String currentPatientId;
  final String householdId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final memberDao = context.read<MemberDao>();

    return FutureBuilder<List<HouseholdMemberEntity>>(
      future: memberDao.getByHouseholdId(householdId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final members = snap.data!;
        // Filter out current patient and empty names
        final others = members
            .where((m) =>
                m.id != currentPatientId &&
                m.name != null &&
                m.name!.isNotEmpty)
            .toList();
        if (others.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.cardSurface,
            border: Border(
              bottom: BorderSide(
                color: tokens.textMuted.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Make header tappable to navigate to household detail
              Semantics(
                label: 'View household details',
                button: true,
                child: GestureDetector(
                key: const Key('patient_household_header_tap'),
                onTap: () {
                  context.push('/patients/household/$householdId');
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.home_outlined,
                      size: 14,
                      color: tokens.brandNavy,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Same household',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tokens.brandNavy,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.brandNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${others.length + 1}', // +1 for current patient
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: tokens.brandNavy,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: tokens.brandNavy,
                    ),
                  ],
                ),
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: others.map((m) {
                    final name = m.name ?? 'Unknown';
                    final age = _ageFromDob(m.dob);
                    // Patient-scoped DAOs key on the national-ID-style
                    // patient_id (e.g. `0390444751459`), not the internal
                    // member.id. Push patientId when present so the
                    // detail screen + downstream repositories find rows.
                    final navId = (m.patientId != null &&
                            m.patientId!.isNotEmpty)
                        ? m.patientId!
                        : m.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _HouseholdMemberChip(
                        name: name,
                        age: age,
                        onTap: () {
                          context.push('/patient/$navId');
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int? _ageFromDob(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    try {
      final birthDate = DateTime.parse(dob);
      final now = DateTime.now();
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }
}

/// Individual chip for a household member in the same-household strip.
class _HouseholdMemberChip extends StatelessWidget {
  const _HouseholdMemberChip({
    required this.name,
    required this.age,
    required this.onTap,
  });

  final String name;
  final int? age;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final ageText = age != null ? ' · ${age}y' : '';
    return Semantics(
      label: 'View patient $name${age != null ? ', age $age' : ''}',
      button: true,
      child: GestureDetector(
      key: const Key('patient_member_chip_tap'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.brandNavy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: tokens.brandNavy.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: tokens.brandNavy.withValues(alpha: 0.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: tokens.brandNavy,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$name$ageText',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.brandNavy,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: tokens.brandNavy.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
