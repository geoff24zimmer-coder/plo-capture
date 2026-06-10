// Browser file download for the solver export. Zips the in-memory bundle and
// pushes it through an object-URL anchor click. Web-only (the app ships as a
// PWA); kept in its own file so the JS-interop stays out of the pure modules.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:web/web.dart' as web;

/// Zip `files` (path → text contents) and trigger a download named [filename].
void downloadZip(String filename, Map<String, String> files) {
  final archive = Archive();
  files.forEach((path, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });
  final zipped = ZipEncoder().encode(archive);
  final bytes = Uint8List.fromList(zipped);

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/zip'),
  );
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
