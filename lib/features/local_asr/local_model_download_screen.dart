import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import 'local_model_manager.dart';

/// Download screen for on-device AI models (ASR + LLM).
///
/// Accessible via the dashboard settings menu → "Local AI Models".
/// Shows install status, download progress, storage estimates, and live RAM.
class LocalModelDownloadScreen extends StatefulWidget {
  const LocalModelDownloadScreen({super.key});

  @override
  State<LocalModelDownloadScreen> createState() =>
      _LocalModelDownloadScreenState();
}

class _LocalModelDownloadScreenState extends State<LocalModelDownloadScreen> {
  Timer? _ramTimer;
  int _rssBytes = 0;

  @override
  void initState() {
    super.initState();
    _rssBytes = ProcessInfo.currentRss;
    _ramTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => _rssBytes = ProcessInfo.currentRss);
    });
  }

  @override
  void dispose() {
    _ramTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<LocalModelManager>();
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: AppColors.textOnNavy,
        title: const Text(
          'Local AI Models',
          style: TextStyle(
            color: AppColors.textOnNavy,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoBanner(bothInstalled: manager.bothInstalled),
            const SizedBox(height: 12),
            _RuntimeStatusBar(
              asrInstalled: manager.asrInstalled,
              llmInstalled: manager.llmInstalled,
              rssBytes: _rssBytes,
            ),
            const SizedBox(height: 12),
            _ModelCard(
              icon: Icons.mic_rounded,
              iconColor: AppColors.aiPurple,
              title: kAsrModel.label,
              subtitle: kAsrModel.description,
              size: '${kAsrModel.sizeMb} MB',
              isInstalled: manager.asrInstalled,
              isDownloading: manager.asrDownloading,
              progress: manager.asrProgress,
              error: manager.asrError,
              onDownload: manager.downloadAsr,
              onDelete: manager.deleteAsr,
            ),
            const SizedBox(height: 12),
            _LlmCard(manager: manager),
            const SizedBox(height: 24),
            if (manager.bothInstalled) _DoneCard(),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.bothInstalled});
  final bool bothInstalled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.aiPurpleDark, AppColors.aiPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.offline_bolt_rounded,
              color: AppColors.textOnNavy,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offline Voice Form Fill',
                  style: TextStyle(
                    color: AppColors.textOnNavy,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  bothInstalled
                      ? 'Both models installed. Voice form fill works offline.'
                      : 'Download both models to enable on-device ASR + form fill '
                          'without internet.',
                  style: TextStyle(
                    color: AppColors.textOnNavy.withValues(alpha: 0.80),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.size,
    required this.isInstalled,
    required this.isDownloading,
    this.progress,
    this.error,
    required this.onDownload,
    required this.onDelete,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String size;
  final bool isInstalled;
  final bool isDownloading;
  final double? progress;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInstalled
              ? AppColors.statusSuccess.withValues(alpha: 0.35)
              : AppColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      size,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (isInstalled)
                _StatusChip(
                  label: 'Installed',
                  color: AppColors.statusSuccess,
                )
              else if (!isDownloading)
                _StatusChip(
                  label: 'Not installed',
                  color: AppColors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
          if (isDownloading) ...[
            const SizedBox(height: 14),
            _ProgressBar(progress: progress ?? 0),
            const SizedBox(height: 6),
            Text(
              progress != null
                  ? '${(progress! * 100).toStringAsFixed(0)}% downloaded'
                  : 'Starting...',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ] else ...[
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                'Error: $error',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.statusCritical,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (!isInstalled)
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(error != null ? 'Retry' : 'Download'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.aiPurple,
                      foregroundColor: AppColors.textOnNavy,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: AppColors.statusCritical,
                    ),
                    label: const Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.statusCritical,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// LLM card with model size selector (0.6B vs 1.7B).
class _LlmCard extends StatelessWidget {
  const _LlmCard({required this.manager});
  final LocalModelManager manager;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: manager.llmInstalled
              ? AppColors.statusSuccess.withValues(alpha: 0.35)
              : AppColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: AppColors.navy,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LLM for Form Fill',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Qwen3 — 100+ languages including Bengali',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (manager.llmInstalled)
                _StatusChip(
                  label: 'Installed',
                  color: AppColors.statusSuccess,
                )
              else if (!manager.llmDownloading)
                _StatusChip(
                  label: 'Not installed',
                  color: AppColors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Model size selector
          if (!manager.llmInstalled && !manager.llmDownloading) ...[
            const Text(
              'Choose model size:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _SizeOption(
                  spec: kLlmModelTiny,
                  isSelected:
                      manager.activeLlm.id == kLlmModelTiny.id,
                  onTap: () =>
                      manager.downloadLlm(spec: kLlmModelTiny),
                  recommended: true,
                ),
                const SizedBox(width: 8),
                _SizeOption(
                  spec: kLlmModelSmall,
                  isSelected:
                      manager.activeLlm.id == kLlmModelSmall.id,
                  onTap: () =>
                      manager.downloadLlm(spec: kLlmModelSmall),
                ),
                const SizedBox(width: 8),
                _SizeOption(
                  spec: kLlmModelLarge,
                  isSelected:
                      manager.activeLlm.id == kLlmModelLarge.id,
                  onTap: () =>
                      manager.downloadLlm(spec: kLlmModelLarge),
                ),
              ],
            ),
          ] else if (manager.llmDownloading) ...[
            _ProgressBar(progress: manager.llmProgress ?? 0),
            const SizedBox(height: 6),
            Text(
              manager.llmProgress != null
                  ? '${(manager.llmProgress! * 100).toStringAsFixed(0)}% downloaded'
                  : 'Starting...',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ] else ...[
            if (manager.llmError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Error: ${manager.llmError}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.statusCritical,
                  ),
                ),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: manager.deleteLlm,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: AppColors.statusCritical,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.statusCritical,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  manager.activeLlm.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SizeOption extends StatelessWidget {
  const _SizeOption({
    required this.spec,
    required this.isSelected,
    required this.onTap,
    this.recommended = false,
  });

  final LocalModelSpec spec;
  final bool isSelected;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.aiPurple.withValues(alpha: 0.08)
                : AppColors.cardSurfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.aiPurple : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.id == kLlmModelSmall.id ? '0.6B' : '1.7B',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? AppColors.aiPurple
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (recommended)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.aiPurple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Best',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.aiPurple,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                spec.sizeMb < 1000 ? '${spec.sizeMb} MB' : '${(spec.sizeMb / 1000).toStringAsFixed(1)} GB',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isSelected ? AppColors.aiPurple : AppColors.border,
                    foregroundColor: isSelected
                        ? AppColors.textOnNavy
                        : AppColors.textMuted,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Download'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress > 0 ? progress : null,
        backgroundColor: AppColors.progressTrack,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.aiPurple),
        minHeight: 6,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.statusSuccess.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.statusSuccess.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.statusSuccess,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ready for offline use',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.statusSuccessAction,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Voice form fill now works without internet. '
                  'Tap the mic on any visit form — '
                  'ASR and LLM timing will show in the banner.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.statusSuccessAction.withValues(alpha: 0.80),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeStatusBar extends StatelessWidget {
  const _RuntimeStatusBar({
    required this.asrInstalled,
    required this.llmInstalled,
    required this.rssBytes,
  });

  final bool asrInstalled;
  final bool llmInstalled;
  final int rssBytes;

  String get _ramLabel {
    final mb = rssBytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.memory_rounded, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            'RAM: $_ramLabel',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          _Dot(active: asrInstalled),
          const SizedBox(width: 4),
          Text(
            'ASR ${asrInstalled ? "loaded" : "not loaded"}',
            style: TextStyle(
              fontSize: 11,
              color: asrInstalled ? AppColors.statusSuccess : AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          _Dot(active: llmInstalled),
          const SizedBox(width: 4),
          Text(
            'LLM ${llmInstalled ? "loaded" : "not loaded"}',
            style: TextStyle(
              fontSize: 11,
              color: llmInstalled ? AppColors.statusSuccess : AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? AppColors.statusSuccess : AppColors.textMuted,
        shape: BoxShape.circle,
      ),
    );
  }
}
