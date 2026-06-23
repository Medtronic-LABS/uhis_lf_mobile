import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../referral_api_service.dart';

/// Panel for viewing and adding notes/comments to a referral.
class NotesPanel extends StatefulWidget {
  const NotesPanel({
    super.key,
    required this.referralId,
    required this.notes,
    this.onAddNote,
    this.isLoading = false,
  });

  final String referralId;
  final List<ReferralNote> notes;
  final Future<bool> Function(String note)? onAddNote;
  final bool isLoading;

  /// Show as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String referralId,
    required List<ReferralNote> notes,
    Future<bool> Function(String note)? onAddNote,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => NotesPanel(
          referralId: referralId,
          notes: notes,
          onAddNote: onAddNote,
        ),
      ),
    );
  }

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.notes_rounded,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notes & Comments',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${widget.notes.length} note${widget.notes.length == 1 ? '' : 's'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Notes list
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : widget.notes.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: widget.notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final note = widget.notes[widget.notes.length - 1 - index];
                          return _NoteCard(note: note);
                        },
                      ),
          ),

          // Add note input
          if (widget.onAddNote != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Add a note...',
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _submitNote(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSubmitting || _controller.text.isEmpty
                        ? null
                        : _submitNote,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 48,
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Notes Yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add notes to track communication and updates for this referral.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitNote() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.onAddNote == null) return;

    setState(() => _isSubmitting = true);
    try {
      final success = await widget.onAddNote!(text);
      if (success && mounted) {
        _controller.clear();
        _focusNode.unfocus();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final ReferralNote note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isSystemNote = note.type == 'system' || note.type == 'auto';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSystemNote
            ? scheme.surfaceContainerLow
            : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              if (isSystemNote) ...[
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.outline,
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSystemNote
                      ? scheme.outlineVariant.withValues(alpha: 0.5)
                      : scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  note.author ?? 'Unknown',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSystemNote
                        ? scheme.outline
                        : scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatTime(note.createdAt),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Content
          Text(
            note.content,
            style: textTheme.bodyMedium?.copyWith(
              color: isSystemNote
                  ? scheme.onSurface.withValues(alpha: 0.7)
                  : null,
              fontStyle: isSystemNote ? FontStyle.italic : null,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return DateFormat.MMMd().format(dateTime);
  }
}
