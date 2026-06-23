import 'package:flutter/material.dart';

import '../../../core/models/referral.dart';

/// Bottom action bar for bulk operations on selected referrals.
class BulkActionsBar extends StatelessWidget {
  const BulkActionsBar({
    super.key,
    required this.selectedIds,
    required this.referrals,
    required this.onClearSelection,
    required this.onSelectAll,
    required this.onBulkEscalate,
    required this.onBulkClose,
    required this.onBulkExport,
  });

  final Set<String> selectedIds;
  final List<Referral> referrals;
  final VoidCallback onClearSelection;
  final VoidCallback onSelectAll;
  final Future<void> Function() onBulkEscalate;
  final Future<void> Function() onBulkClose;
  final Future<void> Function() onBulkExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 200),
      offset: selectedIds.isEmpty ? const Offset(0, 1) : Offset.zero,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: selectedIds.isEmpty ? 0 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selection info row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${selectedIds.length} selected',
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onClearSelection,
                      child: const Text('Clear'),
                    ),
                    if (selectedIds.length < referrals.length)
                      TextButton(
                        onPressed: onSelectAll,
                        child: const Text('Select All'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Action buttons row
                Row(
                  children: [
                    Expanded(
                      child: _BulkActionButton(
                        icon: Icons.trending_up_rounded,
                        label: 'Escalate',
                        color: scheme.tertiary,
                        onPressed: onBulkEscalate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BulkActionButton(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Close',
                        color: scheme.primary,
                        onPressed: onBulkClose,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BulkActionButton(
                        icon: Icons.file_download_outlined,
                        label: 'Export',
                        color: scheme.secondary,
                        onPressed: onBulkExport,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BulkActionButton extends StatefulWidget {
  const _BulkActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onPressed;

  @override
  State<_BulkActionButton> createState() => _BulkActionButtonState();
}

class _BulkActionButtonState extends State<_BulkActionButton> {
  bool _isLoading = false;

  Future<void> _handlePress() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('referral_bulk_action_tap'),
        onTap: _isLoading ? null : _handlePress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.color,
                  ),
                )
              else
                Icon(
                  widget.icon,
                  size: 22,
                  color: widget.color,
                ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: widget.color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable referral card wrapper that adds selection UI.
class SelectableReferralCard extends StatelessWidget {
  const SelectableReferralCard({
    super.key,
    required this.referralId,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onToggleSelection,
    required this.child,
  });

  final String referralId;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onToggleSelection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Selection overlay
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(color: scheme.primary, width: 2)
                : null,
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isSelected ? 0.95 : 1,
            child: GestureDetector(
              key: const Key('referral_card_long_press'),
              onLongPress: onToggleSelection,
              child: child,
            ),
          ),
        ),

        // Selection checkbox (shown in selection mode)
        if (isSelectionMode)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              key: const Key('referral_card_select_tap'),
              onTap: onToggleSelection,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primary
                      : scheme.surface.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? scheme.primary : scheme.outline,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: isSelected
                    ? Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: scheme.onPrimary,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Confirmation dialog for bulk actions.
class BulkActionConfirmDialog extends StatelessWidget {
  const BulkActionConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.count,
    this.isDestructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final int count;
  final bool isDestructive;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required int count,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => BulkActionConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        count: count,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDestructive
                  ? scheme.errorContainer
                  : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isDestructive ? Icons.warning_rounded : Icons.info_outline_rounded,
              color: isDestructive
                  ? scheme.onErrorContainer
                  : scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.layers_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$count referral${count == 1 ? '' : 's'} will be affected',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
