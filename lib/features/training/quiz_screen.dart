/// MCQ quiz screen — shown after completing all lesson cards in a module.
///
/// Layout matches spice-coaching-android SDK QuizQuestionScreen + QuizResultScreen:
///   - Question: inline "Q N of M" counter, titleMedium SemiBold, no Card wrapper
///   - Pre-selection: disabled "Select an answer" button
///   - Post-selection: InlineAnswerFeedback (explanation callout + Next inline)
///   - Result: 72sp orange score %, badge label heading, "Your answers" list,
///     pinned Try Again (orange) + Done (primary) pill buttons
///
/// Pass threshold: ≥ 70% correct.
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

// SDK-matched local palette
const _kResultOrange = Color(0xFFC23C02);
const _kHeadingText = Color(0xFF1A1A1A);
const _kMutedText = Color(0xFF6B6B6B);
const _kDividerColor = Color(0xFFECECEC);
const _kCorrectTint = Color(0xFF2E7D52);
const _kCorrectCircleBg = Color(0xFFE6F4EC);
const _kWrongTint = Color(0xFFD9534F);
const _kWrongCircleBg = Color(0xFFFBEAEA);

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

  // Records per-question selections for the result "Your answers" list.
  late final List<int?> _answers = List.filled(widget.module.quiz.length, null);

  List<QuizQuestion> get _questions => widget.module.quiz;
  QuizQuestion get _current => _questions[_questionIndex];
  bool get _isCorrect => _selectedOption == _current.correctIndex;

  void _selectOption(int index) {
    if (_answered) return;
    setState(() {
      _selectedOption = index;
      _answered = true;
      _answers[_questionIndex] = index;
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
      final score = _correctCount / _questions.length;
      context.read<CoachingRepository>().markQuizCompleted(widget.module.id, score);
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
      for (var i = 0; i < _answers.length; i++) {
        _answers[i] = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) return _EmptyQuizScreen(module: widget.module);
    if (_done) {
      return _ResultScreen(
        questions: _questions,
        answers: _answers,
        correctCount: _correctCount,
        onRestart: _restart,
        onDone: () => Navigator.of(context).pop(),
      );
    }
    return _QuestionScreen(
      module: widget.module,
      questions: _questions,
      questionIndex: _questionIndex,
      selectedOption: _selectedOption,
      answered: _answered,
      isCorrect: _isCorrect,
      onSelect: _selectOption,
      onNext: _advance,
      onBack: () => Navigator.of(context).pop(),
    );
  }
}

// ─── Active question screen ───────────────────────────────────────────────────

class _QuestionScreen extends StatelessWidget {
  const _QuestionScreen({
    required this.module,
    required this.questions,
    required this.questionIndex,
    required this.selectedOption,
    required this.answered,
    required this.isCorrect,
    required this.onSelect,
    required this.onNext,
    required this.onBack,
  });

  final CoachingModule module;
  final List<QuizQuestion> questions;
  final int questionIndex;
  final int? selectedOption;
  final bool answered;
  final bool isCorrect;
  final void Function(int) onSelect;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = questions[questionIndex];
    final total = questions.length;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(module.titleEn),
        backgroundColor: const Color(0xFF2514BE),
        foregroundColor: Colors.white,
        leading: BackButton(onPressed: onBack),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            onPressed: onBack,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "Q N of M" counter in primary color
                  Text(
                    CoachingStrings.quizQuestionCounter(questionIndex + 1, total),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Question text — no card wrapper
                  Text(
                    q.questionEn,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Answer options
                  ...List.generate(q.options.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      child: _OptionTile(
                        label: q.options[i],
                        index: i,
                        selectedIndex: selectedOption,
                        correctIndex: q.correctIndex,
                        answered: answered,
                        onTap: () => onSelect(i),
                      ),
                    );
                  }),

                  // Inline feedback — explanation + Next button (shown after answering)
                  if (answered)
                    _InlineAnswerFeedback(
                      correct: isCorrect,
                      rationale: q.rationale,
                      onNext: onNext,
                    )
                  else
                    // Pre-selection: disabled button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(CoachingStrings.quizSelectAnswer),
                      ),
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Inline answer feedback ───────────────────────────────────────────────────

class _InlineAnswerFeedback extends StatelessWidget {
  const _InlineAnswerFeedback({
    required this.correct,
    required this.rationale,
    required this.onNext,
  });

  final bool correct;
  final String rationale;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = correct ? AppColors.statusSuccess : AppColors.statusCritical;
    final surface = correct ? AppColors.statusSuccessSurface : AppColors.statusCriticalSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Explanation callout
        Container(
          width: double.infinity,
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
                correct ? Icons.lightbulb_rounded : Icons.info_outline_rounded,
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
        ),

        const SizedBox(height: AppSpacing.xl),

        // Next button inline
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2514BE),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(CoachingStrings.nextQuestion),
          ),
        ),
      ],
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
      borderColor = AppColors.navy;
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
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: answered
                      ? (isCorrect
                          ? AppColors.statusSuccessSurface
                          : (index == (selectedIndex ?? -1)
                              ? AppColors.statusCriticalSurface
                              : bgColor))
                      : Colors.white.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: (answered && isCorrect) ? FontWeight.w700 : null,
                    height: 1.4,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: AppSpacing.md),
                Icon(
                  trailingIcon,
                  size: 20,
                  color: isCorrect ? AppColors.statusSuccess : AppColors.statusCritical,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Result screen ────────────────────────────────────────────────────────────

class _ResultScreen extends StatelessWidget {
  const _ResultScreen({
    required this.questions,
    required this.answers,
    required this.correctCount,
    required this.onRestart,
    required this.onDone,
  });

  final List<QuizQuestion> questions;
  final List<int?> answers;
  final int correctCount;
  final VoidCallback onRestart;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = questions.length;
    final score = correctCount / total;
    final passed = score >= _QuizScreenState._passThreshold;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2514BE),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(CoachingStrings.quizResult),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 48),

                // 72sp orange score %
                Text(
                  '${(score * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: _kResultOrange,
                  ),
                ),
                const SizedBox(height: 4),

                // Badge label heading
                Text(
                  CoachingStrings.badgeLabel(score),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _kHeadingText,
                  ),
                ),
                const SizedBox(height: 8),

                // Score summary
                Text(
                  CoachingStrings.quizScore(correctCount, total),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: _kMutedText),
                ),
                const SizedBox(height: 24),

                // "Your answers" section
                if (questions.isNotEmpty) ...[
                  Text(
                    CoachingStrings.yourAnswers,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _kMutedText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...List.generate(questions.length, (i) {
                    final isCorrect = answers[i] == questions[i].correctIndex;
                    return Column(
                      children: [
                        _AnswerRow(
                          questionText: questions[i].questionEn,
                          isCorrect: isCorrect,
                        ),
                        if (i < questions.length - 1)
                          Container(
                            height: 1,
                            color: _kDividerColor,
                          ),
                      ],
                    );
                  }),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),

          // Pinned bottom CTAs
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!passed) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onRestart,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kResultOrange,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          CoachingStrings.tryAgain,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onDone,
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        CoachingStrings.quizDone,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
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

// ─── Answer row ───────────────────────────────────────────────────────────────

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({required this.questionText, required this.isCorrect});

  final String questionText;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isCorrect ? _kCorrectCircleBg : _kWrongCircleBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCorrect ? Icons.check_rounded : Icons.close_rounded,
              size: 16,
              color: isCorrect ? _kCorrectTint : _kWrongTint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              questionText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _kHeadingText,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty quiz state ─────────────────────────────────────────────────────────

class _EmptyQuizScreen extends StatelessWidget {
  const _EmptyQuizScreen({required this.module});

  final CoachingModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(CoachingStrings.quizTitle),
        backgroundColor: const Color(0xFF2514BE),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.h8xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.quiz_rounded, size: 64, color: AppColors.textMuted),
              const SizedBox(height: AppSpacing.h6xl),
              Text(
                CoachingStrings.quizNotReady,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                CoachingStrings.quizNotReadySub,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.h8xl),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(CoachingStrings.backToModules),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2514BE),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
