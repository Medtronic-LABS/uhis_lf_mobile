import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/patient_dao.dart';
import '../referral/referral_repository.dart';
import 'cce_alert.dart';
import 'cce_repository.dart';
import 'widgets/cce_alert_card.dart';
import 'widgets/cce_journey_strip.dart';
import 'widgets/cce_update_status_sheet.dart';

/// The Care Coordination Alerts drawer — a full-height sheet listing open
/// referrals as action-first SLA alerts, sorted worst-first.
///
/// Self-contained: it builds its own [CceRepository] from the already-provided
/// [ReferralRepository] + [PatientDao], so wiring it in is a single call from
/// the Tasks screen with no provider-tree changes.
class CceAlertsDrawer extends StatefulWidget {
  const CceAlertsDrawer({super.key, required this.repository});

  final CceRepository repository;

  /// Open the drawer. Constructs the CCE repository from context, so callers
  /// only need a [BuildContext] under the app's provider scope.
  static Future<void> show(BuildContext context) {
    final repository = CceRepository(
      referrals: context.read<ReferralRepository>(),
      patients: context.read<PatientDao>(),
      households: context.read<HouseholdDao>(),
    );
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CceAlertsDrawer(repository: repository),
    );
  }

  @override
  State<CceAlertsDrawer> createState() => _CceAlertsDrawerState();
}

class _CceAlertsDrawerState extends State<CceAlertsDrawer> {
  late Future<List<CceAlert>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.loadAlerts();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.92;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppColors.cardSurfaceMuted,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: FutureBuilder<List<CceAlert>>(
        future: _future,
        builder: (context, snap) {
          final alerts = snap.data ?? const <CceAlert>[];
          final count = widget.repository.actionsNeededCount(alerts);
          return Column(
            children: [
              _header(count),
              if (snap.connectionState == ConnectionState.waiting)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (alerts.isEmpty)
                const Expanded(child: _EmptyState())
              else
                Expanded(child: _list(alerts)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  CceStrings.drawerTitle,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.statusCritical,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(CceStrings.done,
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _list(List<CceAlert> alerts) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: alerts.map(_card).toList(),
    );
  }

  Widget _card(CceAlert alert) {
    return CceAlertCard(
      alert: alert,
      journey: CceJourneyStrip(steps: alert.journey),
      onUpdateStatus: () => _onUpdateStatus(alert),
      onCall: () => _onCall(alert),
      onLocate: () => _onLocate(alert),
      onWhatsapp: alert.hasPhone ? () => _onWhatsapp(alert) : null,
    );
  }

  Future<void> _onUpdateStatus(CceAlert alert) async {
    final saved = await CceUpdateStatusSheet.show(
      context,
      alert: alert,
      repository: widget.repository,
    );
    if (!mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CceStrings.updateSaved)),
      );
      setState(_reload);
    }
  }

  Future<void> _onCall(CceAlert alert) async {
    final phone = alert.patientPhone;
    if (phone == null || phone.trim().isEmpty) {
      _snack(CceStrings.noPhone);
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone.trim());
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) _snack(CceStrings.dialFailed);
    } catch (_) {
      if (mounted) _snack(CceStrings.dialFailed);
    }
  }

  Future<void> _onWhatsapp(CceAlert alert) async {
    final phone = alert.patientPhone;
    if (phone == null || phone.trim().isEmpty) {
      _snack(CceStrings.noPhone);
      return;
    }
    final cleaned = phone.trim().replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$cleaned');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack(CceStrings.dialFailed);
    } catch (_) {
      if (mounted) _snack(CceStrings.dialFailed);
    }
  }

  Future<void> _onLocate(CceAlert alert) async {
    // Precise pin when the household has coordinates; otherwise fall back to a
    // name search enriched with the landmark + village + facility.
    final Uri uri;
    if (alert.hasGeo) {
      final lat = alert.latitude!;
      final lng = alert.longitude!;
      final label = Uri.encodeComponent(alert.patientName);
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng($label)');
    } else {
      final query = [
        alert.landmark,
        alert.villageName,
        alert.facilityName,
      ].where((s) => s != null && s.trim().isNotEmpty).join(', ');
      if (query.isEmpty) {
        _snack(CceStrings.noLocation);
        return;
      }
      uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack(CceStrings.noLocation);
    } catch (_) {
      if (mounted) _snack(CceStrings.noLocation);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: EmptyStateCard(
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.statusSuccess,
          iconBg: AppColors.statusSuccess.withValues(alpha: 0.1),
          title: CceStrings.emptyTitle,
          subtitle: CceStrings.emptyBody,
        ),
      ),
    );
  }
}
