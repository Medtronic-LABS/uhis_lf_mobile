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
}

// ─── Static mock data ─────────────────────────────────────────────────────────

abstract final class MockCoachingData {
  MockCoachingData._();

  static const List<CoachingModule> modules = [
    CoachingModule(
      id: 'anc-danger-signs',
      domain: CoachingDomain.anc,
      titleEn: 'ANC Danger Signs',
      titleBn: 'এএনসি বিপদ চিহ্ন',
      estimatedMinutes: 8,
      priorityToday: true,
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
                'Severe headache or blurred vision',
                'Swelling of hands, face, or feet',
                'Vaginal bleeding at any stage',
                'Reduced or absent fetal movement',
                'High fever (≥ 38°C)',
              ],
            ),
          ],
        ),
        LessonCard(
          titleEn: 'Blood Pressure Thresholds',
          titleBn: 'রক্তচাপের সীমা',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Blood pressure is the most critical vital to monitor in ANC visits.',
            ),
            ContentBlock(
              type: ContentBlockType.heading,
              text: 'Action thresholds:',
            ),
            ContentBlock(
              type: ContentBlockType.orderedList,
              items: [
                'BP ≥ 160/110 → Band 1: immediate emergency referral',
                'BP ≥ 140/90 → Band 2: refer within the day',
                'BP ≥ 130/85 → Band 3: schedule facility visit this week',
                'BP < 130/85 → Routine monitoring, document and continue',
              ],
            ),
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Always take two readings 5 minutes apart. Record the higher '
                  'of the two in the app.',
            ),
          ],
        ),
        LessonCard(
          titleEn: 'When to Refer Immediately',
          titleBn: 'তাৎক্ষণিক রেফারের সময়',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'A single danger sign triggers immediate referral — do not wait '
                  'to confirm with a second reading or a supervisor.',
            ),
            ContentBlock(
              type: ContentBlockType.heading,
              text: 'Immediate referral checklist:',
            ),
            ContentBlock(
              type: ContentBlockType.bulletList,
              items: [
                'Call the facility before sending the mother',
                'Accompany or arrange transport',
                'Bring the antenatal card and last BP reading',
                'Log the referral in the app before leaving',
                'Follow up within 24 hours',
              ],
            ),
          ],
        ),
      ],
      quiz: [
        QuizQuestion(
          questionEn: 'A pregnant woman has a BP of 165/112. What is the correct action?',
          questionBn: 'একজন গর্ভবতী মহিলার রক্তচাপ 165/112। সঠিক পদক্ষেপ কী?',
          options: [
            'Schedule a follow-up visit next week',
            'Refer to facility within the day (Band 2)',
            'Immediate emergency referral (Band 1)',
            'Advise rest and recheck in 2 hours',
          ],
          correctIndex: 2,
          rationale:
              'BP ≥ 160/110 is a Band 1 danger sign requiring immediate referral. '
              'Do not wait or recheck.',
        ),
        QuizQuestion(
          questionEn: 'Which of these is NOT an ANC danger sign?',
          questionBn: 'নিচের কোনটি এএনসি বিপদ চিহ্ন নয়?',
          options: [
            'Severe headache with blurred vision',
            'Mild ankle swelling in the third trimester',
            'Vaginal bleeding at any stage',
            'Absent fetal movement for more than 12 hours',
          ],
          correctIndex: 1,
          rationale:
              'Mild ankle swelling in the third trimester is common and not a danger sign. '
              'Face/hand swelling with headache is the concerning pattern.',
        ),
        QuizQuestion(
          questionEn: 'How many BP readings should you take before recording?',
          questionBn: 'রেকর্ড করার আগে কতটি রক্তচাপ রিডিং নেওয়া উচিত?',
          options: [
            'One — the first reading is most accurate',
            'Two, 5 minutes apart — record the higher value',
            'Three — take the average',
            'Two — record the lower value to avoid patient alarm',
          ],
          correctIndex: 1,
          rationale:
              'Protocol is two readings 5 minutes apart; record the higher of the two '
              'for safety — underreporting a high BP is more dangerous.',
        ),
      ],
    ),

    CoachingModule(
      id: 'ncd-bp-monitoring',
      domain: CoachingDomain.ncd,
      titleEn: 'NCD Blood Pressure Monitoring',
      titleBn: 'এনসিডি রক্তচাপ পর্যবেক্ষণ',
      estimatedMinutes: 6,
      priorityToday: true,
      passed: false,
      cards: [
        LessonCard(
          titleEn: 'Understanding Hypertension',
          titleBn: 'উচ্চ রক্তচাপ বোঝা',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Hypertension (high blood pressure) is the leading preventable '
                  'cause of stroke and heart disease in Bangladesh. Many patients '
                  'have no symptoms until a crisis.',
            ),
            ContentBlock(
              type: ContentBlockType.heading,
              text: 'NCD band thresholds (systolic / diastolic):',
            ),
            ContentBlock(
              type: ContentBlockType.orderedList,
              items: [
                'Band 1: BP ≥ 180/110 or one-sided weakness (stroke sign)',
                'Band 2: BP 160–179 / 100–109',
                'Band 3: BP 140–159 / 90–99',
                'Band 4: BP 130–139 / 85–89 (Routine)',
              ],
            ),
          ],
        ),
        LessonCard(
          titleEn: 'Medication Adherence Check',
          titleBn: 'ওষুধ গ্রহণ যাচাই',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Most NCD patients are on long-term antihypertensive medication. '
                  'Stopping suddenly causes rebound hypertension.',
            ),
            ContentBlock(
              type: ContentBlockType.heading,
              text: 'Questions to ask every visit:',
            ),
            ContentBlock(
              type: ContentBlockType.bulletList,
              items: [
                '"Did you take your medicine every day this week?"',
                '"Do you have enough pills for the next month?"',
                '"Any side effects — dizziness, dry cough, swelling?"',
              ],
            ),
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Log adherence in the app. Flag missed doses — the AI will '
                  'adjust the band modifier accordingly.',
            ),
          ],
        ),
      ],
      quiz: [
        QuizQuestion(
          questionEn: 'An NCD patient has a BP of 172/105 and no other symptoms. What band?',
          questionBn: 'একজন এনসিডি রোগীর রক্তচাপ 172/105 এবং অন্য কোনো লক্ষণ নেই। কোন ব্যান্ড?',
          options: [
            'Band 1 — immediate referral',
            'Band 2 — refer within the day',
            'Band 3 — facility visit this week',
            'Band 4 — routine monitoring',
          ],
          correctIndex: 1,
          rationale:
              'BP 160–179/100–109 = Band 2. No stroke signs present, so Band 1 is not triggered.',
        ),
        QuizQuestion(
          questionEn: 'A patient reports stopping their BP medication 2 weeks ago. What is the risk?',
          questionBn: 'একজন রোগী জানান তিনি ২ সপ্তাহ আগে রক্তচাপের ওষুধ বন্ধ করেছেন। ঝুঁকি কী?',
          options: [
            'No risk — the body adjusts naturally',
            'Rebound hypertension — BP may spike dangerously',
            'Lower BP — the medication was raising it',
            'Only a risk if they have diabetes too',
          ],
          correctIndex: 1,
          rationale:
              'Sudden cessation causes rebound hypertension. Always encourage adherence '
              'and escalate to the supervising clinician.',
        ),
      ],
    ),

    CoachingModule(
      id: 'imci-fever-child',
      domain: CoachingDomain.imci,
      titleEn: 'IMCI: Fever in Under-5s',
      titleBn: 'আইএমসিআই: ৫ বছরের কম শিশুর জ্বর',
      estimatedMinutes: 7,
      passed: true,
      quizScore: 0.85,
      cards: [
        LessonCard(
          titleEn: 'Assessing Fever in Children',
          titleBn: 'শিশুদের জ্বর মূল্যায়ন',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'Fever in children under 5 may indicate malaria, pneumonia, or '
                  'other serious infections. Always assess for danger signs first.',
            ),
            ContentBlock(
              type: ContentBlockType.heading,
              text: 'General danger signs in under-5s:',
            ),
            ContentBlock(
              type: ContentBlockType.bulletList,
              items: [
                'Unable to drink or breastfeed',
                'Vomiting everything',
                'Convulsions in this illness',
                'Lethargic or unconscious',
                'Stiff neck (meningitis sign)',
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

    CoachingModule(
      id: 'tb-adherence',
      domain: CoachingDomain.tb,
      titleEn: 'TB: Supporting Treatment Adherence',
      titleBn: 'টিবি: চিকিৎসা মেনে চলতে সহায়তা',
      estimatedMinutes: 5,
      passed: false,
      cards: [
        LessonCard(
          titleEn: 'Why Adherence Matters in TB',
          titleBn: 'টিবিতে কেন আনুগত্য গুরুত্বপূর্ণ',
          blocks: [
            ContentBlock(
              type: ContentBlockType.paragraph,
              text:
                  'TB is curable with a full 6-month course of antibiotics. '
                  'Missing doses creates drug-resistant TB (DR-TB) which is '
                  'much harder and more expensive to treat.',
            ),
            ContentBlock(
              type: ContentBlockType.bulletList,
              items: [
                'Full course: 6 months without break',
                'DR-TB treatment: 18–24 months, more toxic drugs',
                'DOTS (Directly Observed Treatment) — watch the patient swallow each dose',
                'Log each DOTS visit in the app',
              ],
            ),
          ],
        ),
      ],
      quiz: [
        QuizQuestion(
          questionEn: 'What does DOTS stand for?',
          questionBn: 'DOTS মানে কী?',
          options: [
            'Drug-Only Treatment Strategy',
            'Directly Observed Treatment, Short-course',
            'Daily Oral Tuberculosis Support',
            'District Outreach Treatment Service',
          ],
          correctIndex: 1,
          rationale:
              'DOTS = Directly Observed Treatment, Short-course. '
              'The SK watches each dose to ensure adherence.',
        ),
      ],
    ),
  ];

  static List<CoachingModule> get todaysPriorities =>
      modules.where((m) => m.priorityToday).toList();

  static List<CoachingModule> get allModules => modules;
}
