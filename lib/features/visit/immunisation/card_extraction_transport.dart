import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/api/endpoints.dart';
import '../../../core/api/frappe_client.dart';

/// Normalized (0-1) bounding box, relative to the full card photo — lets a
/// scan screen draw a highlight without any separate CV pass. Shared by
/// every programme (ANC's located visit column, EPI's not-given vaccine
/// rows): null unless the backend's independent reads reached IoU
/// consensus on roughly the same region — advisory only, never a guarantee
/// the values in/around it are correct.
class CardBoundingBox {
  const CardBoundingBox({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;

  factory CardBoundingBox.fromJson(Map<String, dynamic> json) =>
      CardBoundingBox(
        xMin: (json['xMin'] as num).toDouble(),
        yMin: (json['yMin'] as num).toDouble(),
        xMax: (json['xMax'] as num).toDouble(),
        yMax: (json['yMax'] as num).toDouble(),
      );
}

/// Typed failure for a card-extraction call — never leak a raw [DioException]
/// (or its stack trace) up to the UI layer. Shared by every programme's
/// repository (EPI, ANC, ...) so each can catch/map its own exception type.
class CardExtractionTransportException implements Exception {
  const CardExtractionTransportException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Shared HTTP plumbing for every card-extraction call — the Frappe
/// `spice_next_ai` endpoint ([Endpoints.cardExtractionExtract]) via
/// [FrappeClient], the long vote-call timeout, and the multipart upload
/// (same `card_image` / `programme` / `visit_number` fields as the legacy
/// ai-scribe route).
///
/// Extracted once EPI and ANC both needed the identical transport (only the
/// `programme` value and a couple of optional form fields differ) — each
/// per-programme repository (`EpiDateExtractionRepository`,
/// `AncVisitExtractionRepository`) owns its own typed request/response
/// parsing and exception type, and calls this for the actual network call.
class CardExtractionTransport {
  const CardExtractionTransport(this._client);

  final FrappeClient _client;

  /// The backend majority-votes 3 independent Gemini calls per card (see
  /// `card_extraction_service._majority_vote`/`_majority_vote_anc`) to catch
  /// the model's run-to-run non-determinism — field-measured at up to
  /// ~130s end-to-end (Gemini throttles concurrent calls on the same API
  /// key, so 3-in-parallel isn't 3x faster than 1). Sized well above that,
  /// independent of [ApiClient]'s shorter global default which the rest of
  /// the app's fast endpoints rely on.
  static const timeout = Duration(seconds: 180);

  /// Sends [cardImage] to the card-extraction service for [programme],
  /// optionally pinning [visitNumber] (ANC/NCD only — selects which visit
  /// column/row on the card to read), and returns the raw decoded JSON
  /// response.
  ///
  /// Throws [CardExtractionTransportException] on any failure (network,
  /// timeout, non-2xx, or an unexpected response shape) — callers map this
  /// to their own typed exception.
  Future<Map<String, dynamic>> extract({
    required String programme,
    required File cardImage,
    int? visitNumber,
  }) async {
    final ext = cardImage.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final form = FormData.fromMap({
      'programme': programme,
      if (visitNumber != null) 'visit_number': '$visitNumber',
      'card_image': await MultipartFile.fromFile(
        cardImage.path,
        filename: 'card.$ext',
        contentType: DioMediaType.parse(mime),
      ),
    });
    try {
      return await _client.postMultipart(
        Endpoints.cardExtractionExtract,
        form,
        // The vote calls take far longer than FrappeClient's default budget.
        sendTimeout: timeout,
        receiveTimeout: timeout,
      );
    } on FrappeException catch (e) {
      // spice_next_ai answers 417 when the photo itself can't be read (bad
      // type, too large, nothing legible); anything else is "unavailable".
      throw CardExtractionTransportException(
        e.statusCode == 417
            ? 'Could not read this card.'
            : 'Card extraction unavailable — try again when online.',
        statusCode: e.statusCode,
      );
    }
  }
}
