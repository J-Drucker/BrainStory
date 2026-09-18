import 'package:flutter/material.dart';

import '../nodes/node_type.dart';

Future<NodeArtifactExportOptions?> showNodeArtifactExportOptionsDialog(
  BuildContext context,
) {
  return showDialog<NodeArtifactExportOptions>(
    context: context,
    builder: (_) => const _NodeArtifactExportOptionsDialog(),
  );
}

class _NodeArtifactExportOptionsDialog extends StatefulWidget {
  const _NodeArtifactExportOptionsDialog();

  @override
  State<_NodeArtifactExportOptionsDialog> createState() =>
      _NodeArtifactExportOptionsDialogState();
}

class _NodeArtifactExportOptionsDialogState
    extends State<_NodeArtifactExportOptionsDialog> {
  final Set<NodeArtifactExportFormat> _formats = <NodeArtifactExportFormat>{
    NodeArtifactExportFormat.csv,
  };
  bool _separateDatasets = true;
  bool _separateArtifacts = true;
  NodeArtifactExportShape _shape = NodeArtifactExportShape.long;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export formats'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Formats',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('CSV'),
                value: _formats.contains(NodeArtifactExportFormat.csv),
                onChanged: (bool? value) =>
                    _toggleFormat(NodeArtifactExportFormat.csv, value == true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('JSON'),
                value: _formats.contains(NodeArtifactExportFormat.json),
                onChanged: (bool? value) =>
                    _toggleFormat(NodeArtifactExportFormat.json, value == true),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Separate file for every dataset'),
                value: _separateDatasets,
                onChanged: (bool value) =>
                    setState(() => _separateDatasets = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Separate file for every artifact'),
                value: _separateArtifacts,
                onChanged: (bool value) =>
                    setState(() => _separateArtifacts = value),
              ),
              const SizedBox(height: 8),
              const Text(
                'Layout',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SegmentedButton<NodeArtifactExportShape>(
                segments: const <ButtonSegment<NodeArtifactExportShape>>[
                  ButtonSegment<NodeArtifactExportShape>(
                    value: NodeArtifactExportShape.long,
                    label: Text('Long'),
                  ),
                  ButtonSegment<NodeArtifactExportShape>(
                    value: NodeArtifactExportShape.wide,
                    label: Text('Wide'),
                  ),
                ],
                selected: <NodeArtifactExportShape>{_shape},
                onSelectionChanged: (Set<NodeArtifactExportShape> value) {
                  setState(() => _shape = value.single);
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _formats.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  NodeArtifactExportOptions(
                    formats: Set<NodeArtifactExportFormat>.from(_formats),
                    separateDatasets: _separateDatasets,
                    separateArtifacts: _separateArtifacts,
                    shape: _shape,
                  ),
                ),
          child: const Text('Export'),
        ),
      ],
    );
  }

  void _toggleFormat(NodeArtifactExportFormat format, bool selected) {
    setState(() => selected ? _formats.add(format) : _formats.remove(format));
  }
}
