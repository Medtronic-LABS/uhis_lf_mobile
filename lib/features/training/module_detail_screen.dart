/// Module detail screen — shown before launching the lesson player.
///
/// Layout matches spice-coaching-android SDK ModuleDetailScreen:
///   - Navy AppBar + title in scroll area (no gradient header)
///   - StatsRow: SpiceBlueContainer bg, MenuBook/HelpOutline/AccessTime icons
///   - Curriculum: "Learning cards" + "Quiz" sub-sections with 36dp circles
///   - Pinned CTA row: 28dp pill Start Course / Do a Quiz; completed → Read course
///
/// Engineering Design Standards:
///   - All strings from [CoachingStrings].
///   - No I/O — reads data passed in via constructor.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import 'coaching_models.dart';
import 'coaching_repository.dart';
import 'module_player_screen.dart';
import 'quiz_screen.dart';

// SDK-matched local palette
const _kTitleColor = Color(0xFF101828);
const _kMetadataColor = Color(0xFF667085);
const _kDividerColor = Color(0xFFE4E7EC);
const _kIndexBg = Color(0xFFEFF4FF);
const _kSpiceBlueContainer = Color(0xFFE8F0FE);

String _fmtDate(DateTime d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class ModuleDetailScreen extends StatelessWidget {
  const ModuleDetailScreen({super.key, required this.module});

  final CoachingModule module;

  void _startCourse(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ModulePlayerScreen(module: module)),
    );
  }

  void _doQuiz(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => QuizScreen(module: module)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardCount = module.cards.length;
    final quizCount = module.quiz.length;
    final hasQuiz = quizCount > 0;
    final hasCards = cardCount > 0;
    final completed = module.passed;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(module.titleEn),
        backgroundColor: const Color(0xFF2514BE),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbnail — shows presigned URL from coaching backend if available
                  Builder(
                    builder: (ctx) {
                      final thumb =
                          ctx.watch<CoachingRepository>().moduleThumbnailUrl(module.id);
                      if (thumb == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            thumb,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      );
                    },
                  ),

                  // Title
                  Text(
                    module.titleEn,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: _kTitleColor,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Assigned ${_fmtDate(DateTime.now())}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _kMetadataColor,
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Stats row
                  _StatsRow(
                    cardCount: cardCount,
                    quizCount: quizCount,
                    estimatedMinutes: module.estimatedMinutes,
                  ),
                  const SizedBox(height: 24),

                  // Curriculum heading
                  Text(
                    CoachingStrings.curriculumLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _kTitleColor,
                        ),
                  ),
                  const SizedBox(height: 12),

                  // Learning cards sub-section
                  if (hasCards) ...[
                    Text(
                      CoachingStrings.detailLearningCardsSection,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2514BE),
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(cardCount, (i) {
                      final card = module.cards[i];
                      return Column(
                        children: [
                          _CurriculumRow(
                            number: i + 1,
                            title: card.titleEn,
                            subtitle: CoachingStrings.detailCurriculumCardMin,
                            isQuiz: false,
                          ),
                          if (i < cardCount - 1)
                            Divider(
                              color: _kDividerColor,
                              thickness: 0.5,
                              height: 0,
                            ),
                        ],
                      );
                    }),
                  ],

                  // Quiz sub-section
                  if (hasQuiz) ...[
                    const SizedBox(height: 16),
                    Text(
                      CoachingStrings.detailQuizSection,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2514BE),
                          ),
                    ),
                    const SizedBox(height: 8),
                    _CurriculumRow(
                      number: cardCount + 1,
                      title: CoachingStrings.detailKnowledgeCheck,
                      subtitle: CoachingStrings.quizCurriculumQuestions(quizCount),
                      isQuiz: true,
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Listen toggle stub
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.hearing_rounded, size: 16),
                    label: const Text('Listen in Bangla'),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                    ),
                  ),

                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),

          // Pinned CTA row
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: _kDividerColor, width: 0.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: completed
                  ? _ReadAgainCta(onPressed: hasCards ? () => _startCourse(context) : null)
                  : _CtaRow(
                      hasCards: hasCards,
                      hasQuiz: hasQuiz,
                      onStartCourse: hasCards ? () => _startCourse(context) : null,
                      onDoQuiz: hasQuiz ? () => _doQuiz(context) : null,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.cardCount,
    required this.quizCount,
    required this.estimatedMinutes,
  });

  final int cardCount;
  final int quizCount;
  final int estimatedMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _kSpiceBlueContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(
            icon: Icons.menu_book_rounded,
            value: '$cardCount',
            label: CoachingStrings.detailCards,
          ),
          _StatDivider(),
          _StatItem(
            icon: Icons.help_outline_rounded,
            value: '$quizCount',
            label: CoachingStrings.detailQuestions,
          ),
          _StatDivider(),
          _StatItem(
            icon: Icons.access_time_rounded,
            value: '$estimatedMinutes',
            label: CoachingStrings.minLabel,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF2514BE)),
            const SizedBox(width: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _kTitleColor,
                  ),
            ),
          ],
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _kMetadataColor,
              ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: _kDividerColor);
}

// ─── Curriculum row ───────────────────────────────────────────────────────────

class _CurriculumRow extends StatelessWidget {
  const _CurriculumRow({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.isQuiz,
  });

  final int number;
  final String title;
  final String subtitle;
  final bool isQuiz;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isQuiz ? _kSpiceBlueContainer : _kIndexBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number.toString().padLeft(2, '0'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: const Color(0xFF2514BE),
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: _kTitleColor,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _kMetadataColor,
                      ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded, size: 16, color: _kMetadataColor),
        ],
      ),
    );
  }
}

// ─── CTA rows ─────────────────────────────────────────────────────────────────

class _CtaRow extends StatelessWidget {
  const _CtaRow({
    required this.hasCards,
    required this.hasQuiz,
    required this.onStartCourse,
    required this.onDoQuiz,
  });

  final bool hasCards;
  final bool hasQuiz;
  final VoidCallback? onStartCourse;
  final VoidCallback? onDoQuiz;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasCards) ...[
          Expanded(
            child: FilledButton.icon(
              onPressed: onStartCourse,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text(CoachingStrings.startCourse),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2514BE),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (hasQuiz) const SizedBox(width: 12),
        ],
        if (hasQuiz)
          Expanded(
            child: OutlinedButton(
              onPressed: onDoQuiz,
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(CoachingStrings.doQuiz),
            ),
          ),
      ],
    );
  }
}

class _ReadAgainCta extends StatelessWidget {
  const _ReadAgainCta({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: Text(CoachingStrings.detailReadCourse),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2514BE),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
