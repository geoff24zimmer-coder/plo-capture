import 'dart:convert';

import 'package:archive/archive.dart';

/// Self-contained hand sharing — no backend, no account.
///
/// A whole hand's canonical JSON is gzip-compressed and base64url-encoded into a
/// single token that rides in the URL *fragment* (`…/#/r?h=<token>`). The
/// fragment is never sent to the server, so GitHub Pages serves the same static
/// app and Flutter decodes the hand on the recipient's device and replays it
/// locally. The token is the full schema-v1.0 blob, so [decodeHand] feeds
/// straight back into `loadHand` with zero divergence from a stored hand.
///
/// Pure Dart (no Flutter): unit-testable, and the parse helpers run at app
/// launch before any widget tree exists.

/// Hash route that carries a shared hand: `…/#/r?h=<token>`.
const String shareRoute = '/r';

/// gzip + base64url-encode [json] into a URL-safe token (padding stripped so the
/// link stays tidy; [decodeHand] restores it).
String encodeHand(Map<String, dynamic> json) {
  final raw = utf8.encode(jsonEncode(json));
  final gz = const GZipEncoder().encode(raw);
  return base64Url.encode(gz).replaceAll('=', '');
}

/// Inverse of [encodeHand]. Throws on a malformed/truncated token — callers that
/// parse untrusted URLs should guard with try/catch (see [parseShareLink]).
Map<String, dynamic> decodeHand(String token) {
  // Restore the base64 padding we stripped (length must be a multiple of 4).
  final padded = token.padRight((token.length + 3) & ~3, '=');
  final gz = base64Url.decode(padded);
  final raw = const GZipDecoder().decodeBytes(gz);
  return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
}

/// Full shareable URL for [json], anchored at wherever the app is served from
/// (`Uri.base` honours the GitHub Pages sub-path). The hand lives in the
/// fragment, so the path/query are left untouched.
String shareUrlForHand(Map<String, dynamic> json) {
  final base = Uri.base.removeFragment();
  return '$base#$shareRoute?h=${encodeHand(json)}';
}

/// Read the current URL for a shared hand. Returns:
/// - `isShare: false` — not a share link (boot the normal app).
/// - `isShare: true, hand: {...}` — a valid shared hand to replay.
/// - `isShare: true, hand: null` — a share link we couldn't decode (broken or
///   from an incompatible build) → show a friendly error rather than the app.
({bool isShare, Map<String, dynamic>? hand}) parseShareLink() {
  final frag = Uri.base.fragment; // e.g. "/r?h=<token>"
  final q = frag.indexOf('?');
  if (q < 0 || frag.substring(0, q) != shareRoute) {
    return (isShare: false, hand: null);
  }
  final token = Uri.splitQueryString(frag.substring(q + 1))['h'];
  if (token == null || token.isEmpty) return (isShare: true, hand: null);
  try {
    return (isShare: true, hand: decodeHand(token));
  } catch (_) {
    return (isShare: true, hand: null);
  }
}
