import 'dart:async';
import 'dart:convert';
import 'dart:io';

const supportsCodeExecution = true;
const _maxBundleBytes = 20 * 1024 * 1024;

String _relativePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      normalized.contains(':') ||
      normalized
          .split('/')
          .any((part) => part.isEmpty || part == '..' || part == '.')) {
    throw FormatException('Use a relative project path without ..: $path');
  }
  return normalized;
}

Future<String> _process(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  required Duration timeout,
  void Function(String)? onLog,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  await process.stdin.close();
  final captured = StringBuffer();
  void record(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    if (captured.length < 64000) {
      final remaining = 64000 - captured.length;
      final bounded = text.length > remaining
          ? text.substring(0, remaining)
          : text;
      captured.write(bounded);
      onLog?.call(bounded);
    }
  }

  final stdout = process.stdout.listen(record);
  final stderr = process.stderr.listen(record);
  final drained = Future.wait([
    stdout.asFuture<void>(),
    stderr.asFuture<void>(),
  ]);
  try {
    final code = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException(
          'Process exceeded ${timeout.inSeconds} seconds.',
          timeout,
        );
      },
    );
    await drained.timeout(const Duration(seconds: 2));
    if (code != 0) {
      throw StateError('$executable exited with code $code.\n$captured');
    }
    return captured.toString().trim();
  } finally {
    await stdout.cancel();
    await stderr.cancel();
  }
}

Future<String> checkCodeInterpreter(String interpreter) => _process(
  interpreter.trim(),
  ['-c', 'import sys; print(sys.executable); print(sys.version)'],
  timeout: const Duration(seconds: 15),
);

Future<Map<String, String>> importCodeFolder(String path) async {
  final root = Directory(path).absolute;
  final result = <String, String>{};
  var byteCount = 0;
  const excluded = {
    '.git',
    '.venv',
    'venv',
    '__pycache__',
    'node_modules',
    '.DS_Store',
  };
  Future<void> visit(Directory directory, String prefix) async {
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      if (excluded.contains(name)) continue;
      final relative = '$prefix$name';
      if (entity is Directory) {
        await visit(entity, '$relative/');
      } else if (entity is File) {
        final length = await entity.length();
        byteCount += length;
        if (byteCount > _maxBundleBytes || result.length >= 2000) {
          throw const FormatException(
            'Embedded projects are limited to 20 MB and 2,000 files. Link a local folder for larger projects.',
          );
        }
        result[_relativePath(relative)] = base64Encode(
          await entity.readAsBytes(),
        );
      }
    }
  }

  await visit(root, '');
  return result;
}

