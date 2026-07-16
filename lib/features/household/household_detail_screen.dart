import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/user_hierarchy_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/mission/programme_reason.dart';
import '../../core/models/dashboard_tier.dart';
import '../../core/models/mission_queue_item.dart';
import '../../core/models/programme.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/header_icon_button.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/mission_dashboard_repository.dart';
import '../visit/widgets/mission_queue_card.dart';

/// Full details of a household member for display.
class HouseholdMemberData {
  HouseholdMemberData({
    this.id,
    this.referenceId,
    this.patientId,
    this.name,
    this.relation,
    this.age,
    this.gender,
    this.phoneNumber,
    this.dateOfBirth,
    this.isHead = false,
    this.isPregnant = false,
    this.householdId,
    this.villageId,
    this.recentService,
    this.recentServiceAt,
    this.programmes = const {},
    this.ancVisitCount = 0,
    this.pncVisitCount = 0,
  });

  final String? id;
  /// Numeric server-assigned member referenceId (e.g. "823260").
  /// Used as encounter.memberId in the sync payload so the FHIR mapper
  /// can resolve the RelatedPerson. Distinct from [id] (FHIR ID).
  final String? referenceId;
  final String? patientId;
  final String? name;
  final String? relation;
  final int? age;
  final String? gender;
  final String? phoneNumber;
  final String? dateOfBirth;
  final bool isHead;
  final bool isPregnant;
  final String? householdId;
  final String? villageId;
  final String? recentService;
  final DateTime? recentServiceAt;

  /// Enrolled programmes + visit counts — same shared badge inputs
  /// `household_list_screen.dart`'s member rows use, so a member's
  /// urgency/programme badge renders identically here.
  final Set<Programme> programmes;
  final int ancVisitCount;
  final int pncVisitCount;

  static HouseholdMemberData fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? age;
    final ageVal = json['age'];
    if (ageVal is int) {
      age = ageVal;
    } else if (ageVal is num) {
      age = ageVal.toInt();
    } else if (ageVal is String) {
      age = int.tryParse(ageVal);
    }

