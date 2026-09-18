import 'package:flutter/material.dart';

/// Root navigator for the app shell — shared so overlays survive route changes.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

BuildContext? get rootNavigatorContext => rootNavigatorKey.currentContext;
