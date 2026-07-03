/// MCQ quiz screen — shown after completing all lesson cards in a module.
///
/// Flow: question → tap option → immediate per-question feedback (green/red) →
/// "Next" → … → result card (score, pass/fail, try-again or back).
///
/// Pass threshold: ≥ 70% correct.
///
/// Engineering Design Standards:
///   - All strings from [CoachingStrings].
///   - No I/O — reads mock data passed in via constructor.
library;

import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import 'coaching_models.dart';
import 'module_player_screen.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.module});

  final CoachingModule module;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const double _passThreshold = 0.70;

  int _questionIndex = 0;
  int? _selectedOption;
  bool _answered = false;
  int _correctCount = 0;
  bool _done = false;

  List<QuizQuestion> get _questions => widget.module.quiz;

  QuizQuestion get _current => _questions[_questionIndex];

  bool get _isCorrect => _selectedOption == _current.correctIndex;

  void _selectOption(int index) {
    if (_answered) return;
    setState(() {
      _selectedOption = index;
      _answered = true;
      if (index == _current.correctIndex) _correctCount++;
    });
  }

  void _advance() {
    if (_questionIndex < _questions.length - 1) {
      setState(() {
        _questionIndex++;
        _selectedOption = null;
        _answered = false;
      });
    } else {
      setState(() => _done = true);
    }
  }

  void _restart() {
    setState(() {
      _questionIndex = 0;
      _selectedOption = null;
      _answered = false;
      _correctCount = 0;
      _done = false;
    });
  }

  void _backToModule() {
    Navigator.of(context).pop();
  }

  void _reviewModule() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ModulePlayerScreen(module: widget.module),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _ResultScreen(this);
    return _QuestionScreen(this);
  }
}

// ─── Active question screen ───────────────────────────────────────────────────

class _QuestionScreen extends StatelessWidget {
  const _QuestionScreen(this.state);

  final _QuizScreenState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = state._current;
    final total = state._questions.length;
    final idx = state._questionIndex;
    final progress = (idx + 1) / total;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(CoachingStrings.quizTitle),
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Question counter ────────────────────────────────────
                  Text(
                    CoachingStrings.questionProgress(idx + 1, total),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),

                  // ── Question text ───────────────────────────────────────
                  Card(
                    color: AppColors.aiSurfaceStart,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.h5xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q.questionEn,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            q.questionBn,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.h6xl),

                  // ── Options ─────────────────────────────────────────────
                  ...List.generate(q.options.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      child: _OptionTile(
                        label: q.options[i],
                        index: i,
                        selectedIndex: state._selectedOption,
                        correctIndex: q.correctIndex,
                        answered: state._answered,
                        onTap: () => state._selectOption(i),
                      ),
                    );
                  }),

                  // ── Rationale (shown after answering) ───────────────────
                  if (state._answered)
                    _RationaleCard(
                      correct: state._isCorrect,
                      rationale: q.rationale,
                    ),
                ],
              ),
            ),
          ),

          // ── Next button ────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxxl,
                AppSpacing.md,
                AppSpacing.xxxl,
                AppSpacing.xxxl,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state._answered ? state._advance : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.aiPurpleDark,
                  ),
                  child: const Text(CoachingStrings.nextQuestion),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Option tile ──────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.correctIndex,
    required this.answered,
    required this.onTap,
  });

  final String label;
  final int index;
  final int? selectedIndex;
  final int correctIndex;
  final bool answered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = selectedIndex == index;
    final isCorrect = index == correctIndex;

    Color borderColor = AppColors.border;
    Color bgColor = AppColors.cardSurface;
    Color textColor = AppColors.textPrimary;
    IconData? trailingIcon;

    if (answered) {
      if (isCorrect) {
        borderColor = AppColors.statusSuccess;
        bgColor = AppColors.statusSuccessSurface;
        textColor = AppColors.statusSuccessText;
        trailingIcon = Icons.check_circle_rounded;
      } else if (isSelected) {
        borderColor = AppColors.statusCritical;
        bgColor = AppColors.statusCriticalSurface;
        textColor = AppColors.statusCriticalText;
        trailingIcon = Icons.cancel_rounded;
      }
    } else if (isSelected) {
      borderColor = AppColors.aiPurpleDark;
      bgColor = AppColors.aiSurfaceStart;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: answered ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.patRow),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxxl,
            vertical: AppSpacing.xl,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.patRow),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight:
                        (answered && isCorrect) ? FontWeight.w700 : null,
                    height: 1.4,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: AppSpacing.md),
                Icon(
                  trailingIcon,
                  size: 20,
                  color: isCorrect
                      ? AppColors.statusSuccess
                      : AppColors.statusCritical,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Rationale card ───────────────────────────────────────────────────────────

class _RationaleCard extends StatelessWidget {
  const _RationaleCard({required this.correct, required this.rationale});

  final bool correct;
  final String rationale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = correct ? AppColors.statusSuccess : AppColors.statusCritical;
    final surface = correct
        ? AppColors.statusSuccessSurface
        : AppColors.statusCriticalSurface;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.patRow),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct
                ? Icons.lightbulb_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CoachingStrings.rationaleLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  rationale,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: correct
                        ? AppColors.statusSuccessText
                        : AppColors.statusCriticalText,
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

// ─── Result screen ────────────────────────────────────────────────────────────

class _ResultScreen extends StatelessWidget {
  const _ResultScreen(this.state);

  final _QuizScreenState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = state._questions.length;
    final correct = state._correctCount;
    final score = correct / total;
    final passed = score >= _QuizScreenState._passThreshold;
    final scoreColor =
        passed ? AppColors.statusSuccess : AppColors.statusCritical;
    final scoreSurface = passed
        ? AppColors.statusSuccessSurface
        : AppColors.statusCriticalSurface;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(CoachingStrings.quizResult),
        backgroundColor: AppColors.aiPurpleDark,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Score circle ─────────────────────────────────────────────
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: scoreSurface,
                shape: BoxShape.circle,
                border: Border.all(color: scoreColor, width: 3),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(score * 100).round()}%',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scoreColor,
                      ),
                    ),
                    Text(
                      CoachingStrings.quizScore(correct, total),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.h6xl),

            // ── Pass / fail message ──────────────────────────────────────
            Icon(
              passed
                  ? Icons.emoji_events_rounded
                  : Icons.replay_rounded,
              size: 40,
              color: scoreColor,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              passed ? CoachingStrings.quizPassed : CoachingStrings.quizFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.h8xl),

            // ── CTAs ─────────────────────────────────────────────────────
            if (!passed) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: state._reviewModule,
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('Review Module'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state._restart,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text(CoachingStrings.tryAgain),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.aiPurpleDark,
                  ),
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state._backToModule,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(CoachingStrings.backToModules),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.statusSuccessAction,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
