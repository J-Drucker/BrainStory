import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'ant_cnt_import.dart';

@JS('brainstoryImportCnt')
external JSPromise<JSString> _importCnt(JSUint8Array bytes, JSString filename);

Future<AntCntImportData> readAntCnt({
  required String path,
  Uint8List? bytes,
  String? filename,
}) async {
  if (bytes == null || bytes.isEmpty) {
    throw const FormatException(
      'ANT CNT import requires the selected file bytes in the browser.',
    );
  }
  final String response = (await _importCnt(
    bytes.toJS,
    (filename ?? path.split('/').last).toJS,
  ).toDart).toDart;
  final Map<String, dynamic> envelope = decodeAntCntPayload(response);
  if (envelope['ok'] != true) {
    throw FormatException(
      envelope['error']?.toString() ?? 'Browser ANT CNT import failed.',
    );
  }
  final Map<String, dynamic> payload = Map<String, dynamic>.from(
    envelope['payload'] as Map? ?? const <String, dynamic>{},
  );
  final String encodedSamples = payload['samplesBase64']?.toString() ?? '';
  if (encodedSamples.isEmpty) {
    throw const FormatException(
      'Browser ANT CNT importer did not return sample data.',
    );
  }
  return parseAntCntPayload(payload, base64Decode(encodedSamples));
}
