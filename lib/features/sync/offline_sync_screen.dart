import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/sync/offline_push_service.dart';
import '../../core/sync/offline_sync_service.dart';
import '../../core/theme/app_theme.dart';

/// Spice-parity Offline Sync screen: shows pending counts and runs a single
/// partitioned `offline-sync/create` push on Start.
class OfflineSyncScreen extends StatefulWidget {
  const OfflineSyncScreen({super.key});

  @override
  State<OfflineSyncScreen> createState() => _OfflineSyncScreenState();
}

enum _OfflineSyncPhase { idle, running, done }

class _OfflineSyncScreenState extends State<OfflineSyncScreen> {
  _OfflineSyncPhase _phase = _OfflineSyncPhase.idle;
  String? _message;
  bool _success = false;
  DateTime? _lastSyncedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final push = context.read<OfflinePushService>();
    final sync = context.read<OfflineSyncService>();
    await push.refreshCounts();
    final t = await sync.lastSyncedAt();
    if (!mounted) return;
    setState(() => _lastSyncedAt = t);
  }

  Future<void> _onStart() async {
    final push = context.read<OfflinePushService>();
    final syncSvc = context.read<OfflineSyncService>();
    if (push.isRunning || OfflinePushService.isPushInFlight) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OfflineSyncStrings.alreadyRunning)),
      );
      return;
    }

    setState(() {
      _phase = _OfflineSyncPhase.running;
      _message = null;
    });

    final result = await push.pushAll(syncMode: 'ManualSync');

    // When nothing was pending, still warm-pull like Spice (download path).
    if (!result.hadWork) {
      try {
        await syncSvc.warmSync();
      } catch (e) {
        debugPrint('[OfflineSyncScreen] warmSync after empty push: $e');
      }
    }

    if (!mounted) return;
    final t = await syncSvc.lastSyncedAt();
    setState(() {
      _phase = _OfflineSyncPhase.done;
      _success = result.success;
      _message = result.message;
      _lastSyncedAt = t;
    });
  }

  void _onOkay() {
    if (!_success && _phase == _OfflineSyncPhase.done) {
      setState(() {
        _phase = _OfflineSyncPhase.idle;
        _message = null;
      });
      _load();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final push = context.watch<OfflinePushService>();
    final counts = push.counts;

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerHigh,
      appBar: AppBar(
        title: Text(OfflineSyncStrings.title),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  OfflineSyncStrings.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                    ),
                    children: [
                      TextSpan(text: '${OfflineSyncStrings.lastSyncedAt} '),
                      TextSpan(
                        text: _formatLastSynced(_lastSyncedAt),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(child: _buildBody(push, counts)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(OfflinePushService push, OfflinePushCounts counts) {
    switch (_phase) {
      case _OfflineSyncPhase.idle:
        return Column(
          children: [
            Text(
              OfflineSyncStrings.startPrompt,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _CountRow(
              label: OfflineSyncStrings.households,
              count: counts.households,
            ),
            _CountRow(
              label: OfflineSyncStrings.householdMembers,
              count: counts.members,
            ),
            _CountRow(
              label: OfflineSyncStrings.assessments,
              count: counts.assessments,
            ),
            _CountRow(
              label: OfflineSyncStrings.followUps,
              count: counts.followUps,
            ),
            if (counts.failed > 0) ...[
              const SizedBox(height: 4),
              _CountRow(
                label: OfflineSyncStrings.failedPendingRetry,
                count: counts.failed,
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(OfflineSyncStrings.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                    ),
                    child: Text(OfflineSyncStrings.start),
                  ),
                ),
              ],
            ),
          ],
        );
      case _OfflineSyncPhase.running:
        final pct = (push.progress * 100).clamp(0, 100).round();
        return Column(
          children: [
            Text(
              OfflineSyncStrings.started,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  OfflineSyncStrings.offlineData,
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  OfflineSyncStrings.progressPercent(pct),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: push.progress.clamp(0.0, 1.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: AppColors.navy,
              backgroundColor: AppColors.surfaceContainerHigh,
            ),
            const Spacer(),
          ],
        );
      case _OfflineSyncPhase.done:
        return Column(
          children: [
            const Spacer(),
            Icon(
              _success ? Icons.check_circle : Icons.error,
              size: 64,
              color: _success
                  ? AppColors.statusSuccess
                  : AppColors.statusCritical,
            ),
            const SizedBox(height: 16),
            Text(
              _message ??
                  (_success
                      ? OfflineSyncStrings.completed
                      : OfflineSyncStrings.failed),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _onOkay,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                _success ? OfflineSyncStrings.okay : OfflineSyncStrings.retry,
              ),
            ),
          ],
        );
    }
  }

  static String _formatLastSynced(DateTime? t) {
    if (t == null) return '—';
    final local = t.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            ': $count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: count > 0
                  ? AppColors.statusCritical
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
