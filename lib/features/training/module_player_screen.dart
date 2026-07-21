/// Card-by-card lesson player for a [CoachingModule].
///
/// Layout matches the spice-coaching-android SDK `LessonPlayerScreen`:
///   - Navy SdkScreenHeader with "Learning X of N" counter
///   - White body: scrollable card title + rich body
///   - Fixed bottom row: outlined ← Prev | filled Next → / Start Quiz → / Done ✓
///
/// Engineering Design Standards:
///   - All strings from [CoachingStrings].
///   - No I/O — reads data passed in via constructor.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'coaching_models.dart';
import 'coaching_repository.dart';
import 'quiz_screen.dart';

// SDK-matched color constants (not in AppColors — kept local to this screen).
const _kTitleColor = Color(0xFF101828);
const _kBodyTextColor = Color(0xFF344054);

class ModulePlayerScreen extends StatefulWidget {
  const ModulePlayerScreen({super.key, required this.module});

  final CoachingModule module;

  @override
  State<ModulePlayerScreen> createState() => _ModulePlayerScreenState();
}

class _ModulePlayerScreenState extends State<ModulePlayerScreen> {
  int _cardIndex = 0;

  bool get _isLast => _cardIndex == widget.module.cards.length - 1;

  bool get _hasQuiz => widget.module.quiz.isNotEmpty;

  void _next() {
    context.read<CoachingRepository>().markCardViewed(widget.module.id, _cardIndex);
    if (_isLast) {
      if (_hasQuiz) {
        _launchQuiz();
      } else {
        Navigator.of(context).pop();
      }
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
    final cards = widget.module.cards;
    final card = cards[_cardIndex];
    final total = cards.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(CoachingStrings.lessonProgress(_cardIndex + 1, total)),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ── Scrollable body ────────────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: 96, // space for pinned bottom row
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card title
                Text(
                  card.titleEn,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _kTitleColor,
                      ),
                ),
                const SizedBox(height: 12),
                // Rich body
                RichCardBodyWidget(blocks: card.blocks),
              ],
            ),
          ),

          // ── Fixed bottom nav row ───────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    // Prev button — always takes half width, disabled on first card
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cardIndex > 0 ? _prev : null,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: Text(CoachingStrings.prevCard),
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Next / Start Quiz / Done button
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _next,
                        icon: Icon(
                          _isLast && _hasQuiz
                              ? Icons.quiz_rounded
                              : _isLast
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _isLast && _hasQuiz
                              ? CoachingStrings.startQuiz
                              : _isLast
                                  ? CoachingStrings.reviewCourse
                                  : CoachingStrings.nextCard,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _kBodyTextColor,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: _kTitleColor,
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(items.length, (i) {
          final bullet = ordered ? '${i + 1}.' : '•';
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    bullet,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _kBodyTextColor,
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
