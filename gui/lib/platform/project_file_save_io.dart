import 'dart:io';

Future<String?> saveBrainStoryProject({
  required String suggestedName,
  required String jsonPayload,
  String? targetPath,
}) async {
  if (targetPath == null || targetPath.trim().isEmpty) {
    return null;
  }

  final File file = File(targetPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonPayload, flush: true);
  return file.path;
}
