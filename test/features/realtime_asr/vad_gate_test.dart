import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/realtime_asr/vad_gate.dart';

/// Builds a constant-amplitude PCM16LE mono 16kHz buffer of [durationMs],
/// whose RMS (and therefore VadGate's dBFS reading) equals exactly the
/// amplitude derived from [dbfs] — a constant-value sequence makes RMS
/// trivially deterministic for test purposes.
Uint8List _tone({required double dbfs, required int durationMs}) {
  final amplitude = (32768 * math.pow(10, dbfs / 20)).round();
  final sampleCount = durationMs * 16; // 16 samples/ms at 16kHz
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    bytes.setInt16(i * 2, amplitude, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List _silence(int durationMs) => Uint8List(durationMs * 32);

int _bytesOf(List<Uint8List> chunks) =>
    chunks.fold(0, (sum, c) => sum + c.length);

/// Builds a [VadGate] with fixed, explicit thresholds — these tests verify
/// the gate's hysteresis/debounce/floor-adaptation *math* against specific
/// dBFS values worked out by hand, so they pin the exact parameters that
/// math depends on rather than whatever AppConfig's tunable defaults
/// currently are (see vad_gate.dart's own constructor defaults, which are
/// a separately-tunable field-deployment baseline, not a test fixture).
VadGate _testGate() => VadGate(
      enterMarginDb: 12,
      sustainMarginDb: 7,
      floorCeilingDbfs: -25,
      bootstrapDuration: const Duration(milliseconds: 400),
      debounceDuration: const Duration(milliseconds: 180),
      hangoverDuration: const Duration(milliseconds: 550),
      preRollDuration: const Duration(milliseconds: 350),
    );

void main() {
  group('VadGate', () {
    test('all-zero silence indefinitely → always empty, floor stays finite', () {
      final gate = _testGate();
      for (var i = 0; i < 50; i++) {
        final result = gate.process(_silence(50));
        expect(result, isEmpty);
        expect(gate.floorDbfs.isFinite, isTrue);
      }
    });

    test('fresh gate first chunk does not crash with no prior floor history', () {
      final gate = _testGate();
      expect(() => gate.process(_silence(50)), returnsNormally);
      expect(gate.floorDbfs.isFinite, isTrue);
    });

    test('defensive: zero-length and odd-length input do not throw', () {
      final gate = _testGate();
      expect(() => gate.process(Uint8List(0)), returnsNormally);
      expect(() => gate.process(Uint8List(3)), returnsNormally);
    });

    test('silence then sustained tone: empty during debounce, then a byte-exact flush',
        () {
      final gate = _testGate();
      // Bootstrap with one 400ms all-zero chunk.
      gate.process(_silence(400));

      // 100ms of true pre-speech silence.
      final preSpeech = _silence(100);
      expect(gate.process(preSpeech), isEmpty);

      // Sustained loud tone (-15 dBFS, well above the clamped floor's entry
      // threshold) in 50ms chunks, crossing the 180ms debounce on the 4th.
      final toneChunks = [
        for (var i = 0; i < 4; i++) _tone(dbfs: -15, durationMs: 50),
      ];

      final flushedResults = <Uint8List>[];
      List<Uint8List>? flushChunk;
      for (final chunk in toneChunks) {
        final result = gate.process(chunk);
        if (result.isNotEmpty) {
          flushChunk = result;
          break;
        }
        flushedResults.add(chunk);
      }

      expect(flushChunk, isNotNull,
          reason: 'gate should flip to voice once debounce duration elapses');
      final expectedBytes = preSpeech.length +
          flushedResults.fold<int>(0, (sum, c) => sum + c.length) +
          toneChunks[flushedResults.length].length;
      expect(_bytesOf(flushChunk!), expectedBytes);
    });

    test('sustained voice then abrupt silence: non-empty through hangover, then empty',
        () {
      final gate = _testGate();
      gate.process(_silence(400)); // bootstrap

      // Debounce into voice state.
      for (var i = 0; i < 4; i++) {
        gate.process(_tone(dbfs: -15, durationMs: 50));
      }
      expect(gate.isVoiceActive, isTrue);

      // Abrupt silence — hangover is 550ms by default; feed 50ms chunks and
      // confirm output stays non-empty through the window.
      var elapsedMs = 0;
      var wentEmpty = false;
      while (elapsedMs < 900) {
        final result = gate.process(_silence(50));
        elapsedMs += 50;
        if (result.isEmpty) {
          wentEmpty = true;
          break;
        }
      }
      expect(wentEmpty, isTrue,
          reason: 'must eventually stop sending once hangover elapses');
      expect(elapsedMs, greaterThanOrEqualTo(550));
      expect(gate.isVoiceActive, isFalse);
    });

    test('energy wavering between sustain and enter thresholds in voice state: no chatter',
        () {
      final gate = _testGate();
      gate.process(_silence(400)); // bootstrap, floor clamps to -90

      for (var i = 0; i < 4; i++) {
        gate.process(_tone(dbfs: -15, durationMs: 50));
      }
      expect(gate.isVoiceActive, isTrue);

      // -80 dBFS is above sustain (floor -90 + 7 = -83) but below enter
      // (floor -90 + 12 = -78) — must stay in voice state without needing to
      // re-clear the higher enter threshold.
      for (var i = 0; i < 10; i++) {
        final result = gate.process(_tone(dbfs: -80, durationMs: 50));
        expect(result, isNotEmpty);
        expect(gate.isVoiceActive, isTrue);
      }
    });

    test('single loud transient shorter than debounce window never triggers a flip',
        () {
      final gate = _testGate();
      gate.process(_silence(400)); // bootstrap

      final result = gate.process(_tone(dbfs: -15, durationMs: 50));
      expect(result, isEmpty);
      expect(gate.isVoiceActive, isFalse);

      // Back to silence immediately — debounce counter must have reset, not
      // partially carried over.
      final after = gate.process(_silence(50));
      expect(after, isEmpty);
      expect(gate.isVoiceActive, isFalse);
    });

    test('floor adapts upward over sustained moderate "silent" noise', () {
      final gate = _testGate();
      // Bootstrap floor at -50 dBFS.
      gate.process(_tone(dbfs: -50, durationMs: 400));
      final initialFloor = gate.floorDbfs;
      expect(initialFloor, closeTo(-50, 1));

      // -45 dBFS is below the entry threshold (-50+12=-38), so it's
      // classified silence and should pull the floor upward via EMA.
      for (var i = 0; i < 200; i++) {
        final result = gate.process(_tone(dbfs: -45, durationMs: 50));
        expect(result, isEmpty);
      }
      expect(gate.floorDbfs, greaterThan(initialFloor));
      expect(gate.floorDbfs, closeTo(-45, 1));
    });

    test('marginal chunk that triggers voice against the old floor no longer does once adapted',
        () {
      final gate = _testGate();
      gate.process(_tone(dbfs: -50, durationMs: 400)); // floor = -50

      // -36 dBFS is above the ORIGINAL entry threshold (-50+12=-38).
      // Confirm it would have registered as voice against the original floor
      // by checking a fresh gate bootstrapped identically.
      final freshGate = _testGate();
      freshGate.process(_tone(dbfs: -50, durationMs: 400));
      var triggeredOriginally = false;
      for (var i = 0; i < 4; i++) {
        if (freshGate.process(_tone(dbfs: -36, durationMs: 50)).isNotEmpty) {
          triggeredOriginally = true;
        }
      }
      expect(triggeredOriginally, isTrue);

      // Now adapt the floor toward -45 on the original gate.
      for (var i = 0; i < 200; i++) {
        gate.process(_tone(dbfs: -45, durationMs: 50));
      }
      expect(gate.isVoiceActive, isFalse);

      // -36 dBFS is now below the adapted entry threshold (~-45+12=-33).
      var triggeredAfterAdapt = false;
      for (var i = 0; i < 4; i++) {
        if (gate.process(_tone(dbfs: -36, durationMs: 50)).isNotEmpty) {
          triggeredAfterAdapt = true;
        }
      }
      expect(triggeredAfterAdapt, isFalse);
    });

    test('floor does not move during a long run of loud voice frames', () {
      final gate = _testGate();
      gate.process(_silence(400)); // bootstrap, floor clamps to -90
      final floorBefore = gate.floorDbfs;

      for (var i = 0; i < 200; i++) {
        gate.process(_tone(dbfs: -20, durationMs: 50));
      }
      expect(gate.isVoiceActive, isTrue);
      expect(gate.floorDbfs, closeTo(floorBefore, 0.01));
    });

    test('floor never exceeds the ceiling clamp even under sustained loud "silent" noise',
        () {
      final gate = _testGate();
      // Bootstrap just under the ceiling (-25).
      gate.process(_tone(dbfs: -27, durationMs: 400));
      expect(gate.floorDbfs, lessThanOrEqualTo(-25));

      // -20 dBFS is louder than the ceiling but stays below the entry
      // threshold (floor+12) throughout the climb, so it's always
      // classified silence and keeps pulling the floor toward it.
      for (var i = 0; i < 500; i++) {
        final result = gate.process(_tone(dbfs: -20, durationMs: 50));
        expect(result, isEmpty);
        expect(gate.floorDbfs, lessThanOrEqualTo(-25.0));
      }
    });
  });
}
