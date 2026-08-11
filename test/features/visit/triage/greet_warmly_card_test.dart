import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/triage/symptom_picker_screen.dart';

/// [GreetWarmlyCard] is entirely local — it takes no briefing data and makes
/// no network call, so the opener the SK reads at the door is the same every
/// time and is available offline.
///
/// The card used to prefer an AI-generated greeting block and fall back to
/// this copy only when it was missing. The tests that exercised that path
/// were removed with it; what remains covers the copy the SK actually sees.
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
    bool isChild = false,
    Set<Programme> selectedProgrammes = const {},
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GreetWarmlyCard(
          isFemale: isFemale,
          isChild: isChild,
          selectedProgrammes: selectedProgrammes,
        ),
      ),
    );
  }

  group('local-only', () {
    testWidgets('renders the greeting on the very first frame', (tester) async {
      // Declared, not assumed: AppLocale.current defaults to bangla (BD-first),
      // and this group runs before any tearDown has restored english.
      AppLocale.current = AppLanguage.english;

      // pump() once, deliberately not pumpAndSettle(): nothing is awaited, so
      // the SK never sees a skeleton or an empty card while a briefing call is
      // in flight. This is the whole point of dropping the remote path.
      await tester.pumpWidget(buildCard(isFemale: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: true)),
        findsOneWidget,
      );
    });

    testWidgets('renders identically across rebuilds', (tester) async {
      // A server-sourced greeting could word itself differently between two
      // visits to the same patient. Local copy cannot.
      await tester.pumpWidget(buildCard(isFemale: true));
      final first = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();

      await tester.pumpWidget(buildCard(isFemale: true));
      final second = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();

      expect(second, first);
    });
  });

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

        expect(find.textContaining('pregnancy checkup'), findsNothing,
            reason: 'programmes=$programmes');
        expect(find.textContaining('postnatal checkup'), findsNothing,
            reason: 'programmes=$programmes');
      }
    });

    testWidgets('the greeting line is unaffected — it is genderless anyway',
        (tester) async {
      await tester.pumpWidget(buildCard(isFemale: null));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsOneWidget,
      );
    });

    testWidgets('a child with no recorded sex still addresses the guardian',
        (tester) async {
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
      await tester.pumpWidget(buildCard(isFemale: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
        findsOneWidget,
      );
    });

    testWidgets('renders the gendered male header and not the female one', (
      tester,
    ) async {
      await tester.pumpWidget(buildCard(isFemale: false));

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
            find.text(
              SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true),
            ),
            findsOneWidget,
            reason: 'locale=$locale',
          );
        }
      },
    );
  });

  group('greeting line follows the app language, never both at once', () {
    testWidgets('Bangla app language shows only the Bangla line', (
      tester,
    ) async {
      AppLocale.current = AppLanguage.bangla;

      await tester.pumpWidget(buildCard(isFemale: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetBanglaFor()),
        findsOneWidget,
      );
    });

    testWidgets('English app language shows only the English line', (
      tester,
    ) async {
      AppLocale.current = AppLanguage.english;

      await tester.pumpWidget(buildCard(isFemale: true));

      expect(
        find.text(SymptomPickerStrings.sitWithGreetEnglishFor()),
        findsOneWidget,
      );
    });
  });

  group('child patient — addresses the guardian, never the child', () {
    testWidgets('header addresses the guardian, not "her"/"him"', (
      tester,
    ) async {
      await tester.pumpWidget(buildCard(isFemale: true, isChild: true));

      expect(
        find.text(
          SymptomPickerStrings.sitWithGreetHeaderFor(
            isFemale: true,
            isChild: true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHeaderFor(isFemale: true)),
        findsNothing,
      );
    });

    testWidgets('greeting line asks about the child, not the child directly', (
      tester,
    ) async {
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

    testWidgets('hint tells the SK to ask the guardian', (tester) async {
      await tester.pumpWidget(buildCard(isFemale: false, isChild: true));

      expect(
        find.text(
          SymptomPickerStrings.sitWithGreetHintFor(
            isFemale: false,
            isChild: true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(SymptomPickerStrings.sitWithGreetHintFor(isFemale: false)),
        findsNothing,
      );
    });

    testWidgets('Bangla app language shows the guardian-directed Bangla line', (
      tester,
    ) async {
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

  group('the greeting line is generic — two cases only', () {
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
            await tester.pumpWidget(
              buildCard(isFemale: isFemale, selectedProgrammes: programmes),
            );

            expect(
              find.text('How are you feeling? Do you have any concern?'),
              findsOneWidget,
              reason: 'programmes=$programmes isFemale=$isFemale',
            );
          }
        }
      },
    );

    testWidgets(
      'never asks about fetal movement or pregnancy-stage symptoms at any '
      'gestational stage — the opener stays generic and the clinical '
      'questions belong to the assessment form',
      (tester) async {
        for (final programmes in <Set<Programme>>[
          {Programme.anc},
          {Programme.pw},
          {Programme.pnc},
        ]) {
          await tester.pumpWidget(
            buildCard(isFemale: true, selectedProgrammes: programmes),
          );

          expect(find.textContaining('baby moving'), findsNothing);
          expect(find.textContaining('nausea'), findsNothing);
          expect(find.textContaining('since delivery'), findsNothing);
        }
      },
    );

    testWidgets('carries no salutation in either language, for either case', (
      tester,
    ) async {
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

    testWidgets('lines are never quote-wrapped, in either language', (
      tester,
    ) async {
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
      },
    );
  });

  group('hint follows the currently-selected service', () {
    testWidgets('hint names the actual visit type instead of always assuming '
        'a pregnancy checkup', (tester) async {
      await tester.pumpWidget(
        buildCard(isFemale: true, selectedProgrammes: {Programme.ncd}),
      );

      expect(
        find.text(
          SymptomPickerStrings.sitWithGreetHintFor(
            isFemale: true,
            selectedProgrammes: {Programme.ncd},
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('pregnancy checkup'), findsNothing);
    });

    testWidgets('hint still says "pregnancy checkup" for an ANC visit', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(isFemale: true, selectedProgrammes: {Programme.anc}),
      );

      expect(find.textContaining('pregnancy checkup'), findsOneWidget);
    });

    testWidgets('hint says "postnatal checkup" for a PNC visit', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildCard(isFemale: true, selectedProgrammes: {Programme.pnc}),
      );

      expect(find.textContaining('postnatal checkup'), findsOneWidget);
    });
  });
}
