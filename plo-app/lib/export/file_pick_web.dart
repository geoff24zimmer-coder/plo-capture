// Browser file open for restoring a backup: a hidden <input type=file>, read as
// text. Web-only JS interop, kept out of the pure modules (see download_web).

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Let the user pick one file matching [accept] (e.g. `.json`) and return its
/// text, or null if they cancel.
Future<String?> pickTextFile({String accept = '.json'}) {
  final done = Completer<String?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = accept
    ..style.display = 'none';
  input.addEventListener(
      'change',
      (web.Event _) {
        final file = input.files?.item(0);
        input.remove();
        if (file == null) {
          done.complete(null);
          return;
        }
        file.text().toDart.then((t) => done.complete(t.toDart),
            onError: (Object e) => done.completeError(e));
      }.toJS);
  input.addEventListener(
      'cancel',
      (web.Event _) {
        input.remove();
        if (!done.isCompleted) done.complete(null);
      }.toJS);
  web.document.body!.appendChild(input);
  input.click();
  return done.future;
}
