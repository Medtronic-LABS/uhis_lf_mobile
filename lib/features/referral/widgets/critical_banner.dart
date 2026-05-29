import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/referral.dart';

/// Top-of-list banner shown when the highest-priority referral is currently
/// breached or escalated. Persistent — does not auto-dismiss.
class CriticalBanner extends StatelessWidget {
  const CriticalBanner({
    super.key,
    required this.patientName,
    required this.referral,
  });

  final String patientName;
  final Referral referral;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = _detailFor(referral);
    final tier = _tierLabel(referral);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.priority_high_rounded, color: scheme.error, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ReferralStrings.criticalBannerFmt(patientName, tier, detail),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  static String _tierLabel(Referral r) {
    switch (r.slaTier) {
      case SlaTier.emergency:
        return ReferralStrings.tierEmergency;
      case SlaTier.urgent:
        return ReferralStrings.tierUrgent;
      case SlaTier.routine:
        return ReferralStrings.tierRoutine;
    }
  }

  static String _detailFor(Referral r) {
    final breachedSinceMs = r.breachedSince;
    if (breachedSinceMs == null) return r.priorityDrivers.take(2).join(' · ');
    final since = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(breachedSinceMs));
    final h = since.inHours;
    final m = since.inMinutes.remainder(60);
    final overdue = h > 0 ? '${h}h ${m}m' : '${m}m';
    return ReferralStrings.overdueFmt(overdue);
  }
}
