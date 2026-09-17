import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/sync/offline_push_service.dart';
import '../../core/sync/offline_sync_service.dart';
import '../../core/sync/sync_progress.dart';
import '../../core/sync/sync_report.dart';

/// Full-screen loading indicator shown during initial data sync after login.
///
/// Displays:
/// - App logo
/// - Animated progress indicator
/// - Current sync step with entity name
/// - Completion/error states with appropriate actions
class SyncProgressScreen extends StatefulWidget {
  const SyncProgressScreen({super.key});

  @override
  State<SyncProgressScreen> createState() => _SyncProgressScreenState();
}

class _SyncProgressScreenState extends State<SyncProgressScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  StreamSubscription<SyncProgress>? _progressSub;
  SyncProgress _progress = SyncProgress.initial;
  SyncReport? _report;
  bool _syncStarted = false;
  /// True when sync stopped because the session has no auth credentials —
  /// user must re-login; do not offer "continue offline".
  bool _blockedNoAuth = false;

  /// Guards against double navigation when both the progress stream and
  /// [_startSync]'s await path observe the same completion event.
  bool _finishHandled = false;

  @override
  void initState() {
    debugPrint('[_SyncProgressScreenState] initState');
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startSync());
  }

  @override
  void dispose() {
    debugPrint('[_SyncProgressScreenState] dispose');
    _progressSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startSync() async {
    if (_syncStarted) return;
    _syncStarted = true;

    final sync = context.read<OfflineSyncService>();

    // Subscribe to progress updates. progressStream is a broadcast stream so
    // joining mid-sync (background-started during onboarding) works fine.
    _progressSub = sync.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() => _progress = progress);
      // Background-started sync: handle completion via stream events.
      if (progress.isComplete && _report == null) {
        _finishSyncAndGoHome();
      }
    });

    // Catch up with current state immediately — the stream won't replay past
    // events for late subscribers.
    if (mounted) setState(() => _progress = sync.progress);

    debugPrint('[_SyncProgressScreenState] _startSync: isRunning=${sync.isRunning} isComplete=${sync.progress.isComplete} hasError=${sync.progress.hasError}');

    // Sync was already completed in the background (e.g. finished during PIN setup).
    if (sync.progress.isComplete) {
      debugPrint('[_SyncProgressScreenState] background sync already done → navigate');
      _finishSyncAndGoHome();
      return;
    }

    // Sync already running in background — stream subscription handles the rest.
    if (sync.isRunning) {
      debugPrint('[_SyncProgressScreenState] background sync in progress → waiting on stream');
      return;
    }

    // Normal path: /sync reached when first-time setup needs a full pull.
    // UHIS parity: when sync_meta.lastSyncTime exists (same as
    // SERVER_LAST_SYNCED), ResourceLoadingScreen skips download — local data
    // is already on device and background sync handles deltas later.
    final auth = context.read<AuthState>();
    final authRepo = context.read<AuthRepository>();

    // Offline password login can mark signed-in without restoring a Bearer
    // token. Push/pull would 401 and still let the user into /home — block.
    if (!authRepo.hasSessionCredentials) {
      debugPrint(
        '[Sync] blocked — no auth token/session credentials; '
        'cannot push or pull',
      );
      if (!mounted) return;
      setState(() {
        _blockedNoAuth = true;
        _progress = SyncProgress.failed(SyncStrings.syncErrorSessionExpired);
        _report = SyncReport.empty().copyWith(
          errors: const ['Not authenticated — sign in again'],
        );
      });
      return;
    }

    SyncReport report;
    if (auth.sameUserRelogin) {
      final hasSyncCursor = await sync.lastSyncedAt() != null;
      if (hasSyncCursor) {
        debugPrint(
          '[Sync] UHIS parity — sync cursor present, skipping login pull',
        );
        _finishSyncAndGoHome();
        return;
      }
      try {
        final pushResult = await context
            .read<OfflinePushService>()
            .pushAll(syncMode: 'InitialSync');
        debugPrint(
          '[Sync] login push before coldSync: success=${pushResult.success} '
          'hadWork=${pushResult.hadWork} msg=${pushResult.message}',
        );
        if (!pushResult.success &&
            (pushResult.message ?? '')
                .toLowerCase()
                .contains('not authenticated')) {
          if (!mounted) return;
          setState(() {
            _blockedNoAuth = true;
            _progress = SyncProgress.failed(SyncStrings.syncErrorSessionExpired);
            _report = SyncReport.empty().copyWith(
              errors: [pushResult.message ?? 'Not authenticated'],
            );
          });
          return;
        }
      } catch (e) {
        debugPrint('[Sync] login push before coldSync failed: $e');
      }
      report = await sync.coldSync(wipeBeforeSync: false);
    } else {
      report = await sync.coldSync(wipeBeforeSync: false);
    }

    if (!mounted) return;
    setState(() => _report = report);

    debugPrint('[_SyncProgressScreenState] sync done: households=${report.households} members=${report.members} patients=${report.patients} errors=${report.errors}');

    if (report.errors.isEmpty) {
      _finishSyncAndGoHome();
    }
  }

  /// Navigate home immediately after sync.
  ///
  /// Worklist recompute + mission refresh are owned by [PostSyncRefresher]
  /// (listening on the same progress stream). Calling refresh here too caused
  /// a second full pass on every login via the `_dirty` coalesce path.
  void _finishSyncAndGoHome() {
    if (_finishHandled) return;
    _finishHandled = true;
    _warmEncounterCacheInBackground();
    if (mounted) _navigateAfterSync();
  }

  /// Prefetch today's completed-visit ids so Home's first queue build is warm.
  /// Recompute / dashboard refresh is handled by [PostSyncRefresher.attach].
  void _warmEncounterCacheInBackground() {
    final encounters = context.read<EncounterDao>();
    unawaited(() async {
      try {
        await encounters.completedTodayPatientIds();
        debugPrint('[Sync] encounter cache warmed (background)');
      } catch (e) {
        debugPrint('[Sync] Failed to warm encounter cache (background): $e');
      }
    }());
  }

  void _navigateAfterSync() {
    context.go('/home');
  }

  Future<void> _retry() async {
    setState(() {
      _progress = SyncProgress.initial;
      _report = null;
      _syncStarted = false;
      _finishHandled = false;
      _blockedNoAuth = false;
    });
    await _startSync();
  }

  void _continueOffline() {
    if (_blockedNoAuth) return;
    context.go('/home');
  }

  void _returnToLogin() {
    context.go('/login');
  }

  String _friendlyError(String? raw) {
    if (raw == null || raw.isEmpty) return SyncStrings.syncErrorGeneric;
    if (_blockedNoAuth) return SyncStrings.syncErrorSessionExpired;
    final lower = raw.toLowerCase();
    if (lower.contains('not authenticated') ||
        lower.contains('session expired') ||
        lower.contains('401')) {
      return SyncStrings.syncErrorSessionExpired;
    }
    if (lower.contains('host lookup') ||
        lower.contains('no address associated') ||
        lower.contains('connection error') ||
        lower.contains('socketexception') ||
        lower.contains('network is unreachable')) {
      return SyncStrings.syncErrorNoInternet;
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return SyncStrings.syncErrorTimeout;
    }
    if (lower.contains('connection refused') ||
        lower.contains('503') ||
        lower.contains('502')) {
      return SyncStrings.syncErrorServer;
    }
    return SyncStrings.syncErrorGeneric;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasError = _progress.hasError || (_report?.errors.isNotEmpty ?? false);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Text(
                  AppStrings.appName,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppColors.pink,
                    letterSpacing: -0.5,
                  ),
                ),
              
              const SizedBox(height: 48),
              
              // Progress indicator or error icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  if (hasError) {
                    return Icon(
                      Icons.cloud_off_rounded,
                      size: 80,
                      color: scheme.error,
                    );
                  }
                  if (_progress.isComplete) {
                    return Icon(
                      Icons.check_circle_rounded,
                      size: 80,
                      color: scheme.primary,
                    );
                  }
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: _buildProgressRing(scheme),
                  );
                },
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Text(
                hasError
                    ? SyncStrings.syncFailed
                    : _progress.isComplete
                        ? SyncStrings.done
                        : SyncStrings.title,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // Subtitle / current step (or icon summary for complete)
              if (hasError)
                Text(
                  _friendlyError(_progress.error ?? _report?.errors.firstOrNull),
                  style: textTheme.bodyLarge?.copyWith(color: scheme.error),
                  textAlign: TextAlign.center,
                )
              else if (_progress.isComplete)
                _buildCompletionSummaryWidget(scheme, textTheme)
              else
                Text(
                  _progress.persistPhase?.label ?? _progress.currentStep.label,
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              
              // Progress details
              if (!hasError && !_progress.isComplete && _progress.itemsTotal > 0) ...[
                const SizedBox(height: 8),
                Text(
                  SyncStrings.stripProgress(
                    _progress.persistPhase?.label ??
                        _progress.currentStep.label,
                    _progress.itemsDone,
                    _progress.itemsTotal,
                  ),
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              
              // Linear progress indicator (show during sync or preparing)
              if (!hasError && !_progress.isComplete) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress.overallProgress > 0
                          ? _progress.overallProgress
                          : null,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
              ],
              
              // Action buttons for error state
              if (hasError) ...[
                const SizedBox(height: 32),
                if (_blockedNoAuth)
                  FilledButton.icon(
                    onPressed: _returnToLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(SyncStrings.signInAgain),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(SyncStrings.retry),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _continueOffline,
                    child: Text(SyncStrings.continueOffline),
                  ),
                ],
              ],
              
              const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildProgressRing(ColorScheme scheme) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
          Icon(
            _progress.currentStep == SyncStep.connecting
                ? Icons.cloud_sync_rounded
                : _progress.currentStep == SyncStep.fetchingPatients
                    ? Icons.people_rounded
                    : _progress.currentStep == SyncStep.fetchingFollowUps
                        ? Icons.event_note_rounded
                        : _progress.currentStep == SyncStep.fetchingReferrals
                            ? Icons.swap_horiz_rounded
                            : Icons.storage_rounded,
            size: 32,
            color: scheme.primary,
          ),
        ],
      ),
    );
  }

  /// Build a visual summary with icons for households, members, and patients.
  Widget _buildCompletionSummaryWidget(ColorScheme scheme, TextTheme textTheme) {
    if (_report == null) {
      return Text(
        SyncStrings.dataReady,
        style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        textAlign: TextAlign.center,
      );
    }

    // Use brand navy for icons - visible in both light and dark modes
    final iconColor = AppColors.navy;

    final items = <Widget>[];

    if (_report!.households > 0) {
      items.add(_SyncStatChip(
        icon: Icons.home_outlined,
        count: _report!.households,
        label: SyncStrings.households,
        color: iconColor,
      ));
    }

    if (_report!.members > 0) {
      items.add(_SyncStatChip(
        icon: Icons.people_outline,
        count: _report!.members,
        label: SyncStrings.members,
        color: iconColor,
      ));
    }

    if (_report!.patients > 0) {
      items.add(_SyncStatChip(
        icon: Icons.person_outline,
        count: _report!.patients,
        label: SyncStrings.patients,
        color: iconColor,
      ));
    }

    if (items.isEmpty) {
      return Text(
        SyncStrings.dataReady,
        style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        textAlign: TextAlign.center,
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: items,
    );
  }
}

/// Compact stat chip with icon and count for sync summary.
class _SyncStatChip extends StatelessWidget {
  const _SyncStatChip({
    required this.icon,
    required this.count,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
