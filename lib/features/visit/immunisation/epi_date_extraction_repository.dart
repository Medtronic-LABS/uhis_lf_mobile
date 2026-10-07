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

  (Dio, String) _resolve(String gatewayPath, String directPath) {
    final aiUrl = AppConfig.aiServiceBaseUrl;
    if (aiUrl.isNotEmpty) {
      final direct = Dio(BaseOptions(
        baseUrl: aiUrl,
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
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
      final response = await dio.post<dynamic>(path, data: form);
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
