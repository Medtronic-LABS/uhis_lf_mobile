import 'dart:io';

import '../../../core/api/api_client.dart';
import 'card_extraction_transport.dart';
import 'epi_date_extraction_models.dart';

/// Typed failure for a card date-extraction call — never leak a raw
/// transport exception up to the UI layer.
class EpiDateExtractionException implements Exception {
  const EpiDateExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the AI card-extraction service to read handwritten dose dates off
/// a scanned EPI card photo, via Gemini multimodal vision.
///
/// HTTP plumbing (gateway/direct dual-path, timeout, multipart) lives in
/// [CardExtractionTransport], shared with [AncVisitExtractionRepository] —
/// this class owns only the EPI-specific request shape and response typing.
class EpiDateExtractionRepository {
  EpiDateExtractionRepository(ApiClient client)
      : _transport = CardExtractionTransport(client);

  final CardExtractionTransport _transport;

  /// Sends [cardImage] (an EPI vaccination-card photo) to the card-extraction
  /// service and returns the parsed per-vaccine dose/date result.
  ///
  /// Throws [EpiDateExtractionException] on any failure (network, timeout,
  /// non-2xx, or an unexpected response shape) — callers should catch this
  /// and fall back to the offline ML Kit/Tesseract scan.
  Future<EpiDateExtractionResult> extractEpiDates(File cardImage) async {
    try {
      final raw = await _transport.extract(programme: 'epi', cardImage: cardImage);
      return EpiDateExtractionResult.fromJson(raw);
    } on CardExtractionTransportException catch (e) {
      throw EpiDateExtractionException(e.message);
    }
  }
}
