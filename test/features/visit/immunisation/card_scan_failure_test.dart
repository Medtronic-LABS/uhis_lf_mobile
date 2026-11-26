import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/i18n/bn_numerals.dart';
import 'package:uhis_next/features/visit/immunisation/card_extraction_transport.dart';
import 'package:uhis_next/features/visit/immunisation/card_scan_failure.dart';
import 'package:uhis_next/features/visit/immunisation/epi_card_scanner.dart';

void main() {
  epiScanResultTests();

  group('CardScanFailureStrings.forFailure', () {
    test('every failure has a distinct, non-empty message', () {
      final messages = {
        for (final f in CardScanFailure.values)
          f: CardScanFailureStrings.forFailure(f, visitNumber: 3),
      };
      expect(messages.values.every((m) => m.isNotEmpty), isTrue);
      expect(messages.values.toSet().length, CardScanFailure.values.length);
    });

    test('visit-data-missing names the visit', () {
      expect(
        CardScanFailureStrings.forFailure(
          CardScanFailure.visitDataMissing,
          visitNumber: 3,
        ),
        contains(BnNumerals.localize('3')),
      );
    });
  });

  group('CardExtractionTransport failure mapping', () {
    CardScanFailure map(DioException e) =>
        CardExtractionTransport.failureFor(e);

    DioException dio(DioExceptionType t, {int? status}) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: t,
          response: status == null
              ? null
              : Response(
                  requestOptions: RequestOptions(path: '/x'),
                  statusCode: status,
                ),
        );

    test('422 is unreadable', () {
      expect(map(dio(DioExceptionType.badResponse, status: 422)),
          CardScanFailure.unreadable);
    });

    test('timeouts and connection errors are offline', () {
      for (final t in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(map(dio(t)), CardScanFailure.offline);
      }
    });

    test('other server errors are serviceUnavailable', () {
      expect(map(dio(DioExceptionType.badResponse, status: 500)),
          CardScanFailure.serviceUnavailable);
    });
  });
}

void epiScanResultTests() {
  group('EpiScanResult.withFailure', () {
    test('keeps the read data and attaches the cause', () {
      const base = EpiScanResult(matchedCodes: [], rawText: 'x');
      final r = base.withFailure(CardScanFailure.offline);
      expect(r.failure, CardScanFailure.offline);
      expect(r.rawText, 'x');
      expect(r.anyMatched, isFalse);
    });
  });

  group('CardScanFailureStrings without a visit number', () {
    test('visitDataMissing degrades to the unreadable message', () {
      expect(
        CardScanFailureStrings.forFailure(CardScanFailure.visitDataMissing),
        CardScanFailureStrings.forFailure(CardScanFailure.unreadable),
      );
    });
  });
}
