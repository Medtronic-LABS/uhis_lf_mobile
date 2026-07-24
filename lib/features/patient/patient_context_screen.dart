import 'dart:convert';
import 'dart:ui' as ui;

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
import 'patient_actions_row.dart';
import 'patient_repository.dart';
import '../assistant/patient_ai_sheet.dart';
import 'contact_sheet.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../../core/widgets/gestational_age_card.dart';
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
    this.householdHeadPhone,
    this.vitalHistory = const [],
    this.pregnancySnapshot,
  });

  final PatientWithProgrammes? localPatient;
  final MemberHealthDetails? remoteMember;
  final String? householdName;
  final String? householdHeadPhone;
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
    String? householdHeadPhone,
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
      householdHeadPhone: householdHeadPhone ?? this.householdHeadPhone,
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

  @override
  void initState() {
    super.initState();
    debugPrint('[_PatientContextScreenState] initState patientId=${widget.patientId}');
    // Initialize directly without setState since widget isn't mounted yet
    _future = _fetchData();
  }

  void _load() {
    debugPrint('[_PatientContextScreenState] _load');
    final future = _fetchData();
    setState(() {
      _future = future;
    });
  }

  /// Looks up household name from the local DB. Returns null if not found.
  Future<({String? name, String? headPhone})> _householdInfo(
      String? householdId) async {
    if (householdId == null || householdId.isEmpty) {
      return (name: null, headPhone: null);
    }
    try {
      final dao = context.read<HouseholdDao>();
      final entity = await dao.getById(householdId);
      final name =
          entity?.name?.trim().isNotEmpty == true ? entity!.name : null;
      final headPhone =
          entity?.headPhoneNumber?.trim().isNotEmpty == true
              ? entity!.headPhoneNumber
              : null;
      return (name: name, headPhone: headPhone);
    } on Object {
      return (name: null, headPhone: null);
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
    debugPrint('[_PatientContextScreenState] _fetchData');
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
        final info = await _householdInfo(localPatient.patient.householdId);
        if (mounted) setState(() => _remoteLoading = false);
        ConsoleLog.banner('[PatientCtx] phase2 done=${tPhase2.elapsedMilliseconds}ms'
            ' remoteSkipped=true total=${t0.elapsedMilliseconds}ms');
        return localOnly.copyWith(householdName: info.name, householdHeadPhone: info.headPhone);
      }

      ConsoleLog.banner('[PatientCtx] phase2 start — remote assessments + householdInfo');
      final phase2Results = await Future.wait([
        memberRepo
            .getMemberAssessments(
              widget.patientId,
              villageId: localPatient.patient.villageId,
              patientAge: localPatient.patient.age,
              patientGender: localPatient.patient.gender,
            )
            .catchError((_) => <MemberAssessment>[]),
        _householdInfo(localPatient.patient.householdId),
      ]);
      remoteAssessments = phase2Results[0] as List<MemberAssessment>;
      final householdInfo = phase2Results[1] as ({String? name, String? headPhone});
      // ignore: avoid_print
      print('[PatientContextScreen] Found ${remoteAssessments.length} remote assessments');

      if (mounted) setState(() => _remoteLoading = false);

      return localOnly.copyWith(
        remoteAssessments: remoteAssessments,
        householdName: householdInfo.name,
        householdHeadPhone: householdInfo.headPhone,
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
      final memberHouseholdInfo = await _householdInfo(member.householdId);
      return PatientOrMemberData(
        remoteMember: member,
        programmes: progs,
        localAssessments: localAssessments,
        memberId: resolvedMemberId,
        householdName: memberHouseholdInfo.name,
        householdHeadPhone: memberHouseholdInfo.headPhone,
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
      final prePassedHouseholdInfo = await _householdInfo(data['householdId']?.toString());
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
        householdName: prePassedHouseholdInfo.name,
        householdHeadPhone: prePassedHouseholdInfo.headPhone,
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
      // Keep _localSnapshot so the existing content stays visible
      // during the pull-to-refresh; skeleton only shows on cold load.
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
                          child: Text(CommonStrings.retry),
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

    final threads = _deriveThreads(data);

    // ANC / PW pregnancy snapshot (non-null only for active pregnancy)
    final snap = data.pregnancySnapshot;
    final isAnc = data.programmes.contains(Programme.anc);

    // Latest ANC assessment — visit number + gravida/parity for pregnancy bar
    final latestAncVisit = data.assessments
        .where((a) => Programme.fromString(a.type) == Programme.anc)
        .firstOrNull;
    final ancRaw = latestAncVisit != null
        ? _normalizeRaw(latestAncVisit.rawJson)
        : const <String, dynamic>{};
    // Multi-path lookup mirrors LocalAssessmentDao._extractVisitNumber for ANC.
    final ancCount = data.assessments
        .where((a) => Programme.fromString(a.type) == Programme.anc)
        .length;
    final ancVisitNum = ancRaw['ancVisitNumber']?.toString()
        ?? ancRaw['visitNo']?.toString()
        ?? (ancRaw['medicalHistoryPhysicalExamination'] is Map
            ? (ancRaw['medicalHistoryPhysicalExamination'] as Map)['ancVisitNumber']?.toString()
            : null)
        ?? (ancRaw['anc'] is Map
            ? (ancRaw['anc'] as Map)['ancVisitNumber']?.toString()
            : null)
        // Fallback: count of ANC assessments when no explicit visit number field.
        ?? (ancCount > 0 ? '$ancCount' : null);
    final gravida = ancRaw['gravida']?.toString();
    final parity = ancRaw['parity']?.toString();

    // AI context summary (pure local, synchronous)
    final aiCtx = _aiContext(data);

    // Status badge — overdue takes priority over risk band
    final pendingEntry = _derivePendingEntry(data);
    String? statusLabel;
    Color statusBg = Colors.transparent;
    Color statusFg = Colors.white;
    if (pendingEntry != null) {
      statusLabel = 'OVERDUE';
      statusBg = AppColors.statusCritical;
    } else if (data.riskBand == Band.band1) {
      statusLabel = 'CRITICAL';
      statusBg = AppColors.statusCritical;
    } else if (data.riskBand == Band.band2) {
      statusLabel = 'HIGH RISK';
      statusBg = AppColors.statusWarning;
    } else if (data.riskBand == Band.band3) {
      statusLabel = 'MONITORING';
      statusBg = AppColors.navy;
    }

    debugPrint('⏱ [PatientContext] _buildContent setup in ${t0.elapsedMilliseconds}ms'
        ' threads=${threads.length} snap=${snap != null}');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _lightStatusBar,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _PatientDetailHeader(
              data: data,
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
                    // ── AI Insight card ───────────────────────────────────
                    _AiInsightCard(
                      summary: aiCtx.summary,
                      statusLabel: statusLabel,
                      statusBg: statusBg,
                      statusFg: statusFg,
                      riskBand: data.riskBand,
                      riskModifier: data.riskModifier,
                      riskReasons: data.riskReasons,
                      lastAssessedDate: data.assessments.isNotEmpty ? data.assessments.first.date : null,
                    ),
                    const SizedBox(height: 10),

                    // ── Active care threads ───────────────────────────────
                    _CareThreadChipRow(threads: threads),
                    const SizedBox(height: 12),

                    // ── Pregnancy LMP/EDD card (active pregnancy only) ────
                    if (isAnc && snap != null && snap.deliveryDateMillis == null && !snap.facts.isPostpartumWindow) ...[
                      GestationalAgeCard(
                        lmpDate: snap.lmpDate != null
                            ? DateTime.fromMillisecondsSinceEpoch(snap.lmpDate!)
                            : null,
                        eddDate: snap.eddDate != null
                            ? DateTime.fromMillisecondsSinceEpoch(snap.eddDate!)
                            : null,
                        ancVisitNumber: ancVisitNum,
                      ),
                      const SizedBox(height: 12),
                    ],
                    // ── Combined health history ───────────────────────────
                    _CombinedTimeline(
                      entries: _buildTimelineEntries(data),
                      isLoading: remoteLoading,
                    ),

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
  _CareThread({
    required this.programme,
    required this.label,
    required this.bg,
    required this.textColor,
    this.icon = '',
    this.stats = const {},
    this.checkupDate,
  });

  final Programme programme;
  final String label;
  final Color bg;
  final Color textColor;
  final String icon;
  final Map<String, String> stats;
  /// Date of the latest assessment for this thread's programme.
  final DateTime? checkupDate;
}

// ─── Timeline Entry model ──────────────────────────────────────────────────

/// A display-ready timeline entry derived from a [MemberAssessment] or a
/// rule-based synthesis (pending action, enrollment, past illness, etc.).
class _TimelineEntry {
  const _TimelineEntry({
    required this.emoji,
    required this.title,
    required this.relativeDate,
    required this.category,
    required this.date,
    required this.dotColor,
    this.description,
    this.badge,
    this.badgeColor,
    this.badgeFgColor,
    this.isPending = false,
    this.programme,
    this.source,
  });

  final String emoji;
  final String title;
  final String relativeDate;
  final String category;
  final DateTime date;
  final Color dotColor;
  final String? description;
  final String? badge;
  final Color? badgeColor;
  final Color? badgeFgColor;
  final bool isPending;
  final Programme? programme;
  /// Original assessment for tap-to-detail; null for synthetic entries.
  final MemberAssessment? source;
}

// ─── Timeline synthesis helpers ────────────────────────────────────────────

/// Human-readable relative date from [date] to now.
String _relativeDate(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inDays == 0) return 'Today';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  if (diff.inDays < 14) return '1 week ago';
  if (diff.inDays < 60) {
    final w = (diff.inDays / 7).round();
    return '$w week${w > 1 ? 's' : ''} ago';
  }
  if (diff.inDays < 365) {
    final m = (diff.inDays / 30.5).round();
    return '$m month${m > 1 ? 's' : ''} ago';
  }
  final yrs = diff.inDays ~/ 365;
  final rem = diff.inDays - yrs * 365;
  final mos = (rem / 30.5).round();
  if (mos == 0) return '$yrs yr${yrs > 1 ? 's' : ''} ago';
  return '$yrs yr${yrs > 1 ? 's' : ''} $mos mo ago';
}

// ── Timeline colour palette ──────────────────────────────────────────────────

const _kDotCritical = Color(0xFFEF4444); // red-500
const _kDotHigh     = Color(0xFFBE185D); // rose-700
const _kDotModerate = Color(0xFFD97706); // amber-600
const _kDotOk       = Color(0xFF059669); // emerald-600
const _kDotAnc      = Color(0xFF9D174D); // rose-800
const _kDotPnc      = Color(0xFF9D174D); // rose-800
const _kDotEpi      = Color(0xFF1D4ED8); // blue-700
const _kDotTb       = Color(0xFF059669); // emerald-600
const _kDotImci     = Color(0xFFDC2626); // red-600
const _kDotFp       = Color(0xFF7C3AED); // violet-600
const _kDotGeneral  = Color(0xFF6B7280); // gray-500
const _kDotPending  = Color(0xFFEF4444); // red-500

const _kBadgeCriticalBg = Color(0xFFFEE2E2);
const _kBadgeCriticalFg = Color(0xFFDC2626);
const _kBadgeHighBg     = Color(0xFFFCE7F3);
const _kBadgeHighFg     = Color(0xFF9D174D);
const _kBadgeAmberBg    = Color(0xFFFEF3C7);
const _kBadgeAmberFg    = Color(0xFFB45309);
const _kBadgeGreenBg    = Color(0xFFECFDF5);
const _kBadgeGreenFg    = Color(0xFF065F46);
const _kBadgeGrayBg     = Color(0xFFF3F4F6);
const _kBadgeGrayFg     = Color(0xFF374151);

// ── BP parse helpers ─────────────────────────────────────────────────────────

int _sys(String bp) => int.tryParse(bp.split('/').firstOrNull ?? '') ?? 0;
int _dia(String bp) => int.tryParse(bp.split('/').lastOrNull ?? '') ?? 0;

/// Convert a single [MemberAssessment] into a display [_TimelineEntry].
/// Builds a clinical narrative that combines referral reason tokens WITH actual
/// vitals from [raw]. Each condition is checked from two directions:
///   1. Does the reason string mention it? (backend clinical decision)
///   2. Does the raw vital value exceed a clinical threshold?
/// Actual values are injected when available and within plausible ranges.
/// Implausible test values (e.g. Hb 43 g/dL) are silently ignored.
String _buildReferralNarrative(String? reasons, Map<String, dynamic> raw) {
  final tokens = (reasons ?? '')
      .split(',')
      .map((r) => r.toLowerCase().trim())
      .where((r) => r.isNotEmpty)
      .toSet();

  bool mentions(List<String> keys) => tokens.any((t) => keys.any(t.contains));

  final findings = <String>[];
  final handled = <String>{};

  // ── Danger signs ─────────────────────────────────────────────────────────
  final dSign = (raw['dangerSigns']?.toString() ?? raw['dangerSign']?.toString() ?? '').trim();
  final dSignPresent = dSign.isNotEmpty &&
      !const ['none', 'no', 'false', ''].contains(dSign.toLowerCase());
  if (mentions(['danger']) || dSignPresent) {
    findings.add(dSignPresent
        ? 'Danger sign reported: $dSign.'
        : 'Danger sign reported — urgent attention required.');
    handled.addAll(['danger']);
  }

  // ── BP ───────────────────────────────────────────────────────────────────
  final bp = raw['bp']?.toString() ?? '';
  final sys = _sys(bp);
  final dia = _dia(bp);
  final bpHigh = sys >= 140 || dia >= 90;
  if (mentions(['bp', 'blood pressure', 'hypertension']) || bpHigh) {
    if (bp.isNotEmpty && sys > 0) {
      if (sys >= 160 || dia >= 110) {
        findings.add('BP $bp is dangerously elevated — urgent referral needed.');
      } else {
        findings.add('BP $bp is above the normal — review and follow-up required.');
      }
    } else {
      findings.add('BP is above the normal — review and follow-up required.');
    }
    handled.addAll(['bp', 'blood pressure', 'hypertension']);
  }

  // ── Blood glucose ─────────────────────────────────────────────────────────
  final bg = double.tryParse(raw['bg']?.toString() ?? '') ?? 0;
  final bgType = raw['bgType']?.toString() ?? 'RBS';
  final bgThreshold = bgType == 'FBS' ? 7.0 : 11.1;
  final bgHigh = bg > 0 && bg < 50 && bg >= bgThreshold; // cap 50 to exclude junk
  if (mentions(['glucose', 'blood sugar', 'bloodglucose']) || bgHigh) {
    if (bg > 0 && bg < 50) {
      findings.add('Blood sugar $bg mmol/L ($bgType) is elevated — review and follow-up required.');
    } else {
      findings.add('Blood sugar is elevated — review and follow-up required.');
    }
    handled.addAll(['glucose', 'blood sugar', 'bloodglucose']);
  }

  // ── Hemoglobin ────────────────────────────────────────────────────────────
  final hb = double.tryParse(raw['hemoglobin']?.toString() ?? '') ?? 0;
  final hbPlausible = hb > 0 && hb <= 20;
  final hbLow = hbPlausible && hb < 8;
  if (mentions(['hemoglobin', 'anemia', 'anaemia']) || hbLow) {
    if (hbPlausible) {
      findings.add(hb < 7
          ? 'Severe anemia (Hb $hb g/dL) — urgent review needed.'
          : 'Anemia (Hb $hb g/dL) — review iron supplementation.');
    } else {
      findings.add('Severe anemia — urgent review needed.');
    }
    handled.addAll(['hemoglobin', 'anemia', 'anaemia']);
  }

  // ── Pulse ─────────────────────────────────────────────────────────────────
  final pulse = int.tryParse(
      raw['pulse']?.toString() ?? raw['heartRate']?.toString() ?? '') ?? 0;
  final pulseAbnormal = pulse > 0 && (pulse > 90 || pulse < 60);
  if (mentions(['pulse']) || pulseAbnormal) {
    if (pulse > 0) {
      final dir = pulse > 90 ? 'above' : 'below';
      findings.add('Pulse $pulse bpm is $dir normal — needs urgent attention.');
    } else {
      findings.add('Pulse is abnormal — needs urgent attention.');
    }
    handled.add('pulse');
  }

  // ── Temperature ───────────────────────────────────────────────────────────
  final rawTemp = double.tryParse(raw['temperature']?.toString() ?? '') ?? 0;
  // detect °F vs °C by magnitude
  final tempC = rawTemp >= 50 ? (rawTemp - 32) * 5 / 9 : rawTemp;
  final tempHigh = tempC > 0 && tempC >= 38.9;
  if (mentions(['temperature', 'fever']) || tempHigh) {
    if (tempC > 0) {
      findings.add('Temperature ${tempC.toStringAsFixed(1)}°C is elevated — needs urgent attention.');
    } else {
      findings.add('Elevated temperature — needs urgent attention.');
    }
    handled.addAll(['temperature', 'fever']);
  }

  // ── Weight ────────────────────────────────────────────────────────────────
  final wt = double.tryParse(raw['weight']?.toString() ?? '') ?? 0;
  final wtPlausible = wt >= 20 && wt <= 200;
  final wtLow = wtPlausible && wt < 45;
  if (mentions(['weight']) || wtLow) {
    if (wtPlausible) {
      findings.add('Low weight ($wt kg) — monitor nutrition.');
    } else {
      findings.add('Low weight detected — monitor nutrition.');
    }
    handled.add('weight');
  }

  // ── Medication adherence ──────────────────────────────────────────────────
  if (mentions(['medication', 'adherence'])) {
    findings.add('Medication adherence is low — confirm daily intake.');
    handled.addAll(['medication', 'adherence']);
  }

  // ── Family planning ───────────────────────────────────────────────────────
  if (mentions(['family planning', 'contraception', 'fp'])) {
    findings.add('No contraception method in use — counsel on options.');
    handled.addAll(['family planning', 'contraception', 'fp']);
  }

  // ── Supplements ───────────────────────────────────────────────────────────
  if (mentions(['supplement', 'vitamin', 'ifa', 'calcium'])) {
    findings.add('Supplement gap — ensure continued supplementation.');
    handled.addAll(['supplement', 'vitamin', 'ifa', 'calcium']);
  }

  // ── Overdue ───────────────────────────────────────────────────────────────
  if (mentions(['overdue', 'missed visit'])) {
    findings.add('Visit overdue — schedule follow-up urgently.');
    handled.addAll(['overdue', 'missed visit']);
  }

  // ── Pass-through for unrecognised tokens ─────────────────────────────────
  for (final token in tokens) {
    if (token.length > 2 && !handled.any(token.contains)) {
      final t = token.trim();
      findings.add('${t[0].toUpperCase()}${t.substring(1)}.');
    }
  }

  return findings.isEmpty
      ? 'Referred for clinical review — follow-up required.'
      : findings.join(' ');
}

/// Short human-readable label for a single referral reason token.
/// Used in the detail sheet where space is tighter than the full narrative.
String _shortReasonLabel(String reason) {
  final k = reason.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (k.contains('bloodglucose') || k.contains('blood glucose') ||
      (k.contains('glucose') && !k.contains('blood pressure'))) return 'Blood glucose elevated';
  if (k.contains('pulse')) return 'Abnormal pulse';
  if (k.contains('blood pressure') || k.contains('bloodpressure') ||
      k == 'bp' || k.contains('hypertension')) return 'High BP';
  if (k.contains('hemoglobin') || k.contains('anaemia') || k.contains('anemia') ||
      (k.startsWith('hb') && k.length <= 4)) return 'Low Hb / Anemia';
  if (k.contains('danger sign') || k == 'dangersign' || k == 'danger') return 'Danger sign';
  if (k.contains('temperature') || k.contains('fever')) return 'Elevated temperature';
  if (k.contains('weight') && !k.contains('birth')) return 'Low weight';
  if (k.contains('medication') || k.contains('adherence')) return 'Low medication adherence';
  if (k.contains('family planning') || k.contains('contraception') || k == 'fp') return 'No FP method';
  if (k.contains('supplement') || k.contains('vitamin') ||
      k.contains('ifa') || k.contains('calcium')) return 'Supplement gap';
  if (k.contains('overdue') || k.contains('missed visit')) return 'Visit overdue';
  final t = reason.trim();
  return t.isEmpty ? '' : t[0].toUpperCase() + t.substring(1);
}

_TimelineEntry _assessmentToEntry(MemberAssessment a) {
  final raw = _normalizeRaw(a.rawJson);
  final prog = Programme.fromString(a.type);
  final relDate = _relativeDate(a.date);

  final dx = (raw['confirmDiagnosis'] as String? ?? '').toLowerCase();
  final notesLower = (a.notes ?? '').toLowerCase();
  final combined = '$dx $notesLower';

  // Backend referral status is the primary clinical signal — more reliable than
  // re-deriving from raw vitals, which may be missing or contain test data.
  final rawStatus = (raw['referralStatus'] as String? ?? a.status ?? '').toLowerCase().trim();
  final referralReasons = a.notes?.isNotEmpty == true ? a.notes! : null;

  String emoji;
  String title;
  String category;
  String? description;
  String? badge;
  Color? badgeColor;
  Color? badgeFgColor;
  Color dotColor;

  switch (prog) {
    // ─── ANC / Antenatal ──────────────────────────────────────────────────
    case Programme.anc:
    case Programme.pw:
      emoji = '🤰';
      final vn = raw['ancVisitNumber']?.toString();
      title = vn != null && vn.isNotEmpty ? 'ANC Visit $vn' : 'ANC Checkup';
      category = 'Antenatal Care';

      final bpANC = raw['bp']?.toString() ?? '';
      final sysANC = _sys(bpANC);
      final diaANC = _dia(bpANC);
      final hbRaw = raw['hemoglobin']?.toString() ?? '';
      final hbANC = double.tryParse(hbRaw) ?? 0;

      if (sysANC >= 160 || diaANC >= 110) {
        dotColor = _kDotCritical;
        badge = 'Danger — High BP';
        badgeColor = _kBadgeCriticalBg;
        badgeFgColor = _kBadgeCriticalFg;
        description = 'BP $bpANC is dangerously elevated — urgent referral needed.';
      } else if (hbANC > 0 && hbANC < 7) {
        dotColor = _kDotCritical;
        badge = 'Severe anemia';
        badgeColor = _kBadgeCriticalBg;
        badgeFgColor = _kBadgeCriticalFg;
        description = 'Hb ${hbANC}g/dL — severe anemia. Urgent review needed.';
      } else if (sysANC >= 140 || diaANC >= 90) {
        dotColor = _kDotHigh;
        badge = 'High-risk pregnancy';
        badgeColor = _kBadgeHighBg;
        badgeFgColor = _kBadgeHighFg;
        final dp = <String>[];
        if (bpANC.isNotEmpty) dp.add('BP $bpANC above target');
        if (hbANC > 0 && hbANC < 10) dp.add('Anemia (Hb ${hbANC}g/dL)');
        description = dp.isEmpty ? 'High BP detected — monitor closely.' : dp.join(' · ');
      } else if (hbANC > 0 && hbANC < 10) {
        dotColor = _kDotModerate;
        badge = 'Anemia';
        badgeColor = _kBadgeAmberBg;
        badgeFgColor = _kBadgeAmberFg;
        description = 'Hb ${hbANC}g/dL — anemia. Review iron supplementation.';
      } else if (hbANC >= 10 && hbANC < 11) {
        dotColor = _kDotModerate;
        badge = 'Mild anemia';
        badgeColor = _kBadgeAmberBg;
        badgeFgColor = _kBadgeAmberFg;
        description = 'Hb ${hbANC}g/dL — mild anemia. Ensure iron supplementation continues.';
      } else {
        dotColor = _kDotAnc;
        description = 'Routine antenatal visit — vitals within normal range.';
      }

    // ─── PNC / Delivery ───────────────────────────────────────────────────
    case Programme.pnc:
      final delivery = raw['modeOfDelivery']?.toString() ?? '';
      final pncVN = raw['pncVisitNumber']?.toString() ?? '';

      if (delivery.isNotEmpty && pncVN.isEmpty) {
        // Pregnancy outcome
        emoji = '🏥';
        title = 'Pregnancy Outcome';
        category = 'Delivery';

        final allVals = raw.values.map((v) => v.toString().toLowerCase()).join(' ');
        if (allVals.contains('stillbirth') || allVals.contains('neonatal death')) {
          dotColor = _kDotCritical;
          badge = 'Stillbirth / Neonatal death';
          badgeColor = _kBadgeCriticalBg;
          badgeFgColor = _kBadgeCriticalFg;
          description = 'Stillbirth or neonatal death recorded — follow-up and counselling needed.';
        } else if (allVals.contains('abortion') || allVals.contains('miscarriage')) {
          dotColor = _kDotHigh;
          badge = 'Pregnancy loss';
          badgeColor = _kBadgeCriticalBg;
          badgeFgColor = _kBadgeCriticalFg;
          description = 'Pregnancy loss (abortion) recorded — follow-up care advised.';
        } else {
          final isCs = delivery.toLowerCase().contains('caesar') ||
              delivery.toLowerCase().contains('c-section') ||
              delivery.toLowerCase().contains('section');
          dotColor = isCs ? _kDotHigh : _kDotOk;
          badge = isCs ? 'Emergency C-section' : 'Normal delivery';
          badgeColor = isCs ? _kBadgeHighBg : _kBadgeGreenBg;
          badgeFgColor = isCs ? _kBadgeHighFg : _kBadgeGreenFg;
          final babyWt = raw['babyBirthWeight']?.toString() ?? raw['birthWeight']?.toString();
          description = 'Healthy delivery outcome — mother and baby both doing well.'
              '${babyWt != null && babyWt.isNotEmpty ? ' Baby $babyWt kg.' : ''}';
        }
      } else {
        // PNC follow-up
        emoji = '🤱';
        title = 'PNC Visit${pncVN.isNotEmpty ? ' $pncVN' : ''}';
        category = 'Postnatal Care';

        final dSign = raw['dangerSigns']?.toString() ?? raw['dangerSign']?.toString() ?? '';
        final bpPNC = raw['bp']?.toString() ?? '';
        final sysPNC = _sys(bpPNC);
        final diaPNC = _dia(bpPNC);
        final hbPNC = double.tryParse(raw['hemoglobin']?.toString() ?? '') ?? 0;
        final fpMethod = raw['familyPlanningMethods']?.toString() ?? raw['currentFpMethod']?.toString() ?? '';
        final rawTemp = double.tryParse(raw['temperature']?.toString() ?? '') ?? 0;
        // temperature stored as °C (≥38.9) or °F (≥102); detect by magnitude
        final tempHighC = rawTemp >= 50 ? rawTemp >= 102 : rawTemp >= 38.9;
        final pulse = int.tryParse(raw['pulse']?.toString() ?? raw['heartRate']?.toString() ?? '') ?? 0;
        final pulseHigh = pulse > 90;
        final pulseLow = pulse > 0 && pulse < 60;
        final bpHighPNC = sysPNC >= 140 || diaPNC >= 90;

        if (dSign.isNotEmpty && !['none', 'no', 'false', ''].contains(dSign.trim().toLowerCase())) {
          dotColor = _kDotCritical;
          badge = 'Danger sign';
          badgeColor = _kBadgeCriticalBg;
          badgeFgColor = _kBadgeCriticalFg;
          description = 'Danger sign reported: $dSign.';
        } else if (bpHighPNC || tempHighC || pulseHigh || pulseLow) {
          dotColor = _kDotCritical;
          badge = 'Urgent';
          badgeColor = _kBadgeCriticalBg;
          badgeFgColor = _kBadgeCriticalFg;
          final urgentParts = <String>[];
          if (bpHighPNC) urgentParts.add('BP $bpPNC is above target');
          if (tempHighC) urgentParts.add('Temperature is elevated');
          if (pulseHigh) urgentParts.add('Pulse $pulse bpm is above normal');
          if (pulseLow)  urgentParts.add('Pulse $pulse bpm is below normal');
          description = '${urgentParts.join(', ')} — needs urgent attention.';
        } else if (hbPNC > 0 && hbPNC < 8) {
          dotColor = _kDotHigh;
          badge = 'Severe anemia';
          badgeColor = _kBadgeAmberBg;
          badgeFgColor = _kBadgeAmberFg;
          description = 'Severe anemia (Hb $hbPNC g/dL).';
        } else if (fpMethod.isEmpty || ['none', 'no method', 'not using'].contains(fpMethod.trim().toLowerCase())) {
          dotColor = _kDotPnc;
          description = 'No contraception method in use — counsel on options.';
        } else {
          dotColor = _kDotOk;
          description = 'Recovering well — no concerns at this PNC visit.';
        }
      }

    // ─── NCD ──────────────────────────────────────────────────────────────
    case Programme.ncd:
      emoji = '❤️';
      title = 'NCD Visit';
      category = 'NCD Follow-up';

      final bpNCD = raw['bp']?.toString() ?? '';
      final sysNCD = _sys(bpNCD);
      final diaNCD = _dia(bpNCD);
      final bgNCD = double.tryParse(raw['bg']?.toString() ?? '') ?? 0;
      final bgTypeNCD = raw['bgType']?.toString() ?? 'RBS';
      final bpHighNCD = sysNCD >= 140 || diaNCD >= 90;
      final bgThreshold = bgTypeNCD == 'FBS' ? 7.0 : 11.1;
      final bgHighNCD = bgNCD > 0 && bgNCD >= bgThreshold;

      if (bpHighNCD && bgHighNCD) {
        dotColor = _kDotCritical;
        badge = 'High-risk';
        badgeColor = _kBadgeCriticalBg;
        badgeFgColor = _kBadgeCriticalFg;
        description = 'Both BP and blood sugar are above target — needs review today and planned follow-up.';
      } else if (bpHighNCD) {
        dotColor = _kDotHigh;
        badge = 'High BP';
        badgeColor = _kBadgeHighBg;
        badgeFgColor = _kBadgeHighFg;
        description = 'BP is above the normal. Require review and follow-up';
      } else if (bgHighNCD) {
        dotColor = _kDotModerate;
        badge = 'High blood sugar';
        badgeColor = _kBadgeAmberBg;
        badgeFgColor = _kBadgeAmberFg;
        description = 'Blood sugar is elevated. Require review and follow-up';
      } else {
        dotColor = _kDotOk;
        description = 'Vitals within target — continue current management.';
      }

    // ─── EPI / Vaccination ────────────────────────────────────────────────
    case Programme.epi:
      emoji = '💉';
      title = 'Vaccination';
      category = 'Immunization';
      dotColor = _kDotEpi;
      final vacName = raw['vaccineName']?.toString() ?? raw['vaccine']?.toString() ?? '';
      final dose = raw['dose']?.toString() ?? '';
      description = vacName.isNotEmpty
          ? '$vacName${dose.isNotEmpty ? " — Dose $dose" : ""} administered.'
          : 'Immunization on schedule, growth on track.';

    // ─── IMCI ─────────────────────────────────────────────────────────────
    case Programme.imci:
      emoji = '👶';
      title = 'Child health visit';
      category = 'IMCI / Child care';
      dotColor = _kDotImci;
      final dSignImci = raw['dangerSigns']?.toString() ?? '';
      if (dSignImci.isNotEmpty && dSignImci.toLowerCase() != 'none') {
        badge = 'Danger sign';
        badgeColor = _kBadgeCriticalBg;
        badgeFgColor = _kBadgeCriticalFg;
        dotColor = _kDotCritical;
        description = 'Danger sign: $dSignImci — urgent referral needed.';
      } else {
        final wtImci = raw['weight']?.toString();
        final vaccines = raw['receivedVaccine']?.toString() ?? '';
        final imciParts = <String>[
          if (wtImci != null) 'Weight $wtImci kg',
          if (vaccines.isNotEmpty) 'Vaccines: $vaccines',
        ];
        description = imciParts.isEmpty ? null : imciParts.join(' · ');
      }

    // ─── TB ───────────────────────────────────────────────────────────────
    case Programme.tb:
      emoji = '🫁';
      title = 'TB follow-up';
      category = 'TB Programme';
      dotColor = _kDotTb;
      description = dx.isNotEmpty ? 'Status: $dx' : null;

    // ─── Family Planning ──────────────────────────────────────────────────
    case Programme.familyPlanning:
      emoji = '🌸';
      title = 'Family Planning';
      category = 'Family Planning';
      dotColor = _kDotFp;
      final fpM = raw['familyPlanningMethods']?.toString() ?? '';
      description = fpM.isNotEmpty ? 'Method: $fpM' : null;

    // ─── General / Unknown ────────────────────────────────────────────────
    default:
      dotColor = _kDotGeneral;
      if (combined.contains('malaria')) {
        emoji = '🦟';
        title = 'Malaria — treated';
        category = 'Past illness';
        badge = 'Past illness';
        badgeColor = _kBadgeGrayBg;
        badgeFgColor = _kBadgeGrayFg;
        description = 'Tested positive, completed antimalarial course';
      } else if (combined.contains('diarrhea') || combined.contains('diarrhoea') || combined.contains('vomit')) {
        emoji = '🤢';
        title = 'Severe diarrhea & vomiting — treated';
        category = 'Past illness';
        badge = 'Past illness';
        badgeColor = _kBadgeGrayBg;
        badgeFgColor = _kBadgeGrayFg;
        description = 'Treated with ORS & antibiotics, fully recovered';
      } else if (combined.contains('fever')) {
        emoji = '🌡️';
        title = 'Fever — treated';
        category = 'Past illness';
        badge = 'Past illness';
        badgeColor = _kBadgeGrayBg;
        badgeFgColor = _kBadgeGrayFg;
        description = dx.isNotEmpty ? dx : null;
      } else {
        emoji = '📝';
        title = prog == Programme.unknown ? 'General visit' : prog.displayName;
        category = 'General';
        description = a.notes?.isNotEmpty == true ? a.notes : null;
      }
  }

  // Post-switch: referral status overrides vitals-derived severity.
  // Vitals may be absent or junk in test data; the backend already encoded
  // the clinical decision in referralStatus + referralReason.
  if (rawStatus == 'referred') {
    dotColor = _kDotCritical;
    badge = 'Referred';
    badgeColor = _kBadgeCriticalBg;
    badgeFgColor = _kBadgeCriticalFg;
    description = _buildReferralNarrative(referralReasons, raw);
  } else if (rawStatus == 'ontreatment') {
    dotColor = _kDotHigh;
    badge = 'On treatment';
    badgeColor = _kBadgeHighBg;
    badgeFgColor = _kBadgeHighFg;
    description = _buildReferralNarrative(referralReasons, raw);
  }

  return _TimelineEntry(
    emoji: emoji,
    title: title,
    relativeDate: relDate,
    category: category,
    date: a.date,
    dotColor: dotColor,
    description: description,
    badge: badge,
    badgeColor: badgeColor,
    badgeFgColor: badgeFgColor,
    programme: prog,
    source: a,
  );
}

/// Derives an optional rule-based "today" pending entry to pin at top of timeline.
/// Rules evaluated (in priority order):
///   1. ANC: rising systolic (>5 mmHg from prior visit) or systolic ≥ 130 → BP recheck
///   2. IMCI: no assessment in last 60 days → "Child visit overdue"
///   3. NCD: no assessment in last 30 days → "Follow-up overdue"
_TimelineEntry? _derivePendingEntry(PatientOrMemberData data) {
  final ancVisits = data.assessments
      .where((a) => Programme.fromString(a.type) == Programme.anc)
      .toList();

  if (ancVisits.isNotEmpty) {
    final latestRaw = _normalizeRaw(ancVisits.first.rawJson);
    final bpStr = latestRaw['bp']?.toString() ?? '';
    final sysStr = bpStr.split('/').firstOrNull ?? '';
    final sys = int.tryParse(sysStr);

    bool rising = false;
    if (ancVisits.length >= 2) {
      final prevRaw = _normalizeRaw(ancVisits[1].rawJson);
      final prevBp = prevRaw['bp']?.toString() ?? '';
      final prevSys = int.tryParse(prevBp.split('/').firstOrNull ?? '');
      if (sys != null && prevSys != null) rising = sys - prevSys > 5;
    }

    if (sys != null && (sys >= 130 || rising)) {
      return _TimelineEntry(
        emoji: '🔔',
        title: 'BP recheck due',
        relativeDate: 'Today',
        category: 'Pre-eclampsia watch',
        date: DateTime.now(),
        dotColor: _kDotPending,
        description: 'Rising trend flagged — check urine protein & danger signs',
        isPending: true,
        programme: Programme.anc,
      );
    }
  }

  final imciVisits = data.assessments
      .where((a) => Programme.fromString(a.type) == Programme.imci)
      .toList();
  if (imciVisits.isNotEmpty) {
    final daysSince = DateTime.now().difference(imciVisits.first.date).inDays;
    if (daysSince >= 60) {
      return _TimelineEntry(
        emoji: '🔔',
        title: 'Child visit overdue',
        relativeDate: 'Today',
        category: 'IMCI / Child care',
        date: DateTime.now(),
        dotColor: _kDotPending,
        description: 'Last child health visit was $daysSince days ago — check growth & vaccines',
        isPending: true,
        programme: Programme.imci,
      );
    }
  }

  final ncdVisits = data.assessments
      .where((a) => Programme.fromString(a.type) == Programme.ncd)
      .toList();
  if (ncdVisits.isNotEmpty) {
    final daysSince = DateTime.now().difference(ncdVisits.first.date).inDays;
    if (daysSince >= 30) {
      return _TimelineEntry(
        emoji: '🔔',
        title: 'Follow-up overdue',
        relativeDate: 'Today',
        category: 'NCD Follow-up',
        date: DateTime.now(),
        dotColor: _kDotPending,
        description: 'NCD follow-up due — last visit $daysSince days ago',
        isPending: true,
        programme: Programme.ncd,
      );
    }
  }

  return null;
}

/// Builds the full display timeline from [data.assessments] + rule-based entries.
/// Returns newest-first (pending entry at index 0, oldest at end).
List<_TimelineEntry> _buildTimelineEntries(PatientOrMemberData data) {
  final entries = <_TimelineEntry>[];

  for (final a in data.assessments) {
    entries.add(_assessmentToEntry(a));
  }

  return entries;
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

    // EDD/weeks-to-go shown in GestationalAgeCard above — omit here to avoid duplication.
    final visitNum = raw['ancVisitNumber'] as String?;
    if (visitNum != null && visitNum.isNotEmpty) stats[PatientProfileStrings.visitsCompleted] = visitNum;
    final ancBp = raw['bp'] as String?;
    if (ancBp != null && ancBp.isNotEmpty) stats['Last BP'] = '$ancBp mmHg';
    final hb = raw['hemoglobin'] as String?;
    if (hb != null && hb.isNotEmpty) stats['Haemoglobin'] = '$hb g/dL';
    final ancWeight = raw['weight'] as String?;
    if (ancWeight != null && ancWeight.isNotEmpty) stats['Weight'] = '$ancWeight kg';
    final g = raw['gravida'] as String?;
    final p = raw['parity'] as String?;
    if (g != null && g.isNotEmpty && p != null && p.isNotEmpty) stats['Gravida / Parity'] = 'G$g P$p';
    final ancTotal =
        data.assessments.where((a) => Programme.fromString(a.type) == Programme.anc).length;
    if (ancTotal > 0) stats['ANC visits'] = '$ancTotal';

    threads.add(_CareThread(
      programme: Programme.anc,
      label: CareThreadStrings.anc,
      icon: '🤰',
      bg: AppColors.ancSurface,
      textColor: AppColors.ancText,
      stats: stats,
      checkupDate: latest?.date,
    ));
  }

  // NCD — HTN + optional blood-sugar thread
  if (data.programmes.contains(Programme.ncd)) {
    final latest = latestOf(Programme.ncd);
    final raw = latest != null ? _normalizeRaw(latest.rawJson) : const <String, dynamic>{};
    final bp = raw['bp'] as String?;
    final dx = (raw['confirmDiagnosis'] as String?)?.trim();
    final ncdTotal = data.assessments.where((a) => Programme.fromString(a.type) == Programme.ncd).length;

    threads.add(_CareThread(
      programme: Programme.ncd,
      label: CareThreadStrings.htn,
      icon: '❤️',
      bg: AppColors.ncdSurface,
      textColor: AppColors.ncdText,
      stats: {
        if (bp != null && bp.isNotEmpty) 'Last BP': '$bp mmHg',
        if (ncdTotal > 0) 'NCD visits': '$ncdTotal',
        if (dx != null && dx.isNotEmpty) 'Diagnosis': dx,
      },
      checkupDate: latest?.date,
    ));

    final bg = raw['bg'] as String?;
    if (bg != null && bg.isNotEmpty) {
      final bgType = (raw['bgType'] as String?)?.trim();
      final bgLabel = (bgType != null && bgType.isNotEmpty) ? 'Blood sugar ($bgType)' : 'Blood sugar';
      threads.add(_CareThread(
        programme: Programme.ncd,
        label: CareThreadStrings.sugar,
        icon: '🩸',
        bg: AppColors.statusInfoSurface,
        textColor: AppColors.threadInfoText,
        stats: {bgLabel: '$bg mg/dL'},
      ));
    }
  }

  // PNC — postnatal recovery
  if (data.programmes.contains(Programme.pnc)) {
    final latest = latestOf(Programme.pnc);
    final raw = latest != null ? _normalizeRaw(latest.rawJson) : const <String, dynamic>{};
    final pncVisit = raw['pncVisitNumber'] as String?;
    final deliveryMode = raw['modeOfDelivery'] as String?;
    final complications = raw['anyComplicationsDuringDelivery'] as String?;
    final livingChildren = raw['numberOfLivingChildren'] as String?;
    threads.add(_CareThread(
      programme: Programme.pnc,
      label: CareThreadStrings.pnc,
      icon: '🤱',
      bg: AppColors.pncSurface,
      textColor: AppColors.pncText,
      stats: {
        if (pncVisit != null) 'PNC visits': pncVisit,
        if (deliveryMode != null) 'Delivery': deliveryMode,
        if (complications?.toLowerCase() == 'yes') 'Complications': 'Yes',
        if (livingChildren != null) 'Living children': livingChildren,
      },
      checkupDate: latest?.date,
    ));
  }

  // IMCI — immunization + growth monitoring
  if (data.programmes.contains(Programme.imci)) {
    final latest = latestOf(Programme.imci);
    final raw = latest != null ? _normalizeRaw(latest.rawJson) : const <String, dynamic>{};
    final weight = raw['weight'] as String?;
    final imciTotal = data.assessments.where((a) => Programme.fromString(a.type) == Programme.imci).length;
    threads.add(_CareThread(
      programme: Programme.imci,
      label: CareThreadStrings.imm,
      icon: '💉',
      bg: AppColors.threadImmBg,
      textColor: AppColors.tbText,
      stats: {
        if (weight != null) 'Last weight': '$weight kg',
        if (imciTotal > 0) 'IMCI visits': '$imciTotal',
      },
      checkupDate: latest?.date,
    ));
    threads.add(_CareThread(
      programme: Programme.imci,
      label: CareThreadStrings.growth,
      icon: '📈',
      bg: AppColors.pncSurface,
      textColor: AppColors.aiPurpleDark,
    ));
  }

  // TB — with latest assessment stats
  if (data.programmes.contains(Programme.tb)) {
    final latest = latestOf(Programme.tb);
    final raw = latest != null ? _normalizeRaw(latest.rawJson) : const <String, dynamic>{};
    final dx = (raw['confirmDiagnosis'] as String?)?.trim();
    final tbTotal =
        data.assessments.where((a) => Programme.fromString(a.type) == Programme.tb).length;
    threads.add(_CareThread(
      programme: Programme.tb,
      label: CareThreadStrings.general,
      icon: '🫁',
      bg: AppColors.tbSurface,
      textColor: AppColors.tbText,
      stats: {
        if (dx != null && dx.isNotEmpty) 'Diagnosis': dx,
        if (tbTotal > 0) 'TB visits': '$tbTotal',
      },
      checkupDate: latest?.date,
    ));
  }

  // Fallback when no programme is active
  if (threads.isEmpty) {
    threads.add(_CareThread(
      programme: Programme.unknown,
      label: CareThreadStrings.general,
      icon: '🏥',
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

/// Wrapping row of thread chips — one pill per active clinical pathway.
/// Display-only (not tappable).
class _CareThreadChipRow extends StatelessWidget {
  const _CareThreadChipRow({required this.threads});

  final List<_CareThread> threads;

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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: threads.map((t) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: t.textColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                t.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cardSurface,
                  letterSpacing: 0.6,
                  height: 1.2,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
    debugPrint('⏱ [PatientContext] _CareThreadChipRow build in ${sw.elapsedMilliseconds}ms'
        ' (${threads.length} chips)');
    return result;
  }
}

// ─── AI Insight Card ───────────────────────────────────────────────────────

/// Inline card showing the locally-computed patient AI summary. Content comes
/// from [PatientAiContext.summary] — no async call, always available offline.
/// Falls back to a muted unavailable message when the summary is empty.
class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({
    required this.summary,
    this.statusLabel,
    this.statusBg = Colors.transparent,
    this.statusFg = Colors.white,
    this.riskBand,
    this.riskModifier,
    this.riskReasons = const [],
    this.lastAssessedDate,
  });

  final String summary;
  final String? statusLabel;
  final Color statusBg;
  final Color statusFg;
  final Band? riskBand;
  final Modifier? riskModifier;
  final List<String> riskReasons;
  final DateTime? lastAssessedDate;

  static (String, Color, Color) _bandMeta(Band b) => switch (b) {
        Band.band1 => ('Band 1 — Severe risk', AppColors.statusCriticalSurface, AppColors.statusCriticalText),
        Band.band2 => ('Band 2 — Moderate risk', AppColors.statusWarningSurface, AppColors.statusWarningText),
        Band.band3 => ('Band 3 — Mild risk', const Color(0xFFEFF6FF), AppColors.navy),
        Band.band4 => ('Band 4 — Routine', const Color(0xFFF3F4F6), AppColors.textMuted),
      };

  void _showDetail(BuildContext context) {
    final isEmpty = summary.trim().isEmpty;
    final hasBand = riskBand != null && riskBand != Band.band4;

    _showCardDetail(
      context,
      title: PatientProfileStrings.aiInsight,
      icon: Icons.auto_awesome_rounded,
      iconColor: AppColors.aiPurpleDark,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Clinical priority block ───────────────────────────────────────
          if (hasBand) ...[
            const Text(
              'CLINICAL PRIORITY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Builder(builder: (ctx) {
              final (label, bg, fg) = _bandMeta(riskBand!);
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(label,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
                  ),
                  if (riskModifier != null && riskModifier != Modifier.none)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        riskModifier == Modifier.a
                            ? '+a  Additional clinical risk'
                            : '+b  Follow-up overdue',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMid),
                      ),
                    ),
                ],
              );
            }),
            if (riskReasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'WHY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              ...riskReasons.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6, right: 8),
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.textMid,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(r,
                              style: const TextStyle(
                                  fontSize: 13, height: 1.5, color: AppColors.textStrong)),
                        ),
                        if (lastAssessedDate != null) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              _relativeDate(lastAssessedDate!),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted, height: 1.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
          ],
          // ── AI summary ───────────────────────────────────────────────────
          Text(
            isEmpty ? PatientProfileStrings.aiInsightUnavailable : summary,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: isEmpty ? AppColors.textMuted : AppColors.textStrong,
              fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
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
                  if (statusLabel != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: statusFg,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.aiPurpleDark),
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
    this.gravida,
    this.parity,
  });

  final PregnancySnapshotRow snapshot;
  final String? ancVisitNumber;
  final String? gravida;
  final String? parity;

  // Bangladesh national ANC protocol: 4 focused visits
  static const _totalAncVisits = 4;

  // Trimester bar segment colors — visual rendering only
  static const _colorT1 = Color(0xFFBFB0F5); // lavender  (T1: 0–13 wks)
  static const _colorT2 = Color(0xFFF4B8C8); // pink/mauve (T2: 14–27 wks)
  static const _colorT3 = Color(0xFFFFD97D); // amber/gold  (T3: 28–40 wks)

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

    // Derive LMP from EDD (EDD − 280 days) when lmpDate is absent but eddDate is set.
    final effectiveLmp = lmpDate ?? (eddDate?.subtract(const Duration(days: 280)));
    final gaWeeks = effectiveLmp != null ? now.difference(effectiveLmp).inDays ~/ 7 : null;
    final weeksLeft = eddDate != null ? eddDate.difference(now).inDays ~/ 7 : null;
    final progress = gaWeeks != null ? (gaWeeks / 40.0).clamp(0.0, 1.0) : 0.0;
    final visitsDone = int.tryParse(ancVisitNumber ?? '0') ?? 0;

    final dateFormat = DateFormat('d MMM yyyy');

    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showCardDetail(
        context,
        title: PatientProfileStrings.pregnancyProgress,
        icon: Icons.favorite_border_rounded,
        iconColor: AppColors.ancText,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (effectiveLmp != null)
              _DetailRow(label: 'LMP', value: dateFormat.format(effectiveLmp)),
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "~X weeks to go" headline
            if (weeksLeft != null && weeksLeft > 0)
              Text(
                '~$weeksLeft ${PatientProfileStrings.weeksToGo}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            // Space for floating Wk pill above bar
            const SizedBox(height: 28),
            // Three-color trimester bar with floating week pill + tick
            LayoutBuilder(
              builder: (_, bc) {
                final tickX = (bc.maxWidth * progress).clamp(2.0, bc.maxWidth - 2.0);
                const pillW = 56.0;
                final pillLeft = (tickX - pillW / 2).clamp(0.0, bc.maxWidth - pillW);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Segmented bar — explicit width so Expanded children get bounded width
                    SizedBox(
                      width: bc.maxWidth,
                      height: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          children: [
                            // T1: 0–13 wks (13/40)
                            Expanded(flex: 13, child: Container(color: _colorT1)),
                            // T2: 14–27 wks (14/40)
                            Expanded(flex: 14, child: Container(color: _colorT2)),
                            // T3: 28–40 wks (13/40)
                            Expanded(flex: 13, child: Container(color: _colorT3)),
                          ],
                        ),
                      ),
                    ),
                    // Vertical tick at current week
                    Positioned(
                      left: tickX - 1,
                      top: -4,
                      child: Container(
                        width: 2,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                    // Floating "Wk X" pill above bar
                    if (gaWeeks != null)
                      Positioned(
                        left: pillLeft,
                        top: -28,
                        child: Container(
                          width: pillW,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Wk $gaWeeks',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textOnNavy,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // LMP (left) / EDD (right) label+date pairs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (effectiveLmp != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LMP',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFormat.format(effectiveLmp),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
                if (eddDate != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'EDD',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFormat.format(eddDate),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    debugPrint('⏱ [PatientContext] _PregnancyProgressSection build in ${sw.elapsedMilliseconds}ms'
        ' gaWeeks=$gaWeeks weeksLeft=$weeksLeft visitsDone=$visitsDone');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PREGNANCY SNAPSHOT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        card,
      ],
    );
  }
}


// ─── Stats Grid ────────────────────────────────────────────────────────────

/// 2-column grid of clinical stat tiles for the currently selected care thread.
/// Used by NCD (BP, blood sugar), IMCI (doses, weight), and PNC (visit, delivery).
/// Shows [noDataLabel] when [stats] is empty.
/// "AT A GLANCE" section — 2-column grid of neutral stat cards.
/// Collects stats from ALL active threads so clinicians see the full snapshot
/// without having to switch thread chips.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.threads,
    required this.assessments,
    required this.noDataLabel,
  });

  final List<_CareThread> threads;
  final List<MemberAssessment> assessments;
  final String noDataLabel;

  static (IconData, Color) _iconFor(String label) {
    if (label.startsWith('Blood sugar')) {
      return (Icons.bloodtype_outlined, const Color(0xFFE65100));
    }
    return switch (label) {
      'Last BP'               => (Icons.favorite_rounded,                const Color(0xFFD32F2F)),
      'Haemoglobin'           => (Icons.water_drop_rounded,              const Color(0xFFD32F2F)),
      'Weight' || 'Last weight' => (Icons.monitor_weight_outlined,       const Color(0xFF1565C0)),
      'Visits completed'      => (Icons.assignment_turned_in_outlined,   const Color(0xFF2E7D32)),
      'Visits'                => (Icons.event_note_outlined,             AppColors.navy),
      'ANC visits'            => (Icons.pregnant_woman_outlined,         const Color(0xFF7B1FA2)),
      'Diagnosis'             => (Icons.local_hospital_outlined,         const Color(0xFF7B1FA2)),
      'Delivery'              => (Icons.child_care_outlined,             const Color(0xFFAD1457)),
      'PNC visits'            => (Icons.baby_changing_station_outlined,  const Color(0xFF00695C)),
      'Living children'       => (Icons.people_outline_rounded,          const Color(0xFF2E7D32)),
      'Gravida / Parity'      => (Icons.pregnant_woman_outlined,         const Color(0xFF7B1FA2)),
      _                       => (Icons.bar_chart_rounded,               AppColors.navy),
    };
  }

  // Maps a stat label to the rawJson field name + display unit.
  static const Map<String, (String field, String suffix)> _fieldMap = {
    'Last BP': ('bp', ' mmHg'),
    'Haemoglobin': ('hemoglobin', ' g/dL'),
    'Weight': ('weight', ' kg'),
    'Last weight': ('weight', ' kg'),
    'Diagnosis': ('confirmDiagnosis', ''),
    'Delivery': ('modeOfDelivery', ''),
    'PNC visits': ('pncVisitNumber', ''),
    'Living children': ('numberOfLivingChildren', ''),
    'Visits completed': ('ancVisitNumber', ''),
    'Gravida / Parity': ('_gravida_parity', ''),
  };

  List<(DateTime date, String display, MemberAssessment assessment)> _extractHistory(
      String label) {
    final fieldEntry = label.startsWith('Blood sugar')
        ? ('bg', ' mg/dL')
        : _fieldMap[label];
    if (fieldEntry == null) return const [];

    final (field, suffix) = fieldEntry;
    final result = <(DateTime, String, MemberAssessment)>[];

    for (final a in assessments) {
      final raw = _normalizeRaw(a.rawJson);
      if (field == '_gravida_parity') {
        final g = raw['gravida'] as String?;
        final p = raw['parity'] as String?;
        if (g != null && p != null && g.isNotEmpty && p.isNotEmpty) {
          result.add((a.date, 'G$g P$p', a));
        }
      } else {
        final v = raw[field] as String?;
        if (v != null && v.isNotEmpty) {
          result.add((a.date, '$v$suffix', a));
        }
      }
    }
    return result;
  }

  List<(DateTime date, String display, MemberAssessment assessment)>
      _extractVisitHistory(List<MapEntry<String, String>> visitEntries) {
    final progNames = visitEntries
        .map((e) => e.key.replaceAll(' visits', '').toLowerCase())
        .toSet();
    final entries = <(DateTime, String, MemberAssessment)>[];
    for (final a in assessments) {
      final progName = Programme.fromString(a.type).name.toLowerCase();
      if (progNames.contains(progName)) {
        final raw = _normalizeRaw(a.rawJson);
        final visitNum =
            raw['ancVisitNumber'] as String? ?? raw['pncVisitNumber'] as String?;
        final progLabel = a.type.toUpperCase();
        final suffix = visitNum != null ? '  #$visitNum' : '';
        entries.add((a.date, '$progLabel$suffix', a));
      }
    }
    return entries;
  }

  void _showStatHistory(
    BuildContext context,
    String label,
    List<(DateTime date, String display, MemberAssessment assessment)> history,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${history.length} record${history.length == 1 ? '' : 's'}  ·  tap to open visit',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                itemCount: history.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 48),
                itemBuilder: (_, i) {
                  final (date, display, assessment) = history[i];
                  final rel = _relativeDate(date);
                  final full =
                      '${date.day} ${_monthAbbr(date.month)} ${date.year}';
                  final prog = Programme.fromString(assessment.type);
                  final (progBg, progFg) = _progBadgeColors(prog);
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _TimelineEventSheet.show(sheetCtx, assessment),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(full,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: progBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        assessment.type.toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: progFg,
                                            letterSpacing: 0.4),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(display,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.navy,
                                    )),
                              ],
                            ),
                          ),
                          Text(rel,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded,
                              size: 18, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckupHistory(BuildContext context) {
    final withDates = threads.where((t) => t.checkupDate != null).toList()
      ..sort((a, b) => b.checkupDate!.compareTo(a.checkupDate!));
    if (withDates.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, ctrl) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: const Text(
                'Check-up history',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                itemCount: withDates.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 48),
                itemBuilder: (_, i) {
                  final t = withDates[i];
                  final rel = _relativeDate(t.checkupDate!);
                  final fullDate =
                      '${t.checkupDate!.day} ${_monthAbbr(t.checkupDate!.month)} ${t.checkupDate!.year}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: t.bg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child:
                              Text(t.icon, style: const TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.label,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textStrong)),
                              Text(fullDate,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Text(rel,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.navy)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();
    final raw = <MapEntry<String, String>>[];
    for (final t in threads) {
      raw.addAll(t.stats.entries);
    }

    // Derive single last-check-up entry from threads (newest across all programmes).
    final threadsWithDate = threads.where((t) => t.checkupDate != null).toList()
      ..sort((a, b) => b.checkupDate!.compareTo(a.checkupDate!));
    final latestThread = threadsWithDate.isNotEmpty ? threadsWithDate.first : null;

    // Merge all "* visits" keys into one combined tile.
    final visitEntries = raw.where((e) => e.key.endsWith(' visits')).toList();
    final displayStats = raw.where((e) => !e.key.endsWith(' visits')).toList();
    if (visitEntries.isNotEmpty) {
      final combinedValue = visitEntries.map((e) {
        final prog = e.key.replaceAll(' visits', '');
        return '$prog  ${e.value}';
      }).join('\n');
      displayStats.add(MapEntry('Visits', combinedValue));
    }

    final hasStats = displayStats.isNotEmpty || latestThread != null;
    if (!hasStats) {
      debugPrint('⏱ [PatientContext] _StatsGrid 0ms (no stats)');
      return const SizedBox.shrink();
    }

    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AT A GLANCE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Builder(builder: (context) {
          final tiles = <Widget>[];
          for (final e in displayStats) {
            final (icon, iconColor) = _iconFor(e.key);
            if (e.key == 'Visits') {
              final hist = _extractVisitHistory(visitEntries);
              tiles.add(GestureDetector(
                onTap: hist.isNotEmpty
                    ? () => _showStatHistory(context, 'Visit history', hist)
                    : null,
                child: _StatTile(
                  label: e.key,
                  value: e.value,
                  icon: icon,
                  iconColor: iconColor,
                  hasHistory: hist.isNotEmpty,
                ),
              ));
            } else {
              final hist = _extractHistory(e.key);
              tiles.add(GestureDetector(
                onTap: hist.isNotEmpty
                    ? () => _showStatHistory(context, e.key, hist)
                    : null,
                child: _StatTile(
                  label: e.key,
                  value: e.value,
                  icon: icon,
                  iconColor: iconColor,
                  hasHistory: hist.isNotEmpty,
                ),
              ));
            }
          }
          if (latestThread != null) {
            tiles.add(GestureDetector(
              onTap: () => _showCheckupHistory(context),
              child: _LastCheckupTile(
                thread: latestThread,
                hasHistory: threadsWithDate.length > 1,
              ),
            ));
          }
          return Column(
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                tiles[i],
              ],
            ],
          );
        }),
      ],
    );
    debugPrint('⏱ [PatientContext] _StatsGrid ${sw.elapsedMilliseconds}ms stats=${displayStats.length}');
    return result;
  }
}

