// MP4 export glue for The PLO Show replay clips.
//
// Turns a sequence of captured RGBA frames (from Flutter's RepaintBoundary,
// already even-sized and composited onto the felt background on the Dart side)
// into an H.264 MP4 entirely in the browser — no backend. WebCodecs does the
// codec; the vendored mp4-muxer (global `Mp4Muxer`) writes the container.
//
// Exposes window.ploEncodeMp4({ width, height, fps, frames }) -> Promise<Uint8Array>.
// `frames` is an array of Uint8Array, each exactly width*height*4 bytes (RGBA).
// Callers should feature-detect `('VideoEncoder' in self)` first; the Dart side
// falls back to GIF when WebCodecs (or H.264) is unavailable.
(function () {
  window.ploEncodeMp4 = async function (opts) {
    const width = opts.width | 0;
    const height = opts.height | 0;
    const fps = opts.fps || 2;
    const frames = opts.frames;
    if (!('VideoEncoder' in self)) throw new Error('WebCodecs unavailable');
    if (!width || !height || !frames || !frames.length) {
      throw new Error('no frames to encode');
    }

    // Resolution-aware bitrate: ~4 bits/pixel/frame keeps the felt's smooth
    // gradients clean (low bitrate is what makes H.264 look grainy). Clamped to
    // a sane band. Override via opts.bitrate.
    const bitrate = opts.bitrate ||
      Math.min(12_000_000, Math.max(4_000_000, Math.round(width * height * 4 * fps)));

    // Prefer the strongest broadly-playable H.264 profile (High → Main →
    // Baseline); High compresses far better at the same bitrate.
    let codec = null;
    for (const c of ['avc1.640028', 'avc1.4d0028', 'avc1.42001f']) {
      try {
        const s = await VideoEncoder.isConfigSupported(
          { codec: c, width, height, bitrate, framerate: fps });
        if (s && s.supported) { codec = c; break; }
      } catch (e) { /* try next */ }
    }
    if (!codec) throw new Error('no supported H.264 config');

    const muxer = new Mp4Muxer.Muxer({
      target: new Mp4Muxer.ArrayBufferTarget(),
      video: { codec: 'avc', width: width, height: height },
      // moov at the front → the clip streams / autoplays inline immediately.
      fastStart: 'in-memory',
    });

    let encodeError = null;
    const encoder = new VideoEncoder({
      output: (chunk, meta) => muxer.addVideoChunk(chunk, meta),
      error: (e) => { encodeError = e; },
    });
    encoder.configure({
      codec: codec,
      width: width,
      height: height,
      bitrate: bitrate,
      framerate: fps,
      // Offline export: let the encoder spend effort on quality, not latency.
      latencyMode: 'quality',
      avc: { format: 'avc' }, // length-prefixed NALs + a decoder description for the muxer
    });

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d');
    const frameDurUs = Math.round(1e6 / fps);

    for (let i = 0; i < frames.length; i++) {
      const u8 = frames[i] instanceof Uint8Array
        ? frames[i]
        : new Uint8Array(frames[i]);
      const clamped = new Uint8ClampedArray(u8.buffer, u8.byteOffset, u8.byteLength);
      ctx.putImageData(new ImageData(clamped, width, height), 0, 0);
      const frame = new VideoFrame(canvas, {
        timestamp: i * frameDurUs,
        duration: frameDurUs,
      });
      encoder.encode(frame, { keyFrame: i === 0 });
      frame.close();
      if (encodeError) throw encodeError;
    }

    await encoder.flush();
    encoder.close();
    if (encodeError) throw encodeError;
    muxer.finalize();
    return new Uint8Array(muxer.target.buffer);
  };
})();
