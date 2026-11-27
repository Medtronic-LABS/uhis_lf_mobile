import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/api/endpoints.dart';
import 'package:uhis_next/features/visit/immunisation/card_extraction_transport.dart';

import '../../../helpers/scripted_dio_adapter.dart';
import '../../../helpers/scripted_frappe_client.dart';

void main() {
  late Directory dir;
  late File card;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('card_scan_test');
    card = File('${dir.path}/card.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
  });

  tearDown(() => dir.delete(recursive: true));

  test('uploads the legacy multipart fields to spice_next_ai', () async {
    final (client, adapter) = scriptedFrappeClient([
      (_) async => jsonResponseBody({
        'message': {'programme': 'anc', 'fields': {}},
      }),
    ]);

    final raw = await CardExtractionTransport(client).extract(
      programme: 'anc',
      cardImage: card,
      visitNumber: 3,
    );

    final request = adapter.requests.single;
    expect(request.path, Endpoints.cardExtractionExtract);
    expect(request.path, startsWith('/api/method/spice_next_ai.'));
    expect(request.headers['X-Auth-Token'], 'Bearer jwt-1');
    final form = request.data as FormData;
    expect(Map.fromEntries(form.fields), {
      'programme': 'anc',
      'visit_number': '3',
    });
    expect(form.files.single.key, 'card_image');
    expect(form.files.single.value.contentType.toString(), 'image/jpeg');
    expect(request.receiveTimeout, CardExtractionTransport.timeout);
    expect(raw['programme'], 'anc');
  });

  test('417 (unreadable photo) → could not read this card', () async {
    final (client, _) = scriptedFrappeClient([
      (_) async => jsonResponseBody({'exc_type': 'X'}, statusCode: 417),
    ]);

    await expectLater(
      CardExtractionTransport(client).extract(programme: 'epi', cardImage: card),
      throwsA(
        isA<CardExtractionTransportException>()
            .having((e) => e.message, 'message', 'Could not read this card.')
            .having((e) => e.statusCode, 'statusCode', 417),
      ),
    );
  });

  test('offline → unavailable message', () async {
    final (client, _) = scriptedFrappeClient([
      (o) async =>
          throw DioException.connectionError(requestOptions: o, reason: 'off'),
    ]);

    await expectLater(
      CardExtractionTransport(client).extract(programme: 'epi', cardImage: card),
      throwsA(
        isA<CardExtractionTransportException>().having(
          (e) => e.message,
          'message',
          startsWith('Card extraction unavailable'),
        ),
      ),
    );
  });
}
