import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/debug/console_log.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/time/calendar_day.dart';
import '../../core/widgets/header_icon_button.dart';
import '../../core/widgets/phi_screen.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart' show MemberDao, HouseholdMemberEntity;
import '../../core/sync/offline_sync_service.dart';
import '../../core/models/programme.dart';
import '../../core/models/risk.dart';
import 'member_detail_repository.dart';
import 'open_followups_section.dart';
import 'patient_actions_row.dart';
import 'patient_repository.dart';
import '../assistant/patient_ai_sheet.dart';
import 'contact_sheet.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../../core/widgets/skeleton.dart';
import 'vitals_repository.dart';

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
    this.vitalHistory = const [],
    this.pregnancySnapshot,
  });

  final PatientWithProgrammes? localPatient;
  final MemberHealthDetails? remoteMember;
  final String? householdName;
  final Set<Programme> programmes;
  final List<MemberAssessment> remoteAssessments;

  /// Per-visit vitals history from local SQLite (offline-first). Used for
  /// spark bar trend charts on the care threads profile card.
  final List<VisitVitals> vitalHistory;

  /// Pregnancy snapshot (LMP, EDD, risk flags) from local SQLite. Null when
  /// the patient has no pregnancy episode stored.
  final PregnancySnapshotRow? pregnancySnapshot;

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

  PatientOrMemberData copyWith({
    List<MemberAssessment>? remoteAssessments,
    List<PatientVisit>? recentVisits,
    String? householdName,
    List<VisitVitals>? vitalHistory,
    PregnancySnapshotRow? pregnancySnapshot,
  }) {
    return PatientOrMemberData(
      localPatient: localPatient,
      remoteMember: remoteMember,
      programmes: programmes,
      localAssessments: localAssessments,
      remoteAssessments: remoteAssessments ?? this.remoteAssessments,
      recentVisits: recentVisits ?? this.recentVisits,
      memberId: memberId,
      householdName: householdName ?? this.householdName,
      vitalHistory: vitalHistory ?? this.vitalHistory,
      pregnancySnapshot: pregnancySnapshot ?? this.pregnancySnapshot,
    );
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
  PatientOrMemberData? _localSnapshot;
  bool _remoteLoading = false;
  /// Index of the currently selected care-thread chip. Drives [_StatsGrid] and
  /// spark chart selection. Reset to 0 whenever threads are re-derived.
  int _selectedThread = 0;

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
            ? PatientContextStrings.genericAssessmentLabel
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
        final prog = Programme.fromString(row.kind ?? '');
        final typeLabel = prog == Programme.unknown
            ? (row.kind ?? PatientContextStrings.genericAssessmentLabel).toUpperCase()
            : prog.wireTag;
        out.add(MemberAssessment(
          id: row.id,
          type: typeLabel,
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
    final syncSvc = context.read<OfflineSyncService>();
    final vitalsRepo = context.read<VitalsRepository>();
    final pregnancyDao = context.read<PregnancySnapshotDao>();

    final t0 = Stopwatch()..start();
    // Phase 1: all local reads in parallel — returns instantly from SQLite.
    final phase1 = await Future.wait([
      _resolveEncounterMemberId(),
      patientRepo.byId(widget.patientId),
      _localAssessmentsFor(widget.patientId),
      syncSvc.lastSyncedAt(),
      vitalsRepo.recentByVisit(widget.patientId).catchError((_) => <VisitVitals>[]),
      pregnancyDao.byPatient(widget.patientId).catchError((_) => null),
    ]);
    final resolvedMemberId = phase1[0] as String?;
    final localPatient = phase1[1] as PatientWithProgrammes?;
    final localAssessments = phase1[2] as List<MemberAssessment>;
    final lastSync = phase1[3] as DateTime?;
    final vitalHistory = phase1[4] as List<VisitVitals>;
    final pregnancySnapshot = phase1[5] as PregnancySnapshotRow?;
    debugPrint('⏱ [PatientContext] phase1 total=${t0.elapsedMilliseconds}ms'
        ' vitals=${vitalHistory.length} pregnancy=${pregnancySnapshot != null}');
    final syncAge = lastSync != null ? DateTime.now().difference(lastSync) : null;
    // Skip remote assessment fetch when a full sync completed within the last
    // 30 minutes — the local DB already has everything the server would return.
    final skipRemote = syncAge != null && syncAge.inMinutes < 30;
    ConsoleLog.banner('[PatientCtx] phase1 local=${t0.elapsedMilliseconds}ms'
        ' localPatient=${localPatient != null} localAssessments=${localAssessments.length}'
        ' syncAge=${syncAge?.inMinutes ?? '?'}min skipRemote=$skipRemote');

    if (localPatient != null) {
      // ignore: avoid_print
      print('[PatientContextScreen] Found local patient: ${localPatient.patient.name}');
      assert(() {
        final p = localPatient.patient;
        final band = p.riskBand ?? Band.band4;
        final modifier = p.riskModifier ?? Modifier.none;
        final code = '${band.wireTag.replaceFirst('band', '')}'
            '${modifier == Modifier.none ? '' : modifier.wireTag}';
        final progs = localPatient.programmes.map((pr) => pr.name).join(',');
        final now = DateTime.now();
        final overdueDays = p.nextDueAt != null
            ? CalendarDay
                .daysBetween(
                  DateTime.fromMillisecondsSinceEpoch(p.nextDueAt!),
                  now,
                )
                .clamp(0, 999)
            : null;
        final tier = p.nextDueAt != null
            ? DashboardTier.fromDueAt(
                DateTime.fromMillisecondsSinceEpoch(p.nextDueAt!),
                now: now,
              )
            : DashboardTier.upcoming;
        final overdueTag =
            (overdueDays != null && overdueDays > 0) ? ' | overdue: ${overdueDays}d' : '';
        final pregnant = localPatient.programmes.contains(Programme.anc);
        ConsoleLog.banner(
          '[Patient opened] [$code] ${p.name ?? widget.patientId}'
          ' | prog: $progs | tier: ${tier.name}'
          '${pregnant ? " | pregnant" : ""}'
          '$overdueTag'
          ' | sortRank: ${sortRankFor(band, modifier)}',
        );
        if (p.riskReasons.isNotEmpty) {
          ConsoleLog.banner('  Why $code:');
          for (final r in p.riskReasons) {
            ConsoleLog.banner('    • $r');
          }
        } else {
          ConsoleLog.banner('  Why $code: (no clinical reasons stored)');
        }
        return true;
      }());

      // Build local-only snapshot and surface it immediately so the screen
      // renders with cached data while the remote enrichment runs.
      final localOnly = PatientOrMemberData(
        localPatient: localPatient,
        programmes: localPatient.programmes,
        localAssessments: localAssessments,
        memberId: resolvedMemberId,
        vitalHistory: vitalHistory,
        pregnancySnapshot: pregnancySnapshot,
      );
      if (mounted) {
        setState(() {
          _localSnapshot = localOnly;
          _remoteLoading = true;
        });
      }

      // Phase 2: householdName (always local) + remote assessments (skipped
      // when sync is fresh — avoids a ~900ms round-trip for data already in DB).
      final tPhase2 = Stopwatch()..start();
      List<MemberAssessment> remoteAssessments = const [];
      if (skipRemote) {
        ConsoleLog.banner('[PatientCtx] phase2 skip remote (sync ${syncAge!.inMinutes}min ago) — householdName only');
        final householdName = await _householdName(localPatient.patient.householdId);
        if (mounted) setState(() => _remoteLoading = false);
        ConsoleLog.banner('[PatientCtx] phase2 done=${tPhase2.elapsedMilliseconds}ms'
            ' remoteSkipped=true total=${t0.elapsedMilliseconds}ms');
        return localOnly.copyWith(householdName: householdName);
      }

      ConsoleLog.banner('[PatientCtx] phase2 start — remote assessments + householdName');
      final phase2 = await Future.wait([
        memberRepo
            .getMemberAssessments(
              widget.patientId,
              villageId: localPatient.patient.villageId,
              patientAge: localPatient.patient.age,
              patientGender: localPatient.patient.gender,
            )
            .catchError((_) => <MemberAssessment>[]),
        _householdName(localPatient.patient.householdId),
      ]);
      remoteAssessments = phase2[0] as List<MemberAssessment>;
      final householdName = phase2[1] as String?;
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${remoteAssessments.length} remote assessments');

      if (mounted) setState(() => _remoteLoading = false);

      return localOnly.copyWith(
        remoteAssessments: remoteAssessments,
        householdName: householdName,
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
      
      final localAssessments = await _localAssessmentsFor(widget.patientId);
      return PatientOrMemberData(
        remoteMember: member,
        programmes: progs,
        localAssessments: localAssessments,
        memberId: resolvedMemberId,
        householdName: await _householdName(member.householdId),
        vitalHistory: vitalHistory,
        pregnancySnapshot: pregnancySnapshot,
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
      
      final localAssessmentsList =
          await _localAssessmentsFor(widget.patientId);
      return PatientOrMemberData(
        remoteMember: MemberHealthDetails(
          id: memberId,
          name: data['name'] as String? ?? PatientContextStrings.unknownMemberName,
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
        memberId: resolvedMemberId,
        householdName: await _householdName(data['householdId']?.toString()),
        vitalHistory: vitalHistory,
        pregnancySnapshot: pregnancySnapshot,
      );
    }

    // ignore: avoid_print
    print('[PatientContextScreen] No member found either');
    return const PatientOrMemberData();
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _localSnapshot = null;
      _remoteLoading = false;
    });
    try {
      final data = await _fetchData();
      if (!mounted) return;
      setState(() => _future = Future.value(data));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PatientContextStrings.refreshDone)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(PatientContextStrings.refreshFailed)),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // Purple-header screens (this screen's real header, and its loading
  // skeleton which mirrors it) need a transparent, light-icon status bar so
  // the header color paints through it. The canvas-background "not found"
  // state needs the opposite (dark icons) or its icons would be invisible.
  static const _lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
  static const _darkStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  /// Build the patient-scoped AI context (chip line, 2-line summary, and the
  /// structured payload the assistant answers from) out of the loaded data.
  PatientAiContext _aiContext(PatientOrMemberData data) {
    final progs = data.programmes.toList();
    final progLabel = progs.isEmpty
        ? '—'
        : progs.map((p) => p.wireTag.toUpperCase()).join('/');
    final band = data.riskBand;
    final bandLabel = band == null ? null : 'Band ${band.index + 1}';
    final reasons = data.riskReasons;

    final chip = <String>[
      progLabel,
      if (data.age != null) '${data.age}y',
      if (bandLabel != null) bandLabel,
    ].join(' · ');

    final summary = StringBuffer()
      ..write('${data.age ?? '—'}'
          '${data.gender != null ? ', ${data.gender}' : ''} · $progLabel.');
    if (bandLabel != null) {
      summary.write(
          ' $bandLabel${reasons.isNotEmpty ? ' — ${reasons.first}' : ''}.');
    }
    if (data.isPregnant) summary.write(' Pregnant.');

    return PatientAiContext(
      patientId: data.patientId ?? widget.patientId,
      patientName: data.name ?? 'Patient',
      patientAge: data.age,
      patientGender: data.gender,
      phone: data.phoneNumber,
      householdId: data.householdId,
      villageId: data.villageId,
      memberId: data.memberId,
      programmes: progs,
      diagnosisLabel: reasons.isNotEmpty ? reasons.first : null,
      chipLine: chip,
      summary: summary.toString(),
      apiContext: <String, dynamic>{
        'patientId': data.patientId ?? widget.patientId,
        'name': data.name,
        'age': data.age,
        'gender': data.gender,
        'programmes': progs.map((p) => p.wireTag).toList(),
        'riskBand': bandLabel,
        'riskReasons': reasons,
        'isPregnant': data.isPregnant,
        'villageName': data.villageName,
      },
    );
  }

  Widget buildPhi(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Scaffold(
      backgroundColor: tokens.canvas,
      floatingActionButton: FutureBuilder<PatientOrMemberData>(
        future: _future,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null || !d.hasData) return const SizedBox.shrink();
          return FloatingActionButton(
            heroTag: 'patient-ai-fab',
            tooltip: PatientAiStrings.fabTooltip,
            onPressed: () => PatientAiSheet.show(context, _aiContext(d)),
            child: const Icon(Icons.auto_awesome),
          );
        },
      ),
      body: FutureBuilder<PatientOrMemberData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            final local = _localSnapshot;
            if (local != null && local.hasData) {
              // Local DB data is ready — render immediately; remote still loading.
              return _buildContent(local, remoteLoading: _remoteLoading);
            }
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _lightStatusBar,
              child: SafeArea(
                top: false,
                child: SkeletonPatientDetail(
                  name: widget.memberData?['name'] as String?,
                ),
              ),
            );
          }
          final data = snap.data;
          if (data == null || !data.hasData) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _darkStatusBar,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_search_outlined,
                          size: 64,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          PatientContextStrings.notFound,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
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
              ),
            );
          }
          return _buildContent(data, remoteLoading: false);
        },
      ),
    );
  }
  Widget _buildContent(PatientOrMemberData data, {required bool remoteLoading}) {
    final t0 = Stopwatch()..start();
    final isUrgent = data.riskBand == Band.band1 || data.riskBand == Band.band2;

    final threads = _deriveThreads(data);
    // Clamp selected index if threads shrunk after a refresh
    final safeSelected = _selectedThread.clamp(0, threads.length - 1);
    final selectedThread = threads[safeSelected];

    // ANC / PW pregnancy snapshot (non-null only for active pregnancy)
    final snap = data.pregnancySnapshot;
    final isAnc = data.programmes.contains(Programme.anc);

    // Latest ANC visit number for pregnancy bar
    final latestAncVisit = data.assessments
        .where((a) => Programme.fromString(a.type) == Programme.anc)
        .firstOrNull;
    final ancVisitNum = latestAncVisit != null
        ? (_unpackRaw(latestAncVisit.rawJson)['ancVisitNumber'] as String?)
        : null;

    // Spark charts for the selected thread
    final bpChart = _buildBpSparkChart(data.vitalHistory);
    final weightChart = _buildWeightSparkChart(data.vitalHistory);

    // AI context summary (pure local, synchronous)
    final aiCtx = _aiContext(data);

    debugPrint('⏱ [PatientContext] _buildContent setup in ${t0.elapsedMilliseconds}ms'
        ' threads=${threads.length} selected=$safeSelected snap=${snap != null}');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _lightStatusBar,
      child: SafeArea(
        top: false,
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
            if (data.householdId != null)
              _SameHouseholdStrip(
                currentPatientId: widget.patientId,
                householdId: data.householdId!,
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, AppSpacing.stickyBarClearance),
                  children: [
                    // Patient identity card
                    _PatientProfileCard(data: data),
                    const SizedBox(height: 14),

                    // ── Care thread chip row ──────────────────────────────
                    _CareThreadChipRow(
                      threads: threads,
                      selected: safeSelected,
                      onThreadSelected: (i) => setState(() => _selectedThread = i),
                    ),
                    const SizedBox(height: 12),

                    // ── AI Insight card ───────────────────────────────────
                    _AiInsightCard(summary: aiCtx.summary),
                    const SizedBox(height: 12),

                    // ── Pregnancy progress (ANC / PW only) ───────────────
                    if (isAnc && snap != null) ...[
                      _PregnancyProgressSection(
                        snapshot: snap,
                        ancVisitNumber: ancVisitNum,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Stats grid for selected thread ────────────────────
                    _StatsGrid(
                      thread: selectedThread,
                      noDataLabel: PatientProfileStrings.noVitalsYet,
                    ),
                    const SizedBox(height: 12),

                    // ── Spark charts (BP + growth) ────────────────────────
                    if (bpChart != null || weightChart != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showCardDetail(
                          context,
                          title: 'Vital trends',
                          icon: Icons.show_chart_rounded,
                          iconColor: AppColors.textStrong,
                          body: _VitalTrendDetail(
                            vitalHistory: data.vitalHistory,
                          ),
                        ),
                        child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.cardSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.show_chart_rounded, size: 14, color: AppColors.textMuted),
                                  const SizedBox(width: 6),
                                  const Text('Vital trends',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                                  const Spacer(),
                                  const Icon(Icons.expand_more_rounded, size: 16, color: AppColors.textMuted),
                                ]),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (bpChart != null) Expanded(child: bpChart),
                                    if (bpChart != null && weightChart != null)
                                      const SizedBox(width: 16),
                                    if (weightChart != null) Expanded(child: weightChart),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    if (bpChart != null || weightChart != null) const SizedBox(height: 12),

                    // ── Combined care history timeline ────────────────────
                    _CombinedTimeline(
                      assessments: data.assessments,
                      isLoading: remoteLoading,
                    ),
                    const SizedBox(height: 12),

                    // ── Open follow-ups ───────────────────────────────────
                    OpenFollowupsSection(
                      patientId: widget.patientId,
                      memberReference: data.memberReference,
                    ),
                    const SizedBox(height: 10),

                    // ── Action row ────────────────────────────────────────
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
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Care Thread model ─────────────────────────────────────────────────────

/// One active clinical pathway shown as a chip + stats card on the context screen.
class _CareThread {
  const _CareThread({
    required this.programme,
    required this.label,
    required this.bg,
    required this.textColor,
    this.stats = const {},
  });

  final Programme programme;
  final String label;
  final Color bg;
  final Color textColor;
  /// Key → display value pairs shown in the stats row under each thread.
  final Map<String, String> stats;
}

/// Unpacks the `{kind, raw}` envelope written by AssessmentDao so that
/// clinical fields (bp, bg, ancVisitNumber, …) are accessible at the top level.
Map<String, dynamic> _unpackRaw(Map<String, dynamic> rawJson) {
  final r = rawJson['raw'];
  if (r is String) return jsonDecode(r) as Map<String, dynamic>;
  if (r is Map) return Map<String, dynamic>.from(r);
  return rawJson;
}

/// Normalises a rawJson map so clinical fields are accessible at the top level,
/// regardless of which of three storage formats the assessment used:
///
/// 1. API format (AssessmentDao / member-assessment-history): the unpacked map
///    is the full API response object; clinical fields live under the nested
///    `observations` key — e.g. `raw['observations']['bp']` = "148/90".
/// 2. Local-form format (LocalEncounterDao): vitals spread flat at the top level
///    but under form-specific keys: `systolic`, `diastolic`, `glucoseValue`.
/// 3. NCD bpLog format: `bpLog.avgSystolic` / `glucoseLog.glucose`.
///
/// After normalisation, callers read `out['bp']`, `out['bg']`, `out['bgType']`
/// regardless of origin. The merge uses putIfAbsent so explicit top-level keys
/// always win over sub-map values.
Map<String, dynamic> _normalizeRaw(Map<String, dynamic> rawJson) {
  final raw = _unpackRaw(rawJson);
  final out = Map<String, dynamic>.from(raw);

  // Step 1 — flatten 'observations' and 'assessmentDetails' sub-maps (API format).
  for (final subKey in const ['observations', 'assessmentDetails']) {
    final sub = raw[subKey];
    if (sub is Map) {
      for (final e in sub.entries) {
        out.putIfAbsent(e.key.toString(), () => e.value);
      }
    }
  }

  // Step 2 — map NCD bpLog / glucoseLog nested keys (local-form format).
  final bpLog = raw['bpLog'];
  if (bpLog is Map) {
    out.putIfAbsent('avgSystolic', () => bpLog['avgSystolic']);
    out.putIfAbsent('avgDiastolic', () => bpLog['avgDiastolic']);
  }
  final gLog = raw['glucoseLog'];
  if (gLog is Map) {
    out.putIfAbsent('glucoseValue', () => gLog['glucose']);
    out.putIfAbsent('glucoseType', () => gLog['glucoseType']);
  }

  // Step 3 — synthesise canonical 'bp' ("sys/dia" string) if missing.
  if ((out['bp'] as String?) == null) {
    int? sys;
    int? dia;
    for (final k in const ['systolic', 'bloodPressureSystolic', 'avgSystolic']) {
      final v = out[k];
      if (v is num) { sys = v.toInt(); break; }
      if (v is String) { sys = int.tryParse(v); if (sys != null) break; }
    }
    if (sys == null) {
      // bpLogDetails: [{systolic: x, diastolic: y}]
      final log = out['bpLogDetails'];
      if (log is List && log.isNotEmpty && log.first is Map) {
        final first = log.first as Map;
        final s = first['systolic'];
        sys = s is num ? s.toInt() : (s is String ? int.tryParse(s) : null);
        final d = first['diastolic'];
        dia = d is num ? d.toInt() : (d is String ? int.tryParse(d) : null);
      }
    }
    if (dia == null) {
      for (final k in const ['diastolic', 'bloodPressureDiastolic', 'avgDiastolic']) {
        final v = out[k];
        if (v is num) { dia = v.toInt(); break; }
        if (v is String) { dia = int.tryParse(v); if (dia != null) break; }
      }
    }
    if (sys != null && dia != null) out['bp'] = '$sys/$dia';
  }

  // Step 4 — synthesise canonical 'bg' (value string) + 'bgType' if missing.
  if ((out['bg'] as String?) == null) {
    final glu = out['glucoseValue'] ?? out['glucose'] ?? out['bloodGlucose'];
    if (glu != null) {
      out['bg'] = glu.toString();
      if (out['bgType'] == null) {
        final gt = (out['glucoseType'] as String?)?.toLowerCase();
        out['bgType'] = gt == 'fasting'
            ? 'FBS'
            : gt == 'random'
                ? 'RBS'
                : gt == 'postprandial'
                    ? 'PPBS'
                    : gt?.toUpperCase();
      }
    }
  }

  return out;
}

/// Derives the ordered list of active care threads from local data.
/// Reads only what is already in [data] — no async calls, no new endpoints.
/// Debug timing is emitted to console so per-thread cost is visible in logs.
List<_CareThread> _deriveThreads(PatientOrMemberData data) {
  final sw = Stopwatch()..start();
  final threads = <_CareThread>[];

  MemberAssessment? latestOf(Programme prog) => data.assessments
      .where((a) => Programme.fromString(a.type) == prog)
      .firstOrNull;

  // ANC / Pregnancy
  if (data.programmes.contains(Programme.anc)) {
    final latest = latestOf(Programme.anc);
    final raw = latest != null ? _normalizeRaw(latest.rawJson) : const <String, dynamic>{};
    final stats = <String, String>{};
    final snap = data.pregnancySnapshot;
    if (snap?.eddDate != null) {
      final weeksLeft =
          DateTime.fromMillisecondsSinceEpoch(snap!.eddDate!).difference(DateTime.now()).inDays ~/ 7;
      if (weeksLeft > 0) stats[PatientProfileStrings.weeksToGo] = '$weeksLeft';
    }
    final visitNum = raw['ancVisitNumber'] as String?;
    if (visitNum != null) stats[PatientProfileStrings.visitsCompleted] = visitNum;
    threads.add(_CareThread(
      programme: Programme.anc,
      label: CareThreadStrings.anc,
      bg: AppColors.ancSurface,
      textColor: AppColors.ancText,
      stats: stats,
    ));
  }

  // NCD — split into HTN and blood-sugar threads when readings are available
  if (data.programmes.contains(Programme.ncd)) {
    final latest = latestOf(Programme.ncd);
    final raw = latest != null ? _normalizeRaw(latest.rawJson) : const <String, dynamic>{};
    final bp = raw['bp'] as String?;
    threads.add(_CareThread(
      programme: Programme.ncd,
      label: CareThreadStrings.htn,
      bg: AppColors.ncdSurface,
      textColor: AppColors.ncdText,
      stats: bp != null ? {PatientProfileStrings.bpTarget: bp} : {},
    ));
    final bg = raw['bg'] as String?;
    if (bg != null) {
      final bgType = raw['bgType'] as String?;
      threads.add(_CareThread(
        programme: Programme.ncd,
        label: CareThreadStrings.sugar,
        bg: AppColors.statusInfoSurface,
        textColor: AppColors.threadInfoText,
        stats: {PatientProfileStrings.bloodSugar: '$bg${bgType != null ? ' ($bgType)' : ''}'},
      ));
    }
  }

  // PNC — postnatal recovery
  if (data.programmes.contains(Programme.pnc)) {
    final latest = latestOf(Programme.pnc);
    final raw = latest != null ? _normalizeRaw(latest.rawJson) : const <String, dynamic>{};
    final pncVisit = raw['pncVisitNumber'] as String?;
    final deliveryMode = raw['modeOfDelivery'] as String?;
    threads.add(_CareThread(
      programme: Programme.pnc,
      label: CareThreadStrings.pnc,
      bg: AppColors.pncSurface,
      textColor: AppColors.pncText,
      stats: {
        if (pncVisit != null) PatientProfileStrings.pncVisitsDone: pncVisit,
        if (deliveryMode != null) PatientProfileStrings.delivery: deliveryMode,
      },
    ));
  }

  // IMCI — immunization + growth monitoring
  if (data.programmes.contains(Programme.imci)) {
    threads.add(const _CareThread(
      programme: Programme.imci,
      label: CareThreadStrings.imm,
      bg: AppColors.threadImmBg,
      textColor: AppColors.tbText,
    ));
    threads.add(const _CareThread(
      programme: Programme.imci,
      label: CareThreadStrings.growth,
      bg: AppColors.pncSurface,
      textColor: AppColors.aiPurpleDark,
    ));
  }

  // TB — general enrollment
  if (data.programmes.contains(Programme.tb)) {
    threads.add(const _CareThread(
      programme: Programme.tb,
      label: CareThreadStrings.general,
      bg: AppColors.tbSurface,
      textColor: AppColors.tbText,
    ));
  }

  // Fallback when no programme is active
  if (threads.isEmpty) {
    threads.add(const _CareThread(
      programme: Programme.unknown,
      label: CareThreadStrings.general,
      bg: AppColors.threadGeneralBg,
      textColor: AppColors.textMid,
    ));
  }

  debugPrint(
    '⏱ [PatientContext] _deriveThreads ${threads.length} threads in ${sw.elapsedMilliseconds}ms',
  );
  return threads;
}

// ─── Care Thread Chip Row ──────────────────────────────────────────────────

/// Horizontally scrollable row of thread chips — one pill per active clinical
/// pathway. Tapping a chip scrolls the parent to the matching stats card
/// (handled by the parent via [onThreadSelected]).
class _CareThreadChipRow extends StatelessWidget {
  const _CareThreadChipRow({
    required this.threads,
    required this.selected,
    required this.onThreadSelected,
  });

  final List<_CareThread> threads;
  final int selected;
  final ValueChanged<int> onThreadSelected;

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            PatientProfileStrings.activeCareThreads,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMid,
              letterSpacing: 0.2,
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: threads.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final t = threads[i];
              final isSelected = i == selected;
              return GestureDetector(
                onTap: () => onThreadSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? t.textColor : t.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: t.textColor.withOpacity(isSelected ? 0 : 0.35),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.cardSurface : t.textColor,
                      height: 1.2,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    debugPrint('⏱ [PatientContext] _CareThreadChipRow build in ${sw.elapsedMilliseconds}ms'
        ' (${threads.length} chips, selected=$selected)');
    return result;
  }
}

// ─── AI Insight Card ───────────────────────────────────────────────────────

/// Inline card showing the locally-computed patient AI summary. Content comes
/// from [PatientAiContext.summary] — no async call, always available offline.
/// Falls back to a muted unavailable message when the summary is empty.
class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({required this.summary});

  final String summary;

  void _showDetail(BuildContext context) {
    final isEmpty = summary.trim().isEmpty;
    _showCardDetail(
      context,
      title: PatientProfileStrings.aiInsight,
      icon: Icons.auto_awesome_rounded,
      iconColor: AppColors.aiPurpleDark,
      body: Text(
        isEmpty ? PatientProfileStrings.aiInsightUnavailable : summary,
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: isEmpty ? AppColors.textMuted : AppColors.textStrong,
          fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final isEmpty = summary.trim().isEmpty;
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDetail(context),
      child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.aiSurfaceStart, AppColors.aiSurfaceEnd],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.aiBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.aiPurpleDark),
                  const SizedBox(width: 6),
                  Text(
                    PatientProfileStrings.aiInsight,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.aiPurpleDark,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.expand_more_rounded, size: 16, color: AppColors.aiPurpleDark),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isEmpty ? PatientProfileStrings.aiInsightUnavailable : summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isEmpty ? AppColors.textMuted : AppColors.textStrong,
                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
    );
    debugPrint('⏱ [PatientContext] _AiInsightCard build in ${sw.elapsedMilliseconds}ms');
    return card;
  }
}

// ─── Pregnancy Progress Section ────────────────────────────────────────────

/// Pregnancy progress bar + key stats for ANC / PW patients.
/// Shown only when [snapshot] is non-null (patient has an active pregnancy episode).
class _PregnancyProgressSection extends StatelessWidget {
  const _PregnancyProgressSection({
    required this.snapshot,
    required this.ancVisitNumber,
  });

  final PregnancySnapshotRow snapshot;
  /// Latest ancVisitNumber from assessments, or null if not yet recorded.
  final String? ancVisitNumber;

  static const _totalAncVisits = 8; // WHO recommended minimum

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();

    final now = DateTime.now();
    final lmpDate = snapshot.lmpDate != null
        ? DateTime.fromMillisecondsSinceEpoch(snapshot.lmpDate!)
        : null;
    final eddDate = snapshot.eddDate != null
        ? DateTime.fromMillisecondsSinceEpoch(snapshot.eddDate!)
        : null;

    // Gestational age in weeks from LMP
    final gaWeeks = lmpDate != null ? now.difference(lmpDate).inDays ~/ 7 : null;
    // Weeks remaining to EDD
    final weeksLeft = eddDate != null
        ? eddDate.difference(now).inDays ~/ 7
        : null;
    // Progress fraction of 40-week pregnancy
    final progress = gaWeeks != null ? (gaWeeks / 40.0).clamp(0.0, 1.0) : null;

    final visitsDone = int.tryParse(ancVisitNumber ?? '0') ?? 0;
    final visitProgress = (visitsDone / _totalAncVisits).clamp(0.0, 1.0);

    final dateFormat = DateFormat('d MMM yyyy');

    final widget = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ancSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ancBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_border_rounded, size: 15, color: AppColors.ancText),
              const SizedBox(width: 6),
              Text(
                PatientProfileStrings.pregnancyProgress,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ancText,
                ),
              ),
              const Spacer(),
              if (gaWeeks != null)
                Text(
                  '${gaWeeks}w GA',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ancText,
                  ),
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.ancBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ancText),
              ),
            ),
            if (weeksLeft != null && weeksLeft > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$weeksLeft ${PatientProfileStrings.weeksToGo}',
                  style: const TextStyle(fontSize: 11, color: AppColors.ancText),
                ),
              ),
          ],
          const SizedBox(height: 12),
          // Stats row
          Row(
            children: [
              _PregStat(
                label: PatientProfileStrings.visitsCompleted,
                value: '$visitsDone / $_totalAncVisits',
                progress: visitProgress,
              ),
              const SizedBox(width: 12),
              if (eddDate != null)
                _PregStat(
                  label: 'EDD',
                  value: dateFormat.format(eddDate),
                ),
              if (lmpDate != null && eddDate == null) ...[
                _PregStat(
                  label: 'LMP',
                  value: dateFormat.format(lmpDate),
                ),
              ],
            ],
          ),
        ],
      ),
    );
    debugPrint('⏱ [PatientContext] _PregnancyProgressSection build in ${sw.elapsedMilliseconds}ms'
        ' gaWeeks=$gaWeeks weeksLeft=$weeksLeft visitsDone=$visitsDone');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showCardDetail(
        context,
        title: PatientProfileStrings.pregnancyProgress,
        icon: Icons.favorite_border_rounded,
        iconColor: AppColors.ancText,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lmpDate != null)
              _DetailRow(label: 'LMP', value: dateFormat.format(lmpDate)),
            if (eddDate != null)
              _DetailRow(label: 'EDD', value: dateFormat.format(eddDate)),
            if (gaWeeks != null)
              _DetailRow(label: 'Gestational age', value: '$gaWeeks weeks'),
            if (weeksLeft != null)
              _DetailRow(label: 'Weeks remaining', value: '$weeksLeft weeks'),
            _DetailRow(
              label: PatientProfileStrings.visitsCompleted,
              value: '$visitsDone / $_totalAncVisits',
            ),
            if (snapshot.facts.highRiskPregnantWoman)
              _DetailRow(label: 'Risk', value: 'High risk — elevated BP or other flag'),
            if (snapshot.facts.hasGapsInAnc)
              _DetailRow(label: 'ANC gaps', value: 'Missed visits detected'),
            if (snapshot.facts.isNearTermAnc)
              _DetailRow(label: 'Near term', value: 'Approaching EDD — monitor closely'),
          ],
        ),
      ),
      child: widget,
    );
  }
}

