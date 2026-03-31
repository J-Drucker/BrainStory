import 'file_names.dart';

String resolveEdfExportFilePath({
  required String datasetPath,
  required String outputDirectory,
  required String filenameSuffix,
  required String suggestedBaseName,
}) {
  final String baseName = sanitizeFilename(
    suggestedBaseName.isEmpty ? 'brainstory_signal' : suggestedBaseName,
  );

  if (outputDirectory.isNotEmpty) {
    final String normalizedOutput = outputDirectory.replaceAll(RegExp(r'[\\/]+$'), '');
    return '$normalizedOutput\\$baseName$filenameSuffix.edf';
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
        ? '$sourceName$filenameSuffix.edf'
        : '$sourceDir\\$sourceName$filenameSuffix.edf';
  }

  return 'exports\\$baseName$filenameSuffix.edf';
}
