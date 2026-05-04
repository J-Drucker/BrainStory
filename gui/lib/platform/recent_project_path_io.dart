import 'dart:io';

Future<String?> readRecentBrainStoryPath() async {
  try {
    final File file = _recentProjectFile();
    if (!await file.exists()) {
      return null;
    }
    final String path = (await file.readAsString()).trim();
    return path.isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}

Future<void> writeRecentBrainStoryPath(String? path) async {
  try {
    final File file = _recentProjectFile();
    if (path == null || path.trim().isEmpty) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(path.trim(), flush: true);
  } catch (_) {
    // Best-effort convenience only.
  }
}

File _recentProjectFile() {
  final String appData =
      Platform.environment['APPDATA'] ??
      Platform.environment['LOCALAPPDATA'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  return File('$appData\\BrainStory\\recent_project.txt');
}