/// Single stat tile inside the pregnancy progress card.
class _PregStat extends StatelessWidget {
  const _PregStat({required this.label, required this.value, this.progress});

  final String label;
  final String value;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.ancText)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ancText,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: AppColors.ancBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ancText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Stats Grid ────────────────────────────────────────────────────────────

/// 2-column grid of clinical stat tiles for the currently selected care thread.
/// Used by NCD (BP, blood sugar), IMCI (doses, weight), and PNC (visit, delivery).
/// Shows [noDataLabel] when [stats] is empty.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.thread,
    required this.noDataLabel,
  });

  final _CareThread thread;
  final String noDataLabel;

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final stats = thread.stats;

    late final Widget body;
    if (stats.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          noDataLabel,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else {
      final entries = stats.entries.toList();
      body = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final e in entries)
            SizedBox(
              width: (MediaQuery.of(context).size.width - 28 - 10) / 2,
              child: _StatTile(
                label: e.key,
                value: e.value,
                bg: thread.bg,
                textColor: thread.textColor,
              ),
            ),
        ],
      );
    }

    final result = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: thread.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: thread.textColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thread.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: thread.textColor,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
    debugPrint('⏱ [PatientContext] _StatsGrid build in ${sw.elapsedMilliseconds}ms'
        ' thread=${thread.label} stats=${stats.length}');
    return result;
  }
}

