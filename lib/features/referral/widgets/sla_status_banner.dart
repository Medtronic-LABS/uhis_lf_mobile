import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';
import '../../../core/models/sla.dart';

/// Section 2 — SLA Status Banner
/// Largest visual element showing breach, warning, or completion status.
class SlaStatusBanner extends StatelessWidget {
  const SlaStatusBanner({
    super.key,
    required this.referral,
    this.priority,
  });

  final Referral referral;
  final SlaPriority? priority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stateInfo = _determineState();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        gradient: _gradient(stateInfo.type, scheme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _borderColor(stateInfo.type, scheme),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          _icon(stateInfo.type, scheme),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stateInfo.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _textColor(stateInfo.type, scheme),
                        letterSpacing: 0.5,
                      ),
                ),
                if (stateInfo.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    stateInfo.subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _subtitleColor(stateInfo.type, scheme),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (stateInfo.type == _SlaStateType.breached)
            _PulsingIndicator(color: _accentColor(stateInfo.type, scheme)),
        ],
      ),
    );
  }

  _SlaStateInfo _determineState() {
    // Check if closed/completed
    if (referral.state.isClosed) {
      return _SlaStateInfo(
        type: _SlaStateType.completed,
        title: ReferralStrings.slaCompleted,
        subtitle: 'Care pathway completed',
      );
    }

    // Check if breached
    if (referral.breachedSince != null) {
      final breachDuration = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(referral.breachedSince!),
      );
      return _SlaStateInfo(
        type: _SlaStateType.breached,
        title: ReferralStrings.slaBreached(_formatDuration(breachDuration)),
        subtitle: 'Immediate action required',
      );
    }

    // Check warning state (less than 24h remaining)
    final dueAt = referral.dueArrivalAt ?? referral.dueTreatmentAt;
    if (dueAt != null) {
      final due = DateTime.fromMillisecondsSinceEpoch(dueAt);
      final remaining = due.difference(DateTime.now());
      if (remaining.isNegative) {
        return _SlaStateInfo(
          type: _SlaStateType.breached,
          title: ReferralStrings.slaBreached(_formatDuration(remaining.abs())),
          subtitle: 'Immediate action required',
        );
      }
      if (remaining.inHours < 24) {
        return _SlaStateInfo(
          type: _SlaStateType.warning,
          title: ReferralStrings.slaWarning(_formatDuration(remaining)),
          subtitle: 'SLA deadline approaching',
        );
      }
    }

    return _SlaStateInfo(
      type: _SlaStateType.onTrack,
      title: ReferralStrings.slaOnTrack,
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d';
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  LinearGradient _gradient(_SlaStateType type, ColorScheme scheme) {
    switch (type) {
      case _SlaStateType.breached:
        return LinearGradient(
          colors: [
            scheme.errorContainer,
            scheme.errorContainer.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case _SlaStateType.warning:
        return LinearGradient(
          colors: [
            scheme.tertiaryContainer,
            scheme.tertiaryContainer.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case _SlaStateType.completed:
        return LinearGradient(
          colors: [
            scheme.primaryContainer,
            scheme.primaryContainer.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case _SlaStateType.onTrack:
        return LinearGradient(
          colors: [
            scheme.surfaceContainerHighest,
            scheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _borderColor(_SlaStateType type, ColorScheme scheme) {
    switch (type) {
      case _SlaStateType.breached:
        return scheme.error;
      case _SlaStateType.warning:
        return scheme.tertiary;
      case _SlaStateType.completed:
        return scheme.primary;
      case _SlaStateType.onTrack:
        return scheme.outline;
    }
  }

  Color _textColor(_SlaStateType type, ColorScheme scheme) {
    switch (type) {
      case _SlaStateType.breached:
        return scheme.error;
      case _SlaStateType.warning:
        return scheme.tertiary;
      case _SlaStateType.completed:
        return scheme.primary;
      case _SlaStateType.onTrack:
        return scheme.onSurface;
    }
  }

  Color _subtitleColor(_SlaStateType type, ColorScheme scheme) {
    switch (type) {
      case _SlaStateType.breached:
        return scheme.onErrorContainer;
      case _SlaStateType.warning:
        return scheme.onTertiaryContainer;
      case _SlaStateType.completed:
        return scheme.onPrimaryContainer;
      case _SlaStateType.onTrack:
        return scheme.onSurfaceVariant;
    }
  }

  Color _accentColor(_SlaStateType type, ColorScheme scheme) {
    switch (type) {
      case _SlaStateType.breached:
        return scheme.error;
      case _SlaStateType.warning:
        return scheme.tertiary;
      case _SlaStateType.completed:
        return scheme.primary;
      case _SlaStateType.onTrack:
        return scheme.primary;
    }
  }

  Widget _icon(_SlaStateType type, ColorScheme scheme) {
    switch (type) {
      case _SlaStateType.breached:
        return Icon(
          Icons.warning_rounded,
          color: scheme.error,
          size: 32,
        );
      case _SlaStateType.warning:
        return Icon(
          Icons.schedule_rounded,
          color: scheme.tertiary,
          size: 32,
        );
      case _SlaStateType.completed:
        return Icon(
          Icons.check_circle_rounded,
          color: scheme.primary,
          size: 32,
        );
      case _SlaStateType.onTrack:
        return Icon(
          Icons.trending_up_rounded,
          color: scheme.primary,
          size: 32,
        );
    }
  }
}

enum _SlaStateType {
  breached,
  warning,
  completed,
  onTrack,
}

class _SlaStateInfo {
  const _SlaStateInfo({
    required this.type,
    required this.title,
    this.subtitle,
  });

  final _SlaStateType type;
  final String title;
  final String? subtitle;
}

/// Animated pulsing indicator for critical/breached status.
class _PulsingIndicator extends StatefulWidget {
  const _PulsingIndicator({required this.color});

  final Color color;

  @override
  State<_PulsingIndicator> createState() => _PulsingIndicatorState();
}

class _PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _animation.value * 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }
}
