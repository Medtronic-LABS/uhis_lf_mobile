import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';

/// Section 4 — Current Operational Status
/// Most important operational context showing arrival, queue, or completion status.
class OperationalStatus extends StatelessWidget {
  const OperationalStatus({
    super.key,
    required this.referral,
    this.followUpDueAt,
    this.prescriptionShared = false,
    this.queueDepartment,
    this.queueWaitTime,
  });

  final Referral referral;
  final int? followUpDueAt;
  final bool prescriptionShared;
  final String? queueDepartment;
  final Duration? queueWaitTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusInfo = _determineStatus();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusInfo.backgroundColor(scheme),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: statusInfo.borderColor(scheme),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status label
          Text(
            ReferralStrings.statusLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 6),
          // Main status text
          Text(
            statusInfo.mainStatus,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: statusInfo.textColor(scheme),
                ),
          ),
          // Secondary info (overdue days, waiting time, etc.)
          if (statusInfo.secondaryInfo != null) ...[
            const SizedBox(height: 4),
            Text(
              statusInfo.secondaryInfo!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusInfo.secondaryColor(scheme),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          // Tertiary info (SLA was X days, etc.)
          if (statusInfo.tertiaryInfo != null) ...[
            const SizedBox(height: 2),
            Text(
              statusInfo.tertiaryInfo!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
          const SizedBox(height: 12),
          // Status hints (icon + text pairs)
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: statusInfo.hints
                .map((h) => _StatusHint(hint: h, scheme: scheme))
                .toList(),
          ),
        ],
      ),
    );
  }

  _OperationalStatusInfo _determineStatus() {
    final now = DateTime.now();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(referral.createdAt);

    // Completed/Discharged
    if (referral.state == ReferralStatus.closedRecovered ||
        referral.state == ReferralStatus.closedDeceased) {
      final closedAt = referral.closedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(referral.closedAt!)
          : now;
      final followUpStr = followUpDueAt != null
          ? DateFormat('d MMM').format(
              DateTime.fromMillisecondsSinceEpoch(followUpDueAt!))
          : null;

      return _OperationalStatusInfo(
        statusType: _StatusType.completed,
        mainStatus: 'Discharged ${DateFormat('d MMM').format(closedAt)}',
        secondaryInfo:
            prescriptionShared ? ReferralStrings.prescriptionShared : null,
        tertiaryInfo:
            followUpStr != null ? ReferralStrings.followUpDue(followUpStr) : null,
        hints: [
          ReferralStrings.hintCareCompleted,
          if (followUpStr != null) ReferralStrings.hintFollowUp('7d'),
        ],
      );
    }

    // At facility, waiting
    if (referral.state == ReferralStatus.arrived ||
        referral.state == ReferralStatus.treatmentStarted) {
      final dept = queueDepartment ?? 'OB';
      final waitStr = queueWaitTime != null
          ? _formatDuration(queueWaitTime!)
          : '—';

      return _OperationalStatusInfo(
        statusType: _StatusType.atFacility,
        mainStatus: referral.state == ReferralStatus.treatmentStarted
            ? ReferralStrings.statusInTreatment
            : '${ReferralStrings.statusCheckedIn} — awaiting $dept review',
        secondaryInfo: ReferralStrings.waitingStatus(waitStr),
        hints: [
          ReferralStrings.hintAtFacility,
          ReferralStrings.hintQueueWait(dept, waitStr),
        ],
      );
    }

    // Not arrived
    if (referral.state == ReferralStatus.created ||
        referral.state == ReferralStatus.acknowledged ||
        referral.state == ReferralStatus.inTransit) {
      final daysSinceCreation = now.difference(createdAt).inDays;
      final slaDays = _getSlaWindowDays(referral.slaTier);
      final isOverdue = referral.breachedSince != null;

      if (isOverdue) {
        final overdueDays = now
            .difference(DateTime.fromMillisecondsSinceEpoch(referral.breachedSince!))
            .inDays;
        return _OperationalStatusInfo(
          statusType: _StatusType.notArrived,
          mainStatus: ReferralStrings.statusNotArrived,
          secondaryInfo: ReferralStrings.overdueStatus('$overdueDays days'),
          tertiaryInfo: ReferralStrings.slaWasStatus('$slaDays days'),
          hints: [
            ReferralStrings.hintNotCheckedIn,
            ReferralStrings.hintTransportBarrier,
          ],
        );
      }

      return _OperationalStatusInfo(
        statusType: _StatusType.inTransit,
        mainStatus: referral.state == ReferralStatus.inTransit
            ? 'In transit to facility'
            : ReferralStrings.statusNotArrived,
        secondaryInfo: 'Created $daysSinceCreation days ago',
        hints: [
          ReferralStrings.hintNotCheckedIn,
        ],
      );
    }

    // Default/fallback
    return _OperationalStatusInfo(
      statusType: _StatusType.unknown,
      mainStatus: _stateLabel(referral.state),
      hints: [],
    );
  }

  int _getSlaWindowDays(SlaTier tier) {
    switch (tier) {
      case SlaTier.emergency:
        return 1;
      case SlaTier.urgent:
        return 3;
      case SlaTier.routine:
        return 7;
    }
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  String _stateLabel(ReferralStatus s) {
    switch (s) {
      case ReferralStatus.created:
        return ReferralStrings.stepCreated;
      case ReferralStatus.acknowledged:
        return ReferralStrings.stepAcknowledged;
      case ReferralStatus.inTransit:
        return ReferralStrings.stepInTransit;
      case ReferralStatus.arrived:
        return ReferralStrings.stepArrived;
      case ReferralStatus.treatmentStarted:
        return ReferralStrings.stepTreatmentStarted;
      case ReferralStatus.closedRecovered:
        return ReferralStrings.stepClosedRecovered;
      case ReferralStatus.closedDeceased:
        return ReferralStrings.stepClosedDeceased;
      case ReferralStatus.paused:
        return ReferralStrings.stepPaused;
      case ReferralStatus.refused:
        return ReferralStrings.stepRefused;
      case ReferralStatus.targetUnreachable:
        return ReferralStrings.stepTargetUnreachable;
      case ReferralStatus.duplicate:
        return ReferralStrings.stepDuplicate;
      case ReferralStatus.transportDeclined:
        return ReferralStrings.stepTransportDeclined;
      case ReferralStatus.diverted:
        return ReferralStrings.stepDiverted;
      case ReferralStatus.breachedArrival:
        return ReferralStrings.stepBreached;
    }
  }
}

