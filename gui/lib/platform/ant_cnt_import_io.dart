import 'dart:io';
import 'dart:typed_data';

import 'ant_cnt_import.dart';

Future<AntCntImportData> readAntCntFromPath(String path) async {
  final File script = _findImporterScript();
  final List<_PythonInvocation> invocations = _pythonInvocations();
  Object? lastError;

  for (final _PythonInvocation invocation in invocations) {
    try {
      final ProcessResult result = await Process.run(
        invocation.executable,
        <String>[...invocation.leadingArgs, script.path, path],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) {
        final Map<String, dynamic> payload =
            decodeAntCntPayload(result.stdout.toString());
        final String samplesPath = payload['samplesFile']?.toString() ?? '';
        if (samplesPath.isEmpty) {
          throw const FormatException('ANT CNT importer did not return samplesFile.');
        }
        final Uint8List sampleBytes = await File(samplesPath).readAsBytes();
        final AntCntImportData parsed = parseAntCntPayload(payload, sampleBytes);
        await _deleteImporterTempDir(payload);
        return parsed;
      }
      lastError = result.stderr.toString().trim().isEmpty
          ? result.stdout.toString().trim()
          : result.stderr.toString().trim();
    } catch (error) {
      lastError = error;
    }
  }

  throw FormatException(
    'ANT CNT import requires Python with MNE >= 1.9 and antio/libeep. '
    'Last importer error: ${lastError ?? 'no Python executable was found'}.',
  );
}

Future<void> _deleteImporterTempDir(Map<String, dynamic> payload) async {
  final String tempDirPath = payload['tempDir']?.toString() ?? '';
  if (tempDirPath.isEmpty) {
    return;
  }
  final Directory tempDir = Directory(tempDirPath);
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }
}

List<_PythonInvocation> _pythonInvocations() {
  final String? configuredPython = Platform.environment['BRAINSTORY_PYTHON'];
  return <_PythonInvocation>[
    if (configuredPython != null && configuredPython.trim().isNotEmpty)
      _PythonInvocation(configuredPython.trim()),
    const _PythonInvocation('python'),
    if (Platform.isWindows) const _PythonInvocation('py', leadingArgs: <String>['-3']),
    const _PythonInvocation('python3'),
  ];
}

File _findImporterScript() {
  Directory current = Directory.current.absolute;
  for (int depth = 0; depth < 8; depth++) {
    final File candidate = File('${current.path}${Platform.pathSeparator}'
        'scripts${Platform.pathSeparator}import_ant_cnt.py');
    if (candidate.existsSync()) {
      return candidate;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
  throw const FormatException(
    'Could not find scripts/import_ant_cnt.py for ANT CNT import.',
  );
}

class _PythonInvocation {
  const _PythonInvocation(
    this.executable, {
    this.leadingArgs = const <String>[],
  });

  final String executable;
  final List<String> leadingArgs;
}
