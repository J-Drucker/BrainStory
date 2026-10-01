import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/dataset.dart';
import '../platform/code_runner.dart';
import 'code_contract.dart';
import 'node_type.dart';

class CodeNodeType extends NodeType {
  @override
  String get title => 'Python Code';
  @override
  NodeCategory get category => NodeCategory.transform;
  @override
  String get subcategory => 'Custom Code';
  @override
  String get helpText => codeContractHelp;
  @override
  Map<String, dynamic> get defaultParams => {
    'sourceMode': 'embedded',
    'code': codeNodeExample,
    'files': <String, String>{},
    'entryPoint': 'main.py',
    'sourcePath': '',
    'repository': '',
    'gitRef': '',
    'interpreter': 'python3',
    'timeoutSeconds': 300,
    'parametersJson': '{"gain": 1.0}',
  };
  @override
  List<PortSpec> get inputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'artifacts', type: PortType.metadata),
    PortSpec(name: 'markers', type: PortType.markers),
    PortSpec(name: 'matrix', type: PortType.matrixTransformation),
  ];
  @override
  List<PortSpec> get outputs => const [
    PortSpec(name: 'signal', type: PortType.signal),
    PortSpec(name: 'spectrum', type: PortType.signal),
    PortSpec(name: 'artifacts', type: PortType.metadata),
    PortSpec(name: 'markers', type: PortType.markers),
    PortSpec(name: 'matrix', type: PortType.matrixTransformation),
  ];
  @override
  bool invalidatedByMarkerChanges(Map<String, dynamic> params) => true;
  @override
  Widget buildBody(
    Map<String, dynamic> params, {
    required Map<String, Dataset> datasets,
    required void Function(void Function()) setState,
  }) => _CodeEditor(params: params);

  @override
  Future<void> run(Dataset dataset, Map<String, dynamic> params) =>
      _run(dataset, params, null);
  @override
  Future<void> runChunked(
    Dataset dataset,
    Map<String, dynamic> params,
    NodeExecutionContext context,
  ) => _run(dataset, params, context);

  Future<void> _run(
    Dataset dataset,
    Map<String, dynamic> params,
    NodeExecutionContext? context,
  ) async {
    final log = StringBuffer();
    final started = DateTime.now();
    final report = <String, dynamic>{
      'dataset': dataset.label,
      'startedAt': started.toIso8601String(),
      'status': 'running',
    };
    // Diagnostics are not execution parameters and do not invalidate cached output.
    final reports = Map<String, dynamic>.from(
      params['_codeRuns'] as Map? ?? {},
    );
    reports.remove(dataset.id);
    reports[dataset.id] = report;
    while (reports.length > 20) {
      reports.remove(reports.keys.first);
    }
    params['_codeRuns'] = reports;
    try {
      final parameters = jsonDecode(
        params['parametersJson'] as String? ?? '{}',
      );
      if (parameters is! Map<String, dynamic>) {
        throw const FormatException('Parameters must be a JSON object.');
      }
      await context?.setProgress('Running Python on ${dataset.label}…');
      final result = await executeCodeNode(
        params,
        codeNodeInput(dataset, parameters),
        onLog: (text) {
          if (log.length < 64000) log.write(text);
        },
      );
      final snapshot = parseCodeNodeOutput(result['output']);
      snapshot.applyToDataset(dataset);
      report['status'] = 'succeeded';
      if (result['revision'] != null) report['revision'] = result['revision'];
    } catch (error) {
      report['status'] = 'failed';
      report['error'] = error.toString();
      rethrow;
    } finally {
      report['log'] = log.toString();
      report['durationMs'] = DateTime.now().difference(started).inMilliseconds;
    }
  }
}

