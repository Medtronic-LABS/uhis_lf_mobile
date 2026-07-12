import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactoryOrNull;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'app/theme_provider.dart';
import 'core/api/api_client.dart';
import 'core/api/realtime_asr_service.dart';
import 'core/preferences/scribe_engine_notifier.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/api/scribe_api_service.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/auth_state.dart';
import 'core/auth/biometric_service.dart';
import 'core/constants/app_strings.dart';
import 'core/db/ai_response_cache_dao.dart';
import 'core/db/app_database.dart';
import 'core/db/assessment_dao.dart';
import 'core/db/encounter_dao.dart';
import 'core/db/follow_up_dao.dart';
import 'core/db/household_dao.dart';
import 'core/db/immunisation_dao.dart';
import 'core/db/local_assessment_dao.dart';
import 'core/db/local_dashboard_repository.dart';
import 'core/db/member_dao.dart';
import 'core/db/patient_dao.dart';
import 'core/db/patient_programmes_dao.dart';
import 'core/db/pregnancy_snapshot_dao.dart';
import 'core/db/treatment_presence_dao.dart';
import 'core/db/referral_dao.dart';
import 'core/db/sync_meta_dao.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/repeat_scheduler.dart';
import 'core/risk/risk_scoring_service.dart';
import 'core/sla/priority_scorer.dart';
import 'core/sla/sla_evaluator.dart';
import 'core/auth/user_hierarchy_service.dart';
import 'core/sync/offline_sync_service.dart';
import 'features/dashboard/dashboard_repository.dart';
import 'features/dashboard/mission_dashboard_repository.dart';
import 'features/lock/lock_barrier.dart';
import 'features/patient/followup_repository.dart';
import 'features/patient/member_detail_repository.dart';
import 'features/patient/patient_repository.dart';
import 'features/patient/vitals_repository.dart';
import 'features/referral/referral_repository.dart';
import 'features/search/global_search_repository.dart';
import 'features/search/household_search_repository.dart';
import 'features/search/member_search_repository.dart';
import 'features/search/patient_search_repository.dart';
import 'features/household/enrollment/patient_lookup_repository.dart';
import 'features/visit/assessment_repository.dart';
import 'features/visit/encounter_repository.dart';
import 'features/visit/household_repository.dart';
import 'features/visit/observation_repository.dart';
import 'features/visit/briefing/visit_briefing_repository.dart';
import 'features/visit/programme_selection/programme_recommendation_repository.dart';
import 'features/visit/visit_controller.dart';
import 'features/training/coaching_dao.dart';
import 'features/training/coaching_repository.dart';
import 'features/assistant/assistant_repository.dart';
import 'features/worklist/worklist_repository.dart';
import 'core/sync/sync_connectivity_service.dart';

