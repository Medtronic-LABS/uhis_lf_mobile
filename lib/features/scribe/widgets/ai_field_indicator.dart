import 'package:flutter/material.dart';

import '../models/ai_extracted_field.dart';

/// A small badge showing the confidence level of an AI-extracted field.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.confidence,
    this.size = 16,
    this.showLabel = false,
  });

  final double confidence;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final level = AIConfidenceLevel.fromScore(confidence);
    final color = _colorForLevel(level);
    final label = _labelForLevel(level);

    if (showLabel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Icon(
        Icons.auto_awesome,
        size: size * 0.6,
        color: color,
      ),
    );
  }

  Color _colorForLevel(AIConfidenceLevel level) {
    switch (level) {
      case AIConfidenceLevel.high:
        return const Color(0xFF2E7D32); // Green
      case AIConfidenceLevel.medium:
        return const Color(0xFFF57C00); // Orange
      case AIConfidenceLevel.low:
        return const Color(0xFFC62828); // Red
    }
  }

  String _labelForLevel(AIConfidenceLevel level) {
    switch (level) {
      case AIConfidenceLevel.high:
        return 'High confidence';
      case AIConfidenceLevel.medium:
        return 'Medium';
      case AIConfidenceLevel.low:
        return 'Review needed';
    }
  }
}

/// Shows the source segment as a tooltip when tapped.
class SourceSegmentTooltip extends StatelessWidget {
  const SourceSegmentTooltip({
    super.key,
    required this.sourceSegment,
    required this.child,
  });

  final String sourceSegment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '"$sourceSegment"',
      preferBelow: false,
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontStyle: FontStyle.italic,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// A row of controls to accept, modify, or reject an AI-extracted value.
class AIFieldControls extends StatelessWidget {
  const AIFieldControls({
    super.key,
    required this.onAccept,
    required this.onReject,
    this.onEdit,
    this.compact = false,
  });

  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback? onEdit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 18.0 : 22.0;
    final spacing = compact ? 4.0 : 8.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.check_circle, color: Colors.green[600]),
          iconSize: iconSize,
          padding: EdgeInsets.all(spacing / 2),
          constraints: BoxConstraints(
            minWidth: iconSize + spacing,
            minHeight: iconSize + spacing,
          ),
          tooltip: 'Accept',
          onPressed: onAccept,
        ),
        if (onEdit != null)
          IconButton(
            icon: Icon(Icons.edit, color: Colors.blue[600]),
            iconSize: iconSize,
            padding: EdgeInsets.all(spacing / 2),
            constraints: BoxConstraints(
              minWidth: iconSize + spacing,
              minHeight: iconSize + spacing,
            ),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
        IconButton(
          icon: Icon(Icons.cancel, color: Colors.red[600]),
          iconSize: iconSize,
          padding: EdgeInsets.all(spacing / 2),
          constraints: BoxConstraints(
            minWidth: iconSize + spacing,
            minHeight: iconSize + spacing,
          ),
          tooltip: 'Reject',
          onPressed: onReject,
        ),
      ],
    );
  }
}

/// Wraps a form field with AI indicator and controls.
/// Shows the AI badge if the field was populated by AI.
class AIFieldWrapper extends StatelessWidget {
  const AIFieldWrapper({
    super.key,
    required this.child,
    required this.aiField,
    required this.onAccept,
    required this.onReject,
    this.onEdit,
    this.showSourceOnTap = true,
  });

  final Widget child;
  final AIExtractedField? aiField;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback? onEdit;
  final bool showSourceOnTap;

  @override
  Widget build(BuildContext context) {
    if (aiField == null) {
      return child;
    }

    final field = aiField!;
    final isPending = field.source == FieldSource.aiPending;
    final isAccepted = field.source == FieldSource.aiAccepted;
    final isModified = field.source == FieldSource.aiModified;
    final isRejected = field.source == FieldSource.aiRejected;

    // Border color based on state
    Color borderColor;
    if (isPending) {
      borderColor = _colorForConfidence(field.confidence);
    } else if (isAccepted) {
      borderColor = const Color(0xFF2E7D32).withValues(alpha: 0.5);
    } else if (isModified) {
      borderColor = const Color(0xFF1565C0).withValues(alpha: 0.5);
    } else if (isRejected) {
      borderColor = Colors.grey.withValues(alpha: 0.3);
    } else {
      borderColor = Colors.transparent;
    }

    Widget wrapped = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Field content
          child,

          // AI indicator bar
          if (!isRejected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  ConfidenceBadge(
                    confidence: field.confidence,
                    showLabel: true,
                  ),
                  const Spacer(),
                  if (isPending)
                    AIFieldControls(
                      onAccept: onAccept,
                      onReject: onReject,
                      onEdit: onEdit,
                      compact: true,
                    )
                  else if (isAccepted)
                    _StatusChip(
                      label: 'Accepted',
                      icon: Icons.check,
                      color: const Color(0xFF2E7D32),
                    )
                  else if (isModified)
                    _StatusChip(
                      label: 'Modified',
                      icon: Icons.edit,
                      color: const Color(0xFF1565C0),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    // Add source segment tooltip if available
    if (showSourceOnTap && field.sourceSegment != null) {
      wrapped = SourceSegmentTooltip(
        sourceSegment: field.sourceSegment!,
        child: wrapped,
      );
    }

    return wrapped;
  }

  Color _colorForConfidence(double confidence) =>
      switch (AIConfidenceLevel.fromScore(confidence)) {
        AIConfidenceLevel.high => const Color(0xFF2E7D32),
        AIConfidenceLevel.medium => const Color(0xFFF57C00),
        AIConfidenceLevel.low => const Color(0xFFC62828),
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A floating AI scribe button that can be placed in a form.
class AIScribeFloatingButton extends StatelessWidget {
  const AIScribeFloatingButton({
    super.key,
    required this.isRecording,
    required this.isProcessing,
    required this.onPressed,
    this.pendingFieldCount = 0,
  });

  final bool isRecording;
  final bool isProcessing;
  final VoidCallback onPressed;
  final int pendingFieldCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton.extended(
          onPressed: isProcessing ? null : onPressed,
          backgroundColor:
              isRecording ? Colors.red : Theme.of(context).primaryColor,
          icon: isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Icon(
                  isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                ),
          label: Text(
            isProcessing
                ? 'Processing...'
                : isRecording
                    ? 'Stop'
                    : 'AI Scribe',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        if (pendingFieldCount > 0)
          Positioned(
            top: -8,
            right: -8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$pendingFieldCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A banner showing AI prefill summary that can be dismissed.
class AIPreFillBanner extends StatelessWidget {
  const AIPreFillBanner({
    super.key,
    required this.fieldCount,
    required this.onAcceptAll,
    required this.onReviewAll,
    required this.onDismiss,
  });

  final int fieldCount;
  final VoidCallback onAcceptAll;
  final VoidCallback onReviewAll;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue[50]!,
            Colors.purple[50]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: Colors.blue[700],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Scribe',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$fieldCount fields extracted from recording',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReviewAll,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Review All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue[700],
                    side: BorderSide(color: Colors.blue[300]!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onAcceptAll,
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Accept All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
