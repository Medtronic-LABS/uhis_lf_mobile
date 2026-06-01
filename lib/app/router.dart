import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_state.dart';
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
import '../features/visit/visit_assessment_step.dart';
import '../features/visit/visit_landing_screen.dart';
import '../features/visit/visit_triage_step.dart';
import '../features/visit/visit_vitals_step.dart';
import 'bottom_nav.dart';

/// Navigation keys for each tab's navigator.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _patientsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'patients');
final _tasksNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'tasks');
final _mapNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'map');

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
          return null;
      }
    },
    routes: [
      // ─────────────────────────────────────────────────────────────────────
      // Pre-auth routes
      // ─────────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        builder: (_, __) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          fromLock: state.uri.queryParameters['from'] == 'lock',
        ),
      ),
      GoRoute(
        path: '/lock',
        builder: (_, __) => const LockScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/sync',
        builder: (_, __) => const SyncProgressScreen(),
      ),
      GoRoute(
        path: '/pin-setup',
        builder: (_, __) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/pin-unlock',
        builder: (_, __) => const PinUnlockScreen(),
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
                builder: (_, __) => const DashboardScreen(),
              ),
            ],
          ),

          // Tab 1: Patients
          StatefulShellBranch(
            navigatorKey: _patientsNavigatorKey,
            routes: [
              GoRoute(
                path: '/patients',
                builder: (_, __) => const HouseholdListScreen(
                  mode: HouseholdListMode.members,
                ),
                routes: [
                  // Households view (same tab, different mode)
                  GoRoute(
                    path: 'households',
                    builder: (_, __) => const HouseholdListScreen(
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
                    builder: (_, state) => PatientContextScreen(
                      patientId: state.pathParameters['id']!,
                      memberData: state.extra as Map<String, dynamic>?,
                    ),
                  ),
                  // Visit flow routes
                  GoRoute(
                    path: 'visit/:patientId/start',
                    name: 'visit-start',
                    pageBuilder: (context, state) => MaterialPage(
                      key: ValueKey('visit-start-${state.pathParameters['patientId']}'),
                      child: VisitLandingScreen(
                        patientId: state.pathParameters['patientId']!,
                        data: state.extra as VisitLandingData?,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'visit/:visitId/triage',
                    name: 'visit-triage',
                    pageBuilder: (context, state) => MaterialPage(
                      key: ValueKey('visit-triage-${state.pathParameters['visitId']}'),
                      child: VisitTriageStep(
                        visitId: state.pathParameters['visitId']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'visit/:visitId/vitals',
                    name: 'visit-vitals',
                    pageBuilder: (context, state) => MaterialPage(
                      key: ValueKey('visit-vitals-${state.pathParameters['visitId']}'),
                      child: VisitVitalsStep(
                        visitId: state.pathParameters['visitId']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'visit/:visitId/assessment/:programme',
                    name: 'visit-assessment',
                    pageBuilder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      return MaterialPage(
                        key: ValueKey('visit-assessment-${state.pathParameters['visitId']}-${state.pathParameters['programme']}'),
                        child: VisitAssessmentStep(
                          visitId: state.pathParameters['visitId']!,
                          programme: state.pathParameters['programme']!,
                          patientId: extra?['patientId'] as String?,
                          memberId: extra?['memberId'] as String?,
                          householdId: extra?['householdId'] as String?,
                          villageId: extra?['villageId'] as String?,
                          householdMemberLocalId:
                              extra?['householdMemberLocalId'] as int?,
                          patientAge: extra?['patientAge'] as int?,
                          gestationalWeeks: extra?['gestationalWeeks'] as int?,
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

          // Tab 3: Map
          StatefulShellBranch(
            navigatorKey: _mapNavigatorKey,
            routes: [
              GoRoute(
                path: '/map',
                name: 'map',
                pageBuilder: (context, state) => const MaterialPage(
                  key: ValueKey('map-page'),
                  child: MapPlaceholderScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // ─────────────────────────────────────────────────────────────────────
      // Legacy routes (for backward compatibility)
      // ─────────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/dashboard',
        redirect: (_, __) => '/home',
      ),
      GoRoute(
        path: '/households',
        redirect: (_, __) => '/patients/households',
      ),
      GoRoute(
        path: '/households/:id',
        redirect: (_, state) => '/patients/household/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '/members',
        redirect: (_, __) => '/patients',
      ),
      GoRoute(
        path: '/referrals',
        redirect: (_, __) => '/tasks',
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

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/app-logo-name.png',
                height: 64,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
}
