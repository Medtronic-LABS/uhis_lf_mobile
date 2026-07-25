import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/debug/console_log.dart';

// ── State ─────────────────────────────────────────────────────────────────────

sealed class SttModelState {
  const SttModelState();
}

final class SttModelStateIdle extends SttModelState {
  const SttModelStateIdle();
}

final class SttModelStateDownloading extends SttModelState {
  const SttModelStateDownloading({
    required this.percent,
    required this.bytesDownloaded,
    required this.totalBytes,
  });
  final int percent;
  final int bytesDownloaded;
  final int totalBytes;
}

final class SttModelStateExtracting extends SttModelState {
  const SttModelStateExtracting();
}

final class SttModelStateReady extends SttModelState {
  const SttModelStateReady(this.modelDir);
  final String modelDir;
}

final class SttModelStateFailed extends SttModelState {
  const SttModelStateFailed(this.error);
  final String error;
}

// ── Manager ───────────────────────────────────────────────────────────────────

class SttModelManager {
  static bool _downloadInProgress = false;

  static const String _bengaliModelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
      'sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09.tar.bz2';

  static const List<String> _requiredFiles = [
    'encoder.onnx',
    'decoder.onnx',
    'joiner.onnx',
    'tokens.txt',
  ];

  static const String _archiveFilename = '_archive.tar.bz2';

  final _stateController = StreamController<SttModelState>.broadcast();
  SttModelState _state = const SttModelStateIdle();
  CancelToken? _cancelToken;

  Stream<SttModelState> get stateStream => _stateController.stream;
  SttModelState get currentState => _state;

  Future<String> get _modelDir async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/stt/bn';
  }

  Future<bool> isModelPresent() async {
    final dir = await _modelDir;
    return _requiredFiles.every((f) => File('$dir/$f').existsSync());
  }

  /// Emits [SttModelStateReady] if model is on disk, otherwise emits nothing.
  Future<void> checkIfReady() async {
    if (await isModelPresent()) {
      final dir = await _modelDir;
      _emit(SttModelStateReady(dir));
    }
  }

  Future<void> downloadIfNeeded() async {
    if (await isModelPresent()) {
      final dir = await _modelDir;
      _emit(SttModelStateReady(dir));
      return;
    }
    if (_downloadInProgress) return;
    _downloadInProgress = true;
    try {
      await _download();
    } finally {
      _downloadInProgress = false;
    }
  }

  void cancel() {
    _cancelToken?.cancel('cancelled by user');
    _cancelToken = null;
  }

  void dispose() {
    cancel();
    _stateController.close();
  }

  void _emit(SttModelState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  Future<void> _download() async {
    final dir = await _modelDir;
    await Directory(dir).create(recursive: true);
    final archivePath = '$dir/$_archiveFilename';

    _cancelToken = CancelToken();
    _emit(const SttModelStateDownloading(percent: 0, bytesDownloaded: 0, totalBytes: 0));

    ConsoleLog.step('[SttModelManager] download started → $dir');

    try {
      final dio = Dio(BaseOptions(receiveTimeout: const Duration(minutes: 15)));
      await dio.download(
        _bengaliModelUrl,
        archivePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          final pct = total > 0 ? ((received / total) * 100).toInt().clamp(0, 99) : 0;
          _emit(SttModelStateDownloading(
            percent: pct,
            bytesDownloaded: received,
            totalBytes: total,
          ));
        },
      );

      ConsoleLog.step('[SttModelManager] download complete — extracting');
      _emit(const SttModelStateExtracting());

      await _extract(archivePath, dir);

      final missing = _requiredFiles.where((f) => !File('$dir/$f').existsSync()).toList();
      if (missing.isNotEmpty) {
        throw Exception('missing after extract: $missing');
      }

      await File(archivePath).delete().catchError((_) => File(archivePath));
      ConsoleLog.success('[SttModelManager] Bengali STT model ready at $dir');
      _emit(SttModelStateReady(dir));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        ConsoleLog.warn('[SttModelManager] download cancelled');
        _emit(const SttModelStateIdle());
      } else {
        ConsoleLog.warn('[SttModelManager] download error: $e');
        _emit(SttModelStateFailed(e.message ?? 'Download failed'));
      }
    } on Exception catch (e) {
      ConsoleLog.warn('[SttModelManager] error: $e');
      _emit(SttModelStateFailed(e.toString()));
    }
  }

  Future<void> _extract(String archivePath, String destDir) async {
    final archiveBytes = await File(archivePath).readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(archiveBytes);
    final archive = TarDecoder().decodeBytes(tarBytes);

    for (final file in archive) {
      if (!file.isFile) continue;
      // Strip leading directory (sherpa-onnx-streaming-…/filename → filename)
      final name = file.name.contains('/')
          ? file.name.substring(file.name.indexOf('/') + 1)
          : file.name;
      if (name.isEmpty) continue;
      if (name.startsWith('test_wavs/')) continue;
      if (name.endsWith('.md')) continue;
      final outFile = File('$destDir/$name');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as Uint8List);
      ConsoleLog.step('[SttModelManager] extracted: $name');
    }
  }
}
