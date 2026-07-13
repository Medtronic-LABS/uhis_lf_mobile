/// Domain models + static mock data for the micro-coaching pilot.
///
/// No API calls — all content is hardcoded here until the coaching backend
/// endpoints are approved and added to endpoints.dart.
///
/// Engineering Design Standards:
///   - Pure data — no Flutter deps, no I/O.
///   - Single source of mock content; screens import this file only.
library;

enum CoachingDomain { anc, ncd, imci, tb, epi, nutrition }

/// A single SK row in the leaderboard card.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.initials,
    required this.name,
    required this.wardLabel,
    required this.videoCount,
    required this.points,
    this.rankChange,
    this.isCurrentUser = false,
    this.weeklyRankChangeLabel,
  });

  final int rank;
  final String initials;
  final String name;
  final String wardLabel;
  final int videoCount;
  final int points;
  /// Positive = moved up, negative = moved down, null = unchanged.
  final int? rankChange;
  final bool isCurrentUser;
  /// Extra sub-text shown only for the current user, e.g. "↑2 this week".
  final String? weeklyRankChangeLabel;
}

/// Aggregate progress stats for the monthly progress card.
class MonthlyStats {
  const MonthlyStats({
    required this.videosWatched,
    required this.pointsEarned,
    required this.dayStreak,
  });

  final int videosWatched;
  final int pointsEarned;
  final int dayStreak;
}

enum ContentBlockType { paragraph, heading, bulletList, orderedList }

class ContentBlock {
  const ContentBlock({
    required this.type,
    this.text,
    this.items,
  });

  final ContentBlockType type;
  final String? text;
  final List<String>? items;
}

class LessonCard {
  const LessonCard({
    required this.titleEn,
    required this.titleBn,
    required this.blocks,
  });

  final String titleEn;
  final String titleBn;
  final List<ContentBlock> blocks;
}

class QuizQuestion {
  const QuizQuestion({
    required this.questionEn,
    required this.questionBn,
    required this.options,
    required this.correctIndex,
    required this.rationale,
  });

  final String questionEn;
  final String questionBn;
  final List<String> options;
  final int correctIndex;
  final String rationale;
}

class CoachingModule {
  const CoachingModule({
    required this.id,
    required this.domain,
    required this.titleEn,
    required this.titleBn,
    required this.estimatedMinutes,
    required this.cards,
    required this.quiz,
    this.passed = false,
    this.quizScore = 0.0,
    this.priorityToday = false,
    this.isLocked = false,
    this.isPlaying = false,
    this.progressFraction = 0.0,
    this.pointsEarned = 0,
    this.triggerReason,
    this.unlockAfterN,
  });

  final String id;
  final CoachingDomain domain;
  final String titleEn;
  final String titleBn;
  final int estimatedMinutes;
  final List<LessonCard> cards;
  final List<QuizQuestion> quiz;
  final bool passed;
  final double quizScore;
  final bool priorityToday;

  /// True if this module is locked — SK must complete earlier modules first.
  final bool isLocked;

  /// True if the SK is currently mid-video on this module.
  final bool isPlaying;

  /// Watch progress 0.0–1.0 for the thumbnail progress bar.
  final double progressFraction;

  /// Points earned on completion (shown in the Done pill badge).
  final int pointsEarned;

  /// Why this module appears today (e.g. "today's visit" → pill: "Triggered by today's visit").
  final String? triggerReason;

  /// How many more modules must be completed before this one unlocks.
  /// Null = just show "Locked" with no count.
  final int? unlockAfterN;

  bool get isCompleted => passed;
}

// ─── Static mock data ─────────────────────────────────────────────────────────

abstract final class MockCoachingData {
  MockCoachingData._();

  static const List<LeaderboardEntry> leaderboard = [
    LeaderboardEntry(
      rank: 1,
      initials: 'SR',
      name: 'Sumaiya Rahman',
      wardLabel: 'Ward 2',
      videoCount: 18,
      points: 980,
    ),
    LeaderboardEntry(
      rank: 2,
      initials: 'NK',
      name: 'Nasima Khatun',
      wardLabel: 'Ward 5',
      videoCount: 15,
      points: 845,
    ),
    LeaderboardEntry(
      rank: 4,
      initials: 'FB',
      name: 'Fatema Begum',
      wardLabel: 'Ward 4',
      videoCount: 11,
      points: 710,
      isCurrentUser: true,
      weeklyRankChangeLabel: '↑2 this week',
    ),
    LeaderboardEntry(
      rank: 5,
      initials: 'RB',
      name: 'Roksana Begum',
      wardLabel: 'Ward 1',
      videoCount: 9,
      points: 640,
    ),
  ];

  static const MonthlyStats monthlyStats = MonthlyStats(
    videosWatched: 11,
    pointsEarned: 710,
    dayStreak: 7,
  );

