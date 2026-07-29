import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'ant_cnt_import.dart';
import 'brainstory_engine.dart';

Future<AntCntImportData> readAntCntFromPath(String path) async {
  final String? nativePayload = await Isolate.run<String?>(
    () => readAntCntPayloadNative(path),
  );
  if (nativePayload != null) {
    final Map<String, dynamic> envelope = decodeAntCntPayload(nativePayload);
    if (envelope['ok'] != true) {
      throw FormatException(
        envelope['error']?.toString() ?? 'Native ANT CNT import failed.',
      );
    }
    final Map<String, dynamic> payload = Map<String, dynamic>.from(
      envelope['payload'] as Map? ?? const <String, dynamic>{},
    );
    final String samplesPath = payload['samplesFile']?.toString() ?? '';
    if (samplesPath.isEmpty) {
      throw const FormatException(
        'Native ANT CNT importer did not return sample data.',
      );
    }
    final Uint8List sampleBytes = await File(samplesPath).readAsBytes();
    final AntCntImportData parsed = parseAntCntPayload(payload, sampleBytes);
    await _deleteImporterTempDir(payload);
    return parsed;
  }

  throw FormatException(
    'ANT CNT import could not load BrainStory\'s bundled native engine. '
    'Rebuild the macOS app so libbrainstory_engine.dylib is included.',
  );
}

Future<void> _deleteImporterTempDir(Map<String, dynamic> payload) async {
  final String tempDirPath = payload['tempDir']?.toString() ?? '';
  if (tempDirPath.isEmpty) {
    return;
  }
  final Directory tempDir = Directory(tempDirPath);
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }
}
