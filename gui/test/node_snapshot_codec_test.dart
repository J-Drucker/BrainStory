import 'dart:convert';
import 'dart:io';

import 'package:brainstory_gui/platform/node_snapshot_codec.dart';
import 'package:brainstory_gui/platform/node_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'large time-series snapshots encode in a compatible JSON shape',
    () async {
      final List<List<double>> channels = <List<double>>[
        List<double>.generate(10000, (int index) => index * 0.25),
        List<double>.generate(10000, (int index) => -index * 0.5),
      ];
      final Map<String, dynamic> snapshot = <String, dynamic>{
        'datasetLabel': 'large ICA',
        'timeSeries': <String, dynamic>{
          'samples': const <double>[],
          'channelSamples': channels,
          'sampleRate': 256.0,
          'channelLabels': <String>['IC 1', 'IC 2'],
          'markers': const <dynamic>[],
          'factors': const <dynamic>[],
          'source': 'ICA',
        },
      };

      final String encoded = await encodeNodeSnapshotJson(snapshot);
      final Map<String, dynamic> decoded = Map<String, dynamic>.from(
        jsonDecode(encoded) as Map,
      );
      final Map<String, dynamic> timeSeries = Map<String, dynamic>.from(
        decoded['timeSeries'] as Map,
      );
      final List<dynamic> restored =
          timeSeries['channelSamples'] as List<dynamic>;

      expect(restored, hasLength(2));
      expect((restored[0] as List<dynamic>)[9999], 2499.75);
      expect((restored[1] as List<dynamic>)[9999], -4999.5);
      expect(timeSeries['sampleRate'], 256.0);
      expect(
        (snapshot['timeSeries'] as Map<String, dynamic>)['channelSamples'],
        same(channels),
      );
    },
  );

  test(
    'disk snapshots are compressed and round trip through the store',
    () async {
      final String nonce = DateTime.now().microsecondsSinceEpoch.toString();
      final String nodeId = 'snapshot-codec-test-$nonce';
      const String datasetId = 'dataset';
      final String payload = jsonEncode(<String, dynamic>{
        'values': List<double>.filled(20000, 12.5),
      });
      String? path;
      try {
        path = await saveNodeSnapshotJson(
          nodeId: nodeId,
          datasetId: datasetId,
          jsonPayload: payload,
        );
        expect(path, endsWith('.json.gz'));
        expect(
          await File(path).length(),
          lessThan(utf8.encode(payload).length),
        );
        expect(
          await loadNodeSnapshotJson(nodeId: nodeId, datasetId: datasetId),
          payload,
        );
      } finally {
        await deleteNodeSnapshotFromDisk(nodeId: nodeId, datasetId: datasetId);
      }
    },
  );
}
