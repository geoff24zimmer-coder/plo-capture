// MP4 export bridge. Hands captured replay frames to the in-browser WebCodecs
// encoder (web/mp4_encoder.js) and returns the muxed MP4 bytes. Web-only
// (dart:js_interop), like download_web.dart — the app ships as a PWA.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'gif_export.dart' show GifFrame;

@JS('ploEncodeMp4')
external JSPromise<JSUint8Array> _ploEncodeMp4(JSObject opts);

// Accessing an undefined global through an external getter yields null, so
// these double as feature detection without needing `has`.
@JS('ploEncodeMp4')
external JSFunction? get _encoderFn;
@JS('VideoEncoder')
external JSAny? get _videoEncoder;

/// True when the browser can produce an H.264 MP4 in-page (WebCodecs present
/// and the encoder glue loaded). When false, callers fall back to GIF.
bool mp4ExportAvailable() => _encoderFn != null && _videoEncoder != null;

/// Encode [frames] (even-sized RGBA, e.g. from [normalizeFrames]) into an MP4 at
/// [fps]. Throws if WebCodecs/H.264 fails at runtime — callers should catch and
/// fall back to GIF.
Future<Uint8List> encodeReplayMp4(List<GifFrame> frames,
    {double fps = 2}) async {
  final opts = JSObject()
    ..setProperty('width'.toJS, frames.first.width.toJS)
    ..setProperty('height'.toJS, frames.first.height.toJS)
    ..setProperty('fps'.toJS, fps.toJS)
    ..setProperty('frames'.toJS,
        [for (final f in frames) f.rgba.toJS].toJS);
  final result = await _ploEncodeMp4(opts).toDart;
  return result.toDart;
}
