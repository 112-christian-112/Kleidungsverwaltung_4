// lib/services/download_stub.dart
// Wird auf Mobilgeräten / Desktop verwendet — tut nichts.

import 'dart:typed_data';

void downloadFileOnWeb(
    Uint8List bytes, String fileName, String mimeType) {
  throw UnsupportedError('Web-Download ist auf dieser Plattform nicht verfügbar.');
}
