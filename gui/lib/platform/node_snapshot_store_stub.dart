const bool supportsNodeSnapshotDiskStore = false;

Future<String> saveNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
  required String jsonPayload,
}) {
  throw UnsupportedError('Node snapshot disk storage is not available on this platform.');
}

Future<String?> loadNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
}) async {
  return null;
}

Future<bool> hasNodeSnapshotOnDisk({
  required String nodeId,
  required String datasetId,
}) async {
  return false;
}

Future<void> deleteNodeSnapshotFromDisk({
  required String nodeId,
  required String datasetId,
}) async {}