/// Single stat tile within [_StatsGrid].
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.bg,
    required this.textColor,
    this.note,
  });

  final String label;
  final String value;
  final Color bg;
  final Color textColor;
  /// Optional extra clinical note shown in the detail sheet only.
  final String? note;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showCardDetail(
        context,
        title: label,
        iconColor: textColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 12),
              Text(
                note!,
                style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: textColor.withOpacity(0.15), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.8)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared card-detail helpers ────────────────────────────────────────────

/// Shows a titled bottom sheet with arbitrary [body] content.
/// Used by AI insight, pregnancy section, stat tiles, and vital chart.
void _showCardDetail(
  BuildContext context, {
  required String title,
  IconData? icon,
  Color? iconColor,
  required Widget body,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: iconColor ?? AppColors.textStrong),
                  const SizedBox(width: 8),
                ],
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              ]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: body,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Labelled row used inside card detail sheets.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, color: AppColors.textStrong, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Full vital trend table shown in the chart detail sheet.
class _VitalTrendDetail extends StatelessWidget {
  const _VitalTrendDetail({required this.vitalHistory});
  final List<VisitVitals> vitalHistory;

  @override
  Widget build(BuildContext context) {
    if (vitalHistory.isEmpty) {
      return const Text('No vitals recorded yet.',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted, fontStyle: FontStyle.italic));
    }
    final dateFormat = DateFormat('d MMM yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final visit in vitalHistory) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${visit.programme} — ${dateFormat.format(visit.date)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textStrong),
                ),
                const SizedBox(height: 8),
                for (final r in visit.readings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Text(_vitalLabel(r.type), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const Spacer(),
                      Text(_vitalValue(r), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _vitalLabel(VitalType t) => switch (t) {
    VitalType.bloodPressure => 'Blood pressure',
    VitalType.glucose => 'Blood glucose',
    VitalType.weight => 'Weight',
    VitalType.height => 'Height',
    VitalType.temperature => 'Temperature',
    VitalType.spO2 => 'SpO₂',
    VitalType.respiratoryRate => 'Respiratory rate',
    VitalType.muac => 'MUAC',
    VitalType.bmi => 'BMI',
  };

  String _vitalValue(VitalReading r) {
    if (r.type == VitalType.bloodPressure) {
      return '${r.systolic?.toInt() ?? '—'}/${r.diastolic?.toInt() ?? '—'} mmHg';
    }
    final v = r.value;
    final u = r.unit ?? '';
    return v != null ? '${v.toStringAsFixed(1)} $u'.trim() : '—';
  }
}

// ─── Spark Bar Chart ───────────────────────────────────────────────────────

/// Lightweight bar-chart sparkline rendered as a [Row] of [Container] widgets.
/// No additional packages — satisfies the "no new packages" constraint.
///
/// Supports two series (e.g. systolic + diastolic) when [secondValues] is set.
class _SparkBarChart extends StatelessWidget {
  const _SparkBarChart({
    required this.values,
    required this.barColor,
    this.secondValues,
    this.secondBarColor,
    this.label,
    this.maxHeight = 48,
    this.barWidth = 6,
    this.barSpacing = 3,
  });

  final List<double> values;
  final Color barColor;
  final List<double>? secondValues;
  final Color? secondBarColor;
  final String? label;
  final double maxHeight;
  final double barWidth;
  final double barSpacing;

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    if (values.isEmpty) {
      final empty = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null)
            Text(label!, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            PatientProfileStrings.noVitalsYet,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
          ),
        ],
      );
      debugPrint('⏱ [PatientContext] _SparkBarChart build in ${sw.elapsedMilliseconds}ms (empty)');
      return empty;
    }

