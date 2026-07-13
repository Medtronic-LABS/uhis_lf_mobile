import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/assistant/assistant_models.dart';

/// The action allowlist is safety-critical: the LLM may only *select* from a
/// fixed set, and any unknown value must fold to a no-op so a stray/injected
/// action can never trigger navigation.
void main() {
  group('AssistantActionType.fromWire', () {
    test('maps known wire tags', () {
      expect(AssistantActionType.fromWire('start_visit'),
          AssistantActionType.startVisit);
      expect(AssistantActionType.fromWire('open_referral'),
          AssistantActionType.openReferral);
      expect(AssistantActionType.fromWire('schedule_followup'),
          AssistantActionType.scheduleFollowUp);
      expect(AssistantActionType.fromWire('call_patient'),
          AssistantActionType.callPatient);
    });

    test('unknown / null / injected values fold to none', () {
      expect(AssistantActionType.fromWire('delete_patient'),
          AssistantActionType.none);
      expect(AssistantActionType.fromWire(null), AssistantActionType.none);
      expect(AssistantActionType.fromWire(''), AssistantActionType.none);
      expect(AssistantActionType.fromWire('DROP TABLE'),
          AssistantActionType.none);
    });
  });

  group('AssistantAction.fromJson', () {
    test('parses a valid action with label', () {
      final a = AssistantAction.fromJson(
          {'type': 'start_visit', 'label': 'Start visit now'});
      expect(a, isNotNull);
      expect(a!.type, AssistantActionType.startVisit);
      expect(a.label, 'Start visit now');
    });

    test('supplies a default label when missing', () {
      final a = AssistantAction.fromJson({'type': 'open_referral'});
      expect(a!.label, 'Open referral');
    });

    test('returns null for an unknown action (dropped, not rendered)', () {
      expect(AssistantAction.fromJson({'type': 'launch_missiles'}), isNull);
    });
  });

  group('AssistantAnswer', () {
    test('defaults to no actions', () {
      const ans = AssistantAnswer(text: 'hello');
      expect(ans.actions, isEmpty);
    });
  });

  group('ChatMessage', () {
    test('assistant message can carry actions; defaults empty', () {
      final m = ChatMessage(
        role: MessageRole.assistant,
        text: 'x',
        timestamp: DateTime(2026),
        actions: const [
          AssistantAction(
              type: AssistantActionType.startVisit, label: 'Start visit')
        ],
      );
      expect(m.actions, hasLength(1));
      final u = ChatMessage(
          role: MessageRole.user, text: 'q', timestamp: DateTime(2026));
      expect(u.actions, isEmpty);
    });
  });
}
