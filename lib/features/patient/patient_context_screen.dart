import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/phi_screen.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart' show MemberDao, HouseholdMemberEntity;
import '../../core/models/programme.dart';
import '../../core/models/risk.dart';
import 'member_detail_repository.dart';
import 'open_followups_section.dart';
import 'patient_actions_row.dart';
import 'patient_repository.dart';
import 'recent_vitals_section.dart';
import 'vitals_repository.dart';
import '../visit/briefing/visit_briefing_repository.dart';
import 'followup_repository.dart';
import '../../core/widgets/skeleton.dart';

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
    this.householdName,
  });

  final PatientWithProgrammes? localPatient;
  final MemberHealthDetails? remoteMember;
  final String? householdName;
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
  String? get nationalId =>
      localPatient?.patient.nationalId ?? remoteMember?.nationalId;
  String? get dateOfBirth =>
      localPatient?.patient.dob ?? remoteMember?.dateOfBirth;
  String? get maritalStatus => remoteMember?.maritalStatus;
  String? get disability => remoteMember?.disability;
  bool get isHouseholdHead => remoteMember?.isHouseholdHead ?? false;
  String? get shasthyaShebikaId => remoteMember?.shasthyaShebikaId;
  String? get guardianId => remoteMember?.guardianId;
  String? get guardianFhirId => remoteMember?.guardianFhirId;
  String? get motherReferenceId => remoteMember?.motherReferenceId;
  double? get latitude => remoteMember?.latitude;
  double? get longitude => remoteMember?.longitude;
  String? get idType => remoteMember?.idType;
  int? get riskScore => localPatient?.patient.riskScore;
  Band? get riskBand => localPatient?.patient.riskBand;
  Modifier? get riskModifier => localPatient?.patient.riskModifier;
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
class PatientContextScreen extends PhiScreen {
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
  PhiScreenState<PatientContextScreen> createState() =>
      _PatientContextScreenState();
}

