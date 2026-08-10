import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/scribe_api_service.dart';
import '../../core/db/app_database.dart';
import '../../core/db/audio_sample_dao.dart';

/// Background service that uploads staged training audio samples.
///
/// Singleton — call [AudioSampleSyncService.init] once after the DB is open,
/// then use [AudioSampleSyncService.instance] everywhere. ConnectivityPlus
/// triggers uploads on reconnect; [nudge] triggers an immediate attempt.
///
/// Audio failures never surface to the CHW and never block encounter sync.
class AudioSampleSyncService {
  AudioSampleSyncService._({
    required AudioSampleDao dao,
    required ScribeApiService api,
  })  : _dao = dao,
        _api = api;

  final AudioSampleDao _dao;
  final ScribeApiService _api;

  static AudioSampleSyncService? _instance;

  /// The singleton instance. Throws if [init] has not been called.
  static AudioSampleSyncService get instance {
    assert(_instance != null, 'AudioSampleSyncService.init() not called');
    return _instance!;
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _uploadInFlight = false;

  /// Initialize the singleton. Safe to call multiple times — only the first
  /// call has any effect.
  static void init({
    required AppDatabase db,
    required ScribeApiService api,
  }) {
    _instance ??= AudioSampleSyncService._(
      dao: AudioSampleDao(db),
      api: api,
    ).._startListening();
  }

  void _startListening() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);
    unawaited(_cleanupAbandoned());
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    debugPrint('[AudioSampleSync] connectivity changed — online=$isOnline');
    if (isOnline) nudge();
  }

  /// Fire-and-forget: attempt to upload all due pending samples now.
  void nudge() {
    debugPrint('[AudioSampleSync] nudge()');
    unawaited(_uploadPending());
  }

  Future<void> _uploadPending() async {
    if (_uploadInFlight) {
      debugPrint('[AudioSampleSync] upload already in flight, skipping');
      return;
    }
    _uploadInFlight = true;
    try {
      final samples = await _dao.getDueSamples();
      debugPrint('[AudioSampleSync] due samples: ${samples.length}');
      for (final sample in samples) {
        final file = File(sample.localFilePath);
        debugPrint(
            '[AudioSampleSync] processing id=${sample.id} file=${sample.localFilePath} exists=${file.existsSync()}');
        if (!file.existsSync()) {
          debugPrint('[AudioSampleSync] file missing → abandoned id=${sample.id}');
          await _dao.markAbandoned(sample.id);
          continue;
        }
        try {
          debugPrint(
              '[AudioSampleSync] uploading id=${sample.id} size=${file.lengthSync()}B encounterId=${sample.encounterId}');
          await _api.uploadAudioSample(
            file,
            localSampleId: sample.id,
            encounterId: sample.encounterId,
            fhirEncounterId: sample.fhirEncounterId,
            scribeMode: sample.scribeMode,
            language: sample.language,
          );
          debugPrint('[AudioSampleSync] upload OK id=${sample.id} — deleting local file');
          await file.delete();
          debugPrint('[AudioSampleSync] local file deleted id=${sample.id}');
          await _dao.markUploaded(sample.id);
          debugPrint('[AudioSampleSync] DB marked uploaded id=${sample.id}');
        } catch (e) {
          debugPrint('[AudioSampleSync] upload FAILED id=${sample.id} retry=${sample.retryCount}: $e');
          await _dao.scheduleRetry(sample.id, sample.retryCount);
        }
      }
    } catch (e) {
      debugPrint('[AudioSampleSync] _uploadPending error: $e');
    } finally {
      _uploadInFlight = false;
    }
  }

  /// Called when [OfflinePushService] resolves a FHIR id for an encounter.
  /// Updates only the local DB — the fhir_encounter_id is included in the
  /// next upload payload; no PATCH to the server is required.
  Future<void> updateFhirEncounterId(
      String encounterId, String fhirId) async {
    try {
      await _dao.updateFhirEncounterId(encounterId, fhirId);
      nudge();
    } catch (e) {
      debugPrint('[AudioSampleSync] updateFhirEncounterId error: $e');
    }
  }

  /// Delete local files for abandoned rows and orphan files older than 7 days.
  Future<void> _cleanupAbandoned() async {
    try {
      final paths = await _dao.getAbandonedLocalPaths();
      for (final path in paths) {
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
      final dir = await getApplicationDocumentsDirectory();
      final trainingDir = Directory('${dir.path}/training_audio');
      if (!trainingDir.existsSync()) return;
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      await for (final entity in trainingDir.list()) {
        if (entity is! File) continue;
        final stat = entity.statSync();
        if (stat.modified.millisecondsSinceEpoch < cutoff) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[AudioSampleSync] cleanup error: $e');
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}
