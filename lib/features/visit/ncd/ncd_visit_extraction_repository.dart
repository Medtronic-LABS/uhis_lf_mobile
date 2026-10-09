import 'dart:io';

import '../../../core/api/api_client.dart';
import '../immunisation/card_extraction_transport.dart';
import 'ncd_visit_extraction_models.dart';

/// Typed failure for an NCD card visit-extraction call — never leak a raw
/// transport exception up to the UI layer.
class NcdVisitExtractionException implements Exception {
  const NcdVisitExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the AI card-extraction service to read one NCD visit's handwritten
/// vitals off a scanned BP/glucose follow-up card photo, via Gemini
/// multimodal vision.
///
/// The card's ROWS are visit instances (not columns, unlike ANC), so the
/// caller must say which visit it's currently recording — the backend
/// targets Gemini at exactly that row rather than returning every visible
/// visit and making the mobile side guess which one matches.
///
/// HTTP plumbing lives in [CardExtractionTransport], shared with
/// [AncVisitExtractionRepository]/[EpiDateExtractionRepository] — this class
/// owns only the NCD-specific request shape and response typing.
class NcdVisitExtractionRepository {
  NcdVisitExtractionRepository(ApiClient client)
      : _transport = CardExtractionTransport(client);

  final CardExtractionTransport _transport;

  /// Sends [cardImage] to the card-extraction service, targeted at
  /// [visitNumber] (1-indexed, top-to-bottom dated rows as printed on the
  /// card), and returns the parsed visit-vitals result.
  ///
  /// Throws [NcdVisitExtractionException] on any failure (network, timeout,
  /// non-2xx, or an unexpected response shape) — callers should catch this
  /// and fall back to manual entry.
  Future<NcdVisitExtractionResult> extractNcdVisit(
    File cardImage,
    int visitNumber,
  ) async {
    try {
      final raw = await _transport.extract(
        programme: 'ncd',
        cardImage: cardImage,
        visitNumber: visitNumber,
      );
      return NcdVisitExtractionResult.fromJson(raw);
    } on CardExtractionTransportException catch (e) {
      throw NcdVisitExtractionException(e.message);
    }
  }
}
