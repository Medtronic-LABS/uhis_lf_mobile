import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/features/visit/immunisation/card_extraction_transport.dart';

void main() {
  test('each failure maps to its own localized message', () {
    String msg(CardExtractionFailure f) =>
        CardExtractionTransportException(f).message;

    expect(msg(CardExtractionFailure.notRecognised),
        EpiStrings.scanCardNotRecognised);
    expect(
        msg(CardExtractionFailure.unreadable), EpiStrings.scanImageUnreadable);
    expect(msg(CardExtractionFailure.unavailable),
        EpiStrings.scanServiceUnavailable);
    expect(msg(CardExtractionFailure.badResponse), EpiStrings.scanFailed);
  });
}
