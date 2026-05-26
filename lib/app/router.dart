import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_state.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/lock/lock_screen.dart';
import '../features/login/login_screen.dart';
import '../features/search/household_search_screen.dart';
import '../features/search/patient_search_screen.dart';

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
          if (auth.biometricEnabled) {
            // Cold-start or post-expiry with biometric still enrolled.
            // Bounce login attempts back through /lock unless user explicitly
            // asked for the password fallback.
            if (loc.startsWith('/login') &&
                state.uri.queryParameters['from'] == 'lock') {
              return null;
            }
            if (loc == '/lock') return null;
            return '/lock';
          }
          if (loc.startsWith('/login')) return null;
          return '/login';
        case AuthStatus.signedIn:
          // Mid-session lock is overlaid by LockBarrier — no route swap, so
          // route stays where the user was. Cold-start /lock is still
          // reachable via signedOut + biometricEnabled below.
          if (loc.startsWith('/login') || loc == '/' || loc == '/lock') {
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
        path: '/search/patient',
        builder: (_, __) => const PatientSearchScreen(),
      ),
      GoRoute(
        path: '/search/household',
        builder: (_, __) => const HouseholdSearchScreen(),
      ),
    ],
  );
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
