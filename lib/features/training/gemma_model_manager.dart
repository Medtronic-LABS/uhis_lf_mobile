import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

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
  CancelToken? _cancelToken;

  Stream<GemmaModelState> get stateStream => _controller.stream;

  Future<String> get modelPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_subdir/$_filename';
  }

  Future<bool> isModelPresent() async {
    final path = await modelPath;
    return File(path).exists();
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

    _cancelToken = CancelToken();
    _emit(const GemmaModelDownloading(progress: 0));
    ConsoleLog.step('[GemmaModelManager] download started → $path');

    final dio = Dio();
    try {
      await dio.download(
        modelUrl,
        path,
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

      ConsoleLog.success('[GemmaModelManager] download complete → $path');
      _emit(GemmaModelReady(path));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        ConsoleLog.step('[GemmaModelManager] download cancelled');
        _emit(const GemmaModelIdle());
      } else {
        ConsoleLog.error('[GemmaModelManager] download failed', e);
        _emit(GemmaModelFailed(e.message ?? 'Download failed'));
      }
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() {
    _cancelToken?.cancel('user cancelled');
  }

  void dispose() {
    cancel();
    _controller.close();
  }

  void _emit(GemmaModelState state) {
    if (!_controller.isClosed) _controller.add(state);
  }
}