const codeContractHelp =
    '''Python runs once per dataset using your selected interpreter and project folder as the working directory.

Command: <interpreter> -u <entry.py> <input.json> <output.json>
The same absolute paths are available as BRAINSTORY_INPUT and BRAINSTORY_OUTPUT.

INPUT: {"protocolVersion":1,"dataset":{"id":"…","label":"…"},"parameters":{},"artifacts":{…}}
OUTPUT: {"protocolVersion":1,"artifacts":{…}}

The output artifacts object is the complete downstream result. Copy input artifacts to preserve them; omit an artifact to remove it. Supported keys: timeSeries, segmentedTimeSeries, spectrum, fooofResult, featureTable, gaussianMixture, bridgeDetection, timeFrequency, matrixTransformation. Markers and channel metadata live inside timeSeries.

timeSeries: samples (legacy single channel), channelSamples (channel-major arrays), sampleRate (Hz), channelLabels, channelCoordinates, markers, factors, source. Populate samples OR channelSamples; leave the other array empty. All channels must have equal length.
spectrum: frequencies and power arrays of equal length.
featureTable: columns (strings) and rows (objects keyed by column name; values become strings).
Other artifacts use BrainStory's existing JSON representation, provided in input.json.

Write UTF-8 JSON with finite numbers. Exit 0 on success; a nonzero exit, timeout, missing output or invalid artifact fails the node without applying the output. print() and stderr appear in Recent runs.

Return at least one artifact. Python code nodes execute on every requested run, including when previously done, so changes to linked files and environments take effect. Git is cloned per dataset execution; use a commit ID for repeatability.

Embedded source is saved with the BrainStory project. Imported files are a copy; local folders are live references. Dependencies must already be installed in your chosen interpreter. Code runs with your desktop account's filesystem and network access; it is not sandboxed.

Desktop execution only. Full contract and examples: docs/code_nodes.md.
''';

