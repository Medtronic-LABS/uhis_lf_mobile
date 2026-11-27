import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/endpoints.dart';
import 'package:uhis_next/features/assistant/assistant_models.dart';
import 'package:uhis_next/features/assistant/assistant_repository.dart';

import '../../helpers/scripted_dio_adapter.dart';
import '../../helpers/scripted_frappe_client.dart';

const _ctx = {'ageYears': 30};

void main() {
  test('patient-scoped ask goes to spice_next_ai with the legacy body', () async {
    final (client, adapter) = scriptedFrappeClient([
      (_) async => jsonResponseBody({
        'message': {
          'answer': 'Check her BP today.',
          'actions': [
            {'type': 'start_visit', 'label': 'Start visit'},
            {'type': 'not_allowed', 'label': 'x'},
          ],
        },
      }),
    ]);

    final answer = await AssistantRepository(client).ask(
      'What should I check?',
      patientContext: {'ageYears': 30},
      history: [
        {'role': 'user', 'text': 'hi'},
      ],
    );

    final request = adapter.requests.single;
    expect(request.path, Endpoints.assistantAsk);
    expect(request.path, startsWith('/api/method/spice_next_ai.'));
    final body = request.data as Map<String, dynamic>;
    expect(body['question'], 'What should I check?');
    expect(body['context'], 'patient-scoped');
    expect(body['patientContext'], {'ageYears': 30});
    expect(body['history'], hasLength(1));
    expect(body.containsKey('appLanguage'), isTrue);
    expect(answer.text, 'Check her BP today.');
    expect(answer.actions.map((a) => a.type), [AssistantActionType.startVisit]);
  });

  test('empty answer → AssistantException', () async {
    final (client, _) = scriptedFrappeClient([
      (_) async => jsonResponseBody({
        'message': {'answer': '', 'actions': []},
      }),
    ]);

    await expectLater(
      AssistantRepository(client).ask('q?', patientContext: _ctx),
      throwsA(isA<AssistantException>()),
    );
  });

  test('offline keeps the Dio error as the cause for analytics', () async {
    final (client, _) = scriptedFrappeClient([
      (o) async =>
          throw DioException.connectionError(requestOptions: o, reason: 'off'),
    ]);

    await expectLater(
      AssistantRepository(client).ask('q?', patientContext: _ctx),
      throwsA(
        isA<AssistantException>()
            .having((e) => e.cause, 'cause', isA<DioException>())
            .having((e) => e.statusCode, 'statusCode', isNull),
      ),
    );
  });

  test('server error keeps its status code', () async {
    final (client, _) = scriptedFrappeClient([
      (_) async => jsonResponseBody({'exc_type': 'X'}, statusCode: 503),
    ]);

    await expectLater(
      AssistantRepository(client).ask('q?', patientContext: _ctx),
      throwsA(
        isA<AssistantException>().having((e) => e.statusCode, 'statusCode', 503),
      ),
    );
  });
}
