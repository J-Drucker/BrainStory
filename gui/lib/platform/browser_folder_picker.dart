import 'dart:typed_data';

import 'browser_folder_picker_stub.dart'
    if (dart.library.html) 'browser_folder_picker_web.dart'
    as impl;

Future<Map<String, Uint8List>?> pickBrowserSourceFolder() =>
    impl.pickBrowserSourceFolder();