class _CodeEditor extends StatefulWidget {
  const _CodeEditor({required this.params});
  final Map<String, dynamic> params;
  @override
  State<_CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<_CodeEditor> {
  late final TextEditingController _code;
  String? _message;
  bool _busy = false;
  Map<String, dynamic> get params => widget.params;
  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: params['code'] as String? ?? '');
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _action(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label, {String? help}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: NodeParamTextField(
      key: ValueKey('$key:${params[key]}'),
      params: params,
      paramKey: key,
      labelText: label,
      helperText: help,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final mode = params['sourceMode'] as String? ?? 'embedded';
    final files = params['files'] as Map? ?? {};
    final reports = params['_codeRuns'] as Map? ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Run your Python code on upstream artifacts. Results become ordinary BrainStory artifacts.',
        ),
        if (!supportsCodeExecution)
          const Text('Open this project in the desktop app to execute Python.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: mode,
          decoration: const InputDecoration(labelText: 'Code source'),
          items: const [
            DropdownMenuItem(
              value: 'embedded',
              child: Text('Embedded in this node'),
            ),
            DropdownMenuItem(
              value: 'local',
              child: Text('Local project folder'),
            ),
            DropdownMenuItem(value: 'git', child: Text('Git repository')),
          ],
          onChanged: (value) => setState(() => params['sourceMode'] = value),
        ),
        const SizedBox(height: 12),
        if (mode == 'embedded') ...[
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Import Python file'),
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                        final file = await openFile(
                          acceptedTypeGroups: [
                            const XTypeGroup(
                              label: 'Python',
                              extensions: ['py'],
                            ),
                          ],
                        );
                        if (file == null) return null;
                        if (await file.length() > 1024 * 1024) {
                          throw const FormatException(
                            'Use a local folder for scripts larger than 1 MB.',
                          );
                        }
                        final text = await file.readAsString();
                        if (!mounted) return null;
                        setState(() {
                          params['code'] = text;
                          params['entryPoint'] = file.name;
                          _code.text = text;
                        });
                        return 'Copied ${file.name} into the node.';
                      }),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_copy_outlined),
                label: const Text('Import project folder'),
                onPressed: _busy || !supportsCodeExecution
                    ? null
                    : () => _action(() async {
                        final path = await getDirectoryPath();
                        if (path == null) return null;
                        final imported = await importCodeFolder(path);
                        if (!mounted) return null;
                        setState(() {
                          params['files'] = imported;
                          params['code'] = '';
                          _code.clear();
                        });
                        return 'Copied ${imported.length} files. Set the entry point below. Virtual environments and .git are excluded.';
                      }),
              ),
            ],
          ),
          if (files.isNotEmpty)
            ExpansionTile(
              title: Text('${files.length} embedded project files'),
              children: [
                SelectableText(files.keys.join('\n')),
                TextButton(
                  onPressed: () =>
                      setState(() => params['files'] = <String, String>{}),
                  child: const Text('Remove embedded project files'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            minLines: 10,
            maxLines: 22,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'Python entry point code',
              border: OutlineInputBorder(),
              helperText:
                  'Blank uses the imported entry point file; text here overrides it.',
            ),
            onChanged: (text) => params['code'] = text,
          ),
          TextButton(
            onPressed: () => setState(() {
              params['code'] = codeNodeExample;
              _code.text = codeNodeExample;
            }),
            child: const Text('Use gain example'),
          ),
        ],
        if (mode == 'local') ...[
          _field(
            'sourcePath',
            'Project folder',
            help: 'Live files; edits take effect when you rerun the node.',
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _action(() async {
                    final path = await getDirectoryPath();
                    if (path != null && mounted) {
                      setState(() => params['sourcePath'] = path);
                    }
                    return null;
                  }),
            child: const Text('Choose folder'),
          ),
        ],
        if (mode == 'git') ...[
          _field(
            'repository',
            'Repository URL',
            help: 'HTTPS or SSH; uses your existing Git credentials.',
          ),
          _field(
            'gitRef',
            'Commit, tag or branch',
            help: 'Blank uses repository HEAD. Pin a commit for repeatability.',
          ),
        ],
        const SizedBox(height: 12),
        _field(
          'entryPoint',
          'Entry point',
          help:
              'Path relative to the project folder, e.g. main.py or scripts/analyze.py',
        ),
        _field(
          'interpreter',
          'Python interpreter',
          help: 'Executable or absolute path, e.g. /project/.venv/bin/python',
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy || !supportsCodeExecution
                  ? null
                  : () => _action(() async {
                      final file = await openFile();
                      if (file != null && mounted) {
                        setState(() => params['interpreter'] = file.path);
                      }
                      return null;
                    }),
              child: const Text('Choose interpreter'),
            ),
            OutlinedButton(
              onPressed: _busy || !supportsCodeExecution
                  ? null
                  : () => _action(
                      () => checkCodeInterpreter(
                        params['interpreter'] as String? ?? 'python3',
                      ),
                    ),
              child: const Text('Test interpreter'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          'parametersJson',
          'Parameters (JSON object)',
          help: 'Available to your code as request["parameters"].',
        ),
        NodeParamTextField(
          params: params,
          paramKey: 'timeoutSeconds',
          labelText: 'Timeout per process (seconds)',
          keyboardType: TextInputType.number,
          parser: (text, previous) => int.tryParse(text) ?? previous,
        ),
        const SizedBox(height: 12),
        const Text(
          'Uses the selected Python environment as-is. Code runs with your account’s filesystem and network access.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SelectableText(_message!),
          ),
        const ExpansionTile(
          title: Text('Artifact contract & instructions'),
          children: [SelectableText(codeContractHelp)],
        ),
        if (reports.isNotEmpty)
          ExpansionTile(
            title: const Text('Recent runs'),
            children: [
              for (final value in reports.values.toList().reversed)
                ListTile(
                  title: Text('${value['dataset']} — ${value['status']}'),
                  subtitle: SelectableText(
                    '${value['startedAt']} · ${value['durationMs'] ?? 0} ms\n${value['error'] ?? ''}\n${value['log'] ?? ''}',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
