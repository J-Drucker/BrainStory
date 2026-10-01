import '../model/data_artifacts.dart';
import '../model/dataset.dart';
import '../model/dataset_artifact_snapshot.dart';

const codeArtifactNames = <String>{
  'timeSeries',
  'segmentedTimeSeries',
  'spectrum',
  'fooofResult',
  'featureTable',
  'gaussianMixture',
  'bridgeDetection',
  'timeFrequency',
  'matrixTransformation',
};

const codeNodeExample = '''import json
import sys
from pathlib import Path

request = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
artifacts = request["artifacts"]
parameters = request["parameters"]

# Example: multiply each signal sample by a configurable gain.
signal = artifacts.get("timeSeries")
if signal is not None:
    gain = float(parameters.get("gain", 1.0))
    signal["samples"] = [x * gain for x in signal.get("samples", [])]
    signal["channelSamples"] = [
        [x * gain for x in channel]
        for channel in signal.get("channelSamples", [])
    ]

# Return every artifact you want downstream nodes to receive.
response = {"protocolVersion": 1, "artifacts": artifacts}
Path(sys.argv[2]).write_text(json.dumps(response, allow_nan=False), encoding="utf-8")
print("Finished", request["dataset"]["label"])
''';

Map<String, dynamic> codeNodeInput(
  Dataset dataset,
  Map<String, dynamic> parameters,
) {
  final snapshot = DatasetArtifactSnapshot.fromDataset(
    dataset,
    copyTimeSeries: false,
  ).toJson();
  return <String, dynamic>{
    'protocolVersion': 1,
    'dataset': {'id': dataset.id, 'label': dataset.label},
    'parameters': parameters,
    'artifacts': {
      for (final name in codeArtifactNames)
        if (snapshot.containsKey(name)) name: snapshot[name],
    },
  };
}

/// Parse everything before changing the live dataset. A failed run is atomic.
DatasetArtifactSnapshot parseCodeNodeOutput(dynamic response) {
  if (response is! Map<String, dynamic> ||
      response['protocolVersion'] != 1 ||
      response['artifacts'] is! Map<String, dynamic>) {
    throw const FormatException(
      'output.json must contain protocolVersion: 1 and an artifacts object.',
    );
  }
  final artifacts = response['artifacts'] as Map<String, dynamic>;
  if (artifacts.isEmpty) {
    throw const FormatException('Return at least one artifact.');
  }
  for (final entry in artifacts.entries) {
    if (!codeArtifactNames.contains(entry.key) ||
        entry.value is! Map<String, dynamic>) {
      throw FormatException(
        'Unsupported artifact or invalid object: ${entry.key}',
      );
    }
  }
  void checkFinite(dynamic value) {
    if (value is num && !value.isFinite) {
      throw const FormatException(
        'Artifact numbers must be finite (no NaN or Infinity).',
      );
    }
    if (value is Map) value.values.forEach(checkFinite);
    if (value is List) value.forEach(checkFinite);
  }

  checkFinite(artifacts);
  final signal = artifacts['timeSeries'];
  if (signal != null) {
    if (signal['sampleRate'] is! num || (signal['sampleRate'] as num) <= 0) {
      throw const FormatException('timeSeries.sampleRate must be positive.');
    }
    final channels = signal['channelSamples'];
    final samples = signal['samples'];
    if (channels is! List ||
        samples is! List ||
        signal['channelLabels'] is! List) {
      throw const FormatException(
        'timeSeries requires samples, channelSamples and channelLabels arrays.',
      );
    }
    if (channels.isNotEmpty) {
      if (samples.isNotEmpty) {
        throw const FormatException(
          'Use either samples or channelSamples; leave the other empty.',
        );
      }
      if (channels.any(
            (dynamic row) =>
                row is! List || row.length != (channels.first as List).length,
          ) ||
          (signal['channelLabels'] as List).length != channels.length) {
        throw const FormatException(
          'Signal channels must have equal lengths and one label per channel.',
        );
      }
    }
  }
  final spectrum = artifacts['spectrum'];
  if (spectrum != null &&
      (spectrum['frequencies'] is! List ||
          spectrum['power'] is! List ||
          (spectrum['frequencies'] as List).length !=
              (spectrum['power'] as List).length)) {
    throw const FormatException(
      'Spectrum frequencies and power must be equal-length arrays.',
    );
  }
  final table = artifacts['featureTable'];
  if (table != null &&
      (table['columns'] is! List ||
          table['rows'] is! List ||
          (table['rows'] as List).any(
            (dynamic row) =>
                row is! Map ||
                row.keys.any(
                  (key) => !(table['columns'] as List).contains(key),
                ),
          ))) {
    throw const FormatException(
      'Feature table rows must be objects keyed by column name.',
    );
  }
  const requiredArrays = <String, List<String>>{
    'segmentedTimeSeries': ['segments', 'channelLabels'],
    'fooofResult': ['peaks'],
    'gaussianMixture': [
      'featureColumns',
      'assignments',
      'probabilities',
      'weights',
      'means',
      'variances',
    ],
    'bridgeDetection': ['channelLabels', 'frames'],
    'timeFrequency': ['times', 'frequencies', 'powerMatrix'],
    'matrixTransformation': ['matrix'],
  };
  for (final entry in requiredArrays.entries) {
    final artifact = artifacts[entry.key];
    if (artifact == null) continue;
    for (final key in entry.value) {
      if (artifact[key] is! List) {
        throw FormatException('${entry.key}.$key must be an array.');
      }
    }
  }
  for (final name in ['segmentedTimeSeries', 'bridgeDetection']) {
    final artifact = artifacts[name];
    if (artifact != null &&
        (artifact['sampleRate'] is! num ||
            (artifact['sampleRate'] as num) <= 0)) {
      throw FormatException('$name.sampleRate must be positive.');
    }
  }
  final fooof = artifacts['fooofResult'];
  if (fooof != null &&
      (fooof['intercept'] is! num || fooof['exponent'] is! num)) {
    throw const FormatException(
      'fooofResult requires numeric intercept and exponent.',
    );
  }
  try {
    return DatasetArtifactSnapshot.fromJson(artifacts);
  } catch (error) {
    throw FormatException('Invalid artifact payload: $error');
  }
}

Set<BrainStoryArtifactKind> codeSnapshotKinds(
  DatasetArtifactSnapshot snapshot,
) {
  final json = snapshot.toJson();
  return {
    for (final name in codeArtifactNames)
      if (json.containsKey(name)) artifactKindFromWireValue(name),
    if (snapshot.timeSeries != null) BrainStoryArtifactKind.markers,
  };
}
