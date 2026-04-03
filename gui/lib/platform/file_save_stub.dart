import 'dart:typed_data';

import 'file_save.dart';

Future<SavedFileResult> saveEdfBytes({
  required Uint8List bytes,
  required String suggestedBaseName,
  required String filenameSuffix,
  required String datasetPath,
  required String outputDirectory,
}) {
  throw UnsupportedError('EDF export is not supported on this platform.');
}

Future<SavedFileResult> saveTextFile({
  required String text,
  required String suggestedBaseName,
  required String filenameSuffix,
  required String fileExtension,
  required String datasetPath,
  required String outputDirectory,
}) {
  throw UnsupportedError('Text export is not supported on this platform.');
}
