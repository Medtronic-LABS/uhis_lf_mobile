import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Describes one downloadable local AI model.
class LocalModelSpec {
  const LocalModelSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.sizeMb,
    required this.files,
    required this.subDir,
    this.hfRepo,
    this.archiveUrl,
  }) : assert(
          hfRepo != null || archiveUrl != null,
          'Either hfRepo or archiveUrl must be provided',
        );

  final String id;
  final String label;
  final String description;
  final int sizeMb;

  /// HuggingFace repo — individual file downloads. Null when [archiveUrl] set.
  final String? hfRepo;

  /// Direct download URL for a tar.bz2 archive. Null when [hfRepo] set.
  final String? archiveUrl;

  /// File names to verify after download (relative to [subDir]).
  final List<String> files;

  /// Sub-directory under the models root where this model lives.
  final String subDir;
}

/// Official sherpa-onnx Bengali zipformer model — compatible with the
/// sherpa_onnx OnlineRecognizer zipformer2 decoder.
const kAsrModel = LocalModelSpec(
  id: 'sherpa-bn-zipformer',
  label: 'Bengali ASR Model',
  description: 'Sherpa-onnx Bengali Zipformer streaming transducer. '
      'Used for on-device speech recognition.',
  sizeMb: 92,
  archiveUrl: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'asr-models/sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09.tar.bz2',
  files: ['encoder.onnx', 'decoder.onnx', 'joiner.onnx', 'tokens.txt'],
  subDir: 'sherpa_bn_zipformer',
);

const kLlmModelTiny = LocalModelSpec(
  id: 'smollm2-135m',
  label: 'SmolLM2 135M LLM (fastest)',
  description: 'SmolLM2-135M Q4_K_M — ~80MB, ~300ms inference. '
      'Best for real-time symptom and field extraction.',
  sizeMb: 82,
  hfRepo: 'bartowski/SmolLM2-135M-Instruct-GGUF',
  files: ['SmolLM2-135M-Instruct-Q4_K_M.gguf'],
  subDir: 'llm_models',
);

const kLlmModelSmall = LocalModelSpec(
  id: 'qwen2.5-0.5b',
  label: 'Qwen2.5 0.5B LLM (fast)',
  description: 'Qwen2.5-0.5B Q4_K_M — no thinking mode, Bengali + 100+ languages. '
      '~3-8s inference. Recommended for symptom extraction.',
  sizeMb: 320,
  hfRepo: 'bartowski/Qwen2.5-0.5B-Instruct-GGUF',
  files: ['Qwen2.5-0.5B-Instruct-Q4_K_M.gguf'],
  subDir: 'llm_models',
);

const kLlmModelLarge = LocalModelSpec(
  id: 'qwen2.5-1.5b',
  label: 'Qwen2.5 1.5B LLM (accurate)',
  description: 'Qwen2.5-1.5B Q4_K_M — no thinking mode, higher accuracy. '
      'Requires ~1GB storage.',
  sizeMb: 986,
  hfRepo: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
  files: ['Qwen2.5-1.5B-Instruct-Q4_K_M.gguf'],
  subDir: 'llm_models',
);

enum _DownloadTarget { asr, llm }

/// Manages download, storage, and status of local AI model files.
class LocalModelManager extends ChangeNotifier {
  LocalModelManager();

  bool _isDisposed = false;
  String? _modelsRoot;

  double? _asrProgress;
  double? _llmProgress;

  double? get asrProgress => _asrProgress;
  double? get llmProgress => _llmProgress;

  bool _asrInstalled = false;
  bool _llmInstalled = false;
  LocalModelSpec _activeLlm = kLlmModelSmall;

  bool get asrInstalled => _asrInstalled;
  bool get llmInstalled => _llmInstalled;
  LocalModelSpec get activeLlm => _activeLlm;

  String? _asrError;
  String? _llmError;
  String? get asrError => _asrError;
  String? get llmError => _llmError;

  bool get asrDownloading => _asrProgress != null;
  bool get llmDownloading => _llmProgress != null;

  bool get bothInstalled => _asrInstalled && _llmInstalled;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  Future<void> init() async {
    final root = await _getRoot();
    _modelsRoot = root;
    _asrInstalled = _checkInstalled(root, kAsrModel);
    _llmInstalled = _checkInstalled(root, _activeLlm);
    debugPrint(
      '[LocalModelManager] root=$root '
      'asrInstalled=$_asrInstalled llmInstalled=$_llmInstalled',
    );
    _notify();
  }

  String get asrModelDir => '${_modelsRoot ?? ''}/${kAsrModel.subDir}';

  String get llmModelPath {
    final file = _activeLlm.files.first;
    return '${_modelsRoot ?? ''}/${_activeLlm.subDir}/$file';
  }

