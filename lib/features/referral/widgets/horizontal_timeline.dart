import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';

/// Section 5 — Horizontal Timeline Progress
/// Compact horizontal timeline showing referral progression stages.
class HorizontalTimeline extends StatelessWidget {
  const HorizontalTimeline({
    super.key,
    required this.events,
    required this.currentState,
    this.isBreached = false,
  });

  final List<ReferralStatusEventRow> events;
  final ReferralStatus currentState;
  final bool isBreached;

  @override
  Widget build(BuildContext context) {
    final nodes = _buildNodes();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < nodes.length; i++) ...[
            _TimelineNode(
              node: nodes[i],
              isFirst: i == 0,
              isLast: i == nodes.length - 1,
            ),
            if (i < nodes.length - 1) _TimelineConnector(node: nodes[i]),
          ],
        ],
      ),
    );
  }

  List<_NodeData> _buildNodes() {
    final completedStates = events.map((e) => e.toState).toSet();
    final dateFormatter = DateFormat('d MMM');

    final List<_NodeData> nodes = [];

    // Define the standard progression path
    final standardPath = [
      (ReferralStatus.created, ReferralStrings.timelineSKVisit),
      (ReferralStatus.acknowledged, ReferralStrings.timelineReferred),
      (ReferralStatus.arrived, ReferralStrings.timelineArrived),
      (ReferralStatus.treatmentStarted, ReferralStrings.timelineTreated),
      (ReferralStatus.closedRecovered, ReferralStrings.timelineDischarged),
    ];

    for (final (state, label) in standardPath) {
      final event = events.where((e) => e.toState == state).firstOrNull;
      final isCompleted = completedStates.contains(state);
      final isCurrent = currentState == state;
      final isBlocked = isBreached && !isCompleted && !isCurrent;
      final isWaiting = !isCompleted && !isBlocked && !isCurrent &&
          currentState.index < state.index;

      String? dateStr;
      if (event != null) {
        dateStr = dateFormatter.format(
          DateTime.fromMillisecondsSinceEpoch(event.occurredAt),
        );
      }

      nodes.add(_NodeData(
        label: label,
        state: _determineNodeState(isCompleted, isCurrent, isBlocked, isWaiting),
        dateStr: dateStr,
      ));
    }

    return nodes;
  }

  _NodeState _determineNodeState(
    bool isCompleted,
    bool isCurrent,
    bool isBlocked,
    bool isWaiting,
  ) {
    if (isCompleted) return _NodeState.completed;
    if (isCurrent) return _NodeState.active;
    if (isBlocked) return _NodeState.blocked;
    if (isWaiting) return _NodeState.unknown;
    return _NodeState.unknown;
  }
}

enum _NodeState {
  completed, // Green check
  active, // Animated pulse
  blocked, // Orange/red warning
  unknown, // Grey dotted
}

class _NodeData {
  const _NodeData({
    required this.label,
    required this.state,
    this.dateStr,
  });

  final String label;
  final _NodeState state;
  final String? dateStr;
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.node,
    this.isFirst = false,
    this.isLast = false,
  });

  final _NodeData node;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Node circle
        _buildNodeCircle(scheme),
        const SizedBox(height: 6),
        // Label
        SizedBox(
          width: 60,
          child: Column(
            children: [
              // Status indicator for active/blocked
              if (node.state == _NodeState.active)
                Text(
                  '…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              Text(
                node.state == _NodeState.completed && node.label != ReferralStrings.timelineDischarged
                    ? '✓ ${node.label}'
                    : node.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _labelColor(scheme),
                      fontWeight: node.state == _NodeState.completed ||
                              node.state == _NodeState.active
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
              ),
              if (node.dateStr != null)
                Text(
                  node.dateStr!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                ),
              if (node.state == _NodeState.active && node.dateStr == null)
                Text(
                  ReferralStrings.timelineWaiting,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.tertiary,
                        fontStyle: FontStyle.italic,
                      ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNodeCircle(ColorScheme scheme) {
    switch (node.state) {
      case _NodeState.completed:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check,
            size: 14,
            color: scheme.onPrimary,
          ),
        );
      case _NodeState.active:
        return _PulsingCircle(color: scheme.tertiary);
      case _NodeState.blocked:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.error, width: 2),
          ),
          child: Icon(
            Icons.warning_rounded,
            size: 12,
            color: scheme.error,
          ),
        );
      case _NodeState.unknown:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.5),
              width: 2,
              strokeAlign: BorderSide.strokeAlignCenter,
            ),
          ),
        );
    }
  }

  Color _labelColor(ColorScheme scheme) {
    switch (node.state) {
      case _NodeState.completed:
        return scheme.primary;
      case _NodeState.active:
        return scheme.tertiary;
      case _NodeState.blocked:
        return scheme.error;
      case _NodeState.unknown:
        return scheme.onSurface.withValues(alpha: 0.5);
    }
  }
}

class _TimelineConnector extends StatelessWidget {
  const _TimelineConnector({required this.node});

  final _NodeData node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompleted = node.state == _NodeState.completed;

    return Container(
      width: 24,
      height: 3,
      margin: const EdgeInsets.only(bottom: 50), // Align with circles
      decoration: BoxDecoration(
        color: isCompleted
            ? scheme.primary.withValues(alpha: 0.5)
            : scheme.outline.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Animated pulsing circle for active state.
class _PulsingCircle extends StatefulWidget {
  const _PulsingCircle({required this.color});

  final Color color;

  @override
  State<_PulsingCircle> createState() => _PulsingCircleState();
}

class _PulsingCircleState extends State<_PulsingCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulsing ring
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withValues(alpha: _opacityAnimation.value),
                      width: 2,
                    ),
                  ),
                ),
              );
            },
          ),
          // Inner circle
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
