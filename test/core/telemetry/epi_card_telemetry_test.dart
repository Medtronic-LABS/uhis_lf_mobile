import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/telemetry/epi_card_telemetry.dart';
import 'package:uhis_next/core/telemetry/telemetry_event.dart';

void main() {
  group('classifyEpiVaccinationUpdate', () {
    test('missed when OCR did not detect dose', () {
      expect(
        classifyEpiVaccinationUpdate(
          ocrDetected: false,
          hadScanPrefill: false,
          sameCalendarDayAsPrefill: false,
          dateChangedFromPrefill: false,
        ),
        EpiVaccinationChangeType.missed,
      );
    });

    test('correct when detected with matching prefill day', () {
      expect(
        classifyEpiVaccinationUpdate(
          ocrDetected: true,
          hadScanPrefill: true,
          sameCalendarDayAsPrefill: true,
          dateChangedFromPrefill: false,
        ),
        EpiVaccinationChangeType.correct,
      );
    });

    test('wrongly_marked when SK changed scan-filled date', () {
      expect(
        classifyEpiVaccinationUpdate(
          ocrDetected: true,
          hadScanPrefill: true,
          sameCalendarDayAsPrefill: false,
          dateChangedFromPrefill: true,
        ),
        EpiVaccinationChangeType.wronglyMarked,
      );
    });
  });

  test('epi card events map to epi_card ai feature', () {
    expect(
      telemetryAiFeatureForEvent(TelemetryEventType.epiCardScanSession),
      kTelemetryAiFeatureEpiCard,
    );
    expect(
      telemetryAiFeatureForEvent(TelemetryEventType.visitCompleted),
      kTelemetryAiFeatureScribe,
    );
  });
}
