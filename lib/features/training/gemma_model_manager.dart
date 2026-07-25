import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Emits [GemmaModelReady] if model is already on disk; otherwise idle.
  Future<void> checkIfReady() async {
    if (await isModelPresent()) {
      final path = await modelPath;
      _emit(GemmaModelReady(path));
    }
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
        final backendErr = await _downloadFrom(
          '${AppConfig.apiBaseUrl}api/v1/models/gemma/download',
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
      ConsoleLog.success('[GemmaModelManager] [$label] download complete → $destPath');
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
