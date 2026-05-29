import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_state.dart';
import '../features/dashboard/dashboard_screen.dart';
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
            return '/dashboard';
          }
          return null;
      }
    },
    routes: [
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
        path: '/dashboard',
        builder: (_, __) => const DashboardScreen(),
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
      GoRoute(
        path: '/households',
        builder: (_, __) => const HouseholdListScreen(
          mode: HouseholdListMode.households,
        ),
      ),
      GoRoute(
        path: '/members',
        builder: (_, __) => const HouseholdListScreen(
          mode: HouseholdListMode.members,
        ),
      ),
      GoRoute(
        path: '/household/:id',
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
        path: '/patient/:id',
        builder: (_, state) => PatientContextScreen(
          patientId: state.pathParameters['id']!,
          memberData: state.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(
        path: '/patient/:id/referrals',
        builder: (_, state) => ReferralDetailScreen(
          patientId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/referrals',
        builder: (_, __) => const ReferralListScreen(),
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
