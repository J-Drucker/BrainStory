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

Future<int?> nodeSnapshotDiskBytes({
  required String nodeId,
  required String datasetId,
}) async {
  final File file = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  if (!await file.exists()) {
    return null;
  }
  return file.length();
}

File _snapshotFile({
  required String nodeId,
  required String datasetId,
}) {
  final Directory root =
      Directory('${Directory.current.path}${Platform.pathSeparator}.brainstory_cache');
  final Directory nodeDir =
      Directory('${root.path}${Platform.pathSeparator}nodes${Platform.pathSeparator}$nodeId');
  return File('${nodeDir.path}${Platform.pathSeparator}$datasetId.json');
}
