// Browser file downloads for the exports. Pushes bytes/text through an
// object-URL anchor click. Web-only (the app ships as a PWA); kept in its own
// file so the JS-interop stays out of the pure modules.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:web/web.dart' as web;

/// Zip `files` (path → text contents) and download as [filename] — the
/// population bundle (many small files).
void downloadZip(String filename, Map<String, String> files) {
  final archive = Archive();
  files.forEach((path, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });
  final zipped = Uint8List.fromList(ZipEncoder().encode(archive));
  _save(filename, zipped.toJS, 'application/zip');
}

/// Download a single text file — the review export (one record per file).
void downloadText(String filename, String contents) =>
    _save(filename, contents.toJS, 'application/json');

void _save(String filename, JSAny blobPart, String mime) {
  final blob = web.Blob([blobPart].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