    // Calculate age from dateOfBirth if not directly available
    if (age == null) {
      final dobStr = str('dateOfBirth');
      if (dobStr != null) {
        try {
          final dob = DateTime.parse(dobStr);
          final now = DateTime.now();
          age = now.year - dob.year;
          if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
            age = age - 1;
          }
        } catch (_) {}
      }
    }

    // Parse householdHeadRelationship (API field name) or relation
    final relation = str('householdHeadRelationship') ?? str('relation');
    final relationLower = relation?.toLowerCase();
    final isHead = relationLower == 'head' ||
        relationLower == 'self' ||
        relationLower == 'household head' ||
        relationLower == 'householdhead' ||
        json['isHouseholdHead'] == true;

    final isPregnant = json['isPregnant'] == true;

    return HouseholdMemberData(
      id: str('id'),
      referenceId: str('referenceId') ?? str('memberId'),
      patientId: str('patientId'),
      name: str('name') ?? str('firstName'),
      relation: relation,
      age: age,
      gender: str('gender'),
      phoneNumber: str('phoneNumber') ?? str('phone'),
      dateOfBirth: str('dateOfBirth'),
      isHead: isHead,
      isPregnant: isPregnant,
      householdId: str('householdId'),
      // Mirror Android AssessmentEntity: prefer sub-village ID over parent village
      // so assessments get tagged with the same granularity the Android SK's pull
      // request uses (getAllSubVillageIds → e.g. [203, 204, 206]).
      villageId: str('subVillageId') ?? str('villageId'),
    );
  }

  /// Returns a copy with assessment-derived and programme/queue-derived
  /// fields filled in. Unspecified enrichment fields keep their current
  /// value (so callers enriching only one dimension don't clobber another).
  HouseholdMemberData withEnrichment({
    String? recentService,
    DateTime? recentServiceAt,
    Set<Programme>? programmes,
    int? ancVisitCount,
    int? pncVisitCount,
  }) =>
      HouseholdMemberData(
        id: id,
        referenceId: referenceId,
        patientId: patientId,
        name: name,
        relation: relation,
        age: age,
        gender: gender,
        phoneNumber: phoneNumber,
        dateOfBirth: dateOfBirth,
        isHead: isHead,
        isPregnant: isPregnant,
        householdId: householdId,
        villageId: villageId,
        recentService: recentService ?? this.recentService,
        recentServiceAt: recentServiceAt ?? this.recentServiceAt,
        programmes: programmes ?? this.programmes,
        ancVisitCount: ancVisitCount ?? this.ancVisitCount,
        pncVisitCount: pncVisitCount ?? this.pncVisitCount,
      );

  /// Creates from local SQLite HouseholdMemberEntity.
  static HouseholdMemberData fromEntity(HouseholdMemberEntity e) {
    int? age;
    if (e.dob != null && e.dob!.isNotEmpty) {
      try {
        final dob = DateTime.parse(e.dob!);
        final now = DateTime.now();
        age = now.year - dob.year;
        if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
          age = age - 1;
        }
      } catch (_) {}
    }
    return HouseholdMemberData(
      id: e.id,
      referenceId: e.referenceId,
      patientId: e.patientId,
      name: e.name,
      relation: e.relation,
      age: age,
      gender: e.gender,
      phoneNumber: e.phone,
      dateOfBirth: e.dob,
      isHead: e.isHouseholdHead,
      isPregnant: e.isPregnant,
      householdId: e.householdId,
      // Mirror Android AssessmentEntity: prefer sub-village ID so assessment
      // payloads scope to the same level used by getAllSubVillageIds() pull.
      villageId: e.subVillageId ?? e.villageId,
    );
  }
}

/// Full household data for the detail screen.
class HouseholdDetailData {
  HouseholdDetailData({
    this.id,
    this.name,
    this.householdNo,
    this.village,
    this.subVillage,
    this.memberCount,
    this.latitude,
    this.longitude,
    this.members = const [],
    this.ssName,
    this.lastVisitAt,
  });

  final String? id;
  final String? name;
  final String? householdNo;
  final String? village;
  final String? subVillage;
  final int? memberCount;
  final double? latitude;
  final double? longitude;
  final List<HouseholdMemberData> members;
  final String? ssName;
  final DateTime? lastVisitAt;

  HouseholdMemberData? get head => members.where((m) => m.isHead).firstOrNull;

  static HouseholdDetailData fromJson(Map<String, dynamic> json) {
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? memberCount;
    final countVal = json['noOfPeople'];
    if (countVal is int) {
      memberCount = countVal;
    } else if (countVal is num) {
      memberCount = countVal.toInt();
    } else if (countVal is String) {
      memberCount = int.tryParse(countVal);
    }

    double? lat, lng;
    final latVal = json['latitude'];
    final lngVal = json['longitude'];
    if (latVal is double) { lat = latVal; }
    else if (latVal is num) { lat = latVal.toDouble(); }
    if (lngVal is double) { lng = lngVal; }
    else if (lngVal is num) { lng = lngVal.toDouble(); }

    final memberList = <HouseholdMemberData>[];
    if (json['householdMembers'] is List) {
      for (final m in json['householdMembers']) {
        if (m is Map<String, dynamic>) {
          memberList.add(HouseholdMemberData.fromJson(m));
        } else if (m is Map) {
          memberList.add(
              HouseholdMemberData.fromJson(Map<String, dynamic>.from(m)));
        }
      }
    }

    return HouseholdDetailData(
      id: str('id'),
      name: str('name'),
      householdNo: str('householdNo'),
      village: str('village'),
      subVillage: str('subVillage'),
      memberCount: memberCount ?? memberList.length,
      latitude: lat,
      longitude: lng,
      members: memberList,
    );
  }
}

