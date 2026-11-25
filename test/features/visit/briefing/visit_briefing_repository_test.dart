import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/endpoints.dart';
import 'package:uhis_next/core/api/frappe_client.dart';
import 'package:uhis_next/features/visit/briefing/visit_briefing_repository.dart';

import '../../../helpers/scripted_dio_adapter.dart';
import '../../../helpers/scripted_frappe_client.dart';

void main() {
  const context = {'patientId': 'p-1', 'appLanguage': 'en', 'ageYears': 28};

  test('generate posts the patient context to spice_next_ai and parses the cards',
      () async {
    final (client, adapter) = scriptedFrappeClient([
      (_) async => jsonResponseBody({
        'message': {
          'patientId': 'p-1',
          'briefingCard': {
            'headline': 'ANC visit 3',
            'points': ['BP was high last time'],
          },
          'todaysPriorities': ['Check BP'],
          'suggestedDiscussionPoints': {
            'openingLine': 'How are you feeling?',
            'sections': [
              {
                'topic': 'Baby',
                'icon': 'baby',
                'questions': ['Is the baby moving?'],
              },
            ],
          },
          'greeting': {'bangla': 'b', 'english': 'e', 'hint': 'h'},
          'transitionPrompt': 'Begin the consultation.',
        },
      }),
    ]);

    final result = await VisitBriefingRepository(client).generate(
      Map.of(context),
    );

    final request = adapter.requests.single;
    expect(request.path, Endpoints.visitBriefingGenerate);
    expect(request.path, startsWith('/api/method/spice_next_ai.'));
    expect(request.data, context);
    expect(result.briefingCard.headline, 'ANC visit 3');
    expect(result.suggestedDiscussionPoints.sections.single.topic, 'Baby');
    expect(result.transitionPrompt, 'Begin the consultation.');
  });

  test('summary posts to spice_next_ai and returns the text', () async {
    final (client, adapter) = scriptedFrappeClient([
      (_) async => jsonResponseBody({
        'message': {'patientId': 'p-1', 'summary': 'Doing well.'},
      }),
    ]);

    final summary = await VisitBriefingRepository(client).summary(
      Map.of(context),
    );

    expect(adapter.requests.single.path, Endpoints.visitBriefingSummary);
    expect(summary, 'Doing well.');
  });

  test('a server error surfaces as FrappeException for the fallback path',
      () async {
    final (client, _) = scriptedFrappeClient([
      (_) async => jsonResponseBody({'exc_type': 'X'}, statusCode: 417),
    ]);

    await expectLater(
      VisitBriefingRepository(client).generate(Map.of(context)),
      throwsA(isA<FrappeException>()),
    );
  });
}