class _PatientContextScreenState
    extends PhiScreenState<PatientContextScreen> {
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

  /// Looks up household name from the local DB. Returns null if not found.
  Future<String?> _householdName(String? householdId) async {
    if (householdId == null || householdId.isEmpty) return null;
    try {
      final dao = context.read<HouseholdDao>();
      final entity = await dao.getById(householdId);
      return entity?.name?.trim().isNotEmpty == true ? entity!.name : null;
    } on Object {
      return null;
    }
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
        final prog = Programme.fromString(e.programme);
        final serviceLabel = prog == Programme.unknown
            ? 'Assessment'
            : prog.wireTag;
        out.add(MemberAssessment(
          id: e.id,
          type: serviceLabel,
          date: date,
          status: e.status.name,
          rawJson: <String, dynamic>{
            'programme': e.programme,
            'status': e.status.name,
            'serverVisitId': e.serverVisitId,
            'encounterId': e.id,
            'serviceProvided': serviceLabel,
            if (e.triageData != null) ...e.triageData!,
            if (e.vitalsData != null) ...e.vitalsData!,
            if (e.assessmentData != null) ...e.assessmentData!,
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
      // ignore: avoid_print
      print('[PatientContextScreen] localDrafts for patientId=$stripped count=${drafts.length}');
      for (final d in drafts) {
        // ignore: avoid_print
        print('[PatientContextScreen]   draft id=${d.id} type=${d.assessmentType} syncStatus=${d.syncStatus.name} storedPatientId=${d.patientId}');
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

  /// Returns 'RelatedPerson/<id>' only when [id] is a numeric backend PK
  /// (< 10^10, i.e. a real server-assigned integer). FHIR patient IDs like
  /// '07007104021868' are 14-digit numbers that parse as int but are NOT
  /// backend member PKs — returning them would cause [getRecentVisits] to
  /// filter out every assessment-history row. Returning null instead tells
  /// [getRecentVisits] to skip client-side member filtering.
  String? _numericMemberRef(String id) {
    final n = int.tryParse(id);
    if (n == null || n >= 10000000000) return null; // not a backend PK
    return 'RelatedPerson/$id';
  }

  /// Resolves the numeric server-assigned member referenceId required by the
  /// FHIR mapper for [encounter.memberId].
  ///
  /// Priority:
  ///   1. Explicit referenceId passed in navigation extras (most reliable).
  ///   2. DB lookup by members.id (primary key = FHIR ID = widget.patientId).
  ///   3. DB lookup by members.patient_id column.
  ///   4. Fallback to extras['id'] or widget.patientId (FHIR ID — mapper may
  ///      still fail, but it is the best available value).
  Future<String> _resolveEncounterMemberId() async {
    // 1. Prefer the numeric referenceId pre-resolved by HouseholdDetailScreen.
    final fromExtras = widget.memberData?['referenceId'] as String?;
    if (fromExtras != null && fromExtras.isNotEmpty) {
      debugPrint('[PatientContext] memberId resolved from extras referenceId: $fromExtras');
      return fromExtras;
    }

    // 2 & 3. Look up the member entity from local DB.
    // The backend may store members with the numeric server PK as entity.id
    // (when no FHIR UUID is present) or as entity.referenceId. Mirror the same
    // resolution strategy used by MemberDetailRepository.getMemberAssessments:
    // collect all known IDs from the entity and prefer the numeric one.
    final memberDao = context.read<MemberDao>();
    final entity = await memberDao.getById(widget.patientId) ??
        await memberDao.getByPatientId(widget.patientId);

    if (entity != null) {
      // Prefer explicit referenceId field.
      if (entity.referenceId?.isNotEmpty == true) {
        debugPrint('[PatientContext] memberId resolved via entity.referenceId: ${entity.referenceId}');
        return entity.referenceId!;
      }
      // When entity.id is a pure numeric string it IS the backend integer PK
      // (the FHIR-ID slot was empty during sync and fell back to referenceId).
      if (int.tryParse(entity.id) != null) {
        debugPrint('[PatientContext] memberId resolved via entity.id (numeric): ${entity.id}');
        return entity.id;
      }
    }

    // 4. Fallback — FHIR ID; FHIR mapper will likely reject this but it is all
    //    we have when the member has no referenceId (e.g. newly enrolled, not yet synced).
    final fallback = widget.memberData?['id'] as String? ?? widget.patientId;
    debugPrint('[PatientContext] memberId fallback to FHIR ID: $fallback');
    return fallback;
  }

  Future<PatientOrMemberData> _fetchData() async {
    // ignore: avoid_print
    print('[PatientContextScreen] _fetchData for patientId: ${widget.patientId}');

    // Capture context-bound objects synchronously before any await to avoid
    // use_build_context_synchronously linter warnings.
    final memberRepo = context.read<MemberDetailRepository>();
    final patientRepo = context.read<PatientRepository>();

    // Resolve encounter.memberId once — shared by all three code paths below.
    // The FHIR mapper needs the numeric server-assigned referenceId, not the FHIR ID.
    final resolvedMemberId = await _resolveEncounterMemberId();

    // First try local patient database
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
      
      // Fetch recent visits — use numeric backend member PK so the client-side
      // filter in getRecentVisits matches householdMemberId from the API.
      final patientIdForVisits = localPatient.patient.patientId ?? widget.patientId;
      final memberRef = _numericMemberRef(resolvedMemberId);
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
        memberId: resolvedMemberId,
        householdName: await _householdName(localPatient.patient.householdId),
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
      
      // Fetch recent visits — use numeric backend member PK so the client-side
      // filter in getRecentVisits matches householdMemberId from the API.
      final patientIdForVisits = member.patientId ?? widget.patientId;
      final memberRef = _numericMemberRef(resolvedMemberId);
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
        memberId: resolvedMemberId,
        householdName: await _householdName(member.householdId),
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
      // Use the FHIR ID (member.id) only for resource references, not for encounter.memberId.
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
        // Use numeric backend member PK so the client-side filter matches.
        final memberRef = _numericMemberRef(resolvedMemberId);
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
        memberId: resolvedMemberId,
        householdName: await _householdName(data['householdId']?.toString()),
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
  Widget buildPhi(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: FutureBuilder<PatientOrMemberData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return SafeArea(
              child: SkeletonPatientDetail(
                name: widget.memberData?['name'] as String?,
              ),
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
          // Spec §2.8.3: Band 1 (Severe) and Band 2 (Moderate) are "urgent"
          // for context-screen styling purposes — both push the patient to
          // the same-day visit list.
          final isUrgent = data.riskBand == Band.band1 ||
              data.riskBand == Band.band2;
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
                      _GeminiSummaryBanner(
                        patientId: data.patientId ?? widget.patientId,
                        patientName: data.name,
                        ageYears: data.age,
                        gender: data.gender,
                        programmes: data.programmes,
                        fallbackReasons: data.riskReasons,
                      ),
                      const SizedBox(height: 10),
                      _PatientProfileCard(data: data),
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
                        memberId: data.memberId,
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
    final dateFormat = DateFormat('MMM d, yyyy · h:mm a');

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
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _AllAssessmentsSheet(
                          assessments: assessments,
                          dateFormat: dateFormat,
                        ),
                      );
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

/// Bottom sheet listing all assessments — shown when the SK taps "View all N assessments".
class _AllAssessmentsSheet extends StatelessWidget {
  const _AllAssessmentsSheet({
    required this.assessments,
    required this.dateFormat,
  });

  final List<MemberAssessment> assessments;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    PatientContextStrings.allAssessmentsTitle,
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
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: assessments.length,
                itemBuilder: (context, index) => _AssessmentTile(
                  assessment: assessments[index],
                  dateFormat: dateFormat,
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
    final raw = assessment.rawJson;
    // assessmentDetails is the nested clinical object from member-assessment-history
    final details = raw['assessmentDetails'] is Map
        ? Map<String, dynamic>.from(raw['assessmentDetails'] as Map)
        : <String, dynamic>{};
    // observations is the vitals snapshot keyed by the server (bp, weight, height, bg, bgType,
    // hemoglobin, ancVisitNumber, pncVisitNumber, fundalHeight, gravida, parity …)
    final obs = raw['observations'] is Map
        ? Map<String, dynamic>.from(raw['observations'] as Map)
        : <String, dynamic>{};

    // Lookup priority: assessmentDetails → observations → rawJson top-level
    double? num_(String key) {
      Object? v = details[key] ?? obs[key] ?? raw[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    String? str_(String key) {
      final v = details[key] ?? obs[key] ?? raw[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty || s == 'null' ? null : s;
    }

    bool? bool_(String key) {
      final v = details[key] ?? obs[key] ?? raw[key];
      if (v is bool) return v;
      if (v == true || v == 1 || v == 'true' || v == 'YES') return true;
      if (v == false || v == 0 || v == 'false' || v == 'NO') return false;
      return null;
    }

    // Parse "systolic/diastolic" string (server observations['bp'] format e.g. "120/80")
    (double, double)? parseBpString(String? s) {
      if (s == null) return null;
      final parts = s.split('/');
      if (parts.length != 2) return null;
      final sys = double.tryParse(parts[0].trim());
      final dia = double.tryParse(parts[1].trim());
      if (sys == null || dia == null) return null;
      return (sys, dia);
    }

    final fields = <_ClinicalField>[];

    switch (assessment.type) {
      case 'NCD':
        // BP: try numeric fields first, then obs['bp'] string
        var sys = num_('avgSystolic') ?? num_('systolicBp') ?? num_('systolic');
        var dia = num_('avgDiastolic') ?? num_('diastolicBp') ?? num_('diastolic');
        if (sys == null || dia == null) {
          final parsed = parseBpString(str_('bp'));
          if (parsed != null) { sys = parsed.$1; dia = parsed.$2; }
        }
        if (sys != null && dia != null) {
          fields.add(_ClinicalField('Blood Pressure', '${sys.toInt()}/${dia.toInt()} mmHg',
              icon: Icons.favorite, urgent: sys >= 140 || dia >= 90));
        }
        final glucose = num_('glucoseValue') ?? num_('bloodGlucose') ?? num_('bg');
        final glucoseType = str_('glucoseType') ?? str_('bgType');
        if (glucose != null) {
          final label = glucoseType != null ? 'Glucose (${glucoseType.toLowerCase()})' : 'Glucose';
          fields.add(_ClinicalField(label, '${glucose.toStringAsFixed(1)} mg/dL',
              icon: Icons.bloodtype, urgent: glucose > 200));
        }
        final height = num_('height'); final weight = num_('weight'); final bmi = num_('bmi');
        if (height != null) fields.add(_ClinicalField('Height', '${height.toInt()} cm', icon: Icons.straighten));
        if (weight != null) fields.add(_ClinicalField('Weight', '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        if (bmi != null) fields.add(_ClinicalField('BMI', bmi.toStringAsFixed(1), icon: Icons.calculate));
        final hb = num_('hemoglobin');
        if (hb != null) {
          fields.add(_ClinicalField('Haemoglobin', '${hb.toStringAsFixed(1)} g/dL',
              icon: Icons.opacity, urgent: hb < 10.0));
        }
        final smoker = bool_('isRegularSmoker') ?? bool_('isSmoking');
        if (smoker != null) fields.add(_ClinicalField('Smoking', smoker ? 'Yes' : 'No', icon: Icons.smoking_rooms));
        final alcohol = bool_('isDrinkingAlcohol') ?? bool_('alcoholConsumption');
        if (alcohol != null) fields.add(_ClinicalField('Alcohol', alcohol ? 'Yes' : 'No', icon: Icons.local_bar));

      case 'ANC':
        final ancVisit = str_('ancVisitNumber');
        if (ancVisit != null) fields.add(_ClinicalField('ANC Visit', ancVisit, icon: Icons.calendar_today));
        final ga = num_('gestationalAge') ?? num_('gestationAge');
        if (ga != null) fields.add(_ClinicalField('Gestational Age', '${ga.toInt()} weeks', icon: Icons.calendar_month));
        final gravida = str_('gravida');
        final parity = str_('parity');
        if (gravida != null || parity != null) {
          fields.add(_ClinicalField('G/P', 'G${gravida ?? '?'} P${parity ?? '?'}', icon: Icons.child_friendly));
        }
        final fetuses = num_('noOfFetus') ?? num_('numberOfFetus');
        if (fetuses != null && fetuses > 1) fields.add(_ClinicalField('Fetuses', fetuses.toInt().toString(), icon: Icons.group));
        final fh = num_('fundalHeight');
        if (fh != null) fields.add(_ClinicalField('Fundal Height', '${fh.toStringAsFixed(1)} cm', icon: Icons.height));
        // BP: try numeric fields first, then obs['bp'] string
        var sys = num_('avgSystolic') ?? num_('systolicBp');
        var dia = num_('avgDiastolic') ?? num_('diastolicBp');
        if (sys == null || dia == null) {
          final parsed = parseBpString(str_('bp'));
          if (parsed != null) { sys = parsed.$1; dia = parsed.$2; }
        }
        if (sys != null && dia != null) {
          fields.add(_ClinicalField('Blood Pressure', '${sys.toInt()}/${dia.toInt()} mmHg',
              icon: Icons.favorite, urgent: sys >= 140 || dia >= 90));
        }
        final weight = num_('weight');
        if (weight != null) fields.add(_ClinicalField('Weight', '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        final hb = num_('hemoglobin');
        if (hb != null) {
          fields.add(_ClinicalField('Haemoglobin', '${hb.toStringAsFixed(1)} g/dL',
              icon: Icons.opacity, urgent: hb < 10.0));
        }
        final glucose = num_('bg') ?? num_('glucoseValue') ?? num_('bloodGlucose');
        final glucoseType = str_('bgType') ?? str_('glucoseType');
        if (glucose != null) {
          final label = glucoseType != null ? 'Glucose (${glucoseType.toLowerCase()})' : 'Glucose';
          fields.add(_ClinicalField(label, '${glucose.toStringAsFixed(1)} mg/dL', icon: Icons.bloodtype));
        }
        final fetalMovement = bool_('fetalMovement') ?? bool_('isFetalMovementNormal');
        if (fetalMovement != null) {
          fields.add(_ClinicalField('Fetal Movement', fetalMovement ? 'Normal' : 'Abnormal',
              icon: Icons.waves, urgent: fetalMovement == false));
        }

      case 'PNC':
        final pncVisit = str_('pncVisitNumber');
        if (pncVisit != null) fields.add(_ClinicalField('PNC Visit', pncVisit, icon: Icons.calendar_today));
        // BP: try numeric fields first, then obs['bp'] string
        var sys = num_('avgSystolic') ?? num_('systolicBp');
        var dia = num_('avgDiastolic') ?? num_('diastolicBp');
        if (sys == null || dia == null) {
          final parsed = parseBpString(str_('bp'));
          if (parsed != null) { sys = parsed.$1; dia = parsed.$2; }
        }
        if (sys != null && dia != null) {
          fields.add(_ClinicalField('Blood Pressure', '${sys.toInt()}/${dia.toInt()} mmHg',
              icon: Icons.favorite, urgent: sys >= 140 || dia >= 90));
        }
        final weight = num_('weight');
        if (weight != null) fields.add(_ClinicalField('Weight', '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        final hb = num_('hemoglobin');
        if (hb != null) {
          fields.add(_ClinicalField('Haemoglobin', '${hb.toStringAsFixed(1)} g/dL',
              icon: Icons.opacity, urgent: hb < 10.0));
        }
        final breastfeeding = bool_('isBreastfeeding') ?? bool_('breastfeeding');
        if (breastfeeding != null) fields.add(_ClinicalField('Breastfeeding', breastfeeding ? 'Yes' : 'No', icon: Icons.child_friendly));

      case 'IMCI':
        final height = num_('height'); final weight = num_('weight'); final muac = num_('muac');
        if (height != null) fields.add(_ClinicalField('Height', '${height.toInt()} cm', icon: Icons.straighten));
        if (weight != null) fields.add(_ClinicalField('Weight', '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        if (muac != null) {
          fields.add(_ClinicalField('MUAC', '${muac.toStringAsFixed(1)} cm', icon: Icons.straighten,
              urgent: muac < 12.5));
        }
        final temp = num_('temperature') ?? num_('temp');
        if (temp != null) {
          fields.add(_ClinicalField('Temperature', '${temp.toStringAsFixed(1)} °C', icon: Icons.thermostat,
              urgent: temp >= 38.5));
        }
        final diagnosis = str_('childDiagnosis') ?? str_('diagnosis') ?? str_('classification');
        if (diagnosis != null) fields.add(_ClinicalField('Diagnosis', diagnosis, icon: Icons.medical_information));

      case 'TB':
        final cough = num_('coughDuration') ?? num_('durationOfCough');
        if (cough != null) fields.add(_ClinicalField('Cough Duration', '${cough.toInt()} days', icon: Icons.air));
        final diabetic = bool_('isDiabetic') ?? bool_('hasDiabetes');
        if (diabetic != null) fields.add(_ClinicalField('Diabetes', diabetic ? 'Yes' : 'No', icon: Icons.bloodtype));
        final smoking = bool_('isSmoking') ?? bool_('isRegularSmoker');
        if (smoking != null) fields.add(_ClinicalField('Smoking', smoking ? 'Yes' : 'No', icon: Icons.smoking_rooms));
        final contact = bool_('hasTbContact') ?? bool_('tbContact');
        if (contact != null) {
          fields.add(_ClinicalField('TB Contact', contact ? 'Yes' : 'No', icon: Icons.people,
              urgent: contact == true));
        }
    }

    if (fields.isEmpty) return const SizedBox.shrink();

    final (label, icon) = switch (assessment.type) {
      'NCD'  => ('NCD Screening Findings', Icons.monitor_heart_outlined),
      'ANC'  => ('Antenatal Care Findings', Icons.pregnant_woman),
      'PNC'  => ('Postnatal Care Findings', Icons.child_friendly),
      'IMCI' => ('Child Health Findings', Icons.child_care),
      'TB'   => ('TB Screening Findings', Icons.air),
      _      => ('Clinical Findings', Icons.assignment),
    };

    return Card(
      color: typeColor.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: typeColor, size: 18),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: typeColor, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...fields.map((f) => _ClinicalFieldRow(field: f)),
          ],
        ),
      ),
    );
  }
}

class _ClinicalField {
  const _ClinicalField(this.label, this.value, {this.icon, this.urgent = false});
  final String label;
  final String value;
  final IconData? icon;
  final bool urgent;
}

class _ClinicalFieldRow extends StatelessWidget {
  const _ClinicalFieldRow({required this.field});
  final _ClinicalField field;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = field.urgent ? scheme.error : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (field.icon != null)
            Icon(field.icon, size: 16, color: color.withValues(alpha: 0.7))
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Text(field.label,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              field.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: field.urgent ? scheme.error : null,
              ),
            ),
          ),
          if (field.urgent)
            const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
        ],
      ),
    );
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
// Patient Profile Card — collapsible demographic card. Shows identity,
// location, contact, care-team, and household-role fields sourced from
// HouseholdMemberEntity (Android-parity: matches HouseholdMemberEntity.kt).
// ─────────────────────────────────────────────────────────────────────────────

class _PatientProfileCard extends StatefulWidget {
  const _PatientProfileCard({required this.data});
  final PatientOrMemberData data;

  @override
  State<_PatientProfileCard> createState() => _PatientProfileCardState();
}

class _PatientProfileCardState extends State<_PatientProfileCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = widget.data;

    Widget buildRow(String label, String? value, {IconData? icon}) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSection(String title, List<Widget> rows) {
      final visible = rows.whereType<Padding>().isNotEmpty ||
          rows.any((w) => w is! SizedBox);
      if (!visible) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          ...rows,
        ],
      );
    }

    String? formatGps() {
      final lat = d.latitude;
      final lon = d.longitude;
      if (lat == null || lon == null) return null;
      return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
    }

    String? boolLabel(bool v) => v ? PatientProfileStrings.yes : null;

    final collapsed = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.nationalId != null)
          buildRow(PatientProfileStrings.labelNid, d.nationalId,
              icon: Icons.badge_outlined),
        if (d.dateOfBirth != null)
          buildRow(PatientProfileStrings.labelDob, d.dateOfBirth,
              icon: Icons.cake_outlined),
        if (d.phoneNumber != null)
          buildRow(PatientProfileStrings.labelPhone, d.phoneNumber,
              icon: Icons.phone_outlined),
        if (d.villageName != null)
          buildRow(PatientProfileStrings.labelVillage, d.villageName,
              icon: Icons.location_on_outlined),
      ],
    );

    final full = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSection(PatientProfileStrings.sectionIdentity, [
          buildRow(PatientProfileStrings.labelNid, d.nationalId,
              icon: Icons.badge_outlined),
          buildRow(PatientProfileStrings.labelGender, d.gender,
              icon: Icons.person_outline),
          buildRow(PatientProfileStrings.labelDob, d.dateOfBirth,
              icon: Icons.cake_outlined),
          buildRow(PatientProfileStrings.labelIdType, d.idType),
          buildRow(PatientProfileStrings.labelMaritalStatus, d.maritalStatus),
          buildRow(PatientProfileStrings.labelDisability, d.disability),
          buildRow(PatientProfileStrings.labelIsPregnant,
              d.isPregnant ? PatientProfileStrings.yes : null,
              icon: Icons.pregnant_woman),
        ]),
        buildSection(PatientProfileStrings.sectionLocation, [
          buildRow(PatientProfileStrings.labelVillage, d.villageName,
              icon: Icons.location_on_outlined),
          buildRow(PatientProfileStrings.labelGps, formatGps(),
              icon: Icons.gps_fixed),
        ]),
        buildSection(PatientProfileStrings.sectionContact, [
          buildRow(PatientProfileStrings.labelPhone, d.phoneNumber,
              icon: Icons.phone_outlined),
        ]),
        buildSection(PatientProfileStrings.sectionCareTeam, [
          buildRow(PatientProfileStrings.labelSk, d.shasthyaShebikaId,
              icon: Icons.health_and_safety_outlined),
          buildRow(PatientProfileStrings.labelGuardian, d.guardianId),
          buildRow(PatientProfileStrings.labelMother, d.motherReferenceId),
        ]),
        buildSection(PatientProfileStrings.sectionHousehold, [
          buildRow(PatientProfileStrings.labelIsHouseholdHead,
              boolLabel(d.isHouseholdHead),
              icon: Icons.house_outlined),
        ]),
      ],
    );

    final recentLabel = d.recentVisits.isNotEmpty
        ? _recentVisitLabel(d.recentVisits.first)
        : d.assessments.isNotEmpty
            ? _recentAssessmentLabel(d.assessments.first)
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_pin_outlined, color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      PatientProfileStrings.profileTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded
                            ? PatientProfileStrings.hide
                            : PatientProfileStrings.showMore,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _expanded ? full : collapsed,
              ],
            ),
          ),
        ),
        if (d.programmes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.medical_services_outlined,
                          size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Services Provided',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: d.programmes.map((p) {
                      final label = p.wireTag.toUpperCase();
                      return Chip(
                        label: Text(
                          label,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        backgroundColor: scheme.primaryContainer,
                        labelStyle:
                            TextStyle(color: scheme.onPrimaryContainer),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 2),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (recentLabel != null) ...[
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.history_rounded,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Status',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          recentLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _recentVisitLabel(PatientVisit v) {
    final svc = v.serviceProvided ?? v.encounterType ?? 'Visit';
    final date = DateFormat('MMM d, yyyy').format(v.visitDate);
    final status = v.status != null ? ' · ${v.status}' : '';
    return '$svc — $date$status';
  }

  static String _recentAssessmentLabel(MemberAssessment a) {
    final date = DateFormat('MMM d, yyyy').format(a.date);
    final status = a.status != null ? ' · ${a.status}' : '';
    return '${a.type} — $date$status';
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

  static const Color _headerColor = Color(0xFF831843);

  @override
  Widget build(BuildContext context) {
    final name = data.name ?? PatientContextStrings.fallbackTitle;

    final resolvedAge = data.age ?? _ageFromDob(data.dateOfBirth);
    final prefixParts = <String>[
      if (resolvedAge != null)
        resolvedAge == 0 ? '< 1 yr' : 'Age $resolvedAge',
      if (data.gender != null && data.gender!.isNotEmpty)
        data.gender!.toUpperCase().startsWith('F') ? 'Female' : 'Male',
    ];
    final subtitlePrefix = prefixParts.join(' · ');
    final householdLabel = data.householdName ??
        (data.householdId != null ? 'House #${data.householdId}' : null);

    final chips = <_HeaderChip>[
      if (data.nationalId != null)
        _HeaderChip(Icons.badge_outlined, data.nationalId!),
      if (data.phoneNumber != null)
        _HeaderChip(Icons.phone_outlined, data.phoneNumber!),
      if (data.villageName != null)
        _HeaderChip(Icons.location_on_outlined, data.villageName!),
      if (data.isPregnant)
        const _HeaderChip(Icons.pregnant_woman, 'Pregnant'),
    ];

    return Container(
      color: _headerColor,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack,
                  tooltip: PatientContextStrings.backToWorklist,
                ),
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
                      if (subtitlePrefix.isNotEmpty || householdLabel != null)
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            children: [
                              if (subtitlePrefix.isNotEmpty)
                                TextSpan(text: subtitlePrefix),
                              if (householdLabel != null) ...[
                                if (subtitlePrefix.isNotEmpty)
                                  const TextSpan(text: ' · '),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: const Icon(Icons.home_outlined,
                                      size: 12, color: Colors.white70),
                                ),
                                const TextSpan(text: ' '),
                                TextSpan(text: householdLabel),
                              ],
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: chips
                    .map(
                      (c) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(c.icon, size: 12, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              c.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
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

  static IconData _genderIcon(String g) {
    final u = g.toUpperCase();
    if (u.startsWith('F')) return Icons.female;
    if (u.startsWith('M')) return Icons.male;
    return Icons.person_outline;
  }

  static String _genderShort(String g) {
    final u = g.toUpperCase();
    if (u.startsWith('F')) return 'F';
    if (u.startsWith('M')) return 'M';
    return g;
  }

  static int? _ageFromDob(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    try {
      final birth = DateTime.parse(dob);
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) age--;
      return age;
    } catch (_) {
      return null;
    }
  }
}

class _HeaderChip {
  const _HeaderChip(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Gemini-powered 2-3 sentence patient summary shown at the top of the
/// patient context screen. Falls back to rule-based risk chips if the
/// AI service is unreachable.
class _GeminiSummaryBanner extends StatefulWidget {
  const _GeminiSummaryBanner({
    required this.patientId,
    this.patientName,
    this.ageYears,
    this.gender,
    this.programmes = const {},
    this.fallbackReasons = const [],
  });

  final String patientId;
  final String? patientName;
  final int? ageYears;
  final String? gender;
  final Set<Programme> programmes;
  final List<String> fallbackReasons;

  @override
  State<_GeminiSummaryBanner> createState() => _GeminiSummaryBannerState();
}

class _GeminiSummaryBannerState extends State<_GeminiSummaryBanner> {
  Future<String?>? _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _fetchSummary();
  }

  Future<String?> _fetchSummary() async {
    try {
      final vitalsRepo = context.read<VitalsRepository>();
      final followUpRepo = context.read<FollowUpRepository>();
      final briefingRepo = context.read<VisitBriefingRepository>();

      final visitsByVisit =
          await vitalsRepo.recentByVisit(widget.patientId, limit: 3);
      final followUps =
          await followUpRepo.openForPatientLocal(widget.patientId);

      Map<String, dynamic>? vitalsMap;
      if (visitsByVisit.isNotEmpty) {
        final latest = visitsByVisit.first;
        final bp = latest.readings
            .where((r) => r.type == VitalType.bloodPressure)
            .firstOrNull;
        final weight = latest.readings
            .where((r) => r.type == VitalType.weight)
            .firstOrNull;
        final glucose = latest.readings
            .where((r) => r.type == VitalType.glucose)
            .firstOrNull;
        final spo2 = latest.readings
            .where((r) => r.type == VitalType.spO2)
            .firstOrNull;
        vitalsMap = {
          if (bp?.systolic != null)
            'bloodPressureSystolic': bp!.systolic!.toInt(),
          if (bp?.diastolic != null)
            'bloodPressureDiastolic': bp!.diastolic!.toInt(),
          if (weight?.value != null) 'weight': weight!.value,
          if (glucose?.value != null) 'glucose': glucose!.value,
          if (spo2?.value != null) 'spO2': spo2!.value!.toInt(),
        };
      }

      final overdue = followUps.where((f) => f.isOverdue).length;
      final risks = <String>[
        if (overdue > 0) 'missed_followup',
        if (visitsByVisit.isNotEmpty) ...() {
          final bp = visitsByVisit.first.readings
              .where((r) => r.type == VitalType.bloodPressure)
              .firstOrNull;
          return bp?.systolic != null && bp!.systolic! >= 140
              ? ['elevated_bp']
              : <String>[];
        }(),
      ];

      final request = <String, dynamic>{
        'patientId': widget.patientId,
        if (widget.patientName != null) 'patientName': widget.patientName,
        if (widget.ageYears != null) 'ageYears': widget.ageYears,
        if (widget.gender != null) 'gender': widget.gender,
        'activeProgrammes': widget.programmes.map((p) => p.name).toList(),
        'visitCount': visitsByVisit.length,
        if (vitalsMap != null && vitalsMap.isNotEmpty) 'recentVitals': vitalsMap,
        'openFollowUps': followUps
            .map((f) => {
                  'type': f.type.name,
                  if (f.isOverdue)
                    'daysOverdue':
                        DateTime.now().difference(f.dueDate).inDays,
                  if (f.reason != null) 'reason': f.reason,
                })
            .toList(),
        'riskIndicators': risks,
      };

      return await briefingRepo.summary(request);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;

    return FutureBuilder<String?>(
      future: _summaryFuture,
      builder: (context, snap) {
        // Loading skeleton
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tokens.aiSurfaceStart, tokens.aiSurfaceEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  BorderRadius.circular(LeapfrogColors.radiusLg),
              border: Border.all(color: tokens.aiBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 18,
                  decoration: BoxDecoration(
                    color: tokens.aiPurple,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < 3; i++) ...[
                  Container(
                    height: 12,
                    width: i == 2 ? 180 : double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: tokens.aiPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        final summary = snap.data;

        // AI service unavailable — fall back to rule-based card
        if (summary == null || summary.isEmpty) {
          if (widget.fallbackReasons.isEmpty) return const SizedBox.shrink();
          return _AiSummaryCard(
            name: widget.patientName ?? PatientContextStrings.fallbackTitle,
            reasons: widget.fallbackReasons,
          );
        }

        // Gemini summary
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tokens.aiPurple,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '✦ AI SUMMARY',
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
                    summary,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: tokens.brandNavy,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
                          color: Theme.of(context).colorScheme.surface,
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
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
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
