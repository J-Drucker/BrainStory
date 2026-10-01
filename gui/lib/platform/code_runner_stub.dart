const supportsCodeExecution = false;

Future<Map<String, dynamic>> executeCodeNode(
  Map<String, dynamic> params,
  Map<String, dynamic> input, {
  void Function(String)? onLog,
}) async {
  throw UnsupportedError(
    'Python code nodes require the BrainStory desktop app.',
  );
}

Future<String> checkCodeInterpreter(String interpreter) async =>
    throw UnsupportedError('Interpreter checks require the desktop app.');

Future<Map<String, String>> importCodeFolder(String path) async =>
    throw UnsupportedError('Folder imports require the desktop app.');
