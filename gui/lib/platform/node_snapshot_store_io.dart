import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

const bool supportsNodeSnapshotDiskStore = true;

Future<String> saveNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
  required String jsonPayload,
}) async {
  final File file = _compressedSnapshotFile(
    nodeId: nodeId,
    datasetId: datasetId,
  );
  await file.parent.create(recursive: true);
  final List<int> compressed = await Isolate.run(
    () => gzip.encode(utf8.encode(jsonPayload)),
  );
  await file.writeAsBytes(compressed, flush: true);
  final File legacy = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  if (await legacy.exists()) {
    await legacy.delete();
  }
  return file.path;
}

Future<String?> loadNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
}) async {
  final File compressed = _compressedSnapshotFile(
    nodeId: nodeId,
    datasetId: datasetId,
  );
  if (await compressed.exists()) {
    final List<int> bytes = await compressed.readAsBytes();
    return Isolate.run(() => utf8.decode(gzip.decode(bytes)));
  }
  final File legacy = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  return await legacy.exists() ? legacy.readAsString() : null;
}

void saveNodeSnapshotMetadataJsonSync({
  required String nodeId,
  required String datasetId,
  required String jsonPayload,
}) {
  final File file = _snapshotMetadataFile(nodeId: nodeId, datasetId: datasetId);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonPayload, flush: true);
}

Future<String?> loadNodeSnapshotMetadataJson({
  required String nodeId,
  required String datasetId,
}) async {
  final File file = _snapshotMetadataFile(nodeId: nodeId, datasetId: datasetId);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsString();
}

Future<bool> hasNodeSnapshotOnDisk({
  required String nodeId,
  required String datasetId,
}) async {
  return await _compressedSnapshotFile(
        nodeId: nodeId,
        datasetId: datasetId,
      ).exists() ||
      await _snapshotFile(nodeId: nodeId, datasetId: datasetId).exists();
}

Future<void> deleteNodeSnapshotFromDisk({
  required String nodeId,
  required String datasetId,
}) async {
  final File file = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  if (await file.exists()) {
    await file.delete();
  }
  final File compressedFile = _compressedSnapshotFile(
    nodeId: nodeId,
    datasetId: datasetId,
  );
  if (await compressedFile.exists()) {
    await compressedFile.delete();
  }
  final File metadataFile = _snapshotMetadataFile(
    nodeId: nodeId,
    datasetId: datasetId,
  );
  if (await metadataFile.exists()) {
    await metadataFile.delete();
  }
}

File _snapshotFile({required String nodeId, required String datasetId}) {
  final Directory root = _cacheRoot();
  final Directory nodeDir = Directory(
    _joinPath(<String>[root.path, 'nodes', nodeId]),
  );
  return File(_joinPath(<String>[nodeDir.path, '$datasetId.json']));
}

File _compressedSnapshotFile({
  required String nodeId,
  required String datasetId,
}) {
  return File('${_snapshotFile(nodeId: nodeId, datasetId: datasetId).path}.gz');
}

File _snapshotMetadataFile({
  required String nodeId,
  required String datasetId,
}) {
  final File snapshot = _snapshotFile(nodeId: nodeId, datasetId: datasetId);
  return File('${snapshot.path}.metadata');
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
