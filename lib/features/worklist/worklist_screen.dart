import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import '../../core/models/worklist_entry.dart';
import '../../core/sync/offline_sync_service.dart';
import 'widgets/programme_chip_row.dart';
import 'widgets/sync_strip.dart';
import 'widgets/urgent_banner.dart';
import 'widgets/worklist_card.dart';
import 'worklist_repository.dart';

/// Embedded view rendered into `DashboardScreen` — not a standalone route.
/// The dashboard supplies the AppBar; we own the chip row, sync strip,
/// urgent banner, and the virtualized list.
class WorklistView extends StatefulWidget {
  const WorklistView({super.key});

  @override
  State<WorklistView> createState() => _WorklistViewState();
}

class _WorklistViewState extends State<WorklistView> {
  Set<Programme> _filter = const <Programme>{};
  Future<List<WorklistEntry>>? _future;
  DateTime? _lastSyncedAt;
  bool _coldSyncTriggered = false;
  late final WorklistRepository _repo;
  late final OfflineSyncService _sync;

  @override
  void initState() {
    super.initState();
    debugPrint('[WorklistScreen] mounted');
    _repo = context.read<WorklistRepository>();
    _sync = context.read<OfflineSyncService>();
    // Initialize directly without setState since widget isn't mounted yet
    _future = _repo.load(filter: _filter);
    _refreshLastSyncedLabel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeColdSync());
    _repo.changes.addListener(_onChanges);
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanges);
    super.dispose();
  }

  void _onChanges() {
    if (!mounted) return;
    _reload();
  }

  void _reload() {
    final future = _repo.load(filter: _filter);
    setState(() {
      _future = future;
    });
    _refreshLastSyncedLabel();
  }

  Future<void> _refreshLastSyncedLabel() async {
    final t = await _sync.lastSyncedAt();
    if (!mounted) return;
    setState(() => _lastSyncedAt = t);
  }

  Future<void> _maybeColdSync() async {
    if (_coldSyncTriggered) return;
    _coldSyncTriggered = true;
    final t = await _sync.lastSyncedAt();
    if (t != null) return; // already cold-synced once
    final report = await _sync.coldSync();
    if (!mounted) return;
    await _repo.recomputeAllAfterSync();
    if (!mounted) return;
    _refreshLastSyncedLabel();
    if (report.errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(WorklistStrings.syncFailed(report.errors.first))),
      );
    }
  }

  Future<void> _syncNow() async {
    final report = await _sync.warmSync();
    if (!mounted) return;
    await _repo.recomputeAllAfterSync();
    _refreshLastSyncedLabel();
    if (!mounted) return;
    final msg = report.errors.isNotEmpty
        ? WorklistStrings.syncFailed(report.errors.first)
        : WorklistStrings.syncSummary(report.patients);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onFilterChanged(Set<Programme> next) {
    setState(() => _filter = next);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<OfflineSyncService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProgrammeChipRow(selection: _filter, onChanged: _onFilterChanged),
        SyncStrip(
          lastSyncedAt: _lastSyncedAt,
          syncing: sync.isRunning,
          isOnline: true, // connectivity wired via SyncStrip caller later
          onSyncNow: _syncNow,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _syncNow,
            child: FutureBuilder<List<WorklistEntry>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                if (snap.hasError) {
                  return _ErrorState(
                    onRetry: _reload,
                    message: snap.error.toString(),
                  );
                }
                final list = snap.data ?? const <WorklistEntry>[];
                if (list.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [const _EmptyState()],
                  );
                }
                final topUrgent = list.first.isUrgent ? list.first : null;
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: list.length + (topUrgent != null ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (topUrgent != null && i == 0) {
                      return UrgentBanner(patientName: topUrgent.displayName);
                    }
                    final entry =
                        list[topUrgent != null ? i - 1 : i];
                    return WorklistCard(
                      entry: entry,
                      onTap: () => context.push('/patient/${entry.patientId}'),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            WorklistStrings.emptyTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            WorklistStrings.emptyBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.message});
  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 40),
            const SizedBox(height: 12),
            Text(WorklistStrings.loadFailed,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text(CommonStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}
