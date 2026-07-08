import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../referral/referral_repository.dart';

/// Bottom-sheet notification drawer — referral alerts, CCE escalations,
/// unread messages. Opened by the bell icon in the dashboard header.
Future<void> showNotificationDrawer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NotificationDrawer(),
  );
}

class _NotificationDrawer extends StatefulWidget {
  const _NotificationDrawer();

  @override
  State<_NotificationDrawer> createState() => _NotificationDrawerState();
}

class _NotificationDrawerState extends State<_NotificationDrawer> {
  Future<({int critical, int active})>? _countsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _countsFuture ??= context.read<ReferralRepository>().counts();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final mq = MediaQuery.of(context);

    return Container(
      height: mq.size.height * 0.72,
      decoration: BoxDecoration(
        color: tokens.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── handle ──
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── header row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(
              children: [
                Text(
                  'Notifications',
                  style: AppTextStyles.listTitle,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── content ──
          Expanded(
            child: FutureBuilder<({int critical, int active})>(
              future: _countsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final counts = snap.data;
                final criticalCount = counts?.critical ?? 0;
                final activeCount = counts?.active ?? 0;

                if (criticalCount == 0 && activeCount == 0) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'No new notifications',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (criticalCount > 0)
                      _NotificationTile(
                        icon: Icons.warning_rounded,
                        iconColor: AppColors.statusCritical,
                        iconBg: AppColors.statusCritical.withValues(alpha: 0.1),
                        title: 'CCE escalations',
                        subtitle: '$criticalCount critical referral${criticalCount == 1 ? '' : 's'} need immediate attention',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/referrals');
                        },
                      ),
                    if (activeCount > 0)
                      _NotificationTile(
                        icon: Icons.assignment_rounded,
                        iconColor: AppColors.statusWarning,
                        iconBg: AppColors.statusWarning.withValues(alpha: 0.1),
                        title: MissionDashboardStrings.referralAlertsLabel,
                        subtitle: '$activeCount pending referral${activeCount == 1 ? '' : 's'} awaiting follow-up',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/referrals');
                        },
                      ),
                  ],
                );
              },
            ),
          ),

          SizedBox(height: mq.padding.bottom + 8),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tokens.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
