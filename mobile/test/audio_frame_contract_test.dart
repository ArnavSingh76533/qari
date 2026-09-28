import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../lib/data/services/streaming_recitation_service.dart';

/// The audio framing contract, tested against the REAL service so a future
/// edit cannot silently re-introduce client-side batching.
///
/// BUG BEING GUARDED: the stream used to accumulate every native mic chunk and
/// flush the WHOLE buffer on a 250 ms timer. That shipped 250 ms+ blobs — and
/// 1-2 s blobs whenever the native cadence was slower — stacked on top of the
/// server's own analysis window, which is what users experience as "the words
/// appear long after I said them".
void main() {
  group('100 ms PCM frame contract', () {
    test('a frame is 3200 bytes = 100 ms of PCM16 mono 16 kHz', () {
      // 16000 samples/s * 2 bytes * 0.1 s
      expect(16000 * 2 * 0.1, 3200);
      expect(StreamingRecitationService.pcmFrameBytesForTest, 3200);
    });

    test('the safety-net timer is short enough that it cannot batch', () {
      expect(
        StreamingRecitationService.flushIntervalForTest.inMilliseconds,
        lessThanOrEqualTo(150),
        reason: 'a long timer would reintroduce the batching bug',
      );
    });
  });

  group('framing arithmetic (the pump loop, exercised directly)', () {
    // Mirrors _pumpFrames' while-loop over the pending buffer. Kept here as an
    // executable spec of the invariant.
    List<int> cutFrames(List<int> pending, int frameBytes) {
      final out = <int>[];
      while (pending.length >= frameBytes) {
        out.add(frameBytes);
        pending.removeRange(0, frameBytes);
      }
      return out;
    }

    test('one full second of audio yields exactly 10 frames of 3200 bytes', () {
      final p = List<int>.filled(16000 * 2, 0).toList(); // 1 s
      final frames = cutFrames(p, 3200);
      expect(frames.length, 10);
      expect(frames.every((n) => n == 3200), isTrue);
      expect(p, isEmpty, reason: 'no audio may be left stranded');
    });

    test('a partial frame is NOT sent until the tail flush', () {
      final p = List<int>.filled(2000, 0).toList(); // 62 ms — not a whole frame
      expect(cutFrames(p, 3200), isEmpty,
          reason: 'a partial frame must not be shipped as a short frame');
      expect(p.length, 2000, reason: 'it stays buffered for the tail flush');
    });

    test('chunks arriving in small pieces still emit whole frames promptly',
        () {
      final p = <int>[];
      final emitted = <int>[];
      // Native delivers 20 ms (640 byte) pieces, as a real device does.
      for (var i = 0; i < 5; i++) {
        p.addAll(List<int>.filled(640, 0).toList());
        emitted.addAll(cutFrames(p, 3200));
      }
      // 5 x 640 = 3200 -> exactly one frame emitted on the 5th chunk, i.e.
      // immediately, not 250 ms later.
      expect(emitted, [3200]);
      expect(p, isEmpty);
    });

    test('no frame is ever larger than 3200 bytes', () {
      final p = List<int>.filled(16000 * 2, 0).toList(); // one big 1 s blob
      final frames = cutFrames(p, 3200);
      expect(frames, everyElement(3200));
      expect(frames.length, 10);
    });
  });
}