  Future<String> _getRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final root = '${dir.path}/local_ai_models';
    await Directory(root).create(recursive: true);
    return root;
  }

  bool _checkInstalled(String root, LocalModelSpec spec) {
    for (final f in spec.files) {
      if (!File('$root/${spec.subDir}/$f').existsSync()) return false;
    }
    return true;
  }

  Future<void> downloadAsr() async {
    if (asrDownloading || _asrInstalled) return;
    _asrError = null;
    await _download(spec: kAsrModel, target: _DownloadTarget.asr);
  }

  Future<void> downloadLlm({LocalModelSpec? spec}) async {
    if (llmDownloading) return;
    _activeLlm = spec ?? _activeLlm;
    _llmError = null;
    _llmInstalled = false;
    await _download(spec: _activeLlm, target: _DownloadTarget.llm);
  }

  Future<void> deleteAsr() async {
    final root = _modelsRoot;
    if (root == null) return;
    final dir = Directory('$root/${kAsrModel.subDir}');
    if (dir.existsSync()) await dir.delete(recursive: true);
    _asrInstalled = false;
    _notify();
  }

  Future<void> deleteLlm() async {
    final root = _modelsRoot;
    if (root == null) return;
    final f = File(llmModelPath);
    if (f.existsSync()) await f.delete();
    _llmInstalled = false;
    _notify();
  }

  Future<void> _download({
    required LocalModelSpec spec,
    required _DownloadTarget target,
  }) async {
    final root = _modelsRoot ?? await _getRoot();
    _modelsRoot = root;
    final destDir = Directory('$root/${spec.subDir}');
    await destDir.create(recursive: true);

    void setProgress(double p) {
      if (target == _DownloadTarget.asr) {
        _asrProgress = p;
      } else {
        _llmProgress = p;
      }
      _notify();
    }

    try {
      if (spec.archiveUrl != null) {
        await _downloadArchive(
          url: spec.archiveUrl!,
          destDir: destDir,
          sizeMb: spec.sizeMb,
          onProgress: setProgress,
        );
      } else {
        await _downloadFiles(
          spec: spec,
          destDir: destDir,
          onProgress: setProgress,
        );
      }

      if (target == _DownloadTarget.asr) {
        _asrInstalled = true;
        _asrProgress = null;
      } else {
        _llmInstalled = true;
        _llmProgress = null;
      }
      _notify();
    } catch (e, st) {
      debugPrint('[LocalModelManager] download error: $e\n$st');
      if (target == _DownloadTarget.asr) {
        _asrError = e.toString();
        _asrProgress = null;
      } else {
        _llmError = e.toString();
        _llmProgress = null;
      }
      _notify();
    }
  }

  Future<void> _downloadArchive({
    required String url,
    required Directory destDir,
    required int sizeMb,
    required void Function(double) onProgress,
  }) async {
    final archivePath = '${destDir.path}/_archive.tar.bz2';
    final archiveFile = File(archivePath);

    final totalEstimatedBytes = sizeMb * 1024 * 1024;
    var received = 0;

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final response = await client.send(req);
      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode} downloading archive');
      }

      final contentLength = response.contentLength ?? 0;
      final denominator =
          contentLength > 0 ? contentLength : totalEstimatedBytes;

      final sink = archiveFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress((received / denominator).clamp(0.0, 0.8));
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    debugPrint('[LocalModelManager] download done, extracting…');
    onProgress(0.85);

    final archiveBytes = await archiveFile.readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(archiveBytes);
    final archive = TarDecoder().decodeBytes(tarBytes);

    for (final file in archive) {
      if (!file.isFile) continue;
      // Strip leading directory (e.g. sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09/encoder.onnx → encoder.onnx)
      final name = file.name.contains('/')
          ? file.name.substring(file.name.lastIndexOf('/') + 1)
          : file.name;
      if (name.isEmpty || name.startsWith('.')) continue;
      final outFile = File('${destDir.path}/$name');
      await outFile.parent.create(recursive: true);
      final content = file.readBytes();
      if (content != null) await outFile.writeAsBytes(content);
    }

    await archiveFile.delete().catchError((_) => archiveFile);
    onProgress(0.99);
    debugPrint('[LocalModelManager] extraction done: ${destDir.path}');
  }

  Future<void> _downloadFiles({
    required LocalModelSpec spec,
    required Directory destDir,
    required void Function(double) onProgress,
  }) async {
    final totalEstimatedBytes = spec.sizeMb * 1024 * 1024;
    var totalReceived = 0;

    for (final hfPath in spec.files) {
      final fileName = hfPath.split('/').last;
      final destFile = File('${destDir.path}/$fileName');
      if (destFile.existsSync()) {
        totalReceived += destFile.lengthSync();
        onProgress((totalReceived / totalEstimatedBytes).clamp(0.0, 0.99));
        continue;
      }

      const hfToken = String.fromEnvironment('HF_TOKEN');
      final url =
          'https://huggingface.co/${spec.hfRepo}/resolve/main/$hfPath?download=true';

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(url));
        if (hfToken.isNotEmpty) {
          req.headers['Authorization'] = 'Bearer $hfToken';
        }
        final response = await client.send(req);
        if (response.statusCode >= 400) {
          throw Exception('HTTP ${response.statusCode} for $hfPath');
        }

        final sink = destFile.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          totalReceived += chunk.length;
          onProgress((totalReceived / totalEstimatedBytes).clamp(0.0, 0.99));
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        if (destFile.existsSync()) await destFile.delete();
        rethrow;
      } finally {
        client.close();
      }

      debugPrint(
        '[LocalModelManager] saved: ${destFile.path} (${destFile.lengthSync()} bytes)',
      );
    }
  }
}
