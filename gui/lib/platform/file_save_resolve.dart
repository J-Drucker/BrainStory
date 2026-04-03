import 'file_names.dart';

String resolveEdfExportFilePath({
  required String datasetPath,
  required String outputDirectory,
  required String filenameSuffix,
  required String suggestedBaseName,
}) {
  return resolveGenericExportFilePath(
    datasetPath: datasetPath,
    outputDirectory: outputDirectory,
    filenameSuffix: filenameSuffix,
    suggestedBaseName: suggestedBaseName,
    fileExtension: 'edf',
  );
}

String resolveGenericExportFilePath({
  required String datasetPath,
  required String outputDirectory,
  required String filenameSuffix,
  required String suggestedBaseName,
  required String fileExtension,
}) {
  final String baseName = sanitizeFilename(
    suggestedBaseName.isEmpty ? 'brainstory_signal' : suggestedBaseName,
  );
  final String normalizedExtension =
      fileExtension.startsWith('.') ? fileExtension.substring(1) : fileExtension;

  if (outputDirectory.isNotEmpty) {
    final String normalizedOutput = outputDirectory.replaceAll(RegExp(r'[\\/]+$'), '');
    return '$normalizedOutput\\$baseName$filenameSuffix.$normalizedExtension';
  }

  if (datasetPath.isNotEmpty) {
    final String normalizedPath = datasetPath.replaceAll('/', '\\');
    final int separatorIndex = normalizedPath.lastIndexOf('\\');
    final String sourceDir =
        separatorIndex >= 0 ? normalizedPath.substring(0, separatorIndex) : '';
    final String lastSegment =
        separatorIndex >= 0 ? normalizedPath.substring(separatorIndex + 1) : normalizedPath;
    final int dotIndex = lastSegment.lastIndexOf('.');
    final String sourceName = sanitizeFilename(
      dotIndex > 0 ? lastSegment.substring(0, dotIndex) : lastSegment,
    );
    return sourceDir.isEmpty
        ? '$sourceName$filenameSuffix.$normalizedExtension'
        : '$sourceDir\\$sourceName$filenameSuffix.$normalizedExtension';
  }

  return 'exports\\$baseName$filenameSuffix.$normalizedExtension';
}
