/// Hidden Network diagnostics page (opened by ten taps on the login logo or the
/// Offline Sync card header).
///
/// Holds no PHI by construction (URLs are sanitised before storage), so it is
/// deliberately not a `PhiScreen`: screenshots are the support workflow. It
/// must also work signed out, so it reads no auth-dependent provider. All
/// state lives in [NetworkLogController]; this file only renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/debug/console_log.dart';
import '../../core/net_log/native_network_event_source.dart';
import '../../core/net_log/network_log_entry.dart';
import '../../core/net_log/network_log_repository.dart';
import '../../core/net_log/service_classifier.dart';
import '../../core/theme/app_theme.dart';
import 'network_log_controller.dart';
import 'network_log_format.dart';

class NetworkLogScreen extends StatefulWidget {
  const NetworkLogScreen({super.key, @visibleForTesting this.endpoints});

  final List<ConfiguredEndpoint>? endpoints;

  @override
  State<NetworkLogScreen> createState() => _NetworkLogScreenState();
}

class _NetworkLogScreenState extends State<NetworkLogScreen> {
  late final NetworkLogController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NetworkLogController(
      context.read<NetworkLogRepository>(),
      endpoints: widget.endpoints,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final List<NetworkLogEntry> rows;
    try {
      rows = await _controller.rowsForCopy();
    } on Exception catch (e) {
      _reportFailure('copy', e);
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: rows.map(NetworkLogFormat.line).join('\n')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(NetworkLogStrings.copied(rows.length))),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(NetworkLogStrings.clearTitle),
        content: Text(NetworkLogStrings.clearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(NetworkLogStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(NetworkLogStrings.clearConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _controller.clear();
    } on Exception catch (e) {
      _reportFailure('clear', e);
    }
  }

  /// Logs the type only and tells the user; the page stays usable.
  void _reportFailure(String action, Exception e) {
    ConsoleLog.warn('[NetworkLog] $action failed: ${e.runtimeType}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(NetworkLogStrings.actionFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(NetworkLogStrings.title),
          actions: [
            IconButton(
              tooltip: NetworkLogStrings.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: _controller.refresh,
            ),
            IconButton(
              tooltip: NetworkLogStrings.copy,
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _copy,
            ),
            IconButton(
              tooltip: NetworkLogStrings.clear,
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmClear,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_controller.loading)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final c = _controller;
    final rows = c.rows;
    // Items: endpoints section, request-log header, notices, chips, then rows,
    // then Load more or the empty state.
    final header = <Widget>[
      _SectionHeading(NetworkLogStrings.endpointsHeading),
      for (final e in c.endpoints) _EndpointRow(e),
      _SectionHeading(NetworkLogStrings.logHeading),
      if (c.nativeStatus != NativeNetworkStatus.ok)
        _Notice(_nativeText(c.nativeStatus)),
      if (c.droppedCount > 0)
        _Notice(NetworkLogStrings.droppedWrites(c.droppedCount)),
      _FilterChips(controller: c),
    ];
    final footer = <Widget>[
      if (rows.isEmpty && !c.loading)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Text(
            NetworkLogStrings.empty,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      if (c.hasMore)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: OutlinedButton(
            onPressed: c.loading ? null : c.loadMore,
            child: Text(NetworkLogStrings.loadMore),
          ),
        ),
    ];
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.xl),
        itemCount: header.length + rows.length + footer.length,
        itemBuilder: (_, i) {
          if (i < header.length) return header[i];
          final r = i - header.length;
          if (r < rows.length) return _LogRow(rows[r]);
          return footer[r - rows.length];
        },
      ),
    );
  }

  static String _nativeText(NativeNetworkStatus s) => switch (s) {
    NativeNetworkStatus.unavailable => NetworkLogStrings.nativeUnavailable,
    NativeNetworkStatus.notInitialized =>
      NetworkLogStrings.nativeNotInitialized,
    NativeNetworkStatus.failed => NetworkLogStrings.nativeFailed,
    NativeNetworkStatus.ok => '',
  };
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.rangeAbnormal),
    ),
  );
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow(this.endpoint);
  final ConfiguredEndpoint endpoint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          endpoint.service,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(NetworkLogFormat.endpointUrl(endpoint.url), style: const TextStyle(fontSize: 13)),
        Text(
          endpoint.rule,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    ),
  );
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.controller});
  final NetworkLogController controller;

  @override
  Widget build(BuildContext context) {
    final services = controller.counts.keys.toList()..sort();
    final total = controller.counts.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        children: [
          ChoiceChip(
            label: Text(
              NetworkLogStrings.chip(NetworkLogStrings.filterAll, total),
            ),
            selected: controller.service == null,
            onSelected: (_) => controller.setService(null),
          ),
          for (final s in services)
            ChoiceChip(
              label: Text(NetworkLogStrings.chip(s, controller.counts[s]!)),
              selected: controller.service == s,
              onSelected: (_) => controller.setService(s),
            ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.entry);
  final NetworkLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(NetworkLogFormat.time(e)),
              Text(
                e.method,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              _Tag(
                NetworkLogFormat.status(e),
                color: NetworkLogFormat.statusColor(e),
              ),
              Text(NetworkLogStrings.durationMs(e.durationMs ?? 0)),
              if (e.timing == 'headers') _Tag(NetworkLogStrings.tagHeaders),
              if (e.timing == 'handshake') _Tag(NetworkLogStrings.tagHandshake),
              if (e.source == 'native') _Tag(NetworkLogStrings.tagNative),
            ],
          ),
          Text(e.url, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color = AppColors.textMuted});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}
