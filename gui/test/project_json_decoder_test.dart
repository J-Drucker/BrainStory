import 'dart:convert';

import 'package:brainstory_gui/platform/project_json_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project decoding defers embedded artifact materialization', () async {
    final Map<String, dynamic> decoded = await decodeBrainStoryProjectJson(
      jsonEncode(<String, dynamic>{
        'nodes': <dynamic>[],
        'artifacts': <dynamic>[
          <String, dynamic>{
            'nodeId': 'node-1',
            'datasetId': 'dataset-1',
            'snapshot': <String, dynamic>{
              'timeSeries': <String, dynamic>{
                'sampleRate': 500.0,
                'samples': <double>[1.0, 2.0],
              },
            },
          },
        ],
      }),
    );

    final Map<String, dynamic> artifact = Map<String, dynamic>.from(
      (decoded['artifacts'] as List<dynamic>).single as Map,
    );
    expect(artifact, isNot(contains('snapshot')));
    expect(artifact['snapshotJson'], isA<String>());
    expect(
      jsonDecode(artifact['snapshotJson'] as String),
      contains('timeSeries'),
    );
  });
}
