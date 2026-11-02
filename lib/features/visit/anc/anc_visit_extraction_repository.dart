import 'dart:io';

import '../../../core/api/api_client.dart';
import '../immunisation/card_extraction_transport.dart';
import 'anc_visit_extraction_models.dart';

/// Typed failure for an ANC card visit-extraction call — never leak a raw
/// transport exception up to the UI layer.
class AncVisitExtractionException implements Exception {
  const AncVisitExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the AI card-extraction service to read one ANC visit's handwritten
/// vitals off a scanned "মা ও নবজাতক স্বাস্থ্য তথ্যকার্ড" photo, via Gemini
/// multimodal vision.
///
/// The card's columns are visit instances (not vaccine rows like EPI), so
/// the caller must say which visit it's currently recording — the backend
/// targets Gemini at exactly that column rather than returning every visible
/// visit and making the mobile side guess which one matches.
///
/// HTTP plumbing lives in [CardExtractionTransport], shared with
/// [EpiDateExtractionRepository] — this class owns only the ANC-specific
/// request shape and response typing.
class AncVisitExtractionRepository {
  AncVisitExtractionRepository(ApiClient client)
      : _transport = CardExtractionTransport(client);

  final CardExtractionTransport _transport;

  /// Sends [cardImage] to the card-extraction service, targeted at
  /// [visitNumber] (1-indexed, left-to-right as printed on the card), and
  /// returns the parsed visit-vitals result.
  ///
  /// Throws [AncVisitExtractionException] on any failure (network, timeout,
  /// non-2xx, or an unexpected response shape) — callers should catch this
  /// and fall back to manual entry.
  Future<AncVisitExtractionResult> extractAncVisit(
    File cardImage,
    int visitNumber,
  ) async {
    try {
      final raw = await _transport.extract(
        programme: 'anc',
        cardImage: cardImage,
        visitNumber: visitNumber,
      );
      return AncVisitExtractionResult.fromJson(raw);
    } on CardExtractionTransportException catch (e) {
      throw AncVisitExtractionException(e.message);
    }
  }
}
