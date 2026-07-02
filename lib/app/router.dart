import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_state.dart';
import '../core/models/programme.dart';
import '../core/constants/app_strings.dart';
import '../core/models/dashboard_tier.dart';
import '../features/dashboard/mission_dashboard_screen.dart';
import '../features/household/household_detail_screen.dart';
import '../features/household/household_list_screen.dart';
import '../features/lock/lock_screen.dart';
import '../features/login/login_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/patient/patient_context_screen.dart';
import '../features/pin/pin_setup_screen.dart';
import '../features/pin/pin_unlock_screen.dart';
import '../features/referral/referral_detail_screen.dart';
import '../features/referral/referral_list_screen.dart';
import '../features/sync/sync_progress_screen.dart';
import '../features/counselling/counselling_screen.dart';
import '../features/teleconsult/teleconsult_screen.dart';
import '../features/training/training_screen.dart';
import '../features/visit/briefing/visit_briefing_screen.dart';
import '../features/visit/visit_flow_screen.dart';
import '../features/household/enrollment/enrollment_nid_scan_screen.dart';
import '../features/household/enrollment/create_household_screen.dart';
import '../features/household/enrollment/household_head_info_screen.dart';
import '../features/household/enrollment/household_created_screen.dart';
import '../features/household/enrollment/add_household_member_screen.dart';
import '../features/household/enrollment/enrollment_controller.dart';
import 'bottom_nav.dart';

/// Navigation keys for each tab's navigator.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _patientsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'patients');
final _tasksNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'tasks');
final _mapNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'assistant');

