import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brainstory_gui/model/data_artifacts.dart';
import 'package:brainstory_gui/model/dataset.dart';
import 'package:brainstory_gui/model/dataset_state.dart';
import 'package:brainstory_gui/nodes/code_contract.dart';
import 'package:brainstory_gui/nodes/code_node.dart';
import 'package:brainstory_gui/nodes/import_node.dart';
import 'package:brainstory_gui/nodes/node_registry.dart';
import 'package:brainstory_gui/platform/code_runner.dart';
import 'package:brainstory_gui/ui/canvas_logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Dataset fixture() => Dataset('test', label: 'Test signal')
  ..timeSeries = TimeSeriesData(
    samples: [],
    channelSamples: [
      [1, 2, 3],
    ],
    channelLabels: ['Fz'],
    sampleRate: 250,
  )
  ..featureTable = const FeatureTableData(
    columns: ['value'],
    rows: [
      {'value': '3'},
    ],
  );

String responseScript(String expression) =>
    '''import json, sys
from pathlib import Path
request = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(json.dumps($expression))
''';

void main() {
  final node = CodeNodeType();
  test('code node is discoverable and its defaults are serializable', () {
    expect(
      NodeRegistry.entries.any((e) => e.visible && e.create() is CodeNodeType),
      isTrue,
    );
    expect(
      jsonDecode(jsonEncode(node.defaultParams))['code'],
      contains('protocolVersion'),
    );
  });

  test(
    'embedded Python transforms samples and preserves other artifacts',
    () async {
      final dataset = fixture();
      final params = node.defaultParams..['parametersJson'] = '{"gain": 2}';
      await node.run(dataset, params);
      expect(dataset.timeSeries!.channels.single, [2, 4, 6]);
      expect(dataset.featureTable!.rows.single['value'], '3');
      expect(params['_codeRuns']['test']['status'], 'succeeded');
      expect(
        params['_codeRuns']['test']['log'],
        contains('Finished Test signal'),
      );
    },
  );

  test('output replaces artifacts and can produce a feature table', () async {
    final dataset = fixture();
    final params = node.defaultParams
      ..['code'] = responseScript('''{
      "protocolVersion": 1, "artifacts": {"featureTable": {
        "columns": ["mean"], "rows": [{"mean": 2.0}]
      }}}''');
    await node.run(dataset, params);
    expect(dataset.timeSeries, isNull);
    expect(dataset.featureTable!.rows.single['mean'], '2.0');
  });

  for (final script in [
    'raise RuntimeError("intentional failure")',
    'print("no output")',
    responseScript(
      '{"protocolVersion": 999, "artifacts": request["artifacts"]}',
    ),
    responseScript(
      '{"protocolVersion": 1, "artifacts": {"timeSeries": {"sampleRate": -1}}}',
    ),
  ]) {
    test(
      'failed Python output is atomic: ${script.split('\n').first}',
      () async {
        final dataset = fixture();
        final before = dataset.timeSeries;
        final params = node.defaultParams..['code'] = script;
        await expectLater(node.run(dataset, params), throwsA(anything));
        expect(identical(dataset.timeSeries, before), isTrue);
        expect(params['_codeRuns']['test']['status'], 'failed');
      },
    );
  }

  test('timeout terminates a stuck interpreter', () async {
    final params = node.defaultParams
      ..['timeoutSeconds'] = 1
      ..['code'] = 'import time\ntime.sleep(60)';
    await expectLater(
      node.run(fixture(), params),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      params['_codeRuns']['test']['error'],
      contains('exceeded 1 seconds'),
    );
  });

  test('missing interpreter fails with diagnostics', () async {
    final params = node.defaultParams
      ..['interpreter'] = '/missing/brainstory-python';
    await expectLater(
      node.run(fixture(), params),
      throwsA(isA<ProcessException>()),
    );
    expect(params['_codeRuns']['test']['status'], 'failed');
  });

  test('interpreter check returns actual executable and version', () async {
    expect(await checkCodeInterpreter('python3'), contains('3.'));
  });

  test(
    'embedded multi-file project supports sibling imports and binary assets',
    () async {
      final params = node.defaultParams
        ..['code'] =
            'from helper import gain\n${codeNodeExample.replaceFirst('1.0)', 'gain)')}'
        ..['parametersJson'] = '{}'
        ..['files'] = {
          'helper.py': base64Encode(utf8.encode('gain = 3')),
          'data.bin': base64Encode([0, 255]),
        };
      final dataset = fixture();
      await node.run(dataset, params);
      expect(dataset.timeSeries!.channels.single, [3, 6, 9]);
    },
  );

  test('local folder uses live files and project working directory', () async {
    final folder = await Directory.systemTemp.createTemp(
      'brainstory-code-test-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final script = File('${folder.path}/main.py');
    await script.writeAsString('''from pathlib import Path
assert Path("asset.txt").read_text() == "asset"
$codeNodeExample''');
    await File('${folder.path}/asset.txt').writeAsString('asset');
    final params = node.defaultParams
      ..['sourceMode'] = 'local'
      ..['sourcePath'] = folder.path;
    final dataset = fixture();
    await node.run(dataset, params);
    await script.writeAsString(codeNodeExample.replaceFirst('1.0)', '4.0)'));
    params['parametersJson'] = '{}';
    await node.run(dataset, params);
    expect(dataset.timeSeries!.channels.single, [4, 8, 12]);
    expect(await File('${folder.path}/input.json').exists(), isFalse);
  });

  test(
    'folder upload preserves paths and skips environments and symlinks',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'brainstory-bundle-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      await Directory('${folder.path}/scripts').create();
      await File(
        '${folder.path}/scripts/main.py',
      ).writeAsString(codeNodeExample);
      await Directory('${folder.path}/.venv').create();
      await File('${folder.path}/.venv/ignored').writeAsString('ignored');
      if (!Platform.isWindows) {
        await Link('${folder.path}/linked').create('/tmp');
      }
      final files = await importCodeFolder(folder.path);
      expect(files.keys, ['scripts/main.py']);
      final params = node.defaultParams
        ..['files'] = files
        ..['code'] = ''
        ..['entryPoint'] = 'scripts/main.py';
      await node.run(fixture(), params);
    },
  );

  test('embedded traversal cannot escape the run directory', () async {
    final params = node.defaultParams
      ..['files'] = {
        '../escape.py': base64Encode([1]),
      };
    await expectLater(
      node.run(fixture(), params),
      throwsA(isA<FormatException>()),
    );
    params['files'] = <String, String>{};
    params['entryPoint'] = '../main.py';
    await expectLater(
      node.run(fixture(), params),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'Git source resolves non-default branches and records exact revision',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'brainstory-git-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      Future<String> git(List<String> args) async {
        final result = await Process.run(
          'git',
          args,
          workingDirectory: folder.path,
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return result.stdout.toString().trim();
      }

      await git(['init', '-b', 'main']);
      await File('${folder.path}/main.py').writeAsString(codeNodeExample);
      await git(['add', 'main.py']);
      await git([
        '-c',
        'user.name=Test',
        '-c',
        'user.email=test@example.invalid',
        '-c',
        'commit.gpgsign=false',
        'commit',
        '-m',
        'fixture',
      ]);
      await git(['branch', 'analysis']);
      final revision = await git(['rev-parse', 'HEAD']);
      final params = node.defaultParams
        ..['sourceMode'] = 'git'
        ..['repository'] = folder.path
        ..['gitRef'] = 'analysis';
      await node.run(fixture(), params);
      expect(params['_codeRuns']['test']['revision'], revision);
    },
  );

  test(
    'contract rejects malformed signals, table rows, nonfinite values and unknown artifacts',
    () {
      for (final artifacts in [
        <String, dynamic>{},
        {'unknown': {}},
        {
          'spectrum': {
            'frequencies': [1],
            'power': [],
          },
        },
        {
          'featureTable': {
            'columns': ['a'],
            'rows': [
              [1],
            ],
          },
        },
        {
          'timeSeries': {
            'sampleRate': 1,
            'samples': [],
            'channelLabels': ['a', 'b'],
            'channelSamples': [
              [1],
              [1, 2],
            ],
          },
        },
        {
          'spectrum': {
            'frequencies': [1],
            'power': [double.infinity],
          },
        },
      ]) {
        expect(
          () => parseCodeNodeOutput({
            'protocolVersion': 1,
            'artifacts': artifacts,
          }),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'graph executes code, restores artifacts for downstream code, and reruns linked computation',
    () async {
      final logic = CanvasLogic(runUiYieldsEnabled: false);
      final dataset = Dataset(
        'graph',
        label: 'Graph',
        path: 'graph.csv',
        sourceBytes: Uint8List.fromList(
          utf8.encode('time,Fz\n0.000,1\n0.004,2\n0.008,3\n'),
        ),
      );
      logic.datasets[dataset.id] = dataset;
      logic.addNode(ImportNodeType());
      logic.addNode(CodeNodeType());
      logic.addNode(CodeNodeType());
      for (final n in logic.nodes) {
        n.params['selectedDatasetIds'] = [dataset.id];
      }
      logic.nodes[1].params['parametersJson'] = '{"gain": 2}';
      logic.nodes[2].params['parametersJson'] = '{"gain": 3}';
      for (var i = 0; i < 2; i++) {
        logic.connections.add({
          'fromNode': logic.nodes[i].id,
          'fromPort': 0,
          'toNode': logic.nodes[i + 1].id,
          'toPort': 0,
        });
      }
      await logic.runAllNodes();
      expect(dataset.timeSeries!.channels.single, [6, 12, 18]);
      expect(logic.nodes.last.datasetStates[dataset.id], DatasetState.done);
      await logic.runAllNodes();
      expect(dataset.timeSeries!.channels.single, [6, 12, 18]);
      final exported = logic.exportProjectJson();
      expect(jsonEncode(exported), contains('Python Code'));
      expect((exported['nodes'] as List)[1]['params']['code'], codeNodeExample);
      final restored = CanvasLogic(runUiYieldsEnabled: false);
      restored.importProjectJson(
        jsonDecode(jsonEncode(exported)) as Map<String, dynamic>,
      );
      expect(restored.nodes[1].type, isA<CodeNodeType>());
      expect(
        restored.nodes[1].params['_codeRuns']['graph']['status'],
        'succeeded',
      );
      await restored.runAllNodes();
      expect(restored.datasets.values.single.timeSeries!.channels.single, [
        6,
        12,
        18,
      ]);
    },
  );

  testWidgets('editor exposes source options and artifact instructions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: node.buildBody(
              node.defaultParams,
              datasets: {},
              setState: (change) => change(),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Embedded in this node'), findsOneWidget);
    expect(find.text('Test interpreter'), findsOneWidget);
    expect(find.text('Artifact contract & instructions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
