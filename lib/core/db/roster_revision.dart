import 'package:flutter/foundation.dart';

/// Bumped whenever a household or member is created locally.
///
/// Screens that cache a query result need this because the bottom-nav shell is
/// an `IndexedStack`: every branch stays mounted, so switching tabs fires no
/// lifecycle callback and no route-observer event. Enrollment also leaves via
/// `go('/home')` rather than popping, so a `RouteAware` list has no way to
/// learn that its roster is out of date.
final ValueNotifier<int> rosterRevision = ValueNotifier<int>(0);

/// Signals that locally created households/members are now on disk.
void bumpRosterRevision() => rosterRevision.value++;
