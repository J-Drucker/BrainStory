import 'project_file_save_stub.dart'
    if (dart.library.io) 'project_file_save_io.dart'
    if (dart.library.html) 'project_file_save_web.dart' as impl;

Future<String?> saveBrainStoryProject({
  required String suggestedName,
  required String jsonPayload,
  String? targetPath,
}) {
  return impl.saveBrainStoryProject(
    suggestedName: suggestedName,
    jsonPayload: jsonPayload,
    targetPath: targetPath,
  );
}
