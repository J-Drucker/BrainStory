import 'dart:typed_data';

/// Files explicitly selected by the user, grouped to avoid filename collisions.
final Map<String, Uint8List> browserSourceFiles = <String, Uint8List>{};

String registerBrowserSourceFiles(Map<String, Uint8List> files) {
  final String root = '/selected/${DateTime.now().microsecondsSinceEpoch}';
  for (final MapEntry<String, Uint8List> file in files.entries) {
    browserSourceFiles['$root/${_normalizeBrowserPath(file.key)}'] = file.value;
  }
  return root;
}

Uint8List? findBrowserSourceFile(String path) {
  final String normalizedPath = _normalizeBrowserPath(path);
  final Uint8List? exact = browserSourceFiles[normalizedPath];
  if (exact != null) return exact;

  final String lowerPath = normalizedPath.toLowerCase();
  for (final MapEntry<String, Uint8List> entry in browserSourceFiles.entries) {
    if (_normalizeBrowserPath(entry.key).toLowerCase() == lowerPath) {
      return entry.value;
    }
  }

  final String? selectionRoot = _browserSelectionRoot(normalizedPath);
  if (selectionRoot == null) return null;
  final String requestedName = _browserBasename(normalizedPath).toLowerCase();
  final List<Uint8List> matches = <Uint8List>[];
  for (final MapEntry<String, Uint8List> entry in browserSourceFiles.entries) {
    final String candidatePath = _normalizeBrowserPath(entry.key);
    if (candidatePath.startsWith(selectionRoot) &&
        _browserBasename(candidatePath).toLowerCase() == requestedName) {
      matches.add(entry.value);
    }
  }
  if (matches.length > 1) {
    throw FormatException(
      'Multiple files named ${_browserBasename(normalizedPath)} were selected. '
      'The BrainVision header must point to the correct relative path.',
    );
  }
  return matches.isEmpty ? null : matches.single;
}

String _normalizeBrowserPath(String path) {
  final String normalized = path.trim().replaceAll('\\', '/');
  return normalized.replaceAll(RegExp('/+'), '/');
}

String? _browserSelectionRoot(String path) {
  const String prefix = '/selected/';
  if (!path.startsWith(prefix)) return null;
  final int separator = path.indexOf('/', prefix.length);
  return separator < 0 ? null : path.substring(0, separator + 1);
}

String _browserBasename(String path) {
  final int separator = path.lastIndexOf('/');
  return separator < 0 ? path : path.substring(separator + 1);
}
