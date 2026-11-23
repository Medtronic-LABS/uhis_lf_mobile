import 'package:flutter/widgets.dart';

import 'analytics.dart';

/// Sends a GA `screen_view` whenever a named page becomes the top route
/// (LEAP-152).
///
/// Screens are identified by the route's *name* — the GoRoute name or path
/// template (`:id`, never the real id) — mapped to a stable screen name.
/// Unnamed routes (plain `MaterialPageRoute`s, dialogs, sheets) are ignored;
/// those screens log themselves with [Analytics.screen].
///
/// A navigator observer can belong to one navigator only, so the router
/// creates one instance per navigator (root, each tab branch, shells).
class AnalyticsRouteObserver extends NavigatorObserver {
  /// GoRoute name / path template → GA screen name. Routes not listed fall
  /// back to [screenNameFor]'s normalisation.
  static const Map<String, String> _names = {
    '/': 'splash',
    '/login': 'login',
    '/lock': 'lock',
    '/forgot-password': 'forgot_password',
    '/onboarding': 'onboarding',
    '/sync': 'sync_progress',
    '/offline-sync': 'offline_sync',
    '/pin-setup': 'pin_setup',
    '/pin-unlock': 'pin_unlock',
    '/home': 'dashboard',
    '/patients': 'patients_list',
    'households': 'patients_list',
    'household/:id': 'household_detail',
    ':id': 'patient_profile',
  };

  /// GA screen name for a route name, or `null` to skip it.
  @visibleForTesting
  static String? screenNameFor(String? routeName) {
    if (routeName == null || routeName.isEmpty) return null;
    final mapped = _names[routeName];
    if (mapped != null) return mapped;
    // Fallback: normalise a name/path template into snake_case and drop
    // path parameters so no id can ever reach GA.
    final cleaned = routeName
        .split('/')
        .where((s) => s.isNotEmpty && !s.startsWith(':'))
        .join('_')
        .replaceAll('-', '_')
        .toLowerCase();
    return cleaned.isEmpty ? null : cleaned;
  }

  void _report(Route<dynamic>? route) {
    if (route is! PageRoute) return; // dialogs/sheets log themselves
    final name = screenNameFor(route.settings.name);
    if (name != null) Analytics.screen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);
}
