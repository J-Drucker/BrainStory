import 'dart:convert';

Future<String> encodeNodeSnapshotJson(Map<String, dynamic> snapshot) async {
  return jsonEncode(snapshot);
}
