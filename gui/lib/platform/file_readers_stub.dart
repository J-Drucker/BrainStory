import 'dart:typed_data';

Future<Uint8List> readBytesFromPath(String path) {
  throw UnsupportedError('Reading arbitrary local paths is not supported on web.');
}

Future<String> readTextFromPath(String path) {
  throw UnsupportedError('Reading arbitrary local paths is not supported on web.');
}