  static const List<CoachingModule> modules = [
    // Module 1: IMCI — NOW PLAYING
    CoachingModule(
      id: 'imci-danger-signs-child',
      domain: CoachingDomain.imci,
      titleEn: 'Recognising danger signs in sick children',
      titleBn: 'অসুস্থ শিশুর বিপদ চিহ্ন চেনা',
      estimatedMinutes: 4,
      priorityToday: true,
      isPlaying: true,
      progressFraction: 0.4,
      triggerReason: "today's visit",
      passed: false,
      cards: [
        LessonCard(
          titleEn: 'What are ANC Danger Signs?',
          titleBn: 'এএনসি বিপদ চিহ্ন কী?',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Danger signs during pregnancy require immediate referral. '
                  'As a community health worker, recognising these signs early '
                  'can save lives.',
            ),
            ContentBlock(
              type: ContentBlockType.heading,
              text: 'Key danger signs to watch for:',
            ),
            ContentBlock(
              type: ContentBlockType.bulletList,
              items: [
                'Unable to drink or breastfeed',
                'Vomiting everything',
                'Convulsions in this illness',
                'Lethargic or unconscious',
                'Stiff neck — possible meningitis',
              ],
            ),
          ],
        ),
      ],
      quiz: [
        QuizQuestion(
          questionEn: 'Which sign requires IMMEDIATE referral in a child with fever?',
          questionBn: 'জ্বরে আক্রান্ত শিশুর ক্ষেত্রে কোন লক্ষণে তাৎক্ষণিক রেফার প্রয়োজন?',
          options: [
            'Temperature 37.8°C with runny nose',
            'Stiff neck and unable to drink',
            'Mild rash on the trunk',
            'One episode of loose stool',
          ],
          correctIndex: 1,
          rationale:
              'Stiff neck + inability to drink are IMCI general danger signs '
              'requiring immediate referral — possible meningitis.',
        ),
      ],
    ),

    // Module 2: NCD — COMPLETED
    CoachingModule(
      id: 'ncd-medicines-safely',
      domain: CoachingDomain.ncd,
      titleEn: 'Giving medicines safely at home visit',
      titleBn: 'বাড়ি পরিদর্শনে নিরাপদে ওষুধ দেওয়া',
      estimatedMinutes: 3,
      passed: true,
      pointsEarned: 80,
      progressFraction: 1.0,
      cards: [
        LessonCard(
          titleEn: 'Safe Medicine Administration',
          titleBn: 'নিরাপদ ওষুধ প্রদান',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Correct medicine administration at home visits prevents dosing '
                  'errors and improves patient outcomes.',
            ),
            ContentBlock(
              type: ContentBlockType.bulletList,
              items: [
                'Verify the patient name and medicine label',
                'Check expiry date before giving',
                'Demonstrate correct dose and timing',
                'Confirm patient understands',
              ],
            ),
          ],
        ),
      ],
      quiz: [
        QuizQuestion(
          questionEn: 'What should you check FIRST before giving a medicine?',
          questionBn: 'ওষুধ দেওয়ার আগে প্রথমে কী পরীক্ষা করবেন?',
          options: [
            'The patient\'s mood',
            'Patient name and medicine label',
            'How many tablets are left',
            'The price of the medicine',
          ],
          correctIndex: 1,
          rationale:
              'Always verify patient identity and medicine label first '
              'to prevent wrong-patient or wrong-drug errors.',
        ),
      ],
    ),

    // Module 3: ANC — NEW
    CoachingModule(
      id: 'anc-danger-signs-refer',
      domain: CoachingDomain.anc,
      titleEn: 'ANC danger signs — when to refer immediately',
      titleBn: 'এএনসি বিপদ চিহ্ন — কখন তাৎক্ষণিক রেফার করবেন',
      estimatedMinutes: 5,
      passed: false,
      cards: [
        LessonCard(
          titleEn: 'ANC Danger Signs',
          titleBn: 'এএনসি বিপদ চিহ্ন',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Danger signs during pregnancy require immediate referral. '
                  'Recognising them early can save lives.',
            ),
            ContentBlock(
              type: ContentBlockType.bulletList,
              items: [
                'Severe headache or blurred vision',
                'Swelling of hands, face, or feet',
                'Vaginal bleeding at any stage',
                'Reduced or absent fetal movement',
                'High fever (≥ 38°C)',
              ],
            ),
          ],
        ),
      ],
      quiz: [
        QuizQuestion(
          questionEn: 'A pregnant woman has BP 165/112. What is the correct action?',
          questionBn: 'গর্ভবতী মহিলার রক্তচাপ 165/112। সঠিক পদক্ষেপ কী?',
          options: [
            'Schedule follow-up next week',
            'Refer to facility within the day',
            'Immediate emergency referral',
            'Advise rest and recheck in 2 hours',
          ],
          correctIndex: 2,
          rationale:
              'BP ≥ 160/110 is a Band 1 danger sign — immediate referral, do not wait.',
        ),
      ],
    ),

    // Module 4: LOCKED — pulse oximeter
    CoachingModule(
      id: 'imci-pulse-oximeter',
      domain: CoachingDomain.imci,
      titleEn: 'Using the pulse oximeter correctly',
      titleBn: 'পালস অক্সিমিটার সঠিকভাবে ব্যবহার করা',
      estimatedMinutes: 3,
      isLocked: true,
      unlockAfterN: 2,
      cards: [],
      quiz: [],
    ),

    // Module 5: LOCKED — TB symptom screening
    CoachingModule(
      id: 'tb-symptom-screening',
      domain: CoachingDomain.tb,
      titleEn: 'TB symptom screening step-by-step',
      titleBn: 'টিবি উপসর্গ স্ক্রিনিং ধাপে ধাপে',
      estimatedMinutes: 4,
      isLocked: true,
      cards: [],
      quiz: [],
    ),
  ];

  static List<CoachingModule> get todaysPriorities =>
      modules.where((m) => m.priorityToday).toList();

  static List<CoachingModule> get allModules => modules;
}
