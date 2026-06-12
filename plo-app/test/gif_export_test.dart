import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:plo_capture/export/gif_export.dart';

/// A solid-colour w×h RGBA frame.
GifFrame solid(int w, int h, int r, int g, int b) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = r;
    px[i * 4 + 1] = g;
    px[i * 4 + 2] = b;
    px[i * 4 + 3] = 255;
  }
  return GifFrame(w, h, px);
}

void main() {
  group('encodeReplayGif', () {
    test('returns null for no frames', () {
      expect(encodeReplayGif(const []), isNull);
    });

    test('encodes a valid animated GIF from frames', () {
      final bytes = encodeReplayGif([
        solid(8, 6, 200, 30, 30),
        solid(8, 6, 30, 200, 30),
        solid(8, 6, 30, 30, 200),
      ]);
      expect(bytes, isNotNull);
      // GIF magic: "GIF87a" or "GIF89a" (animation forces 89a).
      expect(String.fromCharCodes(bytes!.sublist(0, 6)), 'GIF89a');
      expect(bytes.length, greaterThan(20));
    });

    test('downscales frames wider than maxWidth', () {
      // A 1000-px-wide frame must not blow past the cap in the logical screen
      // size header (bytes 6-7 little-endian = canvas width).
      final bytes = encodeReplayGif([solid(1000, 10, 100, 100, 100)],
          maxWidth: 500)!;
      final headerWidth = bytes[6] | (bytes[7] << 8);
      expect(headerWidth, 500);
    });
  });

  group('normalizeFrames', () {
    test('forces even dimensions and caps width (H.264 needs even dims)', () {
      // Odd-sized, oversized source → even, downscaled output.
      final out = normalizeFrames([solid(1001, 599, 40, 120, 40)],
          maxWidth: 500);
      expect(out, hasLength(1));
      expect(out.first.width, 500);
      expect(out.first.width.isEven, isTrue);
      expect(out.first.height.isEven, isTrue);
      expect(out.first.rgba.length, out.first.width * out.first.height * 4);
    });

    test('composites to fully opaque frames (no alpha fringing)', () {
      // Even a transparent source comes out opaque over the felt background.
      final transparent = GifFrame(20, 20, Uint8List(20 * 20 * 4));
      final out = normalizeFrames([transparent], maxWidth: 500).first;
      var allOpaque = true;
      for (var i = 3; i < out.rgba.length; i += 4) {
        if (out.rgba[i] != 255) {
          allOpaque = false;
          break;
        }
      }
      expect(allOpaque, isTrue);
    });
  });
}