    final second = secondValues ?? const [];
    final allVals = [...values, ...second];
    final maxVal = allVals.reduce((a, b) => a > b ? a : b);
    final minVal = allVals.reduce((a, b) => a < b ? a : b);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    double barH(double v) => ((v - minVal) / range * maxHeight).clamp(4.0, maxHeight);

    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label!, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ),
        SizedBox(
          height: maxHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < values.length; i++) ...[
                if (i > 0) SizedBox(width: barSpacing),
                // Bars for this x-position — side by side, aligned to bottom
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: barWidth,
                      height: barH(values[i]),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                    ),
                    if (second.isNotEmpty && i < second.length) ...[
                      const SizedBox(width: 1),
                      Container(
                        width: barWidth,
                        height: barH(second[i]),
                        decoration: BoxDecoration(
                          color: (secondBarColor ?? AppColors.textMuted).withOpacity(0.7),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
    debugPrint('⏱ [PatientContext] _SparkBarChart build in ${sw.elapsedMilliseconds}ms'
        ' bars=${values.length} dual=${second.isNotEmpty}');
    return result;
  }
}

/// Extracts BP spark chart from visit vitals history. Returns null if no BP data.
_SparkBarChart? _buildBpSparkChart(List<VisitVitals> history) {
  final systolics = <double>[];
  final diastolics = <double>[];
  for (final visit in history) {
    for (final r in visit.readings) {
      if (r.type == VitalType.bloodPressure) {
        final sys = r.systolic?.toDouble();
        final dia = r.diastolic?.toDouble();
        if (sys != null && dia != null) {
          systolics.add(sys);
          diastolics.add(dia);
          break;
        }
      }
    }
  }
  if (systolics.isEmpty) return null;
  return _SparkBarChart(
    values: systolics,
    barColor: AppColors.ancText,
    secondValues: diastolics,
    secondBarColor: AppColors.ancBorder,
    label: 'BP trend (systolic/diastolic)',
  );
}

/// Extracts weight/growth spark chart from visit vitals history. Returns null if no weight data.
_SparkBarChart? _buildWeightSparkChart(List<VisitVitals> history) {
  final weights = <double>[];
  for (final visit in history) {
    for (final r in visit.readings) {
      if (r.type == VitalType.weight) {
        final w = r.value?.toDouble();
        if (w != null) {
          weights.add(w);
          break;
        }
      }
    }
  }
  if (weights.isEmpty) return null;
  return _SparkBarChart(
    values: weights,
    barColor: AppColors.aiPurpleDark,
    label: PatientProfileStrings.growthTrend,
  );
}

// ─── Combined Timeline ─────────────────────────────────────────────────────

/// Scrollable vertical timeline of all care events (assessments).
/// Events are already sorted newest-first via [PatientOrMemberData.assessments].
class _CombinedTimeline extends StatelessWidget {
  const _CombinedTimeline({required this.assessments, required this.isLoading});

  final List<MemberAssessment> assessments;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();

    late final Widget body;
    if (assessments.isEmpty && isLoading) {
      body = const _TimelineShimmer();
    } else if (assessments.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          PatientProfileStrings.noVitalsYet,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontStyle: FontStyle.italic),
        ),
      );
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: assessments.length,
        itemBuilder: (context, i) => _TimelineRow(
          assessment: assessments[i],
          isLast: i == assessments.length - 1,
        ),
      );
    }

    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            PatientProfileStrings.careHistory,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        body,
      ],
    );
    debugPrint('⏱ [PatientContext] _CombinedTimeline build in ${sw.elapsedMilliseconds}ms'
        ' events=${assessments.length} loading=$isLoading');
    return result;
  }
}

