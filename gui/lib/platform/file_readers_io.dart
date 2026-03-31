import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readBytesFromPath(String path) {
  return File(path).readAsBytes();
}

Future<String> readTextFromPath(String path) {
  return File(path).readAsString();
}
