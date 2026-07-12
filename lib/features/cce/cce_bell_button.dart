import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/patient_dao.dart';
import '../referral/referral_repository.dart';
import 'cce_alerts_drawer.dart';
import 'cce_repository.dart';

/// AppBar bell that opens the CCE drawer and shows a live count of referrals
/// needing SK action. Recomputes whenever the underlying referral engine
/// signals a change (sync, transition, escalation), so the badge tracks the
/// SLA state without polling.
class CceBellButton extends StatefulWidget {
  const CceBellButton({super.key});

  @override
  State<CceBellButton> createState() => _CceBellButtonState();
}

class _CceBellButtonState extends State<CceBellButton> {
  CceRepository? _repo;
  int _count = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = CceRepository(
        referrals: context.read<ReferralRepository>(),
        patients: context.read<PatientDao>(),
      );
      _repo!.changes.addListener(_refresh);
      _refresh();
    }
  }

  @override
  void dispose() {
    _repo?.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = _repo;
    if (repo == null) return;
    final alerts = await repo.loadAlerts();
    if (!mounted) return;
    setState(() => _count = repo.actionsNeededCount(alerts));
  }

  Future<void> _open() async {
    await CceAlertsDrawer.show(context);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: CceStrings.bellTooltip,
      onPressed: _open,
      icon: Badge(
        isLabelVisible: _count > 0,
        backgroundColor: AppColors.statusCritical,
        label: Text('$_count'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}