/// Single row in the combined timeline — dot + connector + event card.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.assessment, required this.isLast});

  final MemberAssessment assessment;
  final bool isLast;

  static const _dotSize = 10.0;
  static const _lineWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final prog = Programme.fromString(assessment.type);
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    final dotColor = progColors.of(prog);
    final dateStr = DateFormat('d MMM yyyy').format(assessment.date);
    final label = assessment.visitNumber != null
        ? '${assessment.type} — Visit ${assessment.visitNumber}'
        : assessment.type;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dot + vertical connector
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cardSurface, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: _lineWidth,
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Event card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
              child: _PendingEventCard(
                label: label,
                dateStr: dateStr,
                status: assessment.status,
                notes: assessment.notes,
                assessment: assessment,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card shown for each timeline event — label, date, status chip, tap-to-expand.
class _PendingEventCard extends StatelessWidget {
  const _PendingEventCard({
    required this.label,
    required this.dateStr,
    required this.assessment,
    this.status,
    this.notes,
  });

  final String label;
  final String dateStr;
  final String? status;
  final String? notes;
  final MemberAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _TimelineEventSheet.show(context, assessment),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  if (notes != null && notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMid),
                    ),
                  ],
                ],
              ),
            ),
            if (status != null)
              _StatusChip(status: status!),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Small coloured status chip (Referred / OnTreatment / Recovered).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  static const _colors = <String, Color>{
    'referred': AppColors.statusCritical,
    'ontreatment': AppColors.statusWarning,
    'recovered': AppColors.statusSuccess,
  };

  static const _bgColors = <String, Color>{
    'referred': AppColors.statusCriticalSurface,
    'ontreatment': AppColors.statusWarningSurface,
    'recovered': AppColors.statusSuccessSurface,
  };

  @override
  Widget build(BuildContext context) {
    final key = status.toLowerCase().replaceAll(' ', '');
    final color = _colors[key] ?? AppColors.textMuted;
    final bg = _bgColors[key] ?? AppColors.border;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Shimmer placeholder shown while timeline data is loading.
class _TimelineShimmer extends StatelessWidget {
  const _TimelineShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      )),
    );
  }
}