class HouseholdDetailScreen extends StatefulWidget {
  const HouseholdDetailScreen({
    super.key,
    required this.household,
  });

  final HouseholdDetailData household;

  @override
  State<HouseholdDetailScreen> createState() => _HouseholdDetailScreenState();
}

class _HouseholdDetailScreenState extends State<HouseholdDetailScreen> {
  late HouseholdDetailData _household;
  bool _loadingMembers = false;
  String? _loadError;

  // patientId -> queue item, so a member with an active mission-queue entry
  // renders with its real urgency badge — same shared data household_list_
  // screen.dart uses for its own household cards. Loaded independently of
  // member enrichment so a slow/failed queue fetch never blocks the roster
  // from rendering (badge-less rows are an acceptable degradation; a blocked
  // screen is not).
  Map<String, MissionQueueItem> _queueItems = {};

  /// Derives household name from head's name (same logic as household_list_screen).
  /// Returns: "HeadName's Household" or "Household #ID" or existing name.
  String? _deriveHouseholdName({
    required String? existingName,
    required List<HouseholdMemberData> members,
    required String householdId,
  }) {
    // If we already have a valid name, keep it
    if (existingName != null && existingName.isNotEmpty) {
      return existingName;
    }

    // Find household head
    final head = members.firstWhere(
      (m) => m.isHead,
      orElse: () => members.isNotEmpty ? members.first : HouseholdMemberData(),
    );

    // Use head's name to derive household name
    if (head.name != null && head.name!.isNotEmpty) {
      return "${head.name}'s Household";
    }

    // Fallback to "Household #ID"
    if (householdId.isNotEmpty) {
      return 'Household #$householdId';
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    // Derive household name from head if not available
    final derivedName = _deriveHouseholdName(
      existingName: widget.household.name,
      members: widget.household.members,
      householdId: widget.household.id ?? '',
    );
    _household = HouseholdDetailData(
      id: widget.household.id,
      name: derivedName,
      householdNo: widget.household.householdNo,
      village: widget.household.village,
      subVillage: widget.household.subVillage,
      memberCount: widget.household.memberCount,
      latitude: widget.household.latitude,
      longitude: widget.household.longitude,
      members: widget.household.members,
    );
    // Set synchronously (not inside _fetchMembers) so the very first build —
    // before the deferred postFrameCallback even fires — already knows a
    // fetch is coming and can show a loading state instead of a flashed
    // "0 members" (the no-`extra` entry point from the Patient Context
    // screen's "Same household" strip always lands here with an empty list).
    _loadingMembers = _household.members.isEmpty && _household.id != null;
    // Auto-fetch members if not provided (defer to avoid setState in initState)
    if (_household.members.isEmpty && _household.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchMembers();
      });
    } else if (_household.members.isNotEmpty) {
      // Members pre-loaded from list screen — run lightweight meta enrichment
      // so village name, SS name, and last-visit are resolved without a full fetch.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enrichMeta();
      });
    }
    // Queue membership is independent of member enrichment (may load slower,
    // may fail offline) — fetched unconditionally so badges also appear when
    // the screen was navigated to with a full member list already in hand.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadQueueItems();
    });
  }

  /// Loads the mission queue so any household member with an active entry
  /// renders with its real urgency badge — mirrors household_list_screen
  /// .dart's own `_loadQueueItems`. Tolerates failure: a badge-less roster
  /// is an acceptable degradation, a blocked screen is not.
  Future<void> _loadQueueItems() async {
    if (!mounted) return;
    try {
      final missionRepo = context.read<MissionDashboardRepository>();
      final queue = await missionRepo.loadQueue();
      if (!mounted) return;
      // Upcoming-tier members (due >7 days out, or no due date) get no
      // status badge — they still appear in the roster, just untagged.
      final queueMap = <String, MissionQueueItem>{};
      for (final item in queue) {
        if (item.patientId != null && item.tier != DashboardTier.upcoming) {
          queueMap[item.patientId!] = item;
        }
      }
      setState(() => _queueItems = queueMap);
    } catch (_) {}
  }

  /// Resolves village name, SS name, and last-visit date for households that
  /// arrive pre-loaded with members (list-screen → detail navigation). Avoids
  /// a redundant full member fetch when the roster is already in hand.
  Future<void> _enrichMeta() async {
    if (!mounted) return;
    final hierarchy = context.read<UserHierarchyService>();
    final memberDao = context.read<MemberDao>();
    await hierarchy.prefetch();

    // Village ID → human-readable name. Check subVillages first (more specific),
    // then fall back to top-level villages.
    final rawVillage = _household.village;
    final villageName = rawVillage == null
        ? null
        : hierarchy.subVillages
                ?.where((sv) => sv.id == rawVillage)
                .firstOrNull
                ?.name ??
            hierarchy.villages
                ?.where((v) => v.id == rawVillage)
                .firstOrNull
                ?.name;

    // SS name from first member's DB entity (pre-loaded HouseholdMemberData
    // doesn't carry shasthyaShebikaId — must re-query).
    String? ssName;
    final firstId = _household.members.firstOrNull?.id;
    if (firstId != null) {
      final entity = await memberDao.getById(firstId);
      ssName = _resolveSsName(entity?.shasthyaShebikaId, hierarchy);
    }

    final lastVisitAt = _householdLastVisit(_household.members);
    ConsoleLog.banner('[HouseholdDetail] _enrichMeta'
        ' village=${villageName ?? rawVillage} ssName=$ssName lastVisit=$lastVisitAt');

    if (!mounted) return;
    setState(() {
      _household = HouseholdDetailData(
        id: _household.id,
        name: _household.name,
        householdNo: _household.householdNo,
        village: villageName ?? _household.village,
        subVillage: _household.subVillage,
        memberCount: _household.memberCount,
        latitude: _household.latitude,
        longitude: _household.longitude,
        members: _household.members,
        ssName: ssName,
        lastVisitAt: lastVisitAt,
      );
    });
  }

  Future<void> _fetchMembers() async {
    // Guard only blocks concurrent re-fetches triggered by pull-to-refresh
    // while a fetch is already running. The initState path sets _loadingMembers
    // synchronously BEFORE calling here, so we must not bail on that case.
    if (_loadingMembers && _household.members.isNotEmpty) return;
    setState(() {
      _loadingMembers = true;
      _loadError = null;
    });

    final householdId = _household.id;
    if (householdId == null) {
      setState(() {
        _loadError = HouseholdDetailStrings.householdIdNotAvailable;
        _loadingMembers = false;
      });
      return;
    }

    try {
      final memberDao = context.read<MemberDao>();
      final assessmentDao = context.read<AssessmentDao>();
      final patientDao = context.read<PatientDao>();
      final programmesDao = PatientProgrammesDao(context.read<AppDatabase>());
      final hierarchy = context.read<UserHierarchyService>();
      final repo = context.read<DashboardRepository>();
      await hierarchy.prefetch();

      final localMembers = await memberDao.getByHouseholdId(householdId);

      if (localMembers.isNotEmpty && mounted) {
        final base = localMembers.map(HouseholdMemberData.fromEntity).toList();
        final enriched = await _enrichMembers(
          base,
          assessmentDao,
          patientDao,
          programmesDao,
        );
        final ssName = _resolveSsName(
            localMembers.first.shasthyaShebikaId, hierarchy);
        final lastVisitAt = _householdLastVisit(enriched);
        final derivedName = _deriveHouseholdName(
          existingName: _household.name,
          members: enriched,
          householdId: householdId,
        );
        if (!mounted) return;
        setState(() {
          _household = HouseholdDetailData(
            id: _household.id,
            name: derivedName,
            householdNo: _household.householdNo,
            village: _household.village,
            subVillage: _household.subVillage,
            memberCount: enriched.length,
            latitude: _household.latitude,
            longitude: _household.longitude,
            members: enriched,
            ssName: ssName,
            lastVisitAt: lastVisitAt,
          );
          _loadingMembers = false;
        });
        return;
      }

      // Fall back to API only if local cache is empty. Gets the exact same
      // enrichment as the local-cache path — otherwise a household with no
      // local cache yet (first sync) would silently show an unbadged,
      // service-history-less roster with no indication anything is missing.
      final householdData = await repo.getHouseholdById(householdId);

      if (householdData != null && mounted) {
        final updated = HouseholdDetailData.fromJson(householdData);
        final enriched = await _enrichMembers(
          updated.members,
          assessmentDao,
          patientDao,
          programmesDao,
        );
        final ssName = enriched.isNotEmpty
            ? _resolveSsName(
                localMembers.firstOrNull?.shasthyaShebikaId, hierarchy)
            : null;
        final lastVisitAt = _householdLastVisit(enriched);
        final derivedName = _deriveHouseholdName(
          existingName: updated.name,
          members: enriched,
          householdId: householdId,
        );
        if (!mounted) return;
        setState(() {
          _household = HouseholdDetailData(
            id: updated.id,
            name: derivedName,
            householdNo: updated.householdNo,
            village: updated.village,
            subVillage: updated.subVillage,
            // Trust the loaded member list, not the API's own count field —
            // matches the local-cache path so `memberCount` means the same
            // thing (and never disagrees with `members.length`) regardless
            // of which path populated this screen.
            memberCount: enriched.length,
            latitude: updated.latitude,
            longitude: updated.longitude,
            members: enriched,
            ssName: ssName,
            lastVisitAt: lastVisitAt,
          );
          _loadingMembers = false;
        });
      } else if (mounted) {
        setState(() {
          _loadError = HouseholdDetailStrings.noMembers;
          _loadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loadingMembers = false;
        });
      }
    }
  }

  /// Enriches members with most-recent assessment kind + date, and with
  /// enrolled programmes + visit counts — the same shared inputs
  /// `household_list_screen.dart`'s own member rows use, so a member's
  /// programme/urgency badge renders identically on both screens. Members
  /// with no `patientId` are returned unchanged (no lookup, no false badge).
  Future<List<HouseholdMemberData>> _enrichMembers(
    List<HouseholdMemberData> members,
    AssessmentDao assessmentDao,
    PatientDao patientDao,
    PatientProgrammesDao programmesDao,
  ) async {
    final patientIds =
        members.map((m) => m.patientId).whereType<String>().toList();
    if (patientIds.isEmpty) return members;

    final results = await Future.wait([
      assessmentDao.forMany(patientIds),
      patientDao.lastVisitAtForPatients(patientIds),
      programmesDao.programmesForMany(patientIds),
      assessmentDao.visitCountsByPatients(patientIds, ancVisitKinds),
      assessmentDao.visitCountsByPatients(patientIds, pncVisitKinds),
    ]);
    final assessments = results[0] as Map<String, List<AssessmentRow>>;
    final lastVisits = results[1] as Map<String, int>;
    final programmesByPatient = results[2] as Map<String, Set<Programme>>;
    final ancCounts = results[3] as Map<String, int>;
    final pncCounts = results[4] as Map<String, int>;

    return members.map((m) {
      final pid = m.patientId;
      if (pid == null) return m;
      final latestAssessment = assessments[pid]?.first;
      final lastVisitMs = lastVisits[pid];
      final serviceAt = latestAssessment?.occurredAt != null
          ? DateTime.fromMillisecondsSinceEpoch(latestAssessment!.occurredAt!)
          : (lastVisitMs != null
              ? DateTime.fromMillisecondsSinceEpoch(lastVisitMs)
              : null);
      return m.withEnrichment(
        recentService: latestAssessment?.kind,
        recentServiceAt: serviceAt,
        programmes: programmesByPatient[pid] ?? const {},
        ancVisitCount: ancCounts[pid] ?? 0,
        pncVisitCount: pncCounts[pid] ?? 0,
      );
    }).toList();
  }

  String? _resolveSsName(String? shebikaId, UserHierarchyService hierarchy) {
    if (shebikaId == null) return null;
    return hierarchy.ssWorkers
        ?.where((ss) => ss.id == shebikaId)
        .firstOrNull
        ?.name;
  }

  DateTime? _householdLastVisit(List<HouseholdMemberData> members) {
    DateTime? latest;
    for (final m in members) {
      final d = m.recentServiceAt;
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest;
  }

  HouseholdDetailData get household => _household;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchMembers,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.xl),
                        _buildInfoCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildMembersSectionHeader(),
                        const SizedBox(height: AppSpacing.md),
                        _buildMembersBody(context),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Navy header matching `household_list_screen.dart`'s own — status-bar-
  /// covering background, back button (a real "go back," unlike the
  /// Patients-list header's "back to Home," since this is a drill-down
  /// screen reached via push), 🏠-prefixed household name, and a member
  /// count that's suppressed (rather than flashing "0") while the very
  /// first load is still in flight.
  Widget _buildHeader(BuildContext context) {
    final showCount = !(_loadingMembers && household.members.isEmpty);
    final count = household.memberCount ?? household.members.length;
    return Container(
      color: AppColors.navy,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 10,
        20,
        14,
      ),
      child: Row(
        children: [
          HeaderIconButton(
            icon: Icons.arrow_back,
            tooltip: HouseholdDetailStrings.back,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🏠 ${household.name ?? HouseholdDetailStrings.unnamedHousehold}',
                  style: AppTextStyles.householdHeaderTitle,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showCount) ...[
                  const SizedBox(height: 1),
                  Text(
                    HouseholdListStrings.membersCount(count),
                    style: AppTextStyles.householdHeaderSub,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Household metadata card — same muted-surface/shadow language as
  /// `_HouseholdCard`'s own header row. No SVG icon set exists for
  /// location/calendar/person (there's no mockup for this screen to justify
  /// inventing new ones), so these stay Material `Icons.*`, just recolored
  /// via `AppColors` instead of the raw theme's `colorScheme`. Laid out as a
  /// compact 2×2 grid (two rows of two) rather than four stacked full-width
  /// rows, so the card reads at a glance instead of taking up most of the
  /// screen before any member is visible.
  Widget _buildInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.householdCard,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _InfoRow(
                  icon: Icons.tag_outlined,
                  label: HouseholdDetailStrings.householdNumber,
                  value: household.householdNo ??
                      HouseholdDetailStrings.notAvailable,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: HouseholdDetailStrings.village,
                  value: household.village ?? HouseholdDetailStrings.notAvailable,
                  color: AppColors.aiPurpleDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _InfoRow(
                  icon: Icons.person_pin_outlined,
                  label: HouseholdDetailStrings.ssName,
                  value: household.ssName ?? HouseholdDetailStrings.noSsAssigned,
                  color: AppColors.statusSuccessAction,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: HouseholdDetailStrings.lastVisitDate,
                  value: household.lastVisitAt != null
                      ? DateFormat('d MMM yyyy').format(household.lastVisitAt!)
                      : HouseholdDetailStrings.neverVisited,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSectionHeader() {
    final count = household.memberCount ?? household.members.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
      child: Row(
        children: [
          Text(
            HouseholdDetailStrings.householdMembers,
            style: AppTextStyles.worklistRowLabel,
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.aiSurfaceStart,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.aiPurpleDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersBody(BuildContext context) {
    if (_loadingMembers) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: EmptyStateCard(
          icon: Icons.hourglass_empty,
          iconColor: AppColors.aiPurpleDark,
          iconBg: AppColors.aiSurfaceStart,
          title: HouseholdDetailStrings.loadingMembers,
        ),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: EmptyStateCard(
          icon: Icons.error_outline,
          iconColor: AppColors.statusCritical,
          iconBg: AppColors.statusCriticalSurface,
          title: HouseholdDetailStrings.couldNotLoadMembers,
          subtitle: _loadError,
          actionLabel: CommonStrings.retry,
          onAction: _fetchMembers,
        ),
      );
    }
    if (household.members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
        child: EmptyStateCard(
          icon: Icons.people_outline,
          iconColor: AppColors.textMuted,
          iconBg: AppColors.progressTrack,
          title: household.memberCount != null && household.memberCount! > 0
              ? HouseholdDetailStrings.memberDataNotLoaded(household.memberCount!)
              : HouseholdDetailStrings.noMembers,
          actionLabel: household.id != null
              ? HouseholdDetailStrings.loadMembers
              : null,
          onAction: household.id != null ? _fetchMembers : null,
        ),
      );
    }

    // Use all members but cap to memberCount if available to avoid data
    // inconsistencies.
    final allMembers = household.members.toList();
    final actualMemberCount = household.memberCount ?? allMembers.length;
    final cappedMembers = allMembers.length > actualMemberCount
        ? allMembers.take(actualMemberCount).toList()
        : allMembers;
    return Column(
      children: [
        for (final m in cappedMembers)
          _MemberCard(
            member: m,
            queueItem: (m.patientId ?? m.id) != null
                ? _queueItems[m.patientId ?? m.id]
                : null,
            onTap: () => _navigateToPatientDetails(context, m),
          ),
      ],
    );
  }

  /// Tapping any member in the roster goes straight to Patient Details — no
  /// intermediate sheet. Prefer patientId over member.id: the patients table
  /// stores records under patientId when available (same logic as
  /// `_memberToPatient` in offline_sync_service.dart). Pushes directly to
  /// `/patients/:id` — the `/patient/:id` redirect alias exists for backward
  /// compat but GoRouter drops `extra` when redirecting, losing referenceId.
  void _navigateToPatientDetails(BuildContext context, HouseholdMemberData member) {
    final navId = (member.patientId != null && member.patientId!.isNotEmpty)
        ? member.patientId!
        : member.id;
    context.push(
      '/patients/$navId?origin=household',
      extra: {
        'id': member.id,
        'referenceId': member.referenceId,
        'name': member.name,
        'gender': member.gender,
        'age': member.age,
        'dateOfBirth': member.dateOfBirth,
        'phoneNumber': member.phoneNumber,
        'isPregnant': member.isPregnant,
        'householdId': member.householdId ?? household.id,
        'householdName': household.name,
        'patientId': member.patientId,
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One row in the household roster — an embedded `MissionQueueCard` when the
/// member has an active mission-queue entry (real urgency badge), else a
/// `PatientBadgeRow` (programme-reason badge). Same shared widgets/data
/// `household_list_screen.dart` uses for its own member rows, so a member's
/// status reads identically wherever it's shown. Wrapped in its own card
/// boundary (unlike the flush embedding on the Patients-list screen) since
/// here every member gets an equal-weight row, not one flagged primary plus
/// a collapsed "others" panel.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.queueItem,
    required this.onTap,
  });

  final HouseholdMemberData member;
  final MissionQueueItem? queueItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = queueItem;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.householdCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: item != null
          ? MissionQueueCard(
              item: item,
              compact: true,
              embedded: true,
              onTap: onTap,
            )
          : PatientBadgeRow(
              name: member.name,
              age: member.age,
              gender: member.gender,
              phoneNumber: member.phoneNumber,
              programmes: member.programmes,
              ancVisitCount: member.ancVisitCount,
              pncVisitCount: member.pncVisitCount,
              onTap: onTap,
            ),
    );
  }
}
