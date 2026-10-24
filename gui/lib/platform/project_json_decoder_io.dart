import 'dart:convert';
import 'dart:isolate';

Future<Map<String, dynamic>> decodeBrainStoryProjectJson(String payload) {
  return Isolate.run(() => _decodeProject(payload));
}

Map<String, dynamic> _decodeProject(String payload) {
  final Map<String, dynamic> project = Map<String, dynamic>.from(
    jsonDecode(payload) as Map,
  );
  final List<dynamic> artifacts =
      project['artifacts'] as List<dynamic>? ?? const <dynamic>[];
  for (final dynamic rawEntry in artifacts) {
    if (rawEntry is! Map) continue;
    final Map<dynamic, dynamic> entry = rawEntry;
    final dynamic snapshot = entry.remove('snapshot');
    if (snapshot is Map) {
      entry['snapshotJson'] = jsonEncode(snapshot);
    }
  }
  return project;
}
