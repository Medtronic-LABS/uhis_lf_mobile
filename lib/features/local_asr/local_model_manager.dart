import 'dart:io';

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
    required this.hfRepo,
    required this.files,
    required this.subDir,
  });

  final String id;
  final String label;
  final String description;
  final int sizeMb;
  final String hfRepo;

  /// Relative paths within the HF repo → downloaded to [subDir]/filename.
  final List<String> files;

  /// Sub-directory under the models root where this model lives.
  final String subDir;
}

const kAsrModel = LocalModelSpec(
  id: 'sherpa-bn-streaming',
  label: 'Bengali ASR Model',
  description: 'alphacep/vosk streaming transducer fine-tuned on Bengali. '
      'Used for on-device speech recognition.',
  sizeMb: 92,
  hfRepo: 'alphacep/vosk-model-small-streaming-bn',
  files: [
    'am-onnx/encoder.onnx',
    'am-onnx/decoder.onnx',
    'am-onnx/joiner.onnx',
    'lang/bpe.model',
    'lang/tokens.txt',
  ],
  subDir: 'sherpa_bn_streaming',
);

const kLlmModelSmall = LocalModelSpec(
  id: 'qwen3-0.6b',
  label: 'Qwen3 0.6B LLM (faster)',
  description: 'Qwen3-0.6B Q4_K_M — 100+ languages including Bengali. '
      'Used for form field extraction from transcript.',
  sizeMb: 397,
  hfRepo: 'unsloth/Qwen3-0.6B-GGUF',
  files: ['Qwen3-0.6B-Q4_K_M.gguf'],
  subDir: 'llm_models',
);

const kLlmModelLarge = LocalModelSpec(
  id: 'qwen3-1.7b',
  label: 'Qwen3 1.7B LLM (better accuracy)',
  description: 'Qwen3-1.7B Q4_K_M — recommended for reliable form fill. '
      'Requires ~1.1GB storage and more RAM.',
  sizeMb: 1100,
  hfRepo: 'unsloth/Qwen3-1.7B-GGUF',
  files: ['Qwen3-1.7B-Q4_K_M.gguf'],
  subDir: 'llm_models',
);

enum _DownloadTarget { asr, llm }

/// Manages download, storage, and status of local AI model files.
///
/// Provides progress and installed state for [LocalModelDownloadScreen].
/// After download, [asrModelDir] and [llmModelPath] supply paths to
/// [LocalScribeController].
class LocalModelManager extends ChangeNotifier {
  LocalModelManager();

  String? _modelsRoot;

  /// Progress 0.0–1.0 for each active download. Null = not downloading.
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

  Future<void> init() async {
    final root = await _getRoot();
    _modelsRoot = root;
    _asrInstalled = _checkAsrInstalled(root);
    _llmInstalled = _checkLlmInstalled(root, _activeLlm);
    notifyListeners();
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

  bool _checkAsrInstalled(String root) {
    for (final f in kAsrModel.files) {
      final name = f.split('/').last;
      if (!File('$root/${kAsrModel.subDir}/$name').existsSync()) return false;
    }
    return true;
  }

  bool _checkLlmInstalled(String root, LocalModelSpec spec) {
    final file = spec.files.first;
    return File('$root/${spec.subDir}/$file').existsSync();
  }

  Future<void> downloadAsr() async {
    if (asrDownloading || _asrInstalled) return;
    _asrError = null;
    await _download(
      spec: kAsrModel,
      target: _DownloadTarget.asr,
    );
  }

  Future<void> downloadLlm({LocalModelSpec? spec}) async {
    if (llmDownloading) return;
    _activeLlm = spec ?? _activeLlm;
    _llmError = null;
    _llmInstalled = false;
    await _download(
      spec: _activeLlm,
      target: _DownloadTarget.llm,
    );
  }

  Future<void> deleteAsr() async {
    final root = _modelsRoot;
    if (root == null) return;
    final dir = Directory('$root/${kAsrModel.subDir}');
    if (dir.existsSync()) await dir.delete(recursive: true);
    _asrInstalled = false;
    notifyListeners();
  }

  Future<void> deleteLlm() async {
    final root = _modelsRoot;
    if (root == null) return;
    final path = llmModelPath;
    final f = File(path);
    if (f.existsSync()) await f.delete();
    _llmInstalled = false;
    notifyListeners();
  }

  Future<void> _download({
    required LocalModelSpec spec,
    required _DownloadTarget target,
  }) async {
    final root = _modelsRoot ?? await _getRoot();
    _modelsRoot = root;

    final destDir = Directory('$root/${spec.subDir}');
    await destDir.create(recursive: true);

    final totalFiles = spec.files.length;
    var completedFiles = 0;

    void setProgress(double p) {
      final overall = (completedFiles + p) / totalFiles;
      if (target == _DownloadTarget.asr) {
        _asrProgress = overall;
      } else {
        _llmProgress = overall;
      }
      notifyListeners();
    }

    try {
      for (final hfPath in spec.files) {
        final fileName = hfPath.split('/').last;
        final destFile = File('$destDir/$fileName');
        if (destFile.existsSync()) {
          completedFiles++;
          setProgress(0);
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

          final total = response.contentLength ?? 0;
          var received = 0;
          final sink = destFile.openWrite();
          await for (final chunk in response.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) setProgress(received / total);
          }
          await sink.flush();
          await sink.close();
        } catch (e) {
          // Clean up partial file on error
          if (destFile.existsSync()) await destFile.delete();
          rethrow;
        } finally {
          client.close();
        }

        completedFiles++;
        setProgress(0);
      }

      if (target == _DownloadTarget.asr) {
        _asrInstalled = true;
        _asrProgress = null;
      } else {
        _llmInstalled = true;
        _llmProgress = null;
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('[LocalModelManager] download error: $e\n$st');
      if (target == _DownloadTarget.asr) {
        _asrError = e.toString();
        _asrProgress = null;
      } else {
        _llmError = e.toString();
        _llmProgress = null;
      }
      notifyListeners();
    }
  }
}
