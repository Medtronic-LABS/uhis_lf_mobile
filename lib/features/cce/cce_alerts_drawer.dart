import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/assessment_dao.dart';
import '../../core/db/follow_up_dao.dart';
import '../../core/db/household_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/sync/offline_push_service.dart';
import '../../core/widgets/empty_state_card.dart';
import 'cce_alert.dart';
import 'cce_repository.dart';
import 'widgets/cce_alert_card.dart';
import 'widgets/cce_call_result_sheet.dart';
import 'widgets/cce_journey_strip.dart';

/// CCE drawer — open REFERRED follow-ups from offline fetch only, with
/// Android SK-style dial → call-result flow.
class CceAlertsDrawer extends StatefulWidget {
  const CceAlertsDrawer({super.key, required this.repository});

  final CceRepository repository;

  static Future<void> show(BuildContext context) {
    final repository = CceRepository(
      followUps: context.read<FollowUpDao>(),
      members: context.read<MemberDao>(),
      assessments: context.read<AssessmentDao>(),
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

class _CceAlertsDrawerState extends State<CceAlertsDrawer>
    with WidgetsBindingObserver {
  late Future<List<CceAlert>> _future;
  String _searchQuery = '';

  /// Pending dial context — when the app resumes, show the call-result sheet.
  CceAlert? _pendingCallAlert;
  DateTime? _callStartedAt;
  bool _showingCallResult = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onReturnFromDialer();
    }
  }

  void _reload() {
    _future = widget.repository.loadAlerts();
  }

  List<CceAlert> _filtered(List<CceAlert> alerts) {
    if (_searchQuery.isEmpty) return alerts;
    final q = _searchQuery.toLowerCase();
    return alerts
        .where((a) =>
            a.patientName.toLowerCase().contains(q) ||
            (a.villageName?.toLowerCase().contains(q) ?? false) ||
            (a.programmeLabel?.toLowerCase().contains(q) ?? false))
        .toList();
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
          final visible = _filtered(alerts);
          return Column(
            children: [
              _header(count),
              _searchBar(),
              if (snap.connectionState == ConnectionState.waiting)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (visible.isEmpty)
                Expanded(
                    child: _searchQuery.isEmpty
                        ? const _EmptyState()
                        : const _SearchEmptyState())
              else
                Expanded(child: _list(visible)),
            ],
          );
        },
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: CceStrings.searchHint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
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
      onCall: alert.canCall ? () => _onCall(alert) : null,
      onLocate: () => _onLocate(alert),
      onWhatsapp: alert.hasPhone ? () => _onWhatsapp(alert) : null,
    );
  }

  Future<void> _onCall(CceAlert alert) async {
    final phone = alert.patientPhone;
    if (!alert.canCall || phone == null || phone.trim().isEmpty) {
      _snack(CceStrings.noPhone);
      return;
    }
    _pendingCallAlert = alert;
    _callStartedAt = DateTime.now();
    final uri = Uri(scheme: 'tel', path: phone.trim());
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        _pendingCallAlert = null;
        _snack(CceStrings.dialFailed);
      }
      // Some platforms never pause the app for tel:; open the sheet shortly.
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        if (_pendingCallAlert?.followUpId == alert.followUpId &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          _onReturnFromDialer();
        }
      });
    } catch (_) {
      _pendingCallAlert = null;
      if (mounted) _snack(CceStrings.dialFailed);
    }
  }

  Future<void> _onReturnFromDialer() async {
    final alert = _pendingCallAlert;
    if (alert == null || _showingCallResult) return;
    _showingCallResult = true;
    _pendingCallAlert = null;

    final started = _callStartedAt;
    _callStartedAt = null;
    final durationMinutes = started == null
        ? null
        : DateTime.now().difference(started).inSeconds / 60.0;

    if (!mounted) {
      _showingCallResult = false;
      return;
    }

    final saved = await CceCallResultSheet.show(
      context,
      alert: alert,
      durationMinutes: durationMinutes,
    );
    _showingCallResult = false;
    if (!mounted) return;

    if (saved) {
      _snack(CceStrings.callLogged);
      widget.repository.notifyChanged();
      setState(_reload);
      // Best-effort flush; assessment sync also attaches pending follow-ups.
      try {
        final push = context.read<OfflinePushService>();
        // ignore: unawaited_futures
        push.pushAll(syncMode: 'ManualSync');
      } catch (_) {}
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

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: EmptyStateCard(
          icon: Icons.search_off_rounded,
          iconColor: AppColors.textMuted,
          iconBg: AppColors.textMuted.withValues(alpha: 0.1),
          title: CceStrings.searchNoResultsTitle,
          subtitle: CceStrings.searchNoResultsBody,
        ),
      ),
    );
  }
}
