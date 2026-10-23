import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

Future<Map<String, Uint8List>?> pickBrowserSourceFolder() {
  final Completer<Map<String, Uint8List>?> completer =
      Completer<Map<String, Uint8List>?>();
  final HTMLInputElement input =
      document.createElement('input') as HTMLInputElement
        ..type = 'file'
        ..multiple = true
        ..setAttribute('webkitdirectory', '')
        ..setAttribute('directory', '');
  document.body?.appendChild(input);

  void removeInput() {
    if (input.parentNode != null) input.remove();
  }

  input.onChange.first.then((_) async {
    try {
      final Map<String, Uint8List> selected = <String, Uint8List>{};
      final FileList? files = input.files;
      for (int index = 0; files != null && index < files.length; index++) {
        final File file = files.item(index)!;
        if (!_isSupportedSourceFile(file.name)) continue;
        final String relativePath = file.webkitRelativePath.trim();
        selected[relativePath.isEmpty ? file.name : relativePath] =
            await _readBrowserFile(file);
      }
      removeInput();
      if (!completer.isCompleted) completer.complete(selected);
    } catch (error, stackTrace) {
      removeInput();
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  });
  input.addEventListener(
    'cancel',
    ((Event event) {
      removeInput();
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );
  input.onError.first.then((Event event) {
    removeInput();
    if (!completer.isCompleted) {
      completer.completeError(StateError('Folder selection failed.'));
    }
  });

  input.click();
  return completer.future;
}

bool _isSupportedSourceFile(String name) {
  final String lower = name.toLowerCase();
  return const <String>[
    '.csv',
    '.tsv',
    '.txt',
    '.edf',
    '.cnt',
    '.set',
    '.fdt',
    '.vhdr',
    '.eeg',
    '.vmrk',
  ].any(lower.endsWith);
}

Future<Uint8List> _readBrowserFile(File file) async {
  final FileReader reader = FileReader()..readAsArrayBuffer(file);
  await reader.onLoadEnd.first;
  final Uint8List? result = (reader.result as JSArrayBuffer?)?.toDart
      .asUint8List();
  if (result != null) return result;
  throw FormatException('Could not read ${file.name}.');
}