Future<Map<String, dynamic>> executeCodeNode(
  Map<String, dynamic> params,
  Map<String, dynamic> input, {
  void Function(String)? onLog,
}) async {
  final interpreter = (params['interpreter'] as String? ?? 'python3').trim();
  if (interpreter.isEmpty) {
    throw const FormatException('Choose a Python interpreter.');
  }
  final seconds = (params['timeoutSeconds'] as num?)?.toInt() ?? 300;
  if (seconds < 1 || seconds > 86400) {
    throw const FormatException('Timeout must be between 1 and 86400 seconds.');
  }
  final timeout = Duration(seconds: seconds);
  final temporary = await Directory.systemTemp.createTemp('brainstory-code-');
  try {
    final mode = params['sourceMode'] ?? 'embedded';
    late Directory project;
    String entry = _relativePath(params['entryPoint'] as String? ?? 'main.py');
    String? revision;
    if (mode == 'local') {
      project = Directory(params['sourcePath'] as String? ?? '').absolute;
      if ((params['sourcePath'] as String? ?? '').trim().isEmpty ||
          !await project.exists()) {
        throw const FormatException('Choose an existing local project folder.');
      }
    } else {
      project = Directory('${temporary.path}/project');
      if (mode == 'git') {
        final url = (params['repository'] as String? ?? '').trim();
        if (!(url.startsWith('https://') ||
            url.startsWith('ssh://') ||
            url.startsWith('git@') ||
            (url.isNotEmpty &&
                !url.startsWith('-') &&
                await Directory(url).exists()))) {
          throw const FormatException(
            'Use an HTTPS or SSH Git repository URL.',
          );
        }
        onLog?.call('Cloning repository…\n');
        await _process(
          'git',
          ['clone', '--no-checkout', '--', url, project.path],
          timeout: timeout,
          environment: {'GIT_TERMINAL_PROMPT': '0'},
          onLog: onLog,
        );
        final ref = (params['gitRef'] as String? ?? '').trim();
        if (ref.startsWith('-')) {
          throw const FormatException('Git revision cannot start with a dash.');
        }
        Future<String> resolve(String value) => _process(
          'git',
          ['rev-parse', '--verify', '--end-of-options', '$value^{commit}'],
          workingDirectory: project.path,
          timeout: timeout,
        );
        try {
          revision = await resolve(ref.isEmpty ? 'HEAD' : ref);
        } on StateError {
          if (ref.isEmpty) rethrow;
          revision = await resolve('refs/remotes/origin/$ref');
        }
        revision = revision.trim();
        await _process(
          'git',
          ['checkout', '--detach', revision],
          workingDirectory: project.path,
          timeout: timeout,
          onLog: onLog,
        );
        onLog?.call('Revision: $revision\n');
      } else if (mode == 'embedded') {
        await project.create();
        final files = params['files'] as Map? ?? {};
        var total = 0;
        if (files.length > 2000) {
          throw const FormatException('Too many embedded files.');
        }
        for (final item in files.entries) {
          if ((item.value as String).length > _maxBundleBytes * 4 ~/ 3 + 4) {
            throw const FormatException('Embedded file exceeds 20 MB.');
          }
          final bytes = base64Decode(item.value as String);
          total += bytes.length;
          if (total > _maxBundleBytes) {
            throw const FormatException('Embedded project exceeds 20 MB.');
          }
          final file = File(
            '${project.path}/${_relativePath(item.key as String)}',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
        }
        if (params['code'] is String && (params['code'] as String).isNotEmpty) {
          final file = File('${project.path}/$entry');
          await file.parent.create(recursive: true);
          await file.writeAsString(params['code'] as String);
        }
      } else {
        throw FormatException('Unknown code source: $mode');
      }
    }
    final script = File('${project.path}/$entry');
    if (!await script.exists()) {
      throw FormatException('Entry point does not exist: $entry');
    }
    final canonicalRoot = await project.resolveSymbolicLinks();
    final canonicalScript = await script.resolveSymbolicLinks();
    if (!canonicalScript.startsWith(
      '$canonicalRoot${Platform.pathSeparator}',
    )) {
      throw const FormatException(
        'Entry point must be inside the project folder.',
      );
    }
    final inputFile = File('${temporary.path}/input.json');
    final outputFile = File('${temporary.path}/output.json');
    await inputFile.writeAsString(jsonEncode(input));
    onLog?.call('Interpreter: $interpreter\nEntry point: $entry\n');
    await _process(
      interpreter,
      ['-u', canonicalScript, inputFile.path, outputFile.path],
      workingDirectory: canonicalRoot,
      timeout: timeout,
      environment: {
        'BRAINSTORY_INPUT': inputFile.path,
        'BRAINSTORY_OUTPUT': outputFile.path,
        'PYTHONIOENCODING': 'utf-8',
      },
      onLog: onLog,
    );
    if (!await outputFile.exists()) {
      throw const FormatException(
        'Code exited without writing output.json. See the artifact contract.',
      );
    }
    if (await outputFile.length() > 512 * 1024 * 1024) {
      throw const FormatException('output.json exceeds the 512 MB limit.');
    }
    final decoded = jsonDecode(await outputFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('output.json must be a JSON object.');
    }
    return {'output': decoded, if (revision != null) 'revision': revision};
  } finally {
    await temporary.delete(recursive: true);
  }
}
