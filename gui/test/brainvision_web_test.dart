import 'dart:convert';
import 'dart:typed_data';

import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/platform/browser_source_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(browserSourceFiles.clear);

  test('web BrainVision import resolves uploaded companion files', () async {
    const String header = '''
Brain Vision Data Exchange Header File Version 1.0
[Common Infos]
DataFile=C:\\original\\SAMPLE.EEG
MarkerFile=relative/path/SAMPLE.VMRK
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=2
SamplingInterval=2000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Fp1,,
Ch2=Fp2,,
''';
    const String markers = '''
Brain Vision Data Exchange Marker File, Version 1.0
[Marker Infos]
Mk1=Stimulus,S\\1 1,3,1,2
Mk10=Response,R  1,1,1,0
''';
    final ByteData values = ByteData(8 * 2);
    for (final (int index, int value) in <int>[
      100,
      1000,
      200,
      900,
      300,
      800,
      400,
      700,
    ].indexed) {
      values.setInt16(index * 2, value, Endian.little);
    }
    final Uint8List headerBytes = Uint8List.fromList(utf8.encode(header));
    final String root = registerBrowserSourceFiles(<String, Uint8List>{
      'sample.vhdr': headerBytes,
      'sample.eeg': values.buffer.asUint8List(),
      'sample.vmrk': Uint8List.fromList(utf8.encode(markers)),
    });

    final ParsedSignalData parsed = await loadDatasetSignal(
      '$root/sample.vhdr',
      fallbackSampleRate: 256,
      fileBytes: headerBytes,
      sourceDescription: '$root/sample.vhdr',
    );

    expect(parsed.channelLabels, <String>['Fp1', 'Fp2']);
    expect(parsed.sampleRate, 500);
    expect(parsed.channelSamples[0], <double>[100, 200, 300, 400]);
    expect(parsed.channelSamples[1], <double>[1000, 900, 800, 700]);
    expect(parsed.markers.map((marker) => marker.label), <String>[
      'R  1',
      'S, 1',
    ]);
    expect(parsed.markers.last.channelMask, <int>[0, 1]);
  });

  test('web BrainVision batch keeps same-named companions isolated', () async {
    const String header = '''
Brain Vision Data Exchange Header File Version 1.0
[Common Infos]
DataFile=recording.eeg
DataFormat=BINARY
DataOrientation=MULTIPLEXED
NumberOfChannels=1
SamplingInterval=1000

[Binary Infos]
BinaryFormat=INT_16

[Channel Infos]
Ch1=Cz,,
''';
    Uint8List samples(List<int> values) {
      final ByteData data = ByteData(values.length * 2);
      for (final (int index, int value) in values.indexed) {
        data.setInt16(index * 2, value, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    final Uint8List headerBytes = Uint8List.fromList(utf8.encode(header));
    final String root = registerBrowserSourceFiles(<String, Uint8List>{
      'batch/alpha/recording.vhdr': headerBytes,
      'batch/alpha/recording.eeg': samples(<int>[1, 2]),
      'batch/beta/recording.vhdr': headerBytes,
      'batch/beta/recording.eeg': samples(<int>[10, 20]),
    });

    final ParsedSignalData alpha = await loadDatasetSignal(
      '$root/batch/alpha/recording.vhdr',
      fallbackSampleRate: 256,
      fileBytes: headerBytes,
    );
    final ParsedSignalData beta = await loadDatasetSignal(
      '$root/batch/beta/recording.vhdr',
      fallbackSampleRate: 256,
      fileBytes: headerBytes,
    );

    expect(alpha.samples, <double>[1, 2]);
    expect(beta.samples, <double>[10, 20]);
    await expectLater(
      loadDatasetSignal(
        '$root/batch/missing/recording.vhdr',
        fallbackSampleRate: 256,
        fileBytes: headerBytes,
      ),
      throwsFormatException,
    );
  });
}
