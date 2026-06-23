import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';
import '../../../core/models/sla.dart';

class ReferralCard extends StatelessWidget {
  const ReferralCard({
    super.key,
    required this.referral,
    required this.patientLabel,
    this.patientAge,
    required this.onTap,
    required this.onSeeWhy,
  });

  final Referral referral;
  final String patientLabel;
  final int? patientAge;
  final VoidCallback onTap;
  final VoidCallback onSeeWhy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = SlaPriority.fromWireTag(referral.priorityLevel);
    final accent = _accentFor(level, scheme);
    final tierLabel = _tierLabel(referral.slaTier);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        key: const Key('referral_card_tap'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ScorePill(score: referral.priorityScore ?? 0, color: accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _patientSubtitle(),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Badge(label: level.wireTag.toUpperCase(), color: accent),
                  const SizedBox(width: 6),
                  _Badge(label: tierLabel, color: scheme.outline),
                ],
              ),
              const SizedBox(height: 12),
              if (referral.diagnosisLabel != null &&
                  referral.diagnosisLabel!.isNotEmpty)
                Text(
                  referral.diagnosisLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              const SizedBox(height: 6),
              Text(
                _ageLabel(referral),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
              ),
              if (referral.priorityDrivers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  referral.priorityDrivers
                      .map(ReferralStrings.formatDriver)
                      .join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onSeeWhy,
                  icon: const Icon(Icons.psychology_alt_outlined, size: 20),
                  label: Text(
                    ReferralStrings.tapToSeeWhy,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _patientSubtitle() {
    final ageStr = patientAge == null ? '' : 'Age $patientAge · ';
    final stateLabel = _stateLabel(referral.state);
    return '$ageStr$stateLabel';
  }

  String _ageLabel(Referral r) {
    final created = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
    final age = DateTime.now().difference(created);
    final relative = _relative(age);
    if (r.breachedSince != null) {
      final since = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(r.breachedSince!));
      return '${ReferralStrings.agedFmt(relative)} · '
          '${ReferralStrings.overdueFmt(_relative(since))}';
    }
    return ReferralStrings.agedFmt(relative);
  }

  static String _relative(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inDays}d';
  }

  static String _stateLabel(ReferralStatus s) {
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

  static String _tierLabel(SlaTier t) {
    switch (t) {
      case SlaTier.emergency:
        return ReferralStrings.tierEmergency;
      case SlaTier.urgent:
        return ReferralStrings.tierUrgent;
      case SlaTier.routine:
        return ReferralStrings.tierRoutine;
    }
  }

  static Color _accentFor(SlaPriority p, ColorScheme scheme) {
    switch (p) {
      case SlaPriority.critical:
        return scheme.error;
      case SlaPriority.high:
        return scheme.tertiary;
      case SlaPriority.medium:
        return scheme.primary;
      case SlaPriority.low:
        return scheme.onSurfaceVariant;
    }
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score, required this.color});
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
