import 'dart:io';

const bool supportsNodeSnapshotDiskStore = true;

Future<String> saveNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
  required String jsonPayload,
}) async {
  final File file = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonPayload, flush: true);
  return file.path;
}

Future<String?> loadNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
}) async {
  final File file = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsString();
}

Future<bool> hasNodeSnapshotOnDisk({
  required String nodeId,
  required String datasetId,
}) async {
  return _snapshotFile(nodeId: nodeId, datasetId: datasetId).exists();
}

Future<void> deleteNodeSnapshotFromDisk({
  required String nodeId,
  required String datasetId,
}) async {
  final File file = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  if (await file.exists()) {
    await file.delete();
  }
}

File _snapshotFile({required String nodeId, required String datasetId}) {
  final Directory root = _cacheRoot();
  final Directory nodeDir = Directory(
    _joinPath(<String>[root.path, 'nodes', nodeId]),
  );
  return File(_joinPath(<String>[nodeDir.path, '$datasetId.json']));
}

Directory _cacheRoot() {
  final String? home = Platform.environment['HOME'];
  if (Platform.isMacOS && home != null && home.trim().isNotEmpty) {
    return Directory(
      _joinPath(<String>[
        home,
        'Library',
        'Application Support',
        'BrainStory',
        'cache',
      ]),
    );
  }

  final String appData =
      Platform.environment['LOCALAPPDATA'] ??
      Platform.environment['APPDATA'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (Platform.isWindows && appData.trim().isNotEmpty) {
    return Directory(_joinPath(<String>[appData, 'BrainStory', 'cache']));
  }

  return Directory(
    _joinPath(<String>[Directory.systemTemp.path, 'BrainStory', 'cache']),
  );
}

String _joinPath(List<String> parts) {
  return parts
      .where((String part) => part.trim().isNotEmpty)
      .join(Platform.pathSeparator);
}