/// Full-width stat row: colored icon + label + large value.
/// Icon conveys meaning for low-literacy users without reading the label.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.hasHistory = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: value.contains('\n') ? 14 : 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    height: value.contains('\n') ? 1.5 : 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (hasHistory)
            const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// Tappable last-check-up row — programme emoji icon + relative date.
class _LastCheckupTile extends StatelessWidget {
  const _LastCheckupTile({required this.thread, required this.hasHistory});

  final _CareThread thread;
  final bool hasHistory;

  @override
  Widget build(BuildContext context) {
    final rel = _relativeDate(thread.checkupDate!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: thread.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(thread.icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last check-up',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  rel,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    height: 1.2,
                  ),
                ),
                Text(
                  thread.label,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (hasHistory)
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

/// Returns (background, foreground) colors for a programme badge pill.
(Color, Color) _progBadgeColors(Programme prog) => switch (prog) {
      Programme.anc => (AppColors.ancSurface, AppColors.ancText),
      Programme.ncd => (AppColors.ncdSurface, AppColors.ncdText),
      Programme.pnc => (AppColors.pncSurface, AppColors.pncText),
      Programme.tb => (AppColors.tbSurface, AppColors.tbText),
      Programme.imci => (AppColors.threadImmBg, AppColors.tbText),
      _ => (const Color(0xFFF3F4F6), AppColors.textMid),
    };

String _monthAbbr(int month) => const [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][month];

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

// ─── BP / BG Trend Charts ──────────────────────────────────────────────────

/// One data point for a trend chart: a visit's reading + tap target.
class _TrendPoint {
  const _TrendPoint({
    required this.date,
    required this.displayLabel,
    required this.primaryVal,
    this.secondaryVal,
    this.assessment,
  });

  final DateTime date;
  final String displayLabel;
  final double primaryVal;
  final double? secondaryVal;
  final MemberAssessment? assessment;
}

/// Two stacked expandable trend cards (BP + BG).
/// Each card collapses to sparkline + latest value + date.
/// Expanded state shows history list; each row taps to full assessment sheet.
class _BpBgTrendSection extends StatelessWidget {
  const _BpBgTrendSection({
    required this.vitalHistory,
    required this.assessments,
    required this.patientId,
    this.patientName,
  });

  final List<VisitVitals> vitalHistory;
  final List<MemberAssessment> assessments;
  final String patientId;
  final String? patientName;

  List<_TrendPoint> _buildBpPoints() {
    return vitalHistory
        .where((v) => v.readings.any((r) =>
            r.type == VitalType.bloodPressure &&
            r.systolic != null &&
            r.diastolic != null))
        .take(6)
        .toList()
        .reversed
        .map((v) {
          final r = v.readings.firstWhere((r) => r.type == VitalType.bloodPressure);
          return _TrendPoint(
            date: v.date,
            displayLabel: '${r.systolic!.toInt()}/${r.diastolic!.toInt()} mmHg',
            primaryVal: r.systolic!,
            secondaryVal: r.diastolic,
            assessment: assessments.where((a) => a.id == v.encounterId).firstOrNull,
          );
        })
        .toList();
  }

  List<_TrendPoint> _buildBgPoints() {
    return vitalHistory
        .where((v) =>
            v.readings.any((r) => r.type == VitalType.glucose && r.value != null))
        .take(6)
        .toList()
        .reversed
        .map((v) {
          final r = v.readings.firstWhere((r) => r.type == VitalType.glucose);
          return _TrendPoint(
            date: v.date,
            displayLabel: '${r.value!.toStringAsFixed(1)} mg/dL',
            primaryVal: r.value!,
            assessment: assessments.where((a) => a.id == v.encounterId).firstOrNull,
          );
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bpPoints = _buildBpPoints();
    final bgPoints = _buildBgPoints();
    if (bpPoints.isEmpty && bgPoints.isEmpty) return const SizedBox.shrink();

    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PatientProfileStrings.trendsTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: lc.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (bpPoints.isNotEmpty)
          _VitalTrendCard(
            title: PatientProfileStrings.bpChartLabel,
            points: bpPoints,
            isBp: true,
            onAssessmentTap: (ctx, a) => _TimelineEventSheet.show(ctx, a),
          ),
        if (bpPoints.isNotEmpty && bgPoints.isNotEmpty) const SizedBox(height: 8),
        if (bgPoints.isNotEmpty)
          _VitalTrendCard(
            title: PatientProfileStrings.bgChartLabel,
            points: bgPoints,
            isBp: false,
            onAssessmentTap: (ctx, a) => _TimelineEventSheet.show(ctx, a),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => context.push(
              '/patients/$patientId/trends',
              extra: <String, dynamic>{
                'patientName': patientName,
                'vitalHistory': vitalHistory,
                'assessments': assessments,
              },
            ),
            icon: const Icon(Icons.trending_up, size: 16),
            label: Text(PatientProfileStrings.viewAllTrends),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ),
      ],
    );
  }
}

class _VitalTrendCard extends StatefulWidget {
  const _VitalTrendCard({
    required this.title,
    required this.points,
    required this.isBp,
    this.lineColor = AppColors.statusWarning,
    this.onAssessmentTap,
  });

  final String title;
  final List<_TrendPoint> points; // oldest-first
  final bool isBp;
  final Color lineColor;
  final void Function(BuildContext context, MemberAssessment assessment)? onAssessmentTap;

  @override
  State<_VitalTrendCard> createState() => _VitalTrendCardState();
}

class _VitalTrendCardState extends State<_VitalTrendCard> {
  bool _expanded = false;

  List<VitalReading> get _readingsForChart => widget.points
      .map((p) => VitalReading(
            type: widget.isBp ? VitalType.bloodPressure : VitalType.glucose,
            date: p.date,
            systolic: p.primaryVal,
            diastolic: p.secondaryVal,
            value: widget.isBp ? null : p.primaryVal,
            unit: widget.isBp ? 'mmHg' : 'mg/dL',
          ))
      .toList();

  // Delta = latest primaryVal minus previous primaryVal. Null if < 2 points.
  double? get _delta {
    if (widget.points.length < 2) return null;
    return widget.points.last.primaryVal -
        widget.points[widget.points.length - 2].primaryVal;
  }

  Widget _deltaChip(double delta, LeapfrogColors lc) {
    final isUp = delta > 0;
    final color = isUp ? AppColors.statusSuccess : AppColors.statusCritical;
    final prefix = isUp ? '+' : '';
    final label = widget.isBp
        ? '$prefix${delta.round()}'
        : '$prefix${delta.toStringAsFixed(1)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          color: color,
          size: 12,
        ),
        const SizedBox(width: 1),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    final latest = widget.points.last;
    final dateLabel = DateFormat('d MMM').format(latest.date);
    final delta = _delta;

    return Container(
      decoration: BoxDecoration(
        color: lc.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: lc.borderDefault),
      ),
      child: Column(
        children: [
          // ── Collapsed header ────────────────────────────────────
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    height: 62,
                    child: CustomPaint(
                      painter: widget.isBp
                          ? _BpSparklinePainter(readings: _readingsForChart, lc: lc)
                          : _SingleLinePainter(readings: _readingsForChart, lc: lc, color: widget.lineColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: lc.textMuted,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                latest.displayLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: lc.textPrimary,
                                ),
                              ),
                            ),
                            if (delta != null && delta != 0) ...[
                              const SizedBox(width: 5),
                              _deltaChip(delta, lc),
                            ],
                          ],
                        ),
                        Text(
                          dateLabel,
                          style: TextStyle(fontSize: 11, color: lc.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: lc.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // ── Expanded history list ───────────────────────────────
          if (_expanded) ...[
            Divider(height: 1, thickness: 1, color: lc.borderDefault),
            // Newest first in list
            ...widget.points.reversed.map((pt) => _TrendHistoryRow(
                  point: pt,
                  lc: lc,
                  onTap: pt.assessment != null
                      ? () => widget.onAssessmentTap?.call(context, pt.assessment!)
                      : null,
                )),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _TrendHistoryRow extends StatelessWidget {
  const _TrendHistoryRow({required this.point, required this.lc, this.onTap});

  final _TrendPoint point;
  final LeapfrogColors lc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Text(
              DateFormat('d MMM yyyy').format(point.date),
              style: TextStyle(
                fontSize: 12,
                color: lc.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              point.displayLabel,
              style: TextStyle(
                fontSize: 13,
                color: lc.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: lc.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

/// Paints systolic (solid navy) + diastolic (lighter blue) lines with a
/// semi-transparent fill between them.
class _BpSparklinePainter extends CustomPainter {
  const _BpSparklinePainter({required this.readings, required this.lc});

  final List<VitalReading> readings;
  final LeapfrogColors lc;

  static const double _kDateLabelH = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chartH = size.height - _kDateLabelH;
    if (readings.length < 2) {
      _dotAt(canvas, size.width / 2, chartH / 2, AppColors.navy, 4);
      _drawDateLabels(canvas, size, readings);
      return;
    }

    final sys = readings.map((r) => r.systolic!).toList();
    final dia = readings.map((r) => r.diastolic!).toList();

    final allVals = [...sys, ...dia];
    final minVal = allVals.reduce((a, b) => a < b ? a : b) - 10;
    final maxVal = allVals.reduce((a, b) => a > b ? a : b) + 10;
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    double xAt(int i) => i / (readings.length - 1) * size.width;
    double yAt(double v) => chartH - ((v - minVal) / range) * chartH;

    final sysPath = Path()..moveTo(xAt(0), yAt(sys[0]));
    for (int i = 1; i < sys.length; i++) {
      sysPath.lineTo(xAt(i), yAt(sys[i]));
    }

    final diaPath = Path()..moveTo(xAt(0), yAt(dia[0]));
    for (int i = 1; i < dia.length; i++) {
      diaPath.lineTo(xAt(i), yAt(dia[i]));
    }

    // Fill between sys and dia
    final fillPath = Path()..moveTo(xAt(0), yAt(sys[0]));
    for (int i = 1; i < sys.length; i++) {
      fillPath.lineTo(xAt(i), yAt(sys[i]));
    }
    for (int i = readings.length - 1; i >= 0; i--) {
      fillPath.lineTo(xAt(i), yAt(dia[i]));
    }
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()..color = AppColors.navy.withValues(alpha: 0.10),
    );

    final sysPaint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final diaPaint = Paint()
      ..color = AppColors.navy.withValues(alpha: 0.50)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(sysPath, sysPaint);
    canvas.drawPath(diaPath, diaPaint);

    // Data point dots at every reading
    for (int i = 0; i < readings.length; i++) {
      _dotAt(canvas, xAt(i), yAt(sys[i]), AppColors.navy,
          i == sys.length - 1 ? 3.5 : 2.5);
      _dotAt(canvas, xAt(i), yAt(dia[i]),
          AppColors.navy.withValues(alpha: 0.60), i == dia.length - 1 ? 3.0 : 2.0);
    }

    _drawDateLabels(canvas, size, readings);
  }

  void _drawDateLabels(Canvas canvas, Size size, List<VitalReading> r) {
    if (r.isEmpty) return;
    final labelY = size.height - _kDateLabelH + 2;
    final fmt = DateFormat('d MMM');
    _paintLabel(canvas, fmt.format(r.first.date), 0, labelY, align: TextAlign.left);
    if (r.length > 1) {
      _paintLabel(canvas, fmt.format(r.last.date), size.width, labelY,
          align: TextAlign.right);
    }
  }

  void _paintLabel(Canvas canvas, String text, double x, double y,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 8.5,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: 36);
    final dx = align == TextAlign.right ? x - tp.width : x;
    tp.paint(canvas, Offset(dx, y));
  }

  void _dotAt(Canvas canvas, double x, double y, Color color, double r) {
    canvas.drawCircle(Offset(x, y), r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BpSparklinePainter old) => old.readings != readings;
}

/// Generic single-line sparkline with area fill below. Color-parameterised.
class _SingleLinePainter extends CustomPainter {
  const _SingleLinePainter({
    required this.readings,
    required this.lc,
    this.color = AppColors.statusWarning,
  });

  final List<VitalReading> readings;
  final LeapfrogColors lc;
  final Color color;

  static const double _kDateLabelH = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final chartH = size.height - _kDateLabelH;
    if (readings.isEmpty) return;
    if (readings.length < 2) {
      canvas.drawCircle(Offset(size.width / 2, chartH / 2), 4, Paint()..color = color);
      _drawDateLabels(canvas, size, readings);
      return;
    }

    final vals = readings.map((r) => r.value!).toList();
    final minVal = (vals.reduce((a, b) => a < b ? a : b) - 10).clamp(0.0, double.infinity);
    final maxVal = vals.reduce((a, b) => a > b ? a : b) + 10;
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    double xAt(int i) => i / (readings.length - 1) * size.width;
    double yAt(double v) => chartH - ((v - minVal) / range) * chartH;

    final line = Path()..moveTo(xAt(0), yAt(vals[0]));
    for (int i = 1; i < vals.length; i++) {
      line.lineTo(xAt(i), yAt(vals[i]));
    }

    final fill = Path()
      ..moveTo(xAt(0), chartH)
      ..lineTo(xAt(0), yAt(vals[0]));
    for (int i = 1; i < vals.length; i++) {
      fill.lineTo(xAt(i), yAt(vals[i]));
    }
    fill.lineTo(xAt(vals.length - 1), chartH);
    fill.close();

    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Data point dots at every reading
    for (int i = 0; i < vals.length; i++) {
      canvas.drawCircle(
        Offset(xAt(i), yAt(vals[i])),
        i == vals.length - 1 ? 3.5 : 2.5,
        Paint()..color = color,
      );
    }

    _drawDateLabels(canvas, size, readings);
  }

  void _drawDateLabels(Canvas canvas, Size size, List<VitalReading> r) {
    if (r.isEmpty) return;
    final labelY = size.height - _kDateLabelH + 2;
    final fmt = DateFormat('d MMM');
    _paintLabel(canvas, fmt.format(r.first.date), 0, labelY, align: TextAlign.left);
    if (r.length > 1) {
      _paintLabel(canvas, fmt.format(r.last.date), size.width, labelY,
          align: TextAlign.right);
    }
  }

  void _paintLabel(Canvas canvas, String text, double x, double y,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 8.5,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: 36);
    final dx = align == TextAlign.right ? x - tp.width : x;
    tp.paint(canvas, Offset(dx, y));
  }

  @override
  bool shouldRepaint(_SingleLinePainter old) => old.readings != readings || old.color != color;
}

// ─── Combined Timeline ─────────────────────────────────────────────────────

// _BpLineChart removed
/// [entries] are newest-first (pending at top, oldest at bottom).
class _CombinedTimeline extends StatefulWidget {
  const _CombinedTimeline({
    required this.entries,
    required this.isLoading,
  });

  final List<_TimelineEntry> entries;
  final bool isLoading;

  @override
  State<_CombinedTimeline> createState() => _CombinedTimelineState();
}

class _CombinedTimelineState extends State<_CombinedTimeline> {
  static const _kInitialCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sw = Stopwatch()..start();

    late final Widget body;
    if (widget.entries.isEmpty && widget.isLoading) {
      body = const _TimelineShimmer();
    } else if (widget.entries.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          PatientProfileStrings.noVitalsYet,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontStyle: FontStyle.italic),
        ),
      );
    } else {
      final hasMore = widget.entries.length > _kInitialCount;
      final visible = (_expanded || !hasMore)
          ? widget.entries
          : widget.entries.take(_kInitialCount).toList();
      final entryRows = <Widget>[];
      for (int i = 0; i < visible.length; i++) {
        entryRows.add(_TimelineEntryRow(
          entry: visible[i],
          isLast: i == visible.length - 1 && (!hasMore || _expanded),
        ));
      }
      Widget? showMoreBtn;
      if (hasMore) {
        final remaining = widget.entries.length - _kInitialCount;
        showMoreBtn = Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16),
            label: Text(_expanded
                ? PatientProfileStrings.showLess
                : PatientProfileStrings.showMoreEntries(remaining)),
            style: TextButton.styleFrom(
              foregroundColor: _expanded ? AppColors.textMuted : AppColors.aiPurple,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        );
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 1))],
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: entryRows),
          ),
          if (showMoreBtn != null) showMoreBtn,
        ],
      );
    }

    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CARE HISTORY',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
    debugPrint('⏱ [PatientContext] _CombinedTimeline build in ${sw.elapsedMilliseconds}ms'
        ' total=${widget.entries.length} loading=${widget.isLoading}');
    return result;
  }
}


