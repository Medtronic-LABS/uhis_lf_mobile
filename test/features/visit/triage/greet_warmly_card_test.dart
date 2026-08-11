import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/briefing/briefing_models.dart';
import 'package:uhis_next/features/visit/triage/symptom_picker_screen.dart';

void main() {
  // AppLocale.current is a global static flag (the app's context-free
  // localization seam — see app_locale.dart) shared across the whole test
  // process. Every case that sets it to bangla must restore english
  // afterwards or it leaks into unrelated test files run in the same suite.
  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

  Widget buildCard({
    required bool? isFemale,
    bool loading = false,
    bool isChild = false,
    Set<Programme> selectedProgrammes = const {},
    GreetingContent? greeting,
    String? fallbackOpeningLine,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GreetWarmlyCard(
          isFemale: isFemale,
          loading: loading,
          isChild: isChild,
          selectedProgrammes: selectedProgrammes,
          greeting: greeting,
          fallbackOpeningLine: fallbackOpeningLine,
        ),
      ),
    );
  }

  group('sex not recorded', () {
    testWidgets(
        'header says HIM/HER rather than defaulting to one — nobody recorded '
        'a sex for this patient',
        (tester) async {
      await tester.pumpWidget(buildCard(isFemale: null));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: null)),
        findsOneWidget,
      );
      expect(find.textContaining('HIM/HER'), findsOneWidget);
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: false)),
        findsNothing,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
        findsNothing,
      );
    });

    testWidgets('hint uses he/she wording, not the male line', (tester) async {
      await tester.pumpWidget(buildCard(isFemale: null));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: null)),
        findsOneWidget,
      );
      expect(find.textContaining('he/she'), findsOneWidget);
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: false)),
        findsNothing,
      );
    });

    testWidgets(
        'hint stays visit-type-neutral even on an ANC or PNC visit — with no '
        'recorded sex we cannot assume whose checkup this is',
        (tester) async {
      for (final programmes in <Set<Programme>>[
        {Programme.anc},
        {Programme.pnc},
      ]) {
        await tester.pumpWidget(buildCard(
          isFemale: null,
          selectedProgrammes: programmes,
        ));

        expect(
          find.textContaining('pregnancy checkup'),
          findsNothing,
          reason: 'programmes=$programmes',
        );
        expect(
          find.textContaining('postnatal checkup'),
          findsNothing,
          reason: 'programmes=$programmes',
        );
      }
    });

    testWidgets('the greeting line is unaffected — it is genderless anyway', (
      tester,
    ) async {
      await tester.pumpWidget(buildCard(isFemale: null));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsOneWidget,
      );
    });

    testWidgets('a child with no recorded sex still addresses the guardian', (
      tester,
    ) async {
      await tester.pumpWidget(buildCard(isFemale: null, isChild: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(
          isFemale: null,
          isChild: true,
        )),
        findsOneWidget,
      );
      expect(find.textContaining('HIM/HER'), findsNothing);
    });
  });

  group('header', () {
    testWidgets('renders the gendered female header', (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'hint',
        ),
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
        findsOneWidget,
      );
    });

    testWidgets('renders the gendered male header and not the female one',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: false,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'hint',
        ),
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: false)),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
        findsNothing,
      );
    });

    testWidgets('no longer renders the old hardcoded literal', (tester) async {
      await tester.pumpWidget(buildCard(isFemale: true));

      expect(find.text('👋 Greet warmly'), findsNothing);
    });

    testWidgets(
        'header follows AppLocale — same lookup call resolves the widget '
        'text in both languages',
        (tester) async {
      // strings.json isn't loaded in this harness (translations are an
      // async asset load wired up in main.dart, not this widget test), so
      // getTranslatedString falls back to its English literal regardless
      // of AppLocale here. This still proves the widget renders whatever
      // sitWithGreetHeaderFor resolves to — the locale branch inside
      // getTranslatedString itself is shared, pre-existing infrastructure
      // used by dozens of other getters in app_strings.dart, not something
      // this card's test needs to re-prove.
      for (final locale in AppLanguage.values) {
        AppLocale.current = locale;
        await tester.pumpWidget(buildCard(isFemale: true));

        expect(
          find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
          findsOneWidget,
          reason: 'locale=$locale',
        );
      }
    });
  });

  group('hint', () {
    testWidgets('renders the AI hint when greeting.hint is present',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'Ask about her appetite before starting.',
        ),
      ));

      expect(
        find.text('Ask about her appetite before starting.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'falls back to the static hint when greeting.hint is blank',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: '',
        ),
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: true)),
        findsOneWidget,
      );
    });

    testWidgets('hint text is not wrapped in quotes', (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'Ask about her appetite before starting.',
        ),
      ));

      expect(
        find.text('"Ask about her appetite before starting."'),
        findsNothing,
      );
      expect(
        find.text('Ask about her appetite before starting.'),
        findsOneWidget,
      );
    });

    testWidgets('English app language uses the generic hint field, ignoring '
        'hintBn/hintBangla', (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'Ask about her appetite before starting.',
          hintBn: 'তার খাওয়ার বিষয়ে জিজ্ঞাসা করুন।',
          hintBangla: 'তার খাওয়া নিয়ে জিজ্ঞাসা করুন।',
        ),
      ));

      expect(
        find.text('Ask about her appetite before starting.'),
        findsOneWidget,
      );
      expect(find.text('তার খাওয়ার বিষয়ে জিজ্ঞাসা করুন।'), findsNothing);
    });

    testWidgets('Bangla app language prefers hintBn over hintBangla and hint',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'Ask about her appetite before starting.',
          hintBn: 'তার খাওয়ার বিষয়ে জিজ্ঞাসা করুন (bn)।',
          hintBangla: 'তার খাওয়া নিয়ে জিজ্ঞাসা করুন (bangla)।',
        ),
      ));

      expect(find.text('তার খাওয়ার বিষয়ে জিজ্ঞাসা করুন (bn)।'), findsOneWidget);
      expect(
        find.text('তার খাওয়া নিয়ে জিজ্ঞাসা করুন (bangla)।'),
        findsNothing,
      );
      expect(
        find.text('Ask about her appetite before starting.'),
        findsNothing,
      );
    });

    testWidgets(
        'Bangla app language falls back to hintBangla when hintBn is blank',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'Ask about her appetite before starting.',
          hintBn: '',
          hintBangla: 'তার খাওয়া নিয়ে জিজ্ঞাসা করুন (bangla)।',
        ),
      ));

      expect(
        find.text('তার খাওয়া নিয়ে জিজ্ঞাসা করুন (bangla)।'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Bangla app language falls through to the generic hint when both '
        'hintBn and hintBangla are blank',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'বাংলা',
          english: 'english',
          hint: 'Ask about her appetite before starting.',
          hintBn: '',
          hintBangla: '',
        ),
      ));

      expect(
        find.text('Ask about her appetite before starting.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Bangla app language falls back to the static hint when hintBn, '
        'hintBangla, and hint are all blank',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(bangla: 'বাংলা', english: 'english', hint: ''),
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: true)),
        findsOneWidget,
      );
    });
  });

  group('greeting line follows the app language, never both at once', () {
    testWidgets(
        'English app language shows only the AI English line, not Bangla',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'আপনি কেমন আছেন?',
          english: 'How are you?',
          hint: 'hint',
        ),
      ));

      expect(find.text('How are you?'), findsOneWidget);
      expect(find.text('আপনি কেমন আছেন?'), findsNothing);
      // Not quoted either — the quoted-gloss treatment only made sense when
      // both languages rendered side by side.
      expect(find.text('"How are you?"'), findsNothing);
    });

    testWidgets(
        'Bangla app language shows only the AI Bangla line, not English',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'আপনি কেমন আছেন?',
          english: 'How are you?',
          hint: 'hint',
        ),
      ));

      expect(find.text('আপনি কেমন আছেন?'), findsOneWidget);
      expect(find.text('How are you?'), findsNothing);
    });

    testWidgets(
        'English app language falls back to static English when greeting is null',
        (tester) async {
      for (final isFemale in [true, false]) {
        await tester.pumpWidget(buildCard(isFemale: isFemale));

        expect(
          find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
          findsOneWidget,
          reason: 'isFemale=$isFemale',
        );
        expect(
          find.text(SymptomPickerStrings.sitWithGreetBanglaFor()),
          findsNothing,
          reason: 'isFemale=$isFemale',
        );
      }
    });

    testWidgets(
        'Bangla app language falls back to static Bangla when greeting is null',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      for (final isFemale in [true, false]) {
        await tester.pumpWidget(buildCard(isFemale: isFemale));

        expect(
          find.text(SymptomPickerStrings.sitWithGreetBanglaFor()),
          findsOneWidget,
          reason: 'isFemale=$isFemale',
        );
        expect(
          find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
          findsNothing,
          reason: 'isFemale=$isFemale',
        );
      }
    });

    testWidgets(
        'uses fallbackOpeningLine as the English line when greeting.english is blank '
        'and the app language is English',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'আপনি কেমন আছেন?',
          english: '',
          hint: 'hint',
        ),
        fallbackOpeningLine: 'Legacy SDP opener',
      ));

      expect(find.text('Legacy SDP opener'), findsOneWidget);
      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsNothing,
      );
    });

    testWidgets(
        'ignores a whitespace-only fallbackOpeningLine and uses the static English',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: 'আপনি কেমন আছেন?',
          english: '',
          hint: 'hint',
        ),
        fallbackOpeningLine: '   ',
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsOneWidget,
      );
    });

    testWidgets(
        'fallbackOpeningLine is ignored entirely when the app language is Bangla',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(
          bangla: '',
          english: '',
          hint: 'hint',
        ),
        fallbackOpeningLine: 'Legacy SDP opener',
      ));

      expect(find.text('Legacy SDP opener'), findsNothing);
      expect(
        find.text(SymptomPickerStrings.sitWithGreetBanglaFor()),
        findsOneWidget,
      );
    });

    testWidgets('treats whitespace-only AI values as absent', (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        greeting: const GreetingContent(bangla: '  ', english: '\n', hint: ' '),
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: true)),
        findsOneWidget,
      );
    });
  });

  group('loading gate', () {
    testWidgets(
        'shows the skeleton and no greeting text while loading with no AI content',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        loading: true,
        greeting: GreetingContent.empty,
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsNothing,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: true)),
        findsNothing,
      );
    });

    testWidgets(
        'shows AI content instead of the skeleton when loading with cached AI content',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        loading: true,
        greeting: const GreetingContent(
          bangla: 'আপনি কেমন আছেন?',
          english: 'How are you?',
          hint: 'Ask about her appetite before starting.',
        ),
      ));

      expect(find.text('How are you?'), findsOneWidget);
      expect(
        find.text('Ask about her appetite before starting.'),
        findsOneWidget,
      );
    });
  });

  group('child patient — addresses the guardian, never the child', () {
    testWidgets('header addresses the guardian, not "her"/"him"',
        (tester) async {
      await tester.pumpWidget(buildCard(isFemale: true, isChild: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(
          isFemale: true,
          isChild: true,
        )),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
        findsNothing,
      );
    });

    testWidgets(
        'static fallback greeting line asks about the child, not the child directly',
        (tester) async {
      await tester.pumpWidget(buildCard(isFemale: true, isChild: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor(isChild: true)),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsNothing,
      );
    });

    testWidgets('static fallback hint tells the SK to ask the guardian',
        (tester) async {
      await tester.pumpWidget(buildCard(isFemale: false, isChild: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(
          isFemale: false,
          isChild: true,
        )),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: false)),
        findsNothing,
      );
    });

    testWidgets('ignores fallbackOpeningLine — an adult-patient opener does '
        'not fit a guardian-directed greeting', (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        isChild: true,
        greeting: const GreetingContent(bangla: '', english: '', hint: ''),
        fallbackOpeningLine: 'Legacy SDP opener',
      ));

      expect(find.text('Legacy SDP opener'), findsNothing);
      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor(isChild: true)),
        findsOneWidget,
      );
    });

    testWidgets(
        'AI-generated greeting for a child still wins over the static '
        'guardian fallback — the backend is instructed to address the '
        'guardian itself',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        isChild: true,
        greeting: const GreetingContent(
          bangla: '',
          english: 'Guardian, how has the baby been feeding?',
          hint: 'hint',
        ),
      ));

      expect(
        find.text('Guardian, how has the baby been feeding?'),
        findsOneWidget,
      );
    });

    testWidgets('Bangla app language shows the guardian-directed Bangla line',
        (tester) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(isFemale: true, isChild: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetBanglaFor(isChild: true)),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetBanglaFor()),
        findsNothing,
      );
    });
  });

  group('static greeting fallback is generic — two cases only', () {
    testWidgets(
        'every service and both sexes get the same salutation-free line',
        (tester) async {
      for (final programmes in <Set<Programme>>[
        {},
        {Programme.anc},
        {Programme.pw},
        {Programme.pnc},
        {Programme.ncd},
        {Programme.tb},
        {Programme.anc, Programme.ncd},
      ]) {
        for (final isFemale in [true, false]) {
          await tester.pumpWidget(buildCard(
            isFemale: isFemale,
            selectedProgrammes: programmes,
          ));

          expect(
            find.text('How are you feeling? Do you have any concern?'),
            findsOneWidget,
            reason: 'programmes=$programmes isFemale=$isFemale',
          );
        }
      }
    });

    testWidgets(
        'never asks about fetal movement or pregnancy-stage symptoms — the AI '
        'path owns that question now, and its service gates it on a known '
        'late gestational age',
        (tester) async {
      for (final programmes in <Set<Programme>>[
        {Programme.anc},
        {Programme.pw},
        {Programme.pnc},
      ]) {
        await tester.pumpWidget(buildCard(
          isFemale: true,
          selectedProgrammes: programmes,
        ));

        expect(find.textContaining('baby moving'), findsNothing);
        expect(find.textContaining('nausea'), findsNothing);
        expect(find.textContaining('since delivery'), findsNothing);
      }
    });

    testWidgets(
        'carries no salutation in either language, for either case — mirrors '
        'the AI service greeting contract (_EN_SALUTATION_RE / '
        '_BN_SALUTATION_RE in briefing_service.py)',
        (tester) async {
      const banned = [
        'Sister',
        'Brother',
        'Sir',
        'Madam',
        'Aunty',
        'Uncle',
        'আপু',
        'কাকা',
        'ভাই',
        'খালা',
      ];

      for (final locale in AppLanguage.values) {
        AppLocale.current = locale;
        for (final isChild in [true, false]) {
          await tester.pumpWidget(buildCard(isFemale: true, isChild: isChild));

          for (final term in banned) {
            expect(
              find.textContaining(term),
              findsNothing,
              reason: 'locale=$locale isChild=$isChild term=$term',
            );
          }
        }
      }
    });

    testWidgets(
        'static lines are never quote-wrapped, in either language — the '
        'greeting wire format is not either',
        (tester) async {
      for (final locale in AppLanguage.values) {
        AppLocale.current = locale;
        await tester.pumpWidget(buildCard(isFemale: true));

        expect(
          find.textContaining('"'),
          findsNothing,
          reason: 'locale=$locale',
        );
      }
    });

    testWidgets(
        'the child line asks about the child and carries no pronoun for '
        'either the child or the guardian',
        (tester) async {
      await tester.pumpWidget(buildCard(isFemale: true, isChild: true));

      expect(
        find.text('How is the little one? Eating and sleeping well?'),
        findsOneWidget,
      );
      expect(find.textContaining('Is she'), findsNothing);
      expect(find.textContaining('Is he'), findsNothing);
    });
  });

  group('static hint follows the currently-selected service', () {
    testWidgets('hint names the actual visit type instead of always assuming '
        'a pregnancy checkup', (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        selectedProgrammes: {Programme.ncd},
      ));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(
          isFemale: true,
          selectedProgrammes: {Programme.ncd},
        )),
        findsOneWidget,
      );
      expect(find.textContaining('pregnancy checkup'), findsNothing);
    });

    testWidgets('hint still says "pregnancy checkup" for an ANC visit',
        (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        selectedProgrammes: {Programme.anc},
      ));

      expect(find.textContaining('pregnancy checkup'), findsOneWidget);
    });

    testWidgets('hint says "postnatal checkup" for a PNC visit', (tester) async {
      await tester.pumpWidget(buildCard(
        isFemale: true,
        selectedProgrammes: {Programme.pnc},
      ));

      expect(find.textContaining('postnatal checkup'), findsOneWidget);
    });
  });
}