enum _StatusType {
  notArrived,
  inTransit,
  atFacility,
  completed,
  unknown,
}

class _OperationalStatusInfo {
  const _OperationalStatusInfo({
    required this.statusType,
    required this.mainStatus,
    this.secondaryInfo,
    this.tertiaryInfo,
    required this.hints,
  });

  final _StatusType statusType;
  final String mainStatus;
  final String? secondaryInfo;
  final String? tertiaryInfo;
  final List<String> hints;

  Color backgroundColor(ColorScheme scheme) {
    switch (statusType) {
      case _StatusType.notArrived:
        return scheme.errorContainer.withValues(alpha: 0.3);
      case _StatusType.inTransit:
        return scheme.tertiaryContainer.withValues(alpha: 0.3);
      case _StatusType.atFacility:
        return scheme.primaryContainer.withValues(alpha: 0.3);
      case _StatusType.completed:
        return scheme.primaryContainer.withValues(alpha: 0.2);
      case _StatusType.unknown:
        return scheme.surfaceContainerLow;
    }
  }

  Color borderColor(ColorScheme scheme) {
    switch (statusType) {
      case _StatusType.notArrived:
        return scheme.error.withValues(alpha: 0.4);
      case _StatusType.inTransit:
        return scheme.tertiary.withValues(alpha: 0.4);
      case _StatusType.atFacility:
        return scheme.primary.withValues(alpha: 0.4);
      case _StatusType.completed:
        return scheme.primary.withValues(alpha: 0.3);
      case _StatusType.unknown:
        return scheme.outlineVariant;
    }
  }

  Color textColor(ColorScheme scheme) {
    switch (statusType) {
      case _StatusType.notArrived:
        return scheme.error;
      case _StatusType.inTransit:
        return scheme.tertiary;
      case _StatusType.atFacility:
        return scheme.primary;
      case _StatusType.completed:
        return scheme.primary;
      case _StatusType.unknown:
        return scheme.onSurface;
    }
  }

  Color secondaryColor(ColorScheme scheme) {
    switch (statusType) {
      case _StatusType.notArrived:
        return scheme.error.withValues(alpha: 0.8);
      case _StatusType.inTransit:
        return scheme.tertiary.withValues(alpha: 0.8);
      case _StatusType.atFacility:
        return scheme.primary.withValues(alpha: 0.8);
      case _StatusType.completed:
        return scheme.onSurface.withValues(alpha: 0.7);
      case _StatusType.unknown:
        return scheme.onSurfaceVariant;
    }
  }
}

class _StatusHint extends StatelessWidget {
  const _StatusHint({
    required this.hint,
    required this.scheme,
  });

  final String hint;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        hint,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}