/// Single row in the combined timeline — solid colour dot + connector + flat content.
class _TimelineEntryRow extends StatelessWidget {
  const _TimelineEntryRow({required this.entry, required this.isLast});

  final _TimelineEntry entry;
  final bool isLast;

  static const _dotSize = 24.0;
  static const _lineWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Solid dot + vertical connector
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    color: entry.dotColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(entry.emoji, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: _lineWidth,
                        color: const Color(0xFFE5E7EB),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14, top: 6),
              child: _TimelineEntryCard(entry: entry),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat content block for a single [_TimelineEntry]: title + date + badge + narrative.
/// No card border — text sits directly to the right of the dot.
class _TimelineEntryCard extends StatelessWidget {
  const _TimelineEntryCard({required this.entry});

  final _TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final isPending = entry.isPending;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: entry.source != null
          ? () => _TimelineEventSheet.show(context, entry.source!)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title · badge (inline) + relative date
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        entry.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: isPending ? AppColors.statusWarningDark : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (entry.badge != null) ...[
                      const SizedBox(width: 5),
                      _TimelineBadge(
                        label: entry.badge!,
                        bg: entry.badgeColor ?? _kBadgeGrayBg,
                        fg: entry.badgeFgColor ?? _kBadgeGrayFg,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.relativeDate,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          // Clinical narrative
          if (entry.description != null && entry.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.description!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textMid,
              ),
            ),
          ],
          if (entry.source != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: AppColors.textMuted.withValues(alpha: 0.45),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small coloured pill badge — risk level, delivery mode, illness type.
class _TimelineBadge extends StatelessWidget {
  const _TimelineBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
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
    // ── Vitals (all programmes) ────────────────────────────────────────────
    addIfPresent('bp', 'BP');
    addIfPresent('bg', 'Blood glucose');
    addIfPresent('bgType', 'Glucose type');
    addIfPresent('bmi', 'BMI');
    addIfPresent('cvdRisk', 'CVD risk');
    addIfPresent('weight', 'Weight (kg)');
    addIfPresent('height', 'Height (cm)');

    // ── NCD ────────────────────────────────────────────────────────────────
    addIfPresent('confirmDiagnosis', 'Diagnosis');
    addIfPresent('ncdSymptoms', 'Symptoms');
    addIfPresent('ncdSymptomsMedication', 'Taking medication');
    addIfPresent('heartAttack', 'Heart attack history');
    addIfPresent('stroke', 'Stroke history');
    addIfPresent('kidneyDisease', 'Kidney disease');
    addIfPresent('copd', 'COPD');
    addIfPresent('referralFacilityType', 'Referred to');

    // ── ANC ────────────────────────────────────────────────────────────────
    addIfPresent('hemoglobin', 'Hb (g/dL)');
    addIfPresent('fundalHeight', 'Fundal height (cm)');
    addIfPresent('gravida', 'Gravida');
    addIfPresent('parity', 'Parity');
    addIfPresent('ancVisitNumber', 'ANC visit no.');
    addIfPresent('highRiskPregnantWoman', 'High risk');
    addIfPresent('gapsInAnc', 'ANC gaps');
    addIfPresent('dangerSignsDuringPregnancy', 'Danger signs');
    addIfPresent('referralFacility', 'Referred to');
    addIfPresent('followUpVisit', 'Follow-up visit');

    // ── PNC ────────────────────────────────────────────────────────────────
    addIfPresent('pncVisitNumber', 'PNC visit no.');
    addIfPresent('modeOfDelivery', 'Mode of delivery');
    addIfPresent('anyComplicationsDuringDelivery', 'Complications');
    addIfPresent('complicationsDuringDelivery', 'Complication details');
    addIfPresent('numberOfLivingChildren', 'Living children');
    addIfPresent('motherCare', 'Postnatal care');
    addIfPresent('newbornCare', 'Newborn care');

    // ── TB ─────────────────────────────────────────────────────────────────
    addIfPresent('has_cough', 'Cough');
    addIfPresent('had_tb_before', 'Cough >2 weeks');
    addIfPresent('has_night_sweats', 'Night sweats');
    addIfPresent('has_fever', 'Fever');
    addIfPresent('has_weight_loss', 'Weight loss');

    // ── IMCI / childhood ──────────────────────────────────────────────────
    addIfPresent('anyIllness', 'Illness/complication');
    addIfPresent('childIllnessType', 'Complication type');
    addIfPresent('receivedVaccine', 'Vaccines received');
    addIfPresent('childBreastFeeding', 'Breastfeeding');
    addIfPresent('dewormingMedicine', 'Deworming');
    addIfPresent('childReferral', 'Referral made');
    addIfPresent('childReferralFacilityType', 'Refer to');

    // ── Eye care / cataract ───────────────────────────────────────────────
    addIfPresent('eyeTestOutcome', 'Eye test outcome');
    addIfPresent('eyeDisease', 'Eye disease');
    addIfPresent('glassPower', 'Glass power');
    addIfPresent('haveTheGlassesBeenSold', 'Glasses sold');
    addIfPresent('typeOfGlass', 'Glass type');
    addIfPresent('typeOfFrame', 'Frame type');
    addIfPresent('firstTimeUser', 'First time user');
    addIfPresent('referPlace', 'Refer to');
    addIfPresent('patientReferredForOperation', 'Referred for operation');
    addIfPresent('operationName', 'Operation');
    addIfPresent('pseudophakiaPostCataractSurgery', 'Post-surgery status');
    addIfPresent('ncdServiceProvided', 'NCD service provided');

    // ── FP ─────────────────────────────────────────────────────────────────
    addIfPresent('familyPlanningMethods', 'FP method');
    addIfPresent('desireForChildrenInFuture', 'Desire for children');

    // ── Referral (all programmes) ─────────────────────────────────────────
    addIfPresent('referralStatus', 'Referral status');
    // Humanize referral reason codes (camelCase backend tokens → readable labels)
    final reasonRaw = (raw['referralReason']?.toString() ??
        raw['referredReasons']?.toString() ??
        assessment.notes ?? '').trim();
    if (reasonRaw.isNotEmpty) {
      final humanized = reasonRaw
          .split(',')
          .map((r) => _shortReasonLabel(r.trim()))
          .where((r) => r.isNotEmpty)
          .join(', ');
      entries.add(MapEntry('Referral reason', humanized));
    }

    // ── customStatus — only if distinct from referralStatus (avoid duplicate) ──
    final cs = raw['customStatus'];
    if (cs is List && cs.isNotEmpty) {
      final joined = cs.map((e) => e.toString()).join(', ');
      final refStatus = (raw['referralStatus']?.toString() ?? assessment.status ?? '').toLowerCase();
      if (joined.isNotEmpty && joined.toLowerCase() != refStatus) {
        entries.add(MapEntry('Status', joined));
      }
    }

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
    debugPrint('[_PatientProfileCardState] _openContact');
    if (!mounted) return;
    await showContactSheet(context, widget.data);
  }

  Future<void> _openMaps(String place) async {
    debugPrint('[_PatientProfileCardState] _openMaps place=${place}');
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(place.trim())}');
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
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
    required this.refreshing,
    required this.onBack,
    required this.onRefresh,
  });

