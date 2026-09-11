import 'dart:convert';
import 'dart:js_interop';

@JS('brainstoryEngineAsync')
external JSPromise<JSString> _run(JSString request);

Future<dynamic> executeBrowserEngine(Map<String, dynamic> request) async {
  final JSString payload = await _run(jsonEncode(request).toJS).toDart;
  final Map<String, dynamic> response =
      jsonDecode(payload.toDart) as Map<String, dynamic>;
  if (response.containsKey('error')) {
    throw StateError(response['error'].toString());
  }
  return response['result'];
}
