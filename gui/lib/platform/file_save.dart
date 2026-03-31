import 'dart:typed_data';

import 'file_save_stub.dart' if (dart.library.io) 'file_save_io.dart' if (dart.library.html) 'file_save_web.dart'
    as impl;

class SavedFileResult {
  const SavedFileResult({
    required this.locationLabel,
    required this.persistedToDisk,
  });

  final String locationLabel;
  final bool persistedToDisk;
}

Future<SavedFileResult> saveEdfBytes({
  required Uint8List bytes,
  required String suggestedBaseName,
  required String filenameSuffix,
  required String datasetPath,
  required String outputDirectory,
}) {
  return impl.saveEdfBytes(
    bytes: bytes,
    suggestedBaseName: suggestedBaseName,
    filenameSuffix: filenameSuffix,
    datasetPath: datasetPath,
    outputDirectory: outputDirectory,
  );
}
