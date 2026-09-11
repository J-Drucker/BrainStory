import 'dart:typed_data';

/// Files explicitly selected by the user, grouped to avoid filename collisions.
final Map<String, Uint8List> browserSourceFiles = <String, Uint8List>{};

String registerBrowserSourceFiles(Map<String, Uint8List> files) {
  final String root = '/selected/${DateTime.now().microsecondsSinceEpoch}';
  for (final MapEntry<String, Uint8List> file in files.entries) {
    browserSourceFiles['$root/${file.key}'] = file.value;
  }
  return root;
}
