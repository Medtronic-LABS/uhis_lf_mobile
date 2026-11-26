import 'package:flutter/widgets.dart';

/// Fires [onTriggered] after [taps] consecutive taps on [child], where each
/// tap lands within [window] of the previous one (a gap greater than [window]
/// restarts the count at 1; a gap equal to [window] does not).
///
/// Callers must pass a non-interactive [child] (text, logo): a child that
/// handles taps itself wins the gesture arena and its taps are not counted.
/// The trigger is hidden by design, so it adds no semantics.
class HiddenTapTrigger extends StatefulWidget {
  const HiddenTapTrigger({
    super.key,
    this.taps = 10,
    this.window = const Duration(seconds: 2),
    required this.onTriggered,
    required this.child,
    @visibleForTesting this.clock,
  });

  final int taps;
  final Duration window;
  final VoidCallback onTriggered;
  final Widget child;
  final DateTime Function()? clock;

  @override
  State<HiddenTapTrigger> createState() => _HiddenTapTriggerState();
}

class _HiddenTapTriggerState extends State<HiddenTapTrigger> {
  int _count = 0;
  DateTime? _lastTap;

  void _onTap() {
    final now = (widget.clock ?? DateTime.now)();
    final last = _lastTap;
    _count = (last == null || now.difference(last) > widget.window)
        ? 1
        : _count + 1;
    _lastTap = now;
    if (_count >= widget.taps) {
      _count = 0;
      _lastTap = null;
      widget.onTriggered();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _onTap,
      child: widget.child,
    );
  }
}
