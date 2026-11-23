import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/endpoints.dart';
import '../../../core/api/frappe_client.dart';
import '../../../core/debug/console_log.dart';
import 'naba_models.dart';

/// A guideline picture ready to draw: the raster embedded in the server's
/// SVG wrapper when there is one ([raster]), otherwise the SVG itself ([svg]).
class GuidelineImageData {
  const GuidelineImageData.raster(Uint8List this.raster) : svg = null;
  const GuidelineImageData.svg(String this.svg) : raster = null;

  final Uint8List? raster;
  final String? svg;
}

/// Fetches guideline pictures from Frappe and keeps them on the device.
///
/// A picture's bytes never change for a given `sha256`, so the file is cached
/// permanently under `<app support>/naba_visuals/<sha256>.svg` and a cached
/// picture is served without touching the network — which is what keeps them
/// available offline. Bytes are verified against the sha256 before they are
/// written. Any failure returns null so the caller simply hides that picture.
class GuidelineVisualRepository {
  GuidelineVisualRepository(
    this._client, {
    Future<Directory> Function()? cacheRoot,
  }) : _cacheRoot = cacheRoot ?? getApplicationSupportDirectory;

  final FrappeClient _client;
  final Future<Directory> Function() _cacheRoot;

  static const String _cacheFolder = 'naba_visuals';
  static const int _maxDecoded = 24;
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _embeddedImage = RegExp(
    r'''href\s*=\s*["']data:image/[a-zA-Z+.-]+;base64,([^"']+)["']''',
  );

  final Map<String, Future<GuidelineImageData?>> _inFlight = {};
  final Map<String, GuidelineImageData> _decoded = {};

  Future<GuidelineImageData?> load(NabaVisualImage image) {
    final sha = image.sha256.toLowerCase();
    final ready = _decoded[sha];
    if (ready != null) return Future.value(ready);
    // Block body: `remove` returns this very future, and whenComplete waits
    // on any future its callback returns — an arrow body would deadlock.
    return _inFlight.putIfAbsent(
      sha,
      () => _load(image, sha).whenComplete(() {
        _inFlight.remove(sha);
      }),
    );
  }

  Future<GuidelineImageData?> _load(NabaVisualImage image, String sha) async {
    if (!_sha256Pattern.hasMatch(sha)) {
      ConsoleLog.warn('[NabaVisual] ${image.visualKey}: invalid sha256');
      return null;
    }
    if (!image.imagePath.startsWith(Endpoints.nabaVisualImagePrefix)) {
      ConsoleLog.warn('[NabaVisual] ${image.visualKey}: unexpected imagePath');
      return null;
    }
    try {
      final file = await _cacheFile(sha);
      final svg =
          await _readCached(file, sha) ?? await _download(image, sha, file);
      if (svg == null) return null;
      final data = decode(svg);
      _remember(sha, data);
      return data;
    } on FrappeException catch (e) {
      ConsoleLog.warn('[NabaVisual] ${image.visualKey}: $e');
    } on FileSystemException catch (e) {
      ConsoleLog.warn('[NabaVisual] ${image.visualKey}: cache I/O failed: $e');
    } on FormatException catch (e) {
      ConsoleLog.warn('[NabaVisual] ${image.visualKey}: undecodable image: $e');
    }
    return null;
  }

  Future<File> _cacheFile(String sha) async {
    final root = await _cacheRoot();
    final dir = Directory('${root.path}/$_cacheFolder');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}/$sha.svg');
  }

  /// Cached SVG text, or null when absent. A file whose bytes no longer
  /// match its name is deleted and re-downloaded.
  Future<String?> _readCached(File file, String sha) async {
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() == sha) return utf8.decode(bytes);
    ConsoleLog.warn('[NabaVisual] cached $sha is corrupt — re-downloading');
    await file.delete();
    return null;
  }

  Future<String?> _download(
    NabaVisualImage image,
    String sha,
    File file,
  ) async {
    final response = await _client.getBytes(image.imagePath);
    final bytes = response.bytes;
    if (bytes == null) return null;
    if (sha256.convert(bytes).toString() != sha) {
      ConsoleLog.warn(
        '[NabaVisual] ${image.visualKey}: sha256 mismatch — not cached',
      );
      return null;
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return utf8.decode(bytes);
  }

  void _remember(String sha, GuidelineImageData data) {
    if (_decoded.length >= _maxDecoded) _decoded.remove(_decoded.keys.first);
    _decoded[sha] = data;
  }

  /// The server's SVG is a wrapper around one embedded JPEG/PNG; drawing that
  /// raster directly is cheaper than rendering the SVG. Falls back to the SVG
  /// when no embedded image is found.
  static GuidelineImageData decode(String svg) {
    final match = _embeddedImage.firstMatch(svg);
    if (match == null) return GuidelineImageData.svg(svg);
    final payload = match.group(1)!.replaceAll(RegExp(r'\s'), '');
    return GuidelineImageData.raster(base64Decode(payload));
  }
}