  final PatientOrMemberData data;
  final bool refreshing;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final name = data.name ?? PatientContextStrings.fallbackTitle;

    final ageLabel = _ageLabelFromDob(data.dateOfBirth, data.age);
    final genderInitial = data.gender != null && data.gender!.isNotEmpty
        ? data.gender![0].toUpperCase()
        : null;
    final ageSuffix = ageLabel != null && genderInitial != null
        ? '$ageLabel/$genderInitial'
        : ageLabel ?? genderInitial;
    final displayName = ageSuffix != null ? '$name $ageSuffix' : name;
    final subtitle = data.householdId != null
        ? (data.householdName ??
            PatientContextStrings.householdFallback(data.householdId!))
        : null;

    final chips = <_HeaderChip>[
      if (data.nationalId != null)
        _HeaderChip(Icons.badge_outlined, data.nationalId!),
      if (data.phoneNumber != null || data.householdHeadPhone != null)
        _HeaderChip(Icons.phone_outlined, data.phoneNumber ?? data.householdHeadPhone!,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
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
              const SizedBox(width: 8),
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
          SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(PatientProfileStrings.mapsOpenFailed)),
        );
      }
    }
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
                          context.push('/patients/$navId');
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
                label: Text(
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

// ─── Trends Screen ─────────────────────────────────────────────────────────

/// Full-page trend viewer: BP, BG, Weight, SpO2, Haemoglobin (ANC), Temperature.
/// Data passed via GoRouter extra from PatientContextScreen to avoid reload.
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({
    super.key,
    required this.patientId,
    required this.vitalHistory,
    required this.assessments,
    this.patientName,
  });

  final String patientId;
  final List<VisitVitals> vitalHistory;
  final List<MemberAssessment> assessments;
  final String? patientName;

  static const _lightStatusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  List<_TrendPoint> _pointsForType(VitalType type) {
    return vitalHistory
        .where((v) => v.readings.any((r) => r.type == type && _hasValue(r, type)))
        .take(10)
        .toList()
        .reversed
        .map((v) {
          final r = v.readings.firstWhere((r) => r.type == type);
          final match = assessments.where((a) => a.id == v.encounterId).firstOrNull;
          return _TrendPoint(
            date: v.date,
            displayLabel: _formatReading(r, type),
            primaryVal: type == VitalType.bloodPressure ? r.systolic! : r.value!,
            secondaryVal: type == VitalType.bloodPressure ? r.diastolic : null,
            assessment: match,
          );
        })
        .toList();
  }

  bool _hasValue(VitalReading r, VitalType type) {
    if (type == VitalType.bloodPressure) return r.systolic != null && r.diastolic != null;
    return r.value != null;
  }

  String _formatReading(VitalReading r, VitalType type) {
    switch (type) {
      case VitalType.bloodPressure:
        return '${r.systolic!.toInt()}/${r.diastolic!.toInt()} mmHg';
      case VitalType.glucose:
        return '${r.value!.toStringAsFixed(1)} mg/dL';
      case VitalType.weight:
        return '${r.value!.toStringAsFixed(1)} kg';
      case VitalType.spO2:
        return '${r.value!.toStringAsFixed(0)}%';
      case VitalType.temperature:
        return '${r.value!.toStringAsFixed(1)}°C';
      default:
        return r.value!.toStringAsFixed(1);
    }
  }

  List<_TrendPoint> _haemoglobinPoints() {
    final pts = <_TrendPoint>[];
    for (final a in assessments) {
      if (Programme.fromString(a.type) != Programme.anc) continue;
      String? hbStr;
      final rawJson = a.rawJson;
      hbStr = rawJson['hemoglobin'] as String?;
      if (hbStr == null || hbStr.isEmpty) {
        final obs = rawJson['observations'];
        if (obs is Map) hbStr = obs['hemoglobin'] as String?;
      }
      if (hbStr == null || hbStr.isEmpty) {
        final ad = rawJson['assessmentDetails'];
        if (ad is Map) {
          final anc = ad['anc'];
          hbStr = (anc is Map ? anc['hemoglobin'] : ad['hemoglobin']) as String?;
        }
      }
      if (hbStr == null || hbStr.isEmpty) continue;
      final val = double.tryParse(hbStr);
      if (val == null) continue;
      pts.add(_TrendPoint(
        date: a.date,
        displayLabel: '${val.toStringAsFixed(1)} g/dL',
        primaryVal: val,
        assessment: a,
      ));
    }
    return pts.take(10).toList().reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final lc = Theme.of(context).extension<LeapfrogColors>()!;
    final theme = Theme.of(context);

    final bpPoints = _pointsForType(VitalType.bloodPressure);
    final bgPoints = _pointsForType(VitalType.glucose);
    final wtPoints = _pointsForType(VitalType.weight);
    final spO2Points = _pointsForType(VitalType.spO2);
    final tempPoints = _pointsForType(VitalType.temperature);
    final hbPoints = _haemoglobinPoints();

    final cards = <Widget>[];

    void addCard(
      String title,
      List<_TrendPoint> points, {
      bool isBp = false,
      Color lineColor = AppColors.statusWarning,
    }) {
      if (points.isEmpty) return;
      cards.add(_VitalTrendCard(
        title: title,
        points: points,
        isBp: isBp,
        lineColor: lineColor,
        onAssessmentTap: (ctx, a) => _TimelineEventSheet.show(ctx, a),
      ));
      cards.add(const SizedBox(height: 10));
    }

    addCard(PatientProfileStrings.bpChartLabel, bpPoints, isBp: true);
    addCard(PatientProfileStrings.bgChartLabel, bgPoints);
    addCard(PatientProfileStrings.weightChartLabel, wtPoints,
        lineColor: AppColors.navy);
    addCard(PatientProfileStrings.haemoglobinChartLabel, hbPoints,
        lineColor: AppColors.statusCritical);
    addCard(PatientProfileStrings.spO2ChartLabel, spO2Points,
        lineColor: const Color(0xFF10B981));
    addCard(PatientProfileStrings.tempChartLabel, tempPoints,
        lineColor: const Color(0xFFF97316));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _lightStatusBar,
      child: Scaffold(
        backgroundColor: lc.canvas,
        body: Column(
          children: [
            // ── Navy header matching _PatientDetailHeader ────────────
            Container(
              color: AppColors.navy,
              padding: EdgeInsets.fromLTRB(
                8,
                MediaQuery.of(context).padding.top + 8,
                16,
                14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  HeaderIconButton(
                    icon: Icons.arrow_back,
                    tooltip: PatientContextStrings.backToWorklist,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientName ?? PatientProfileStrings.allTrendsTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (patientName != null)
                          Text(
                            PatientProfileStrings.allTrendsTitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Trend cards ──────────────────────────────────────────
            Expanded(
              child: cards.isEmpty
                  ? Center(
                      child: Text(
                        PatientProfileStrings.noVitalsYet,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: lc.textMuted),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(14),
                      children: cards,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
