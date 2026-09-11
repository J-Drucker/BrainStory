import 'dart:convert';
import 'dart:typed_data';

import 'browser_source_files.dart';

Future<Uint8List> readBytesFromPath(String path) async {
  final Uint8List? bytes = browserSourceFiles[path];
  if (bytes == null) {
    throw FormatException(
      'Select the recording and all its companion files together using Add files. '
      'Missing: ${path.split('/').last}',
    );
  }
  return bytes;
}

Future<String> readTextFromPath(String path) async =>
    utf8.decode(await readBytesFromPath(path), allowMalformed: true);
