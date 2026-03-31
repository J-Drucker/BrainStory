import 'dart:io';
import 'dart:typed_data';

import 'file_save.dart';
import 'file_save_resolve.dart';

Future<SavedFileResult> saveEdfBytes({
  required Uint8List bytes,
  required String suggestedBaseName,
  required String filenameSuffix,
  required String datasetPath,
  required String outputDirectory,
}) async {
  final File outputFile = File(resolveEdfExportFilePath(
    datasetPath: datasetPath,
    outputDirectory: outputDirectory,
    filenameSuffix: filenameSuffix,
    suggestedBaseName: suggestedBaseName,
  ));
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsBytes(bytes, flush: true);
  return SavedFileResult(
    locationLabel: outputFile.path,
    persistedToDisk: true,
  );
}
