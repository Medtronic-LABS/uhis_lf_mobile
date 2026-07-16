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
import '../../core/widgets/empty_state_card.dart';
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
import 'recent_vitals_section.dart';
import '../assistant/patient_ai_sheet.dart';
import 'contact_sheet.dart';
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

  PatientOrMemberData copyWith({
    List<MemberAssessment>? remoteAssessments,
    List<PatientVisit>? recentVisits,
    String? householdName,
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
    final t0 = Stopwatch()..start();
    ConsoleLog.banner('[PatientCtx] open patientId=${widget.patientId}');

    // Capture context-bound objects synchronously before any await to avoid
    // use_build_context_synchronously linter warnings.
    final memberRepo = context.read<MemberDetailRepository>();
    final patientRepo = context.read<PatientRepository>();
    final syncSvc = context.read<OfflineSyncService>();

    // Phase 1: all local reads in parallel — returns instantly from SQLite.
    final phase1 = await Future.wait([
      _resolveEncounterMemberId(),
      patientRepo.byId(widget.patientId),
      _localAssessmentsFor(widget.patientId),
      syncSvc.lastSyncedAt(),
    ]);
    final resolvedMemberId = phase1[0] as String?;
    final localPatient = phase1[1] as PatientWithProgrammes?;
    final localAssessments = phase1[2] as List<MemberAssessment>;
    final lastSync = phase1[3] as DateTime?;
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
      );
      if (mounted) {
        setState(() {
          _localSnapshot = localOnly;
          _remoteLoading = true;
        });
      }
      ConsoleLog.banner('[PatientCtx] rendered local at ${t0.elapsedMilliseconds}ms'
          ' — ${localAssessments.length} local assessments');

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
      ConsoleLog.banner('[PatientCtx] phase2 done=${tPhase2.elapsedMilliseconds}ms'
          ' remoteAssessments=${remoteAssessments.length}'
          ' total=${t0.elapsedMilliseconds}ms');

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
    // Spec §2.8.3: Band 1 (Severe) and Band 2 (Moderate) are "urgent"
    // for context-screen styling purposes — both push the patient to
    // the same-day visit list.
    final isUrgent = data.riskBand == Band.band1 ||
        data.riskBand == Band.band2;
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
          // Same-household strip per spec Phase 5
          if (data.householdId != null)
            _SameHouseholdStrip(
              currentPatientId: widget.patientId,
              householdId: data.householdId!,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
              padding: const EdgeInsets.fromLTRB(
                14,
                14,
                14,
                AppSpacing.stickyBarClearance,
              ),
              children: [
                // ── Profile ──────────────────────────────────────────────
                _SectionLabel(PatientContextStrings.sectionGroupProfile),
                _PatientProfileCard(data: data),

                // ── Clinical ─────────────────────────────────────────────
                _SectionLabel(PatientContextStrings.sectionGroupClinical),
                _AssessmentsSection(
                  assessments: data.assessments,
                  isLoading: remoteLoading,
                ),
                const SizedBox(height: 10),
                RecentVitalsSection(
                  patientId: data.patientId ?? widget.patientId,
                  memberReference: data.memberReference,
                ),

                // ── Care Plan ────────────────────────────────────────────
                _SectionLabel(PatientContextStrings.sectionGroupCarePlan),
                OpenFollowupsSection(
                  patientId: widget.patientId,
                  memberReference: data.memberReference,
                ),

                // ── Actions ──────────────────────────────────────────────
                const SizedBox(height: 20),
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


/// Thin divider with a label used to separate content groups on the patient screen.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider(thickness: 1, height: 1)),
        ],
      ),
    );
  }
}

/// Section showing assessment history.
class _AssessmentsSection extends StatelessWidget {
  const _AssessmentsSection({required this.assessments, this.isLoading = false});

  final List<MemberAssessment> assessments;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy · h:mm a');