// ─── Timeline Event Sheet ──────────────────────────────────────────────────

/// Bottom sheet expanding a care-thread timeline event into full clinical detail.
/// Unpacks the rawJson envelope via [_unpackRaw] to surface clinical fields.
class _TimelineEventSheet extends StatelessWidget {
  const _TimelineEventSheet({required this.assessment});

  final MemberAssessment assessment;

  static void show(BuildContext context, MemberAssessment assessment) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TimelineEventSheet(assessment: assessment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final raw = _normalizeRaw(assessment.rawJson);
    final dateFormat = DateFormat('d MMMM yyyy · h:mm a');
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    final prog = Programme.fromString(assessment.type);
    final typeColor = progColors.of(prog);

    final entries = <MapEntry<String, String>>[];
    void addIfPresent(String key, String label) {
      final v = raw[key];
      if (v != null && v.toString().isNotEmpty) {
        entries.add(MapEntry(label, v.toString()));
      }
    }
    addIfPresent('bp', 'BP');
    addIfPresent('bg', 'Blood glucose');
    addIfPresent('bgType', 'Glucose type');
    addIfPresent('weight', 'Weight (kg)');
    addIfPresent('height', 'Height (cm)');
    addIfPresent('hemoglobin', 'Hb (g/dL)');
    addIfPresent('fundalHeight', 'Fundal height (cm)');
    addIfPresent('gravida', 'Gravida');
    addIfPresent('parity', 'Parity');
    addIfPresent('ancVisitNumber', 'ANC visit no.');
    addIfPresent('pncVisitNumber', 'PNC visit no.');
    addIfPresent('modeOfDelivery', 'Mode of delivery');
    addIfPresent('confirmDiagnosis', 'Diagnosis');
    addIfPresent('familyPlanningMethods', 'FP method');

    final result = DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    assessment.visitNumber != null
                        ? '${assessment.type} — Visit ${assessment.visitNumber}'
                        : assessment.type,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                  ),
                ),
                if (assessment.status != null) _StatusChip(status: assessment.status!),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                dateFormat.format(assessment.date),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                if (entries.isEmpty)
                  Text(
                    PatientProfileStrings.noVitalsYet,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  ...entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              e.key,
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.value,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (assessment.notes != null && assessment.notes!.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'Notes',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMid),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    assessment.notes!,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    debugPrint('⏱ [PatientContext] _TimelineEventSheet build in ${sw.elapsedMilliseconds}ms'
        ' type=${assessment.type} fields=${entries.length}');
    return result;
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

  Future<void> _openContact() async {
    if (!mounted) return;
    await showContactSheet(context, widget.data);
  }

  Future<void> _openMaps(String place) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(place.trim())}');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final scheme = Theme.of(context).colorScheme;

    Widget buildRow(String label, String? value,
        {IconData? icon, VoidCallback? onTap}) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
          ],
        ),
      );
      if (onTap != null) {
        return GestureDetector(onTap: onTap, child: row);
      }
      return row;
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
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
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
              icon: Icons.badge_outlined,
              onTap: () => setState(() => _expanded = true)),
        if (d.dateOfBirth != null)
          buildRow(PatientProfileStrings.labelDob, _formatDob(d.dateOfBirth),
              icon: Icons.cake_outlined),
        if (d.phoneNumber != null)
          buildRow(PatientProfileStrings.labelPhone, d.phoneNumber,
              icon: Icons.phone_outlined,
              onTap: _openContact),
        if (d.villageName != null)
          buildRow(PatientProfileStrings.labelVillage, d.villageName,
              icon: Icons.location_on_outlined,
              onTap: () => _openMaps(d.villageName!)),
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
          buildRow(PatientProfileStrings.labelDob, _formatDob(d.dateOfBirth),
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
              icon: Icons.location_on_outlined,
              onTap: d.villageName != null ? () => _openMaps(d.villageName!) : null),
          buildRow(PatientProfileStrings.labelGps, formatGps(),
              icon: Icons.gps_fixed),
        ]),
        buildSection(PatientProfileStrings.sectionContact, [
          buildRow(PatientProfileStrings.labelPhone, d.phoneNumber,
              icon: Icons.phone_outlined,
              onTap: _openContact),
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

    final vitals = _parseVitals();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppShadows.householdCard,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_pin_outlined, color: AppColors.navy, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    PatientProfileStrings.profileTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
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
        const SizedBox(height: 10),
        if (d.programmes.isEmpty)
          _NoServicesCard(
            patientId: d.patientId ?? '',
            patientName: d.name,
            patientAge: d.age,
            patientGender: d.gender,
            villageName: d.villageName,
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppShadows.householdCard,
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medical_services_outlined,
                        size: 16, color: AppColors.navy),
                    const SizedBox(width: 6),
                    Text(
                      PatientProfileStrings.servicesProvidedTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        context.push(
                          '/patients/${d.patientId ?? ''}/enroll',
                          extra: <String, dynamic>{
                            'patientName': d.name,
                            'patientAge': d.age,
                            'patientGender': d.gender,
                            'villageName': d.villageName,
                            'existingProgrammes': d.programmes,
                          },
                        );
                      },
                      child: const Text(
                        '+ Edit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
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
                      labelStyle: TextStyle(color: scheme.onPrimaryContainer),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        // ── Clinical Risk ────────────────────────────────────────────────
        if (d.riskBand != null) ...[
          const SizedBox(height: 10),
          _buildRiskCard(scheme),
        ],

        // ── Scheduling / Next Due ─────────────────────────────────────────
        if (d.localPatient?.patient.nextDueAt != null ||
            d.localPatient?.patient.lastVisitAt != null) ...[
          const SizedBox(height: 10),
          _buildNextDueCard(scheme),
        ],

        // ── Last Vitals ───────────────────────────────────────────────────
        if (vitals != null) ...[
          const SizedBox(height: 10),
          _buildVitalsCard(context, scheme, vitals),
        ],
      ],
    );
  }

  // ── Risk Band ──────────────────────────────────────────────────────────────

  Widget _buildRiskCard(ColorScheme scheme) {
    final band = widget.data.riskBand;
    if (band == null) return const SizedBox.shrink();
    final modifier = widget.data.riskModifier;
    final reasons = widget.data.riskReasons;

    Color bgColor;
    Color textColor;
    String bandLabel;
    switch (band) {
      case Band.band1:
        bgColor = AppColors.statusCriticalSurface;
        textColor = AppColors.statusCriticalText;
        bandLabel = 'Band 1 · Severe';
      case Band.band2:
        bgColor = AppColors.statusWarningSurface;
        textColor = AppColors.statusWarningText;
        bandLabel = 'Band 2 · Moderate';
      case Band.band3:
        bgColor = const Color(0xFFEFF6FF);
        textColor = AppColors.navy;
        bandLabel = 'Band 3 · Mild';
      case Band.band4:
        bgColor = const Color(0xFFF3F4F6);
        textColor = AppColors.textMuted;
        bandLabel = 'Band 4 · Routine';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text('Clinical Risk',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(bandLabel,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: textColor)),
                ),
                if (modifier != null && modifier != Modifier.none) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      modifier == Modifier.a ? '+a  Additional risk' : '+b  Overdue',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ],
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...reasons.map((r) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ',
                            style: TextStyle(color: textColor, fontSize: 12)),
                        Expanded(
                          child: Text(r,
                              style: TextStyle(
                                  fontSize: 12, color: scheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ── Next Due / Overdue ─────────────────────────────────────────────────────

  Widget _buildNextDueCard(ColorScheme scheme) {
    final lastMs = widget.data.localPatient?.patient.lastVisitAt;
    final nextMs = widget.data.localPatient?.patient.nextDueAt;
    if (lastMs == null && nextMs == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final lastDate = lastMs != null ? DateTime.fromMillisecondsSinceEpoch(lastMs) : null;
    final nextDate = nextMs != null ? DateTime.fromMillisecondsSinceEpoch(nextMs) : null;

    // Compare calendar dates only — wall-clock difference truncates (e.g.
    // next due midnight tomorrow vs evening today ⇒ 0 days, not 1).
    final daysToDue =
        nextDate == null ? null : CalendarDay.daysBetween(now, nextDate);
    final isOverdue = daysToDue != null && daysToDue < 0;
    final overdueDays = (daysToDue != null && daysToDue < 0) ? -daysToDue : 0;
    final dueSoonDays = (daysToDue != null && daysToDue >= 0) ? daysToDue : null;

    Color headerColor = scheme.primary;
    if (isOverdue) headerColor = AppColors.statusCritical;
    else if (dueSoonDays != null && dueSoonDays <= 7) headerColor = AppColors.statusWarning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_outlined, size: 16, color: headerColor),
                const SizedBox(width: 6),
                Text('Scheduling',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (isOverdue)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.statusCriticalSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Overdue $overdueDays day${overdueDays == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.statusCriticalText),
                    ),
                  )
                else if (dueSoonDays != null && dueSoonDays <= 7)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.statusWarningSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Due in $dueSoonDays day${dueSoonDays == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.statusWarningText),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (lastDate != null)
              _scheduleRow('Last visit', DateFormat('dd MMM yyyy').format(lastDate), scheme),
            if (nextDate != null)
              _scheduleRow(
                'Next due',
                DateFormat('dd MMM yyyy').format(nextDate),
                scheme,
                valueColor: isOverdue ? AppColors.statusCritical : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleRow(String label, String value, ColorScheme scheme,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? scheme.onSurface)),
        ],
      ),
    );
  }

  // ── Last Vitals (start of next section — visit history removed: redundant
  // with the existing "Recent visits" section lower on the screen) ───────────

  // ── Last Vitals ────────────────────────────────────────────────────────────

  _VitalsSnapshot? _parseVitals() {
    for (final a in widget.data.assessments) {
      final j = a.rawJson;
      if (j.isEmpty) continue;
      final bpLog = j['bpLog'] as Map<String, dynamic>?;
      final glucoseLog = j['glucoseLog'] as Map<String, dynamic>?;
      final phys = j['medicalHistoryPhysicalExamination'] as Map<String, dynamic>?;
      final poc = j['pointOfCareInvestigations'] as Map<String, dynamic>?;

      final bpSys = (bpLog?['avgSystolic'] as num?)?.toInt() ??
          (phys?['bloodPressureSystolic'] as num?)?.toInt();
      final bpDia = (bpLog?['avgDiastolic'] as num?)?.toInt() ??
          (phys?['bloodPressureDiastolic'] as num?)?.toInt();
      final weight = (bpLog?['weight'] as num?)?.toDouble() ??
          (phys?['weight'] as num?)?.toDouble();

      double? glucose;
      String? glucoseType;
      String? glucoseUnit;
      double? hb;

      if (glucoseLog != null) {
        glucose = (glucoseLog['glucoseValue'] as num?)?.toDouble();
        glucoseType = glucoseLog['glucoseType'] as String?;
        glucoseUnit = glucoseLog['glucoseUnit'] as String? ?? 'mmol/L';
      }
      if (poc != null) {
        hb = (poc['hemoglobin'] as num?)?.toDouble();
        glucose ??= (poc['bloodSugarFasting'] as num?)?.toDouble();
        if (glucose != null) {
          glucoseType ??= 'fasting';
          glucoseUnit ??= 'mg/dL';
        }
      }

      if (bpSys != null || glucose != null || weight != null || hb != null) {
        return _VitalsSnapshot(
          bpSys: bpSys, bpDia: bpDia,
          glucose: glucose, glucoseType: glucoseType, glucoseUnit: glucoseUnit,
          weight: weight, hb: hb, recordedAt: a.date,
        );
      }
    }
    return null;
  }

  Widget _buildVitalsCard(BuildContext context, ColorScheme scheme, _VitalsSnapshot v) {
    final date = DateFormat('dd MMM yyyy').format(v.recordedAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite_outline_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text('Last Vitals',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('Recorded $date',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            if (v.bpSys != null && v.bpDia != null)
              _vitalRow(
                'Blood Pressure',
                '${v.bpSys}/${v.bpDia} mmHg',
                v.bpSys! >= 140 ? AppColors.statusCritical : null,
                scheme,
              ),
            if (v.glucose != null)
              _vitalRow(
                v.glucoseType == 'fasting' ? 'Glucose (fasting)' : 'Glucose (random)',
                '${v.glucose!.toStringAsFixed(1)} ${v.glucoseUnit ?? ''}',
                null,
                scheme,
              ),
            if (v.weight != null)
              _vitalRow('Weight', '${v.weight!.toStringAsFixed(1)} kg', null, scheme),
            if (v.hb != null)
              _vitalRow(
                'Haemoglobin',
                '${v.hb!.toStringAsFixed(1)} g/dL',
                v.hb! < 10 ? AppColors.statusCritical : v.hb! < 11 ? AppColors.statusWarning : null,
                scheme,
              ),
          ],
        ),
      ),
    );
  }

  Widget _vitalRow(String label, String value, Color? flagColor, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: flagColor ?? scheme.onSurface)),
          if (flagColor != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.arrow_upward_rounded, size: 13, color: flagColor),
          ],
        ],
      ),
    );
  }

  static String? _formatDob(String? dob) {
    if (dob == null || dob.isEmpty) return null;
    try {
      final d = DateTime.parse(dob);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return dob;
    }
  }
}

