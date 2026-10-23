import 'dart:convert';
import 'dart:typed_data';

import 'browser_source_files.dart';

Future<Uint8List> readBytesFromPath(String path) async {
  final Uint8List? bytes = findBrowserSourceFile(path);
  if (bytes == null) {
    throw FormatException(
      'Choose the folder containing the recording and its companion files. '
      'Missing: ${path.split('/').last}',
    );
  }
  return bytes;
}

Future<String> readTextFromPath(String path) async =>
    utf8.decode(await readBytesFromPath(path), allowMalformed: true);
