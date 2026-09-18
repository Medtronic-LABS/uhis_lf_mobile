import 'package:flutter/widgets.dart';

/// Wraps the home screen so a pending optional/forced update prompt can be shown
/// over it on first paint.
///
/// > **Reconstructed file** — see the note in `app_version_info.dart`. This
/// > placeholder is a pass-through that renders [child] unchanged; restore
/// > PR #689's original gate to re-enable the home-screen update prompt.
class AppVersionHomeGate extends StatelessWidget {
  const AppVersionHomeGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
