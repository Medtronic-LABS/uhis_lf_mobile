import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';

/// Visual chain of referral status events. Rendered as a vertical list of
/// node + label rows; the current state is the first non-completed node.
class ReferralTimeline extends StatelessWidget {
  const ReferralTimeline({
    super.key,
    required this.events,
    required this.currentState,
    this.dueArrivalAt,
    this.dueTreatmentAt,
    this.breachedSince,
  });

  final List<ReferralStatusEventRow> events;
  final ReferralStatus currentState;
  final int? dueArrivalAt;
  final int? dueTreatmentAt;
  final int? breachedSince;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final completed = events.map((e) => e.toState).toSet();
    final nodes = _nodesFor(currentState);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < nodes.length; i++)
          _row(context,
              scheme: scheme,
              node: nodes[i],
              isCompleted: completed.contains(nodes[i].state),
              isCurrent: nodes[i].state == currentState,
              isBlocking: _isBlocking(nodes[i].state),
              eventAt: _eventTimestampFor(nodes[i].state),
              expectedAt: _expectedTimestampFor(nodes[i].state),
              isLast: i == nodes.length - 1),
        if (breachedSince != null) _breachRow(context, scheme: scheme),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required ColorScheme scheme,
    required _TimelineNode node,
    required bool isCompleted,
    required bool isCurrent,
    required bool isBlocking,
    required int? eventAt,
    required int? expectedAt,
    required bool isLast,
  }) {
    final color = isCompleted
        ? scheme.primary
        : isCurrent
            ? scheme.tertiary
            : scheme.onSurfaceVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted ? color : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                ),
                child: isCompleted
                    ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2.5, color: scheme.outline),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: isCompleted || isCurrent
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: color,
                        ),
                  ),
                  if (eventAt != null)
                    Text(
                      _formatTime(eventAt),
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                    )
                  else if (expectedAt != null)
                    Text(
                      'expected by ${_formatTime(expectedAt)}',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                                fontStyle: FontStyle.italic,
                              ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breachRow(BuildContext context, {required ColorScheme scheme}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.error, size: 22),
          const SizedBox(width: 8),
          Text(
            ReferralStrings.stepBreached,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }

  bool _isBlocking(ReferralStatus s) {
    switch (currentState) {
      case ReferralStatus.created:
        return s == ReferralStatus.acknowledged;
      case ReferralStatus.acknowledged:
        return s == ReferralStatus.inTransit;
      case ReferralStatus.inTransit:
        return s == ReferralStatus.arrived;
      case ReferralStatus.arrived:
        return s == ReferralStatus.treatmentStarted;
      default:
        return false;
    }
  }

  int? _eventTimestampFor(ReferralStatus s) {
    for (final e in events.reversed) {
      if (e.toState == s) return e.occurredAt;
    }
    return null;
  }

  int? _expectedTimestampFor(ReferralStatus s) {
    switch (s) {
      case ReferralStatus.arrived:
        return dueArrivalAt;
      case ReferralStatus.treatmentStarted:
        return dueTreatmentAt;
      default:
        return null;
    }
  }

  List<_TimelineNode> _nodesFor(ReferralStatus current) {
    // Exception states show a single trailing node.
    if (current.isException) {
      return [
        _TimelineNode(ReferralStatus.created, ReferralStrings.stepCreated),
        _TimelineNode(
            ReferralStatus.breachedArrival, ReferralStrings.stepBreached),
      ];
    }
    return [
      _TimelineNode(ReferralStatus.created, ReferralStrings.stepCreated),
      _TimelineNode(
          ReferralStatus.acknowledged, ReferralStrings.stepAcknowledged),
      _TimelineNode(ReferralStatus.inTransit, ReferralStrings.stepInTransit),
      _TimelineNode(ReferralStatus.arrived, ReferralStrings.stepArrived),
      _TimelineNode(
          ReferralStatus.treatmentStarted, ReferralStrings.stepTreatmentStarted),
    ];
  }

  static String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} $h:$m';
  }
}

class _TimelineNode {
  const _TimelineNode(this.state, this.label);
  final ReferralStatus state;
  final String label;
}
