import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:brainstory_gui/platform/browser_source_files.dart';
import 'package:brainstory_gui/platform/file_readers_web.dart';

void main() {
  tearDown(browserSourceFiles.clear);

  test('browser companion files are read from their selected group', () async {
    final String root = registerBrowserSourceFiles(<String, Uint8List>{
      'recording.eeg': Uint8List.fromList(<int>[1, 2, 3]),
      'recording.vmrk': Uint8List.fromList('markers'.codeUnits),
    });
    expect(await readBytesFromPath('$root/recording.eeg'), <int>[1, 2, 3]);
    expect(await readTextFromPath('$root/recording.vmrk'), 'markers');
    await expectLater(readBytesFromPath('$root/missing.eeg'), throwsFormatException);
  });
}
