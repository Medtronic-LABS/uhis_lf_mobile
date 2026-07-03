/// Card-by-card lesson player for a [CoachingModule].
///
/// Renders lesson cards sequentially. Each card body is dispatched through
/// [RichCardBodyWidget] which handles paragraph / heading / bullet / ordered
/// block types (pilot scope — image/audio deferred to full scope).
///
/// Engineering Design Standards:
///   - All strings from [CoachingStrings].
///   - No I/O — reads mock data passed in via constructor.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'coaching_models.dart';
import 'coaching_repository.dart';
import 'quiz_screen.dart';

class ModulePlayerScreen extends StatefulWidget {
  const ModulePlayerScreen({super.key, required this.module});

  final CoachingModule module;

  @override
  State<ModulePlayerScreen> createState() => _ModulePlayerScreenState();
}

class _ModulePlayerScreenState extends State<ModulePlayerScreen> {
  int _cardIndex = 0;

  bool get _isLast => _cardIndex == widget.module.cards.length - 1;

  void _next() {
    context.read<CoachingRepository>().markCardViewed(widget.module.id, _cardIndex);
    if (_isLast) {
      _launchQuiz();
      return;
    }
    setState(() => _cardIndex++);
  }

  void _prev() {
    if (_cardIndex > 0) setState(() => _cardIndex--);
  }

  void _launchQuiz() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QuizScreen(module: widget.module),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = widget.module.cards;
    final card = cards[_cardIndex];
    final total = cards.length;
    final progress = (_cardIndex + 1) / total;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(widget.module.titleEn),
        backgroundColor: AppColors.aiPurpleDark,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.aiBorderDark,
            color: AppColors.aiPurpleLight,
            minHeight: 4,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Card counter ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxxl,
              AppSpacing.xxxl,
              AppSpacing.xxxl,
              0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  CoachingStrings.cardProgress(_cardIndex + 1, total),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '${widget.module.estimatedMinutes} ${CoachingStrings.minLabel}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          // ── Card content ───────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.h5xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card title (en)
                      Text(
                        card.titleEn,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      // Card title (bn)
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        card.titleBn,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      const Divider(height: AppSpacing.h6xl * 2),

                      // Rich content blocks
                      RichCardBodyWidget(blocks: card.blocks),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Navigation row ─────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxxl,
                AppSpacing.md,
                AppSpacing.xxxl,
                AppSpacing.xxxl,
              ),
              child: Row(
                children: [
                  if (_cardIndex > 0)
                    OutlinedButton.icon(
                      onPressed: _prev,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text(CoachingStrings.prevCard),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _next,
                    icon: Icon(
                      _isLast
                          ? Icons.quiz_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _isLast
                          ? CoachingStrings.startQuiz
                          : CoachingStrings.nextCard,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.aiPurpleDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Rich content block renderer ─────────────────────────────────────────────
// Pilot scope: paragraph, heading, bulletList, orderedList.
// Full scope adds: image, audio, video, blockquote.

class RichCardBodyWidget extends StatelessWidget {
  const RichCardBodyWidget({super.key, required this.blocks});

  final List<ContentBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((b) => _BlockView(block: b)).toList(),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block});

  final ContentBlock block;

  @override
  Widget build(BuildContext context) {
    return switch (block.type) {
      ContentBlockType.paragraph => _ParagraphBlock(text: block.text ?? ''),
      ContentBlockType.heading => _HeadingBlock(text: block.text ?? ''),
      ContentBlockType.bulletList =>
        _ListBlock(items: block.items ?? [], ordered: false),
      ContentBlockType.orderedList =>
        _ListBlock(items: block.items ?? [], ordered: true),
    };
  }
}

class _ParagraphBlock extends StatelessWidget {
  const _ParagraphBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textMid,
              height: 1.6,
            ),
      ),
    );
  }
}

class _HeadingBlock extends StatelessWidget {
  const _HeadingBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
      ),
    );
  }
}

class _ListBlock extends StatelessWidget {
  const _ListBlock({required this.items, required this.ordered});

  final List<String> items;
  final bool ordered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(items.length, (i) {
          final bullet = ordered ? '${i + 1}.' : '•';
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    bullet,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.aiPurpleDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMid,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
