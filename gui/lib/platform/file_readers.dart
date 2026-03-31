import 'dart:typed_data';

import 'file_readers_stub.dart'
    if (dart.library.io) 'file_readers_io.dart' as impl;

Future<Uint8List> readBytesFromPath(String path) => impl.readBytesFromPath(path);

Future<String> readTextFromPath(String path) => impl.readTextFromPath(path);
