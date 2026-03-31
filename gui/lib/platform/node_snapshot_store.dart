import 'node_snapshot_store_stub.dart'
    if (dart.library.io) 'node_snapshot_store_io.dart' as impl;

bool get supportsNodeSnapshotDiskStore => impl.supportsNodeSnapshotDiskStore;

Future<String> saveNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
  required String jsonPayload,
}) {
  return impl.saveNodeSnapshotJson(
    nodeId: nodeId,
    datasetId: datasetId,
    jsonPayload: jsonPayload,
  );
}

Future<String?> loadNodeSnapshotJson({
  required String nodeId,
  required String datasetId,
}) {
  return impl.loadNodeSnapshotJson(
    nodeId: nodeId,
    datasetId: datasetId,
  );
}

Future<bool> hasNodeSnapshotOnDisk({
  required String nodeId,
  required String datasetId,
}) {
  return impl.hasNodeSnapshotOnDisk(
    nodeId: nodeId,
    datasetId: datasetId,
  );
}

Future<void> deleteNodeSnapshotFromDisk({
  required String nodeId,
  required String datasetId,
}) {
  return impl.deleteNodeSnapshotFromDisk(
    nodeId: nodeId,
    datasetId: datasetId,
  );
}
