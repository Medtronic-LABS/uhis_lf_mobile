import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';

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

/// Shared HTTP plumbing for every `/card-extraction/extract` call — gateway/
/// direct dual-path resolution, the long vote-call timeout, and multipart
/// upload. Mirrors [VisitBriefingRepository]'s gateway/direct pattern.
///
/// Extracted once EPI and ANC both needed the identical transport (only the
/// `programme` value and a couple of optional form fields differ) — each
/// per-programme repository (`EpiDateExtractionRepository`,
/// `AncVisitExtractionRepository`) owns its own typed request/response
/// parsing and exception type, and calls this for the actual network call.
class CardExtractionTransport {
  const CardExtractionTransport(this._client);

  final ApiClient _client;

  /// The backend majority-votes 3 independent Gemini calls per card (see
  /// `card_extraction_service._majority_vote`/`_majority_vote_anc`) to catch
  /// the model's run-to-run non-determinism — field-measured at up to
  /// ~130s end-to-end (Gemini throttles concurrent calls on the same API
  /// key, so 3-in-parallel isn't 3x faster than 1). Sized well above that,
  /// independent of [ApiClient]'s shorter global default which the rest of
  /// the app's fast endpoints rely on.
  static const timeout = Duration(seconds: 180);

  (Dio, String) _resolve(String gatewayPath, String directPath) {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: timeout,
        receiveTimeout: timeout,
      ));
      _client.attachAiServiceAuth(direct);
      return (direct, directPath);
    }
    return (_client.dio, gatewayPath);
  }

  /// Sends [cardImage] to the card-extraction service for [programme],
  /// optionally pinning [visitNumber] (ANC only — selects which visit column
  /// on the card to read), and returns the raw decoded JSON response.
  ///
  /// Throws [CardExtractionTransportException] on any failure (network,
  /// timeout, non-2xx, or an unexpected response shape) — callers map this
  /// to their own typed exception.
  Future<Map<String, dynamic>> extract({
    required String programme,
    required File cardImage,
    int? visitNumber,
  }) async {
    final (dio, path) = _resolve(
      Endpoints.cardExtractionExtract,
      '/card-extraction/extract',
    );
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
      final response = await dio.post<dynamic>(
        path,
        data: form,
        // Per-request override — the gateway path's [dio] is [ApiClient]'s
        // shared instance, whose global timeout is sized for the rest of
        // the app's fast endpoints, not this call's ~130s vote latency.
        options: Options(sendTimeout: timeout, receiveTimeout: timeout),
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const CardExtractionTransportException(
          'Unexpected response from card extraction.',
        );
      }
      return raw;
    } on DioException catch (e) {
      throw CardExtractionTransportException(
        e.response?.statusCode == 422
            ? 'Could not read this card.'
            : 'Card extraction unavailable — try again when online.',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
