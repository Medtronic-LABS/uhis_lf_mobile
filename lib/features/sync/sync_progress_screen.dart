import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/constants/app_strings.dart';
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

  @override
  void initState() {
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
    _progressSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startSync() async {
    if (_syncStarted) return;
    _syncStarted = true;

    final sync = context.read<OfflineSyncService>();
    
    // Subscribe to progress updates
    _progressSub = sync.progressStream.listen((progress) {
      if (mounted) {
        setState(() => _progress = progress);
      }
    });

    // Start the sync
    final report = await sync.coldSync();
    
    if (!mounted) return;
    
    setState(() => _report = report);

    // If sync completed successfully, navigate to home
    if (report.errors.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        context.go('/home');
      }
    }
  }

  Future<void> _retry() async {
    setState(() {
      _progress = SyncProgress.initial;
      _report = null;
      _syncStarted = false;
    });
    await _startSync();
  }

  void _continueOffline() {
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasError = _progress.hasError || (_report?.errors.isNotEmpty ?? false);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Image.asset(
                'assets/images/app-logo-name.png',
                height: 64,
                fit: BoxFit.contain,
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
                  _progress.error ?? _report?.errors.first ?? '',
                  style: textTheme.bodyLarge?.copyWith(color: scheme.error),
                  textAlign: TextAlign.center,
                )
              else if (_progress.isComplete)
                _buildCompletionSummaryWidget(scheme, textTheme)
              else
                Text(
                  _progress.currentStep.label,
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              
              // Progress details
              if (!hasError && !_progress.isComplete && _progress.itemsTotal > 0) ...[
                const SizedBox(height: 8),
                Text(
                  SyncStrings.progressNamed(
                    _progress.entityName,
                    _progress.itemsDone,
                    _progress.itemsTotal,
                  ),
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              
              // Linear progress indicator
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
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(SyncStrings.retry),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _continueOffline,
                  child: const Text(SyncStrings.continueOffline),
                ),
              ],
              
              const SizedBox(height: 32),
              ],
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
        'Your data is ready',
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
        'Your data is ready',
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
