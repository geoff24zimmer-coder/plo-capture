import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One captured replay frame: raw RGBA pixels straight from
/// `RenderRepaintBoundary.toImage(...).toByteData(rawRgba)`.
class GifFrame {
  final int width;
  final int height;
  final Uint8List rgba;
  const GifFrame(this.width, this.height, this.rgba);
}

/// App scaffold colour — frames are composited onto it so the felt's
/// transparent margins render as the same dark background as the live app
/// (GIF has no real alpha; un-composited edges would otherwise fringe).
const _bg = (0x0C, 0x0F, 0x0E);

/// Normalise raw captured frames into a clip-ready set, shared by both the GIF
/// and MP4 encoders: downscaled to [maxWidth], composited onto the felt
/// background (opaque), and forced to EVEN width/height — H.264 rejects odd
/// dimensions, and even frames are harmless for GIF. Returns RGBA frames.
List<GifFrame> normalizeFrames(List<GifFrame> src, {int maxWidth = 500}) {
  final out = <GifFrame>[];
  for (final f in src) {
    var im = img.Image.fromBytes(
      width: f.width,
      height: f.height,
      bytes: f.rgba.buffer,
      bytesOffset: f.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    if (im.width > maxWidth) im = img.copyResize(im, width: maxWidth);
    final ew = im.width - (im.width & 1);
    final eh = im.height - (im.height & 1);
    final canvas = img.Image(width: ew, height: eh)
      ..clear(img.ColorRgb8(_bg.$1, _bg.$2, _bg.$3));
    img.compositeImage(canvas, im); // clips the odd edge row/col if any
    out.add(GifFrame(ew, eh, canvas.getBytes(order: img.ChannelOrder.rgba)));
  }
  return out;
}

/// Assemble a step-frame replay [frames] into an animated GIF (loops forever).
/// Each frame is one replay node held for [stepCentis] hundredths of a second
/// ([lastCentis] for the final frame so the result lingers), downscaled to
/// [maxWidth] for a sane file size. Returns the GIF bytes, or null if empty.
Uint8List? encodeReplayGif(
  List<GifFrame> frames, {
  int maxWidth = 500,
  int stepCentis = 65,
  int lastCentis = 250,
}) {
  if (frames.isEmpty) return null;
  final enc = img.GifEncoder(repeat: 0);
  for (var i = 0; i < frames.length; i++) {
    final fr = frames[i];
    var im = img.Image.fromBytes(
      width: fr.width,
      height: fr.height,
      bytes: fr.rgba.buffer,
      bytesOffset: fr.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    if (im.width > maxWidth) im = img.copyResize(im, width: maxWidth);
    final canvas = img.Image(width: im.width, height: im.height)
      ..clear(img.ColorRgb8(_bg.$1, _bg.$2, _bg.$3));
    img.compositeImage(canvas, im);
    enc.addFrame(canvas,
        duration: i == frames.length - 1 ? lastCentis : stepCentis);
  }
  return enc.finish();
}