/// Remove any legacy seeded/demo test data from local SQLite.
/// This ensures only real API data is shown in the worklist.
Future<void> _clearSeededTestData(AppDatabase db) async {
  try {
    // Clear locally seeded test patients
    await db.db.delete(AppDatabase.tablePatients, where: "id LIKE 'PAT-SEED-%'");
    await db.db.delete(AppDatabase.tablePatientProgrammes, where: "patient_id LIKE 'PAT-SEED-%'");
    await db.db.delete(AppDatabase.tableFollowUps, where: "patient_id LIKE 'PAT-SEED-%'");
    
    // Clear demo referrals
    await db.db.delete('referral_status_events', where: "referral_id LIKE 'ref-demo-%'");
    await db.db.delete(AppDatabase.tableReferrals, where: "id LIKE 'ref-demo-%'");
    
    debugPrint('[main] cleared seeded/demo test data');
  } catch (e) {
    // Silently ignore — tables might not exist yet on fresh install
    debugPrint('[main] clearSeededTestData: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  // Draw behind status bar and navigation bar — true edge-to-edge.
  // SafeArea / Scaffold remain responsible for inset-aware content layout.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (kIsWeb) {
    databaseFactoryOrNull = databaseFactoryFfiWebNoWebWorker;
  }
  // Offline-first: never fetch fonts from the network. Falls back to bundled
  // assets (if declared in pubspec fonts:) then to system fonts.
  GoogleFonts.config.allowRuntimeFetching = false;
  final api = await ApiClient.create();
  final authRepo = AuthRepository(api);
  final biometric = BiometricService();
  final appDb = await AppDatabase.open().onError((e, st) async {
    if (kIsWeb) {
      debugPrint('[main] Web DB open failed ($e) — retrying with in-memory path');
      return AppDatabase.openInMemory();
    }
    throw e!;
  });
  // Clear any legacy seeded test data (PAT-SEED-* entries)
  await _clearSeededTestData(appDb);
  final authState = AuthState(
    authRepo,
    biometric,
    onWipeLocalData: appDb.wipeAllData,
  );
  authState.bootstrap(); // fire-and-forget — splash shows while bootstrap runs async
  runApp(UhisNextApp(
    api: api,
    authRepo: authRepo,
    authState: authState,
    biometric: biometric,
    appDb: appDb,
  ));
}

class UhisNextApp extends StatefulWidget {
  const UhisNextApp({
    super.key,
    required this.api,
    required this.authRepo,
    required this.authState,
    required this.biometric,
    required this.appDb,
  });

  final ApiClient api;
  final AuthRepository authRepo;
  final AuthState authState;
  final BiometricService biometric;
  final AppDatabase appDb;

  @override
  State<UhisNextApp> createState() => _UhisNextAppState();
}

class _UhisNextAppState extends State<UhisNextApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(widget.authState);
  late final PatientDao _patientDao = PatientDao(widget.appDb);
  late final PatientProgrammesDao _progDao =
      PatientProgrammesDao(widget.appDb);
  late final FollowUpDao _followUpDao = FollowUpDao(widget.appDb);
  late final ImmunisationDao _immDao = ImmunisationDao(widget.appDb);
  late final AssessmentDao _assessmentDao = AssessmentDao(widget.appDb);
  late final LocalAssessmentDao _localAssessmentDao =
      LocalAssessmentDao(widget.appDb);
  late final SyncMetaDao _syncMetaDao = SyncMetaDao(widget.appDb);
  late final HouseholdDao _householdDao = HouseholdDao(widget.appDb);
  late final MemberDao _memberDao = MemberDao(widget.appDb);
  late final PregnancySnapshotDao _pregnancySnapshotDao =
      PregnancySnapshotDao(widget.appDb);
  late final TreatmentPresenceDao _treatmentPresenceDao =
      TreatmentPresenceDao(widget.appDb);
  late final EncounterDao _encounterDao = EncounterDao(widget.appDb);
  late final LocalDashboardRepository _localDashboard = LocalDashboardRepository(
    households: _householdDao,
    members: _memberDao,
  );
  late final RiskScoringService _risk = const RiskScoringService();

  // ── Referral SLA Engine wiring (initialized early for sync) ─────────────
  late final ReferralDao _referralDao = ReferralDao(widget.appDb);

  late final OfflineSyncService _sync = OfflineSyncService(
    api: widget.api,
    auth: widget.authRepo,
    db: widget.appDb,
    patients: _patientDao,
    programmes: _progDao,
    followUps: _followUpDao,
    immunisations: _immDao,
    assessments: _assessmentDao,
    syncMeta: _syncMetaDao,
    households: _householdDao,
    members: _memberDao,
    pregnancySnapshot: _pregnancySnapshotDao,
    treatmentPresence: _treatmentPresenceDao,
    encounterDao: _encounterDao,
    // P1: share the same UserHierarchyService instance so OfflineSyncService
    // can reuse already-fetched static-data without a second user-data call.
    hierarchy: _userHierarchy,
  );
  late final WorklistRepository _worklist = WorklistRepository(
    patients: _patientDao,
    programmes: _progDao,
    followUps: _followUpDao,
    immunisations: _immDao,
    syncMeta: _syncMetaDao,
    risk: _risk,
    localAssessments: _localAssessmentDao,
    assessments: _assessmentDao,
  );
  late final PatientRepository _patientRepo = PatientRepository(
    patients: _patientDao,
    programmes: _progDao,
  );

  // ── Referral SLA Engine wiring (ReferralDao initialized above) ──────────
  late final SlaEvaluator _slaEvaluator = const SlaEvaluator();
  late final PriorityScorer _priorityScorer = const PriorityScorer();
  late final NotificationService _notifications = NotificationService();
  late final RepeatScheduler _repeatScheduler = RepeatScheduler(
    dao: _referralDao,
    notifications: _notifications,
  );
  late final ReferralRepository _referrals = ReferralRepository(
    referrals: _referralDao,
    patients: _patientDao,
    programmes: _progDao,
    followUps: _followUpDao,
    slaEvaluator: _slaEvaluator,
    priorityScorer: _priorityScorer,
    notificationScheduler: _repeatScheduler,
  );

  // ── Mission Dashboard wiring ──────────────────────────────────────────
  late final MissionDashboardRepository _missionDashboard =
      MissionDashboardRepository(
    worklist: _worklist,
    patients: _patientDao,
    referralDao: _referralDao,
    followUps: _followUpDao,
    households: _householdDao,
    slaEvaluator: _slaEvaluator,
    priorityScorer: _priorityScorer,
    pregnancySnapshot: _pregnancySnapshotDao,
    treatmentPresence: _treatmentPresenceDao,
    assessments: _assessmentDao,
    hierarchy: _userHierarchy,
  );

  // ── Assessment Repository for offline-first assessment capture ──────────
  late final AssessmentRepository _assessmentRepo = AssessmentRepository(
    dao: _localAssessmentDao,
    api: widget.api,
    auth: widget.authRepo,
    historyDao: _assessmentDao,
  );
  late final AssessmentDraftDao _draftDao = AssessmentDraftDao(widget.appDb);
  late final AiResponseCacheDao _aiCacheDao = AiResponseCacheDao(widget.appDb);
  late final UserHierarchyService _userHierarchy =
      UserHierarchyService(widget.api, widget.authRepo);

  // ── Connectivity-aware auto-sync ─────────────────────────────────────────
  // Monitors network state changes and triggers AutomaticSync (outbound push +
  // inbound warm pull) when connectivity is restored — mirrors Android's
  // ScheduledSyncWork with NetworkType.CONNECTED constraint.
  late final SyncConnectivityService _connectivitySync = SyncConnectivityService(
    assessmentRepo: _assessmentRepo,
    syncService: _sync,
    authState: widget.authState,
  );

  // ── Micro-coaching ────────────────────────────────────────────────────────
  late final CoachingDao _coachingDao = CoachingDao(widget.appDb);
  late final CoachingRepository _coachingRepo =
      CoachingRepository(_coachingDao, widget.api, widget.authRepo);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Register notification channels + rehydrate any pending repeat alarms
    // from the last session. Both are idempotent.
    unawaited(_bootstrapNotifications());
    unawaited(_coachingRepo.initialize());
    // Start connectivity monitoring for automatic offline sync retry.
    _connectivitySync.start();
    // These repositories/services are single long-lived instances for the
    // app's whole process (see the `late final` fields above — none are
    // recreated per login), so each caches session data in memory that
    // AppDatabase.wipeAllData() cannot reach. Without these hooks, the next
    // user to log in on the same device would briefly see the previous
    // user's dashboard snapshot, hierarchy/village assignment, or training
    // progress until something else happened to refresh it.
    widget.authState.registerLogoutHook(_missionDashboard.clearCache);
    widget.authState.registerLogoutHook(_userHierarchy.invalidate);
    widget.authState.registerLogoutHook(_coachingRepo.clear);
  }

  Future<void> _bootstrapNotifications() async {
    try {
      await _notifications.initialize();
      await _repeatScheduler.rehydrateOnBoot();
      // NOTE: Demo referral seeding moved to dashboard_screen.dart
      // to run after login when user context is available
    } catch (e, st) {
      // Notifications are a non-critical surface; failure should not block
      // app startup. Surface to console for now; once a telemetry sink lands
      // (worklist.md §8 / referral-sla-engine.md §8), route through it.
      debugPrint('[notifications] bootstrap failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _lockDebounce?.cancel();
    _connectivitySync.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Timer? _lockDebounce;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Lock after 7 seconds — lets the SK glance at notifications or switch
      // apps briefly without being forced to re-authenticate every time.
      _lockDebounce ??= Timer(const Duration(seconds: 7), () {
        _lockDebounce = null;
        widget.authState.lock();
      });
    } else if (state == AppLifecycleState.inactive) {
      // Inactive is transient (notification shade, app switcher). Only arm the
      // timer if one isn't already running from a paused state.
      _lockDebounce ??= Timer(const Duration(seconds: 7), () {
        _lockDebounce = null;
        widget.authState.lock();
      });
    } else if (state == AppLifecycleState.resumed) {
      _lockDebounce?.cancel();
      _lockDebounce = null;
      // SLA states drift while the device sleeps; refresh on every resume.
      // Fire-and-forget — UI listens to ReferralRepository.changes.
      unawaited(_referrals
          .recomputeAllAfterSync()
          .then((_) => _referrals.dispatchPendingNotifications()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: widget.api),
        Provider<AuthRepository>.value(value: widget.authRepo),
        Provider<BiometricService>.value(value: widget.biometric),
        Provider<AppDatabase>.value(value: widget.appDb),
        ChangeNotifierProvider<AuthState>.value(value: widget.authState),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        Provider<DashboardRepository>(
            create: (_) => DashboardRepository(
                widget.api, widget.authRepo, _householdDao, _memberDao)),
        Provider<PatientSearchRepository>(
            create: (_) => PatientSearchRepository(widget.api)),
        // Remote NID → existing-patient lookup for enrollment de-duplication
        Provider<PatientLookupRepository>(
            create: (_) => PatientLookupRepository(widget.api)),
        Provider<MemberSearchRepository>(
            create: (_) =>
                MemberSearchRepository(widget.api, _memberDao)),
        Provider<HouseholdSearchRepository>(
            create: (_) => HouseholdSearchRepository(_householdDao)),
        ProxyProvider2<MemberSearchRepository, HouseholdSearchRepository,
            GlobalSearchRepository>(
          update: (_, m, h, _) => GlobalSearchRepository(m, h),
        ),
        Provider<RiskScoringService>.value(value: _risk),
        ChangeNotifierProvider<OfflineSyncService>.value(value: _sync),
        Provider<WorklistRepository>.value(value: _worklist),
        Provider<PatientRepository>.value(value: _patientRepo),
        Provider<ReferralDao>.value(value: _referralDao),
        Provider<SlaEvaluator>.value(value: _slaEvaluator),
        Provider<PriorityScorer>.value(value: _priorityScorer),
        Provider<NotificationService>.value(value: _notifications),
        Provider<RepeatScheduler>.value(value: _repeatScheduler),
        Provider<ReferralRepository>.value(value: _referrals),
        Provider<MissionDashboardRepository>.value(value: _missionDashboard),
        Provider<PatientDao>.value(value: _patientDao),
        Provider<HouseholdDao>.value(value: _householdDao),
        Provider<MemberDao>.value(value: _memberDao),
        Provider<FollowUpDao>.value(value: _followUpDao),
        Provider<AssessmentDao>.value(value: _assessmentDao),
        Provider<LocalAssessmentDao>.value(value: _localAssessmentDao),
        Provider<LocalDashboardRepository>.value(value: _localDashboard),
        Provider<PatientProgrammesDao>.value(value: _progDao),
        Provider<PregnancySnapshotDao>.value(value: _pregnancySnapshotDao),
        Provider<ObservationRepository>(
            create: (_) => ObservationRepository(widget.api)),
        Provider<MemberDetailRepository>(
            create: (ctx) => MemberDetailRepository(
                  widget.api,
                  widget.authRepo,
                  members: _memberDao,
                  offlineSync: _sync,
                  observations: ctx.read<ObservationRepository>(),
                )),
        // Visit flow providers
        Provider<EncounterDao>.value(value: _encounterDao),
        Provider<EncounterRepository>(
            create: (ctx) => EncounterRepository(
                  widget.api,
                  ctx.read<EncounterDao>(),
                  offlineSync: _sync,
                )),
        Provider<VitalsRepository>(
            create: (ctx) => VitalsRepository(
                  widget.api,
                  encounters: ctx.read<EncounterDao>(),
                  observations: ctx.read<ObservationRepository>(),
                )),
        Provider<FollowUpRepository>(
            create: (_) =>
                FollowUpRepository(widget.api, dao: _followUpDao)),
        Provider<HouseholdRepository>(
            create: (_) => HouseholdRepository(widget.api,
                members: _memberDao,
                followUps: _followUpDao,
                immunisations: _immDao)),
        ChangeNotifierProxyProvider<EncounterRepository, VisitController>(
          create: (ctx) => VisitController(ctx.read<EncounterRepository>()),
          update: (_, repo, prev) => prev ?? VisitController(repo),
        ),
        // Assessment offline-first repository
        ChangeNotifierProvider<AssessmentRepository>.value(
            value: _assessmentRepo),
        Provider<AssessmentDraftDao>.value(value: _draftDao),
        Provider<AiResponseCacheDao>.value(value: _aiCacheDao),
        // AI Visit Briefing service
        Provider<VisitBriefingRepository>(
            create: (_) =>
                VisitBriefingRepository(widget.api, cache: _aiCacheDao)),
        // AI Assistant — conversational Q&A (Tab 3)
        Provider<AssistantRepository>(
            create: (_) => AssistantRepository(widget.api)),
        // AI Programme Recommendation — Step 2 picker grounded in BRAC + BD
        // national clinical guidelines. Caches per-patient via _aiCacheDao
        // so re-entering Step 2 doesn't re-hit the API.
        Provider<ProgrammeRecommendationRepository>(
            create: (_) => ProgrammeRecommendationRepository(widget.api,
                cache: _aiCacheDao)),
        // AI Scribe API service
        Provider<ScribeApiService>(
            create: (_) => ScribeApiService(widget.api)),
        // Real-Time ASR (Beta) — live streaming transcription + extraction
        Provider<RealtimeAsrService>(
            create: (_) => RealtimeAsrService(widget.api)),
        // Persisted scribe engine preference (Gemini vs Live ASR)
        ChangeNotifierProvider<ScribeEngineNotifier>(
          create: (_) =>
              ScribeEngineNotifier(const FlutterSecureStorage())..load(),
        ),
        // SK → SS → sub-village hierarchy (session cache, invalidated on logout)
        ChangeNotifierProvider<UserHierarchyService>.value(
            value: _userHierarchy),
        // EPI immunisation DAO — exposed for ImmunisationTimelineScreen + PatientContextBuilder
        Provider<ImmunisationDao>.value(value: _immDao),
        // Micro-coaching: module library + progress (offline-first, syncs from spice-coaching)
        ChangeNotifierProvider<CoachingRepository>.value(value: _coachingRepo),
      ],
      child: Builder(
        builder: (context) {
          final themeProvider = context.watch<ThemeProvider>();
          return Provider<GoRouter>.value(
            value: _router,
            // LockBarrier must be outside MaterialApp.router to avoid rebuild
            // conflicts when GoRouter's refreshListenable triggers.
            // Wrap in Directionality since it's outside MaterialApp.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: _LockBarrierOverlay(
                child: MaterialApp.router(
                  title: AppStrings.appName,
                  theme: buildAppTheme(),
                  darkTheme: buildDarkTheme(),
                  themeMode: themeProvider.mode,
                  routerConfig: _router,
                  debugShowCheckedModeBanner: false,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Separate widget to isolate LockBarrier rebuild scope from router rebuilds.
/// Uses direct listener instead of Selector to avoid Provider inheritance
/// conflicts when GoRouter's refreshListenable triggers simultaneously.
class _LockBarrierOverlay extends StatefulWidget {
  const _LockBarrierOverlay({required this.child});
  final Widget? child;

  @override
  State<_LockBarrierOverlay> createState() => _LockBarrierOverlayState();
}

class _LockBarrierOverlayState extends State<_LockBarrierOverlay> {
  AuthState? _authState;
  GoRouter? _router;
  bool _showBarrier = false;
  bool _updateScheduled = false;

  void _onAuthOrRouteChanged() {
    // Defer setState to the next frame to avoid conflicting with GoRouter's
    // rebuild triggered by the same notifyListeners() call.
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) return;
      _updateBarrierState();
    });
  }

  void _updateBarrierState() {
    final auth = _authState;
    if (auth == null) return;
    // Suppress barrier when the user navigated to the PIN entry screen —
    // the barrier would otherwise sit on top of PinUnlockScreen, blocking it.
    final loc = _router?.routerDelegate.currentConfiguration.uri.path ?? '';
    final shouldShow =
        auth.status == AuthStatus.signedIn &&
        auth.locked &&
        auth.reentryEnabled &&
        loc != '/pin-unlock';
    if (shouldShow != _showBarrier) {
      setState(() => _showBarrier = shouldShow);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAuth = context.read<AuthState>();
    if (_authState != newAuth) {
      _authState?.removeListener(_onAuthOrRouteChanged);
      _authState = newAuth;
      _authState!.addListener(_onAuthOrRouteChanged);
      // Defer initial state check to avoid build scope conflicts when
      // GoRouter's refreshListenable triggers simultaneously.
      _onAuthOrRouteChanged();
    }
    final newRouter = context.read<GoRouter>();
    if (_router != newRouter) {
      _router?.routerDelegate.removeListener(_onAuthOrRouteChanged);
      _router = newRouter;
      _router!.routerDelegate.addListener(_onAuthOrRouteChanged);
    }
  }

  @override
  void dispose() {
    _authState?.removeListener(_onAuthOrRouteChanged);
    _router?.routerDelegate.removeListener(_onAuthOrRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = themeProvider.mode == ThemeMode.dark ||
        (themeProvider.mode == ThemeMode.system &&
            brightness == Brightness.dark);
    final theme = isDark ? buildDarkTheme() : buildAppTheme();
    return Stack(
      children: [
        widget.child ?? const SizedBox.shrink(),
        if (_showBarrier)
          Positioned.fill(
            child: MediaQuery.fromView(
              view: View.of(context),
              child: Theme(
                data: theme,
                child: const LockBarrier(),
              ),
            ),
          ),
      ],
    );
  }
}
