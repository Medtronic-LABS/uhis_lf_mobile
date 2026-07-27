import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/debug/console_log.dart';

/// Manages the Whisper Small ONNX model used for offline batch ASR in triage.
///
/// Separate from [SttModelManager] which manages the Bengali streaming model for
/// the coaching tab. Whisper Small (~100 MB) outputs clean English text from
/// code-mixed Bengali/Hindi/English speech — matching the server's Sarvam ASR
/// quality for symptom extraction.
///
/// Files land at `<appDocDir>/stt/whisper/` after extraction.
class WhisperModelManager {
  static const String _whisperSmallUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
      'sherpa-onnx-whisper-small.tar.bz2';

  static const List<String> _requiredFiles = [
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'tokens.txt',
  ];

  Future<String> get modelDir async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/stt/whisper';
  }

  Future<bool> isModelPresent() async {
    final dir = await modelDir;
    return _requiredFiles.every((f) => File('$dir/$f').existsSync());
  }

  /// Download and extract the Whisper Small model if not already present.
  ///
  /// Returns true when the model is ready. On error, returns false and logs via
  /// ConsoleLog so the caller can fall back to the Bengali streaming model.
  ///
  /// [onProgress] receives a 0-99 integer percent during download.
  Future<bool> downloadIfNeeded({
    void Function(int percent)? onProgress,
  }) async {
    if (await isModelPresent()) {
      ConsoleLog.success('[WhisperModelManager] model already present');
      return true;
    }

    final dir = await modelDir;
    await Directory(dir).create(recursive: true);
    final archivePath = '$dir/_archive.tar.bz2';

    ConsoleLog.step('[WhisperModelManager] downloading Whisper Small → $dir');

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 20),
        ),
      );
      await dio.download(
        _whisperSmallUrl,
        archivePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(((received / total) * 100).toInt().clamp(0, 99));
          }
        },
      );

      ConsoleLog.step('[WhisperModelManager] download complete — extracting');
      await _extract(archivePath, dir);

      final missing = _requiredFiles
          .where((f) => !File('$dir/$f').existsSync())
          .toList();
      if (missing.isNotEmpty) {
        throw Exception('missing after extract: $missing');
      }

      await File(archivePath).delete().catchError((_) => File(archivePath));
      ConsoleLog.success('[WhisperModelManager] Whisper Small ready at $dir');
      return true;
    } on DioException catch (e) {
      ConsoleLog.warn('[WhisperModelManager] download error: ${e.message}');
      return false;
    } on Exception catch (e) {
      ConsoleLog.warn('[WhisperModelManager] error: $e');
      return false;
    }
  }

  Future<void> _extract(String archivePath, String destDir) async {
    final archiveBytes = await File(archivePath).readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(archiveBytes);
    final archive = TarDecoder().decodeBytes(tarBytes);

    for (final file in archive) {
      if (!file.isFile) continue;
      // Strip leading directory (sherpa-onnx-whisper-small/filename → filename)
      final name = file.name.contains('/')
          ? file.name.substring(file.name.indexOf('/') + 1)
          : file.name;
      if (name.isEmpty) continue;
      if (name.startsWith('test_wavs/')) continue;
      if (name.endsWith('.md')) continue;
      final outFile = File('$destDir/$name');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as Uint8List);
      ConsoleLog.step('[WhisperModelManager] extracted: $name');
    }
  }
}
