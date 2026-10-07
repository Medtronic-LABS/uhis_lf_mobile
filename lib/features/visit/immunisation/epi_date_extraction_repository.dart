import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/config/app_config.dart';
import 'epi_date_extraction_models.dart';

/// Typed failure for a card date-extraction call — never leak a raw
/// [DioException] (or its stack trace) up to the UI layer.
class EpiDateExtractionException implements Exception {
  const EpiDateExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Calls the AI card-extraction service to read handwritten dose dates off
/// a scanned EPI card photo, via Gemini multimodal vision.
///
/// Mirrors [VisitBriefingRepository]'s gateway/direct dual-path: when
/// [AppConfig.aiServiceBaseUrl] is non-empty (--dart-define AI_SERVICE_URL=
/// http://10.0.2.2:8095), requests go directly to the local service;
/// otherwise they route through the nginx gateway.
///
/// Single-shot multipart upload — a card photo is small, so this does not
/// need the chunked-upload path the audio scribe uses for large files.
class EpiDateExtractionRepository {
  const EpiDateExtractionRepository(this._client);

  final ApiClient _client;

  /// The backend majority-votes 3 independent Gemini calls per card (see
  /// `card_extraction_service._majority_vote`) to catch the model's
  /// run-to-run non-determinism on handwritten dates — field-measured at
  /// up to ~130s end-to-end (Gemini throttles concurrent calls on the same
  /// API key, so 3-in-parallel isn't 3x faster than 1). This request-level
  /// timeout is set well above that, independent of [ApiClient]'s shorter
  /// global default which the rest of the app's fast endpoints rely on.
  static const _voteCallTimeout = Duration(seconds: 180);

  (Dio, String) _resolve(String gatewayPath, String directPath) {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: _voteCallTimeout,
        receiveTimeout: _voteCallTimeout,
      ));
      _client.attachAiServiceAuth(direct);
      return (direct, directPath);
    }
    return (_client.dio, gatewayPath);
  }

  /// Sends [cardImage] (an EPI vaccination-card photo) to the card-extraction
  /// service and returns the parsed per-vaccine dose/date result.
  ///
  /// Throws [EpiDateExtractionException] on any failure (network, timeout,
  /// non-2xx, or an unexpected response shape) — callers should catch this
  /// and fall back to the offline ML Kit/Tesseract scan.
  Future<EpiDateExtractionResult> extractEpiDates(File cardImage) async {
    final (dio, path) = _resolve(
      Endpoints.cardExtractionExtract,
      '/card-extraction/extract',
    );
    final ext = cardImage.path.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final form = FormData.fromMap({
      'programme': 'epi',
      'card_image': await MultipartFile.fromFile(
        cardImage.path,
        filename: 'epi_card.$ext',
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
        options: Options(
          sendTimeout: _voteCallTimeout,
          receiveTimeout: _voteCallTimeout,
        ),
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const EpiDateExtractionException(
          'Unexpected response from date extraction.',
        );
      }
      return EpiDateExtractionResult.fromJson(raw);
    } on DioException catch (e) {
      throw EpiDateExtractionException(
        e.response?.statusCode == 422
            ? 'Could not read dates from this card.'
            : 'Date extraction unavailable — try again when online.',
      );
    }
  }
}
