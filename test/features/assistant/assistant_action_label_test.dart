import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/features/assistant/assistant_models.dart';

/// Locks the English wording for the assistant's action-chip labels and
/// patient-AI starter chips so the app_strings.dart localization refactor
/// cannot silently drift the copy.
void main() {
  setUp(() {
    AppLocale.current = AppLanguage.english;
  });

  // AppLocale.current is a global static flag shared across the whole test
  // process (default is bangla) — restore english so this file never leaks
  // a different locale into unrelated test files run in the same suite.
  tearDown(() {
    AppLocale.current = AppLanguage.english;
  });

  group('AssistantAction.defaultLabel', () {
    test('delegates to AssistantStrings.actionLabel for every action type',
        () {
      expect(AssistantAction.defaultLabel(AssistantActionType.startVisit),
          'Start visit');
      expect(AssistantAction.defaultLabel(AssistantActionType.openReferral),
          'Open referral');
      expect(
          AssistantAction.defaultLabel(AssistantActionType.scheduleFollowUp),
          'Schedule follow-up');
      expect(AssistantAction.defaultLabel(AssistantActionType.callPatient),
          'Call patient');
      expect(AssistantAction.defaultLabel(AssistantActionType.none), '');
    });
  });

  group('AssistantStrings.actionLabel', () {
    test('returns the exact English label for every action type', () {
      expect(AssistantStrings.actionLabel(AssistantActionType.startVisit),
          'Start visit');
      expect(AssistantStrings.actionLabel(AssistantActionType.openReferral),
          'Open referral');
      expect(
          AssistantStrings.actionLabel(AssistantActionType.scheduleFollowUp),
          'Schedule follow-up');
      expect(AssistantStrings.actionLabel(AssistantActionType.callPatient),
          'Call patient');
      expect(AssistantStrings.actionLabel(AssistantActionType.none), '');
    });
  });

  group('PatientAiStrings.starters', () {
    test('returns the 3 expected starter prompts in order', () {
      expect(PatientAiStrings.starters, [
        'Any danger signs to check?',
        'What should I do this visit?',
        'Is a referral needed?',
      ]);
    });
  });
}
