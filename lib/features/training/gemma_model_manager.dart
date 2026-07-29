import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/endpoints.dart';
import '../../core/config/app_config.dart';
import '../../core/debug/console_log.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class GemmaModelState {
  const GemmaModelState();
}

final class GemmaModelIdle extends GemmaModelState {
  const GemmaModelIdle();
}

final class GemmaModelDownloading extends GemmaModelState {
  const GemmaModelDownloading({
    required this.progress,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
  });

  /// 0–100, or -1 when total size is unknown.
  final int progress;
  final int bytesDownloaded;
  final int totalBytes;
}

final class GemmaModelReady extends GemmaModelState {
  const GemmaModelReady(this.modelPath);
  final String modelPath;
}

final class GemmaModelFailed extends GemmaModelState {
  const GemmaModelFailed(this.error);
  final String error;
}

// ── Manager ───────────────────────────────────────────────────────────────────

class GemmaModelManager {
  GemmaModelManager();

  static const String modelUrl =
      'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.task';
  static const String _filename = 'gemma3-270m-it-q8.task';
  static const String _subdir = 'llm';

  final _controller = StreamController<GemmaModelState>.broadcast();
  GemmaModelState _currentState = const GemmaModelIdle();
  CancelToken? _cancelToken;

  Stream<GemmaModelState> get stateStream => _controller.stream;
  GemmaModelState get currentState => _currentState;

  Future<String> get modelPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_subdir/$_filename';
  }

  Future<bool> isModelPresent() async {
    final path = await modelPath;
    return File(path).exists();
  }

  /// Returns true when the file exists and is ≥ 100 MB.
  ///
  /// The real Gemma 3 270M model is ~303 MB. A 100 MB floor catches truncated
  /// downloads while leaving room for future smaller quantisations.
  /// Magic-byte checks were removed — the .task FlatBuffer format does not
  /// reliably start with ZIP PK bytes and caused false-positive "corrupt"
  /// detections on valid files.
  Future<bool> isModelValid() async {
    final path = await modelPath;
    final f = File(path);
    if (!await f.exists()) return false;
    final size = await f.length();
    return size >= 100 * 1024 * 1024;
  }

  /// Emits [GemmaModelReady] if model is valid on disk; deletes and emits idle
  /// if the file is present but corrupt.
  Future<void> checkIfReady() async {
    final path = await modelPath;
    if (await isModelValid()) {
      _emit(GemmaModelReady(path));
    } else if (await isModelPresent()) {
      // File exists but corrupt — delete so next open shows the download gate.
      ConsoleLog.warn('[GemmaModelManager] corrupt model file detected — deleting');
      await File(path).delete().catchError((_) => File(path));
      _emit(const GemmaModelIdle());
    }
  }

  /// Delete the model file and reset to idle (called when MediaPipe init fails).
  Future<void> invalidate() async {
    final path = await modelPath;
    ConsoleLog.warn('[GemmaModelManager] invalidating model file at $path');
    await File(path).delete().catchError((_) => File(path));
    _emit(const GemmaModelIdle());
  }

  Future<void> downloadIfNeeded() async {
    if (await isModelPresent()) {
      final path = await modelPath;
      ConsoleLog.step('[GemmaModelManager] model already present at $path');
      _emit(GemmaModelReady(path));
      return;
    }

    final path = await modelPath;
    final dir = File(path).parent;
    await dir.create(recursive: true);

    // Wait for Dart's socket layer to fully initialize before making requests.
    await Future<void>.delayed(const Duration(seconds: 2));

    _cancelToken = CancelToken();
    _emit(const GemmaModelDownloading(progress: 0));

    // Provider order: Backend (SPICE JWT) → HuggingFace (HF token)
    // Mirrors micro_coaching ModelDownloadWorker provider chain.
    try {
      final sessionToken = await const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      ).read(key: 'bio_auth_token');
      if (sessionToken != null && sessionToken.isNotEmpty) {
        ConsoleLog.step('[GemmaModelManager] trying backend provider');
        final coachingBase = AppConfig.coachingServiceUrl.endsWith('/')
            ? AppConfig.coachingServiceUrl.substring(0, AppConfig.coachingServiceUrl.length - 1)
            : AppConfig.coachingServiceUrl;
        final backendErr = await _downloadFrom(
          '$coachingBase${Endpoints.coachingModelGemmaDownload}',
          path,
          headers: {'Authorization': 'Bearer $sessionToken'},
          label: 'backend',
        );
        if (backendErr == null) return; // success
        if (backendErr.isEmpty) return; // cancelled — stop provider chain
        ConsoleLog.warn('[GemmaModelManager] backend failed: $backendErr — trying HuggingFace');
      } else {
        ConsoleLog.warn('[GemmaModelManager] no session token — skipping backend provider');
      }

      final hfToken = AppConfig.huggingFaceToken;
      final hfErr = await _downloadFrom(
        modelUrl,
        path,
        headers: hfToken.isNotEmpty ? {'Authorization': 'Bearer $hfToken'} : {},
        label: 'HuggingFace',
      );
      if (hfErr == null || hfErr.isEmpty) return; // success or cancelled
      final msg = hfErr.contains('401')
          ? 'Backend unavailable and HuggingFace requires auth (401). '
              'Ensure you are logged in, or pass --dart-define=HF_TOKEN=hf_xxx.'
          : hfErr;
      ConsoleLog.warn('[GemmaModelManager] all providers failed: $msg');
      _emit(GemmaModelFailed(msg));
    } finally {
      _cancelToken = null;
    }
  }

  /// Downloads [url] to [destPath].
  /// Returns null on success, empty string on user cancellation, error string on failure.
  Future<String?> _downloadFrom(
    String url,
    String destPath, {
    required Map<String, String> headers,
    required String label,
  }) async {
    ConsoleLog.step('[GemmaModelManager] [$label] download started → $destPath');
    final dio = Dio(BaseOptions(
      headers: headers,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
    ));
    try {
      await dio.download(
        url,
        destPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          final pct = total > 0 ? ((received / total) * 100).toInt() : -1;
          _emit(GemmaModelDownloading(
            progress: pct,
            bytesDownloaded: received,
            totalBytes: total,
          ));
        },
      );
      final fileSize = await File(destPath).length();
      if (fileSize < 10 * 1024 * 1024) {
        // < 10 MB → corrupt/truncated (real model is ~300 MB)
        await File(destPath).delete().catchError((_) => File(destPath));
        return '[$label] download truncated ($fileSize bytes) — upstream likely returned an error';
      }
      ConsoleLog.success('[GemmaModelManager] [$label] download complete → $destPath ($fileSize bytes)');
      _emit(GemmaModelReady(destPath));
      return null; // success
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        ConsoleLog.step('[GemmaModelManager] download cancelled');
        _emit(const GemmaModelIdle());
        return ''; // sentinel: cancelled — caller stops provider chain
      }
      final code = e.response?.statusCode;
      return '${code != null ? "$code " : ""}${e.message ?? "Download failed"}';
    }
    // _cancelToken is NOT nulled here — caller owns its lifetime.
  }

  void cancel() {
    _cancelToken?.cancel('user cancelled');
  }

  void dispose() {
    cancel();
    _controller.close();
  }

  void _emit(GemmaModelState state) {
    _currentState = state;
    if (!_controller.isClosed) _controller.add(state);
  }
}
