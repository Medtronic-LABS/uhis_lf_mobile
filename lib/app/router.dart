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
import 'bottom_nav.dart';

/// Navigation keys for each tab's navigator.
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _patientsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'patients');
final _tasksNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'tasks');
final _mapNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'map');

GoRouter buildRouter(AuthState auth) {
  return GoRouter(
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
                builder: (_, __) => const ReferralListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => ReferralDetailScreen(
                      patientId: state.pathParameters['id']!,
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
                builder: (_, __) => const MapPlaceholderScreen(),
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
        redirect: (_, __) => '/patients',
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
