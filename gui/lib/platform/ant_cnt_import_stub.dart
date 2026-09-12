import 'dart:typed_data';

import 'ant_cnt_import.dart';

Future<AntCntImportData> readAntCnt({
  required String path,
  Uint8List? bytes,
  String? filename,
}) {
  throw UnsupportedError('ANT CNT import is only available on desktop.');
}