class _VitalsSnapshot {
  const _VitalsSnapshot({
    this.bpSys, this.bpDia,
    this.glucose, this.glucoseType, this.glucoseUnit,
    this.weight, this.hb,
    required this.recordedAt,
  });
  final int? bpSys;
  final int? bpDia;
  final double? glucose;
  final String? glucoseType;
  final String? glucoseUnit;
  final double? weight;
  final double? hb;
  final DateTime recordedAt;
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

    final ageLabel = _ageLabelFromDob(data.dateOfBirth, data.age);
    final subtitleParts = <String>[];
    if (ageLabel != null) subtitleParts.add(ageLabel);
    if (data.gender != null) subtitleParts.add(data.gender!);
    if (data.householdId != null) {
      subtitleParts.add(
        data.householdName ??
            PatientContextStrings.householdFallback(data.householdId!),
      );
    }
    final subtitle = subtitleParts.join(' · ');

    final chips = <_HeaderChip>[
      if (data.nationalId != null)
        _HeaderChip(Icons.badge_outlined, data.nationalId!),
      if (data.phoneNumber != null || data.householdId != null)
        _HeaderChip(Icons.phone_outlined, data.phoneNumber ?? ContactSheetStrings.noContactAvailable,
            onTap: () => showContactSheet(context, data)),
      if (data.villageName != null)
        _HeaderChip(Icons.location_on_outlined, data.villageName!,
            onTap: () => _launchMaps(context, data.villageName!)),
      if (data.isPregnant)
        _HeaderChip(Icons.pregnant_woman, PatientContextStrings.pregnantChip),
    ];

