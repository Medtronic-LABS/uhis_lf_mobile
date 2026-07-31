import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/api/realtime_asr_service.dart';

/// symptomVocab is a client-authoritative symptom vocabulary sent once at WS
/// connect time (see ai-scribe-service's app/api/realtime.py) — these tests
/// only cover URI construction, not the actual socket.
void main() {
  group('RealtimeAsrService.connectionInfo — symptomVocab', () {
    late ApiClient api;

    setUp(() async {
      api = await ApiClient.create();
      api.setTenantId('1');
    });

    test('includes symptomVocab as a comma-joined query param when provided',
        () async {
      final service = RealtimeAsrService(api);
      final info = await service.connectionInfo(
        language: 'bn-IN',
        symptomVocab: const ['fever', 'cough', 'headache'],
      );
      expect(
        info.uri.queryParameters['symptomVocab'],
        'fever,cough,headache',
      );
    });

    test('omits symptomVocab entirely when not passed', () async {
      final service = RealtimeAsrService(api);
      final info = await service.connectionInfo(language: 'bn-IN');
      expect(info.uri.queryParameters.containsKey('symptomVocab'), isFalse);
    });

    test('omits symptomVocab entirely when passed an empty list', () async {
      final service = RealtimeAsrService(api);
      final info = await service.connectionInfo(
        language: 'bn-IN',
        symptomVocab: const [],
      );
      expect(info.uri.queryParameters.containsKey('symptomVocab'), isFalse);
    });

    test('assessmentType and symptomVocab can both be present', () async {
      final service = RealtimeAsrService(api);
      final info = await service.connectionInfo(
        language: 'bn-IN',
        assessmentType: 'ncd',
        symptomVocab: const ['fever'],
      );
      expect(info.uri.queryParameters['assessmentType'], 'ncd');
      expect(info.uri.queryParameters['symptomVocab'], 'fever');
    });
  });
}
