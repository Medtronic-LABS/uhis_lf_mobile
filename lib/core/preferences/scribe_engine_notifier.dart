import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum ScribeEngine { gemini, liveAsr }

class ScribeEngineNotifier extends ChangeNotifier {
  ScribeEngineNotifier(this._storage);

  final FlutterSecureStorage _storage;
  static const _storageKey = 'scribe_engine_v1';

  ScribeEngine _engine = ScribeEngine.gemini;
  ScribeEngine get engine => _engine;
  bool get isLiveAsr => _engine == ScribeEngine.liveAsr;

  Future<void> load() async {
    final val = await _storage.read(key: _storageKey);
    _engine = val == 'liveAsr' ? ScribeEngine.liveAsr : ScribeEngine.gemini;
    notifyListeners();
  }

  Future<void> set(ScribeEngine engine) async {
    if (_engine == engine) return;
    _engine = engine;
    await _storage.write(key: _storageKey, value: engine.name);
    notifyListeners();
  }
}
