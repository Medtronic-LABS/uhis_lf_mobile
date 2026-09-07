import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../local_scribe_controller.dart';

/// Badge shown when local on-device ASR + LLM was used.
///
/// Displays:
///   [Local Model]  ASR: 2.3s · LLM: 8.1s
///
/// Shown inside AiScribeBanner after a local pipeline run completes.
class LocalModelBadge extends StatelessWidget {
  const LocalModelBadge({super.key, required this.controller});

  final LocalScribeController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.result;
    final state = controller.state;

    // Show in-progress indicator while pipeline runs
    if (state == LocalScribeState.transcribing ||
        state == LocalScribeState.inferring) {
      return _buildInProgress(state);
    }

    if (result == null && state != LocalScribeState.done) {
      return const SizedBox.shrink();
    }

    return _buildResult(result);
  }

  Widget _buildInProgress(LocalScribeState state) {
    final label = state == LocalScribeState.transcribing
        ? 'Transcribing...'
        : 'Filling form...';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LocalChip(),
          const SizedBox(width: 8),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.textOnNavy,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textOnNavy.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(LocalScribeResult? result) {
    final asrLabel = result != null
        ? 'ASR: ${(result.asrDurationMs / 1000).toStringAsFixed(1)}s'
        : 'ASR: –';
    final llmLabel = result != null
        ? 'LLM: ${(result.llmDurationMs / 1000).toStringAsFixed(1)}s'
        : 'LLM: –';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LocalChip(),
          const SizedBox(width: 8),
          Text(
            '$asrLabel  ·  $llmLabel',
            style: TextStyle(
              color: AppColors.textOnNavy.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textOnNavy.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.textOnNavy.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: const Text(
        'LOCAL MODEL',
        style: TextStyle(
          color: AppColors.textOnNavy,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