GoRouter buildRouter(AuthState auth) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: auth,
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/' ? null : '/';
        case AuthStatus.signedOut:
          if (!auth.splashReady && loc == '/') return null;
          if (auth.reentryEnabled) {
            // Cold-start or post-expiry with biometric or PIN still enrolled.
            // Bounce login attempts back through /lock unless user explicitly
            // asked for the password fallback.
            if (loc.startsWith('/login') &&
                state.uri.queryParameters['from'] == 'lock') {
              return null;
            }
            if (loc == '/lock' || loc == '/pin-unlock') return null;
            return '/lock';
          }
          if (loc.startsWith('/login')) return null;
          return '/login';
        case AuthStatus.signedIn:
          if (!auth.splashReady && loc == '/') return null;
          // Mid-session lock is overlaid by LockBarrier — no route swap, so
          // route stays where the user was. Cold-start /lock is still
          // reachable via signedOut + reentryEnabled below.
          // /pin-setup and /onboarding are signed-in destinations,
          // so they are intentionally NOT redirected away.
          if (loc.startsWith('/login') || loc == '/' || loc == '/lock') {
            // First-run: redirect to onboarding if not completed yet
            if (!auth.onboardingComplete && !auth.pinEnabled) {
              return '/onboarding';
            }
            return '/home';
          }
          // Safety net: first-run guard for any in-app route (e.g. /home after sync).
          if (!auth.onboardingComplete &&
              !auth.pinEnabled &&
              loc != '/onboarding' &&
              loc != '/pin-setup' &&
              loc != '/sync') {
            return '/onboarding';
          }
          return null;
      }
    },
    routes: [
      // ─────────────────────────────────────────────────────────────────────
      // Pre-auth routes
      // ─────────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        builder: (_, _) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          fromLock: state.uri.queryParameters['from'] == 'lock',
        ),
      ),
      GoRoute(
        path: '/lock',
        builder: (_, _) => const LockScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/sync',
        builder: (_, _) => const SyncProgressScreen(),
      ),
      GoRoute(
        path: '/pin-setup',
        builder: (_, _) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/pin-unlock',
        builder: (_, _) => const PinUnlockScreen(),
      ),

      // ─────────────────────────────────────────────────────────────────────
      // Main app with bottom navigation shell
      // ─────────────────────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => BottomNavShell(
          navigationShell: navigationShell,
        ),
        branches: [
          // Tab 0: Home
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),

          // Tab 1: Patients
          StatefulShellBranch(
            navigatorKey: _patientsNavigatorKey,
            routes: [
              GoRoute(
                path: '/patients',
                builder: (_, state) {
                  // Parse tier query parameter for deep-link filtering
                  final tierParam = state.uri.queryParameters['tier'];
                  DashboardTier? initialTier;
                  if (tierParam != null && tierParam.isNotEmpty) {
                    initialTier = DashboardTier.values
                        .cast<DashboardTier?>()
                        .firstWhere(
                          (t) => t?.name == tierParam,
                          orElse: () => null,
                        );
                  }
                  return HouseholdListScreen(
                    mode: HouseholdListMode.members,
                    initialTier: initialTier,
                  );
                },
                routes: [
                  // Households view (same tab, different mode)
                  GoRoute(
                    path: 'households',
                    builder: (_, _) => const HouseholdListScreen(
                      mode: HouseholdListMode.households,
                    ),
                  ),
                  GoRoute(
                    path: 'household/:id',
                    builder: (_, state) {
                      final extra = state.extra;
                      if (extra is HouseholdDetailData) {
                        return HouseholdDetailScreen(household: extra);
                      }
                      // Fallback: create minimal data from route params
                      final id = state.pathParameters['id'] ?? '';
                      return HouseholdDetailScreen(
                        household: HouseholdDetailData(
                          id: id,
                          householdNo: id,
                          name: null,
                          village: null,
                          memberCount: 0,
                          members: const [],
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (_, state) {
                      // Handle different types of extra data
                      Map<String, dynamic>? memberData;
                      final extra = state.extra;
                      if (extra is Map<String, dynamic>) {
                        memberData = extra;
                      } else if (extra is Map) {
                        memberData = Map<String, dynamic>.from(extra);
                      }
                      // Read origin from query params for return navigation
                      final origin = state.uri.queryParameters['origin'];
                      // Ignore HouseholdDetailData - it's for household routes, not patient routes
                      // This can happen during tab switching in StatefulShellRoute
                      return PatientContextScreen(
                        patientId: state.pathParameters['id']!,
                        memberData: memberData,
                        origin: origin,
                      );
                    },
                  ),
                  // Visit flow routes
                  GoRoute(
                    path: 'visit/:visitId/briefing',
                    name: 'visit-briefing',
                    pageBuilder: (context, state) {
                      Map<String, dynamic>? extra;
                      if (state.extra is Map<String, dynamic>) {
                        extra = state.extra as Map<String, dynamic>;
                      } else if (state.extra is Map) {
                        extra = Map<String, dynamic>.from(state.extra as Map);
                      }
                      final origin = state.uri.queryParameters['origin'];
                      final rawProgrammes =
                          extra?['programmes'] as List<dynamic>?;
                      final programmes = rawProgrammes
                              ?.map((e) => Programme.fromString(e.toString()))
                              .toSet() ??
                          <Programme>{};
                      return MaterialPage(
                        key: ValueKey(
                            'visit-briefing-${state.pathParameters['visitId']}'),
                        child: VisitBriefingScreen(
                          encounterId: state.pathParameters['visitId']!,
                          patientId: extra?['patientId'] as String? ?? '',
                          patientName: extra?['patientName'] as String?,
                          patientAge: extra?['patientAge'] as int?,
                          patientGender: extra?['patientGender'] as String?,
                          householdId: extra?['householdId'] as String?,
                          memberId: extra?['memberId'] as String?,
                          programmes: programmes,
                          origin: origin,
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'visit/:visitId/flow',
                    name: 'visit-flow',
                    pageBuilder: (context, state) {
                      Map<String, dynamic>? extra;
                      if (state.extra is Map<String, dynamic>) {
                        extra = state.extra as Map<String, dynamic>;
                      } else if (state.extra is Map) {
                        extra = Map<String, dynamic>.from(state.extra as Map);
                      }
                      final origin = state.uri.queryParameters['origin'];
                      return MaterialPage(
                        key: ValueKey(
                            'visit-flow-${state.pathParameters['visitId']}'),
                        child: VisitFlowScreen(
                          visitId: state.pathParameters['visitId']!,
                          patientId: extra?['patientId'] as String? ?? '',
                          memberId: extra?['memberId'] as String?,
                          householdId: extra?['householdId'] as String?,
                          villageId: extra?['villageId'] as String?,
                          householdMemberLocalId:
                              extra?['householdMemberLocalId'] as int?,
                          patientAge: extra?['patientAge'] as int?,
                          patientName: extra?['patientName'] as String?,
                          patientGender: extra?['patientGender'] as String?,
                          gestationalWeeks:
                              extra?['gestationalWeeks'] as int?,
                          origin: origin,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Tab 2: Tasks
          StatefulShellBranch(
            navigatorKey: _tasksNavigatorKey,
            routes: [
              GoRoute(
                path: '/tasks',
                name: 'tasks-list',
                pageBuilder: (context, state) => const MaterialPage(
                  key: ValueKey('tasks-list-page'),
                  child: ReferralListScreen(),
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    name: 'task-detail',
                    pageBuilder: (context, state) => MaterialPage(
                      key: ValueKey('task-detail-${state.pathParameters['id']}'),
                      child: ReferralDetailScreen(
                        patientId: state.pathParameters['id']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Tab 3: Assistant
          StatefulShellBranch(
            navigatorKey: _mapNavigatorKey,
            routes: [
              GoRoute(
                path: '/map',
                name: 'map',
                pageBuilder: (context, state) => const MaterialPage(
                  key: ValueKey('assistant-page'),
                  child: AssistantPlaceholderScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // ─────────────────────────────────────────────────────────────────────
      // Household enrollment flow routes
      // ─────────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/household/enrollment/nid-scan',
        pageBuilder: (context, state) => MaterialPage(
          key: const ValueKey('enrollment-nid-scan'),
          child: ChangeNotifierProvider(
            create: (_) => EnrollmentController(),
            child: const EnrollmentNidScanScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/household/enrollment/create',
        pageBuilder: (context, state) => MaterialPage(
          key: const ValueKey('enrollment-create'),
          child: Consumer<EnrollmentController>(
            builder: (context, controller, _) {
              return ChangeNotifierProvider.value(
                value: controller,
                child: const CreateHouseholdScreen(),
              );
            },
          ),
        ),
      ),
      GoRoute(
        path: '/household/enrollment/head-info',
        pageBuilder: (context, state) => MaterialPage(
          key: const ValueKey('enrollment-head-info'),
          child: Consumer<EnrollmentController>(
            builder: (context, controller, _) {
              return ChangeNotifierProvider.value(
                value: controller,
                child: const HouseholdHeadInfoScreen(),
              );
            },
          ),
        ),
      ),
      GoRoute(
        path: '/household/enrollment/success',
        pageBuilder: (context, state) => MaterialPage(
          key: const ValueKey('enrollment-success'),
          child: Consumer<EnrollmentController>(
            builder: (context, controller, _) {
              return ChangeNotifierProvider.value(
                value: controller,
                child: const HouseholdCreatedScreen(),
              );
            },
          ),
        ),
      ),
      GoRoute(
        path: '/household/enrollment/add-member',
        pageBuilder: (context, state) => MaterialPage(
          key: const ValueKey('enrollment-add-member'),
          child: Consumer<EnrollmentController>(
            builder: (context, controller, _) {
              return ChangeNotifierProvider.value(
                value: controller,
                child: const AddHouseholdMemberScreen(),
              );
            },
          ),
        ),
      ),

      // ─────────────────────────────────────────────────────────────────────
      // Standalone feature routes (full-screen, outside the shell)
      // ─────────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/teleconsult',
        name: 'teleconsult',
        pageBuilder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : <String, dynamic>{};
          return MaterialPage(
            key: const ValueKey('teleconsult-page'),
            child: TeleconsultScreen(
              patientLabel: extra['patientLabel'] as String? ?? '',
              patientId: extra['patientId'] as String? ?? '',
            ),
          );
        },
      ),
      GoRoute(
        path: '/counselling',
        name: 'counselling',
        pageBuilder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : <String, dynamic>{};
          return MaterialPage(
            key: const ValueKey('counselling-page'),
            child: CounsellingScreen(
              patientLabel: extra['patientLabel'] as String? ?? '',
              patientId: extra['patientId'] as String? ?? '',
            ),
          );
        },
      ),
      GoRoute(
        path: '/training',
        name: 'training',
        pageBuilder: (context, state) => const MaterialPage(
          key: ValueKey('training-page'),
          child: TrainingScreen(),
        ),
      ),

      // ─────────────────────────────────────────────────────────────────────
      // Legacy routes (for backward compatibility)
      // ─────────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/dashboard',
        redirect: (_, _) => '/home',
      ),
      GoRoute(
        path: '/households',
        redirect: (_, _) => '/patients/households',
      ),
      GoRoute(
        path: '/households/:id',
        redirect: (_, state) => '/patients/household/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '/members',
        redirect: (_, _) => '/patients',
      ),
      GoRoute(
        path: '/referrals',
        redirect: (_, _) => '/tasks',
      ),
      GoRoute(
        path: '/patient/:id',
        redirect: (_, state) => '/patients/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '/patient/:id/referrals',
        redirect: (_, state) => '/tasks/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '/household/:id',
        redirect: (_, state) => '/patients/household/${state.pathParameters['id']}',
      ),
    ],
  );
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final AnimationController _dotsCtrl;

  // Entry animations (driven by _enterCtrl, 2500 ms total)
  late final Animation<double> _logoScale;
  late final Animation<double> _logoTy;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _bnFade;
  late final Animation<Offset> _bnSlide;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _badgesFade;
  late final Animation<Offset> _badgesSlide;
  late final Animation<double> _dotsFade;

  static const _slideOffset = Offset(0, 0.08);
  static const _badges = [
    'AI Triage', 'On-device CDSS', 'Teleconsult', 'Offline-first', 'WhatsApp',
  ];

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..forward();

    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Logo: spring bounce, 300–920 ms
    final logoInterval = CurvedAnimation(
      parent: _enterCtrl,
      curve: const Interval(0.12, 0.37, curve: Curves.elasticOut),
    );
    _logoScale = Tween<double>(begin: 0.4, end: 1.0).animate(logoInterval);
    _logoTy    = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: const Interval(0.12, 0.37, curve: Curves.easeOut)),
    );

    // Title: 800–1300 ms
    final titleAnim = CurvedAnimation(parent: _enterCtrl, curve: const Interval(0.32, 0.52, curve: Curves.easeOut));
    _titleFade  = Tween<double>(begin: 0.0, end: 1.0).animate(titleAnim);
    _titleSlide = Tween<Offset>(begin: _slideOffset, end: Offset.zero).animate(titleAnim);

    // Bengali: 1000–1500 ms
    final bnAnim = CurvedAnimation(parent: _enterCtrl, curve: const Interval(0.40, 0.60, curve: Curves.easeOut));
    _bnFade  = Tween<double>(begin: 0.0, end: 1.0).animate(bnAnim);
    _bnSlide = Tween<Offset>(begin: _slideOffset, end: Offset.zero).animate(bnAnim);

    // Tagline: 1200–1700 ms
    final taglineAnim = CurvedAnimation(parent: _enterCtrl, curve: const Interval(0.48, 0.68, curve: Curves.easeOut));
    _taglineFade  = Tween<double>(begin: 0.0, end: 1.0).animate(taglineAnim);
    _taglineSlide = Tween<Offset>(begin: _slideOffset, end: Offset.zero).animate(taglineAnim);

    // Badges: 1400–1900 ms
    final badgesAnim = CurvedAnimation(parent: _enterCtrl, curve: const Interval(0.56, 0.76, curve: Curves.easeOut));
    _badgesFade  = Tween<double>(begin: 0.0, end: 1.0).animate(badgesAnim);
    _badgesSlide = Tween<Offset>(begin: _slideOffset, end: Offset.zero).animate(badgesAnim);

    // Dots container: 1500–1900 ms
    _dotsFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: const Interval(0.60, 0.76, curve: Curves.easeOut)),
    );

    // Trigger router transition after 2.5 s
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) context.read<AuthState>().setSplashReady();
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  Widget _buildLogoBox() {
    return AnimatedBuilder(
      animation: _enterCtrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _logoTy.value),
        child: Transform.scale(
          scale: _logoScale.value,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE8356D), Color(0xFFb01f52)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE8356D).withValues(alpha: 0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: CustomPaint(
              painter: _SplashIconPainter(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fade({required Animation<double> fade, required Animation<Offset> slide, required Widget child}) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }

  Widget _buildBadges() {
    return FadeTransition(
      opacity: _badgesFade,
      child: SlideTransition(
        position: _badgesSlide,
        child: SizedBox(
          width: 280,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: _badges.map((label) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.80),
                ),
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B2B5E),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogoBox(),
              const SizedBox(height: 20),
              _fade(
                fade: _titleFade, slide: _titleSlide,
                child: const Text(
                  LockStrings.aponSushashthya,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _fade(
                fade: _bnFade, slide: _bnSlide,
                child: Text(
                  LockStrings.aponSushashthyaBn,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.50),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _fade(
                fade: _taglineFade, slide: _taglineSlide,
                child: SizedBox(
                  width: 240,
                  child: Text(
                    LockStrings.splashTagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildBadges(),
              const SizedBox(height: 40),
              FadeTransition(
                opacity: _dotsFade,
                child: _AnimatedDots(controller: _dotsCtrl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Person silhouette + community health pulse arc — from prototype SVG paths
class _SplashIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width / 80; // scale factor relative to 80dp box

    // Person head
    canvas.drawCircle(Offset(cx, cy - 10 * s), 5 * s, paint);
    // Shoulders arc
    final shoulderPath = Path()
      ..moveTo(cx - 10 * s, cy + 12 * s)
      ..quadraticBezierTo(cx, cy + 5 * s, cx + 10 * s, cy + 12 * s);
    canvas.drawPath(shoulderPath, paint);
    // Outer pulse arc
    final arcPaint = Paint()
      ..color = Colors.white.withAlpha(0x99)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - 10 * s), width: 22 * s, height: 22 * s),
      pi * 1.1, pi * 0.8, false, arcPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - 10 * s), width: 34 * s, height: 34 * s),
      pi * 1.15, pi * 0.7, false,
      arcPaint..color = Colors.white.withAlpha(0x55),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _AnimatedDots extends StatelessWidget {
  const _AnimatedDots({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (n) {
        return Padding(
          padding: EdgeInsets.only(left: n == 0 ? 0 : 8),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final phase = (controller.value + n * 0.333) % 1.0;
              final t = sin(phase * pi).clamp(0.0, 1.0);
              final color = Color.lerp(
                Colors.white.withValues(alpha: 0.25),
                const Color(0xFFE8356D),
                t,
              )!;
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              );
            },
          ),
        );
      }),
    );
  }
}
