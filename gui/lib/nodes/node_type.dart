import 'package:flutter/material.dart';
import '../model/dataset.dart';

enum PortType { signal, metadata, markers }

class PortSpec {
  final String name;
  final PortType type;

  const PortSpec({
    required this.name,
    required this.type,
  });
}

abstract class NodeType {
  String get title;
  Map<String, dynamic> get defaultParams;

  List<PortSpec> get inputs;
  List<PortSpec> get outputs;

  /// Nodes implement ONLY their body UI here
  Widget buildBody(
      Map<String, dynamic> params, {
        required Map<String, Dataset> datasets,
        required void Function(void Function()) setState,
      });

  /// Final, shared config panel
  Widget buildConfigWidget(
      Map<String, dynamic> params,
      void Function(Map<String, dynamic>) onSave, {
        required Map<String, Dataset> datasets,
      }) {
    return _NodeConfigDialog(
      title: title,
      params: params,
      datasets: datasets,
      buildBody: buildBody,
      onSave: onSave,
    );
  }

  /// Execution hook
  Future<void> run(Dataset dataset, Map<String, dynamic> params);
}

class _NodeConfigDialog extends StatefulWidget {
  final String title;
  final Map<String, dynamic> params;
  final Map<String, Dataset> datasets;
  final Widget Function(
      Map<String, dynamic> params, {
      required Map<String, Dataset> datasets,
      required void Function(void Function()) setState,
      }) buildBody;
  final void Function(Map<String, dynamic>) onSave;

  const _NodeConfigDialog({
    required this.title,
    required this.params,
    required this.datasets,
    required this.buildBody,
    required this.onSave,
  });

  @override
  State<_NodeConfigDialog> createState() => _NodeConfigDialogState();
}

class _NodeConfigDialogState extends State<_NodeConfigDialog> {
  late Map<String, dynamic> localParams;

  @override
  void initState() {
    super.initState();
    localParams = Map<String, dynamic>.from(widget.params);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: widget.buildBody(
          localParams,
          datasets: widget.datasets,
          setState: setState,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(localParams);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