    return Container(
      color: AppColors.navy,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 8,
        8,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              HeaderIconButton(
                icon: Icons.arrow_back,
                tooltip: PatientContextStrings.backToWorklist,
                onTap: onBack,
              ),
              const SizedBox(width: 10),
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
              if (isUrgent)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: tokens.statusCritical,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    PatientContextStrings.urgentBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              HeaderIconButton(
                icon: Icons.cloud_download_outlined,
                tooltip: PatientContextStrings.refresh,
                onTap: onRefresh,
                child: refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: chips
                    .map(
                      (c) => _buildHeaderChip(context, c),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(BuildContext context, _HeaderChip c) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: c.onTap != null ? 0.22 : 0.15),
        borderRadius: BorderRadius.circular(12),
        border: c.onTap != null
            ? Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.8)
            : null,
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
    );
    if (c.onTap == null) return chip;
    return GestureDetector(onTap: c.onTap, child: chip);
  }

  static Future<void> _launchMaps(BuildContext context, String place) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(place.trim())}');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
        );
      }
    }
  }

  static String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// Smart age label: months for under-2, years otherwise.
  /// Mirrors the logic in [_VisitFlowState._ageDisplay].
  static String? _ageLabelFromDob(String? dob, int? ageYears) {
    if (dob != null && dob.isNotEmpty) {
      try {
        final birth = DateTime.parse(dob);
        final now = DateTime.now();
        final months = (now.year - birth.year) * 12 +
            (now.month - birth.month) -
            (now.day < birth.day ? 1 : 0);
        if (months < 24) return '$months month${months == 1 ? '' : 's'}';
        final years = months ~/ 12;
        return 'Age $years';
      } catch (_) {}
    }
    if (ageYears == null) return null;
    if (ageYears == 0) return '< 1 yr';
    return 'Age $ageYears';
  }
}

class _HeaderChip {
  const _HeaderChip(this.icon, this.label, {this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
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
        // Show all household members including the current patient
        final others = members
            .where((m) => m.name != null && m.name!.isNotEmpty)
            .toList();
        if (others.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: AppColors.cardSurface,
            border: Border(
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Make header tappable to navigate to household detail
              Semantics(
                label: PatientContextStrings.viewHouseholdDetails,
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
                      PatientContextStrings.sameHousehold,
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
                        '${others.length}',
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
                    final name = m.name ?? PatientContextStrings.unknownMemberName;
                    final age = CalendarDay.ageFromDob(m.dob);
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
                        gender: m.gender,
                        isCurrent: m.id == currentPatientId ||
                            m.patientId == currentPatientId,
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

}

/// Individual chip for a household member in the same-household strip.
class _HouseholdMemberChip extends StatelessWidget {
  const _HouseholdMemberChip({
    required this.name,
    required this.age,
    required this.onTap,
    this.gender,
    this.isCurrent = false,
  });

  final String name;
  final int? age;
  final String? gender;
  final bool isCurrent;
  final VoidCallback onTap;

  String get _label {
    final buf = StringBuffer(name);
    if (age != null) buf.write(' · ${age}y');
    if (gender != null && gender!.isNotEmpty) {
      final g = gender![0].toUpperCase();
      if (g == 'M' || g == 'F') buf.write(' · $g');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final bgColor = isCurrent
        ? tokens.brandNavy.withValues(alpha: 0.18)
        : tokens.brandNavy.withValues(alpha: 0.08);
    return Semantics(
      label: PatientContextStrings.viewPatientSemantics(name, age),
      button: true,
      child: GestureDetector(
      key: const Key('patient_member_chip_tap'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: tokens.brandNavy.withValues(alpha: isCurrent ? 0.6 : 0.3),
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
              _label,
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

/// Banner shown when a patient has no programmes enrolled yet.
class _NoServicesCard extends StatelessWidget {
  const _NoServicesCard({
    required this.patientId,
    required this.patientName,
    this.patientAge,
    this.patientGender,
    this.villageName,
  });

  final String patientId;
  final String? patientName;
  final int? patientAge;
  final String? patientGender;
  final String? villageName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF2F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.medical_services_outlined,
                    size: 18,
                    color: Color(0xFF9D174D),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        EnrollStrings.noServicesTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        EnrollStrings.noServicesSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  context.push(
                    '/patients/$patientId/new-visit',
                    extra: <String, dynamic>{
                      'patientName': patientName ?? 'Patient',
                      if (patientAge != null) 'patientAge': patientAge,
                      if (patientGender != null)
                        'patientGender': patientGender,
                      if (villageName != null) 'villageName': villageName,
                    },
                  );
                },
                icon: const Icon(Icons.add, size: 18, color: Colors.white),
                label: const Text(
                  EnrollStrings.addServicesCta,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEC4899),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