    if (assessments.isEmpty && isLoading) {
      // Remote fetch still in flight and no local assessments yet — show shimmer.
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.householdCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined, color: AppColors.navy),
                const SizedBox(width: 8),
                Text(
                  PatientContextStrings.sectionRecentVisits,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _AssessmentShimmerRow(),
            const SizedBox(height: 8),
            const _AssessmentShimmerRow(),
          ],
        ),
      );
    }

    if (assessments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.householdCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined, color: AppColors.navy),
                const SizedBox(width: 8),
                Text(
                  PatientContextStrings.sectionRecentVisits,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            EmptyStateCard(
              icon: Icons.history_outlined,
              iconColor: AppColors.textMuted,
              iconBg: AppColors.progressTrack,
              title: PatientContextStrings.noAssessmentsYet,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.householdCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined, color: AppColors.navy),
              const SizedBox(width: 8),
              Text(
                PatientContextStrings.sectionRecentVisits,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                PatientContextStrings.assessmentsTotal(assessments.length),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
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
                  child: Text(
                    PatientContextStrings.viewAllAssessments(assessments.length),
                  ),
                ),
              ),
            ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: _AssessmentShimmerRow(),
            ),
        ],
      ),
    );
  }
}

class _AssessmentShimmerRow extends StatelessWidget {
  const _AssessmentShimmerRow();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
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
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    PatientContextStrings.allAssessmentsTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    PatientContextStrings.assessmentsTotal(assessments.length),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
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
    ConsoleLog.banner('[AssessmentDetail] open id=${assessment.id}'
        ' type=${assessment.type} date=${assessment.date}'
        ' rawKeys=${assessment.rawJson.keys.toList()}'
        ' rawJson=${assessment.rawJson}');
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
        typeColor = AppColors.navy;
        typeIcon = Icons.assignment;
    }

    final visitLabel = assessment.visitNumber != null
        ? '${assessment.type}  ·  Visit ${assessment.visitNumber}'
        : assessment.type;

    return Semantics(
      label: PatientContextStrings.viewAssessmentSemantics(
        assessment.type,
        dateFormat.format(assessment.date),
      ),
      button: true,
      child: InkWell(
      key: const Key('patient_assessment_row_tap'),
      onTap: () => _showAssessmentDetail(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(typeIcon, size: 18, color: typeColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                visitLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: typeColor,
                ),
              ),
            ),
            Text(
              dateFormat.format(assessment.date),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
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

  /// Unpacks the nested `raw` field stored as {kind, raw: "...JSON..." | Map}.
  Map<String, dynamic> _effectiveRaw() {
    final outer = assessment.rawJson;
    final rawField = outer['raw'];
    if (rawField is Map) {
      return Map<String, dynamic>.from(rawField);
    }
    if (rawField is String && rawField.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(rawField) as Map);
      } catch (_) {}
    }
    return outer;
  }

  @override
  Widget build(BuildContext context) {
    final progColors = Theme.of(context).extension<ProgrammeColors>()!;
    final raw = _effectiveRaw();

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
        typeColor = AppColors.navy;
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
          decoration: const BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
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
                                  child: Text(
                                    PatientContextStrings.latestBadge,
                                    style: const TextStyle(
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
                            PatientContextStrings.visitOnLabel(dateFormat.format(assessment.date)),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: PatientContextStrings.close,
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
                    _DetailRow(
                      label: PatientContextStrings.serviceLabel,
                      value: serviceProvided ?? assessment.type,
                    ),
                    if (assessment.visitNumber != null)
                      _DetailRow(
                        label: PatientContextStrings.visitNumberFieldLabel,
                        value: '${assessment.visitNumber}',
                      ),
                    if (encounterId != null)
                      _DetailRow(label: PatientContextStrings.encounterIdLabel, value: encounterId),
                    if (memberId != null)
                      _DetailRow(label: PatientContextStrings.memberIdLabel, value: memberId),
                    if (referralStatus != null && referralStatus.isNotEmpty)
                      _DetailRow(
                        label: PatientContextStrings.referralStatusLabel,
                        value: referralStatus,
                        valueColor: referralStatus.toLowerCase() == 'referred' ? AppColors.statusWarning : null,
                      ),
                    if (referralReason != null && referralReason.isNotEmpty)
                      _DetailRow(label: PatientContextStrings.referralReasonLabel, value: referralReason),
                    if (nextFollowUpDate != null && nextFollowUpDate.isNotEmpty)
                      _DetailRow(label: PatientContextStrings.nextFollowUpLabel, value: nextFollowUpDate),
                    if (customStatus != null && customStatus.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        PatientContextStrings.statusIndicatorsTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
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
                    const SizedBox(height: 16),
                    // Raw stored fields — shows everything not already rendered above
                    _buildRawFieldsDump(typeColor),
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
    final raw = _effectiveRaw();
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
          fields.add(_ClinicalField(PatientContextStrings.bloodPressureLabel, '${sys.toInt()}/${dia.toInt()} mmHg',
              icon: Icons.favorite, urgent: sys >= 140 || dia >= 90));
        }
        final glucose = num_('glucoseValue') ?? num_('bloodGlucose') ?? num_('bg');
        final glucoseType = str_('glucoseType') ?? str_('bgType');
        if (glucose != null) {
          final label = PatientContextStrings.glucoseLabel(glucoseType?.toLowerCase());
          fields.add(_ClinicalField(label, '${glucose.toStringAsFixed(1)} mg/dL',
              icon: Icons.bloodtype, urgent: glucose > 200));
        }
        final height = num_('height'); final weight = num_('weight'); final bmi = num_('bmi');
        if (height != null) fields.add(_ClinicalField(PatientContextStrings.heightLabel, '${height.toInt()} cm', icon: Icons.straighten));
        if (weight != null) fields.add(_ClinicalField(PatientContextStrings.weightLabel, '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        if (bmi != null) fields.add(_ClinicalField(PatientContextStrings.bmiLabel, bmi.toStringAsFixed(1), icon: Icons.calculate));
        final hb = num_('hemoglobin');
        if (hb != null) {
          fields.add(_ClinicalField(PatientContextStrings.haemoglobinLabel, '${hb.toStringAsFixed(1)} g/dL',
              icon: Icons.opacity, urgent: hb < 10.0));
        }
        final smoker = bool_('isRegularSmoker') ?? bool_('isSmoking');
        if (smoker != null) fields.add(_ClinicalField(PatientContextStrings.smokingLabel, smoker ? PatientContextStrings.yes : PatientContextStrings.no, icon: Icons.smoking_rooms));
        final alcohol = bool_('isDrinkingAlcohol') ?? bool_('alcoholConsumption');
        if (alcohol != null) fields.add(_ClinicalField(PatientContextStrings.alcoholLabel, alcohol ? PatientContextStrings.yes : PatientContextStrings.no, icon: Icons.local_bar));

      case 'ANC':
        final ancVisit = str_('ancVisitNumber');
        if (ancVisit != null) fields.add(_ClinicalField(PatientContextStrings.ancVisitLabel, ancVisit, icon: Icons.calendar_today));
        final ga = num_('gestationalAge') ?? num_('gestationAge');
        if (ga != null) fields.add(_ClinicalField(PatientContextStrings.gestationalAgeLabel, '${ga.toInt()} weeks', icon: Icons.calendar_month));
        final gravida = str_('gravida');
        final parity = str_('parity');
        if (gravida != null || parity != null) {
          fields.add(_ClinicalField(PatientContextStrings.gravidaParityLabel, 'G${gravida ?? '?'} P${parity ?? '?'}', icon: Icons.child_friendly));
        }
        final fetuses = num_('noOfFetus') ?? num_('numberOfFetus');
        if (fetuses != null && fetuses > 1) fields.add(_ClinicalField(PatientContextStrings.fetusesLabel, fetuses.toInt().toString(), icon: Icons.group));
        final fh = num_('fundalHeight');
        if (fh != null) fields.add(_ClinicalField(PatientContextStrings.fundalHeightLabel, '${fh.toStringAsFixed(1)} cm', icon: Icons.height));
        // BP: try numeric fields first, then obs['bp'] string
        var sys = num_('avgSystolic') ?? num_('systolicBp');
        var dia = num_('avgDiastolic') ?? num_('diastolicBp');
        if (sys == null || dia == null) {
          final parsed = parseBpString(str_('bp'));
          if (parsed != null) { sys = parsed.$1; dia = parsed.$2; }
        }
        if (sys != null && dia != null) {
          fields.add(_ClinicalField(PatientContextStrings.bloodPressureLabel, '${sys.toInt()}/${dia.toInt()} mmHg',
              icon: Icons.favorite, urgent: sys >= 140 || dia >= 90));
        }
        final weight = num_('weight');
        if (weight != null) fields.add(_ClinicalField(PatientContextStrings.weightLabel, '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        final hb = num_('hemoglobin');
        if (hb != null) {
          fields.add(_ClinicalField(PatientContextStrings.haemoglobinLabel, '${hb.toStringAsFixed(1)} g/dL',
              icon: Icons.opacity, urgent: hb < 10.0));
        }
        final glucose = num_('bg') ?? num_('glucoseValue') ?? num_('bloodGlucose');
        final glucoseType = str_('bgType') ?? str_('glucoseType');
        if (glucose != null) {
          final label = PatientContextStrings.glucoseLabel(glucoseType?.toLowerCase());
          fields.add(_ClinicalField(label, '${glucose.toStringAsFixed(1)} mg/dL', icon: Icons.bloodtype));
        }
        final fetalMovement = bool_('fetalMovement') ?? bool_('isFetalMovementNormal');
        if (fetalMovement != null) {
          fields.add(_ClinicalField(PatientContextStrings.fetalMovementLabel, fetalMovement ? PatientContextStrings.normal : PatientContextStrings.abnormal,
              icon: Icons.waves, urgent: fetalMovement == false));
        }

      case 'PNC':
        final pncVisit = str_('pncVisitNumber');
        if (pncVisit != null) fields.add(_ClinicalField(PatientContextStrings.pncVisitLabel, pncVisit, icon: Icons.calendar_today));
        // BP: try numeric fields first, then obs['bp'] string
        var sys = num_('avgSystolic') ?? num_('systolicBp');
        var dia = num_('avgDiastolic') ?? num_('diastolicBp');
        if (sys == null || dia == null) {
          final parsed = parseBpString(str_('bp'));
          if (parsed != null) { sys = parsed.$1; dia = parsed.$2; }
        }
        if (sys != null && dia != null) {
          fields.add(_ClinicalField(PatientContextStrings.bloodPressureLabel, '${sys.toInt()}/${dia.toInt()} mmHg',
              icon: Icons.favorite, urgent: sys >= 140 || dia >= 90));
        }
        final weight = num_('weight');
        if (weight != null) fields.add(_ClinicalField(PatientContextStrings.weightLabel, '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        final hb = num_('hemoglobin');
        if (hb != null) {
          fields.add(_ClinicalField(PatientContextStrings.haemoglobinLabel, '${hb.toStringAsFixed(1)} g/dL',
              icon: Icons.opacity, urgent: hb < 10.0));
        }
        final breastfeeding = bool_('isBreastfeeding') ?? bool_('breastfeeding');
        if (breastfeeding != null) fields.add(_ClinicalField(PatientContextStrings.breastfeedingLabel, breastfeeding ? PatientContextStrings.yes : PatientContextStrings.no, icon: Icons.child_friendly));

      case 'IMCI':
        final height = num_('height'); final weight = num_('weight'); final muac = num_('muac');
        if (height != null) fields.add(_ClinicalField(PatientContextStrings.heightLabel, '${height.toInt()} cm', icon: Icons.straighten));
        if (weight != null) fields.add(_ClinicalField(PatientContextStrings.weightLabel, '${weight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight));
        if (muac != null) {
          fields.add(_ClinicalField(PatientContextStrings.muacLabel, '${muac.toStringAsFixed(1)} cm', icon: Icons.straighten,
              urgent: muac < 12.5));
        }
        final temp = num_('temperature') ?? num_('temp');
        if (temp != null) {
          fields.add(_ClinicalField(PatientContextStrings.temperatureLabel, '${temp.toStringAsFixed(1)} °C', icon: Icons.thermostat,
              urgent: temp >= 38.5));
        }
        final diagnosis = str_('childDiagnosis') ?? str_('diagnosis') ?? str_('classification');
        if (diagnosis != null) fields.add(_ClinicalField(PatientContextStrings.diagnosisLabel, diagnosis, icon: Icons.medical_information));

      case 'TB':
        final cough = num_('coughDuration') ?? num_('durationOfCough');
        if (cough != null) fields.add(_ClinicalField(PatientContextStrings.coughDurationLabel, '${cough.toInt()} days', icon: Icons.air));
        final diabetic = bool_('isDiabetic') ?? bool_('hasDiabetes');
        if (diabetic != null) fields.add(_ClinicalField(PatientContextStrings.diabetesLabel, diabetic ? PatientContextStrings.yes : PatientContextStrings.no, icon: Icons.bloodtype));
        final smoking = bool_('isSmoking') ?? bool_('isRegularSmoker');
        if (smoking != null) fields.add(_ClinicalField(PatientContextStrings.smokingLabel, smoking ? PatientContextStrings.yes : PatientContextStrings.no, icon: Icons.smoking_rooms));
        final contact = bool_('hasTbContact') ?? bool_('tbContact');
        if (contact != null) {
          fields.add(_ClinicalField(PatientContextStrings.tbContactLabel, contact ? PatientContextStrings.yes : PatientContextStrings.no, icon: Icons.people,
              urgent: contact == true));
        }
    }

    if (fields.isEmpty) return const SizedBox.shrink();

    final (label, icon) = switch (assessment.type) {
      'NCD'  => (PatientContextStrings.ncdFindingsTitle, Icons.monitor_heart_outlined),
      'ANC'  => (PatientContextStrings.ancFindingsTitle, Icons.pregnant_woman),
      'PNC'  => (PatientContextStrings.pncFindingsTitle, Icons.child_friendly),
      'IMCI' => (PatientContextStrings.childHealthFindingsTitle, Icons.child_care),
      'TB'   => (PatientContextStrings.tbFindingsTitle, Icons.air),
      _      => (PatientContextStrings.clinicalFindingsTitle, Icons.assignment),
    };

    return Container(
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
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
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          ...fields.map((f) => _ClinicalFieldRow(field: f)),
        ],
      ),
    );
  }

  /// Shows any rawJson fields not already rendered in the structured sections.
  /// Skips nulls, empty strings, known-rendered keys, and deeply-nested objects.
  Widget _buildRawFieldsDump(Color typeColor) {
    // Keys already shown in structured sections — skip to avoid duplication.
    const _knownKeys = {
      'kind', 'raw',
      'encounterId', 'id', 'serviceProvided', 'assessmentName', 'type',
      'visitDate', 'createdAt', 'startTime', 'date', 'visitNumber',
      'referralStatus', 'referralReason', 'nextFollowUpDate',
      'householdMemberId', 'memberId', 'latestVisit', 'customStatus',
      'assessmentDetails', 'observations',
    };
    final entries = _effectiveRaw().entries
        .where((e) =>
            !_knownKeys.contains(e.key) &&
            e.value != null &&
            e.value.toString().isNotEmpty &&
            e.value.toString() != 'null' &&
            e.value is! Map &&
            e.value is! List)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            PatientContextStrings.storedDataTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...entries.map(
            (e) => _DetailRow(
              label: e.key,
              value: e.value.toString(),
            ),
          ),
        ],
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
    final color = field.urgent ? AppColors.statusCritical : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(
              field.value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: field.urgent ? AppColors.statusCritical : AppColors.textPrimary,
              ),
            ),
          ),
          if (field.urgent)
            const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.statusWarning),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
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
              full,
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
