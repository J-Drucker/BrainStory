import 'package:flutter/material.dart';

class BandpassConfigWidget extends StatefulWidget {
  final Map<String, dynamic> initialParams;
  final void Function(Map<String, dynamic>) onSave;

  const BandpassConfigWidget({
    super.key,
    required this.initialParams,
    required this.onSave,
  });

  @override
  State<BandpassConfigWidget> createState() => _BandpassConfigWidgetState();
}

class _BandpassConfigWidgetState extends State<BandpassConfigWidget> {
  late TextEditingController lowController;
  late TextEditingController highController;
  late TextEditingController steepController;
  late TextEditingController notchController;

  @override
  void initState() {
    super.initState();
    lowController =
        TextEditingController(text: widget.initialParams['low']?.toString() ?? '');
    highController =
        TextEditingController(text: widget.initialParams['high']?.toString() ?? '');
    steepController = TextEditingController(
      text: widget.initialParams['steepness']?.toString() ?? '',
    );
    notchController =
        TextEditingController(text: widget.initialParams['notch']?.toString() ?? '');
  }

  @override
  void dispose() {
    lowController.dispose();
    highController.dispose();
    steepController.dispose();
    notchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bandpass Filter Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: lowController,
            decoration: const InputDecoration(labelText: 'Low Cut (Hz)'),
          ),
          TextField(
            controller: highController,
            decoration: const InputDecoration(labelText: 'High Cut (Hz)'),
          ),
          TextField(
            controller: steepController,
            decoration: const InputDecoration(labelText: 'Steepness'),
          ),
          TextField(
            controller: notchController,
            decoration:
            const InputDecoration(labelText: 'Notch (Hz, optional)'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(<String, dynamic>{
              'low': double.tryParse(lowController.text),
              'high': double.tryParse(highController.text),
              'steepness': double.tryParse(steepController.text),
              'notch': double.tryParse(notchController.text),
            });
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class VisualizationConfigWidget extends StatefulWidget {
  final Map<String, dynamic> initialParams;
  final void Function(Map<String, dynamic>) onSave;

  const VisualizationConfigWidget({
    super.key,
    required this.initialParams,
    required this.onSave,
  });

  @override
  State<VisualizationConfigWidget> createState() =>
      _VisualizationConfigWidgetState();
}

class _VisualizationConfigWidgetState extends State<VisualizationConfigWidget> {
  static const List<String> _backends = <String>['mne', 'matplotlib'];
  static const List<String> _views = <String>['raw', 'psd'];

  late String backend;
  late String view;
  late TextEditingController windowController;
  late TextEditingController channelController;

  @override
  void initState() {
    super.initState();
    final String initialBackend =
        widget.initialParams['backend']?.toString() ?? 'mne';
    final String initialView =
        widget.initialParams['view']?.toString() ?? 'raw';

    backend = _backends.contains(initialBackend) ? initialBackend : _backends.first;
    view = _views.contains(initialView) ? initialView : _views.first;

    windowController = TextEditingController(
      text: widget.initialParams['window_sec']?.toString() ?? '5.0',
    );
    channelController = TextEditingController(
      text: widget.initialParams['channel']?.toString() ?? 'all',
    );
  }

  @override
  void dispose() {
    windowController.dispose();
    channelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('EEG Visualization Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: backend,
            decoration: const InputDecoration(labelText: 'Backend'),
            items: _backends
                .map(
                  (String b) =>
                  DropdownMenuItem<String>(value: b, child: Text(b.toUpperCase())),
            )
                .toList(),
            onChanged: (String? value) {
              if (value == null) return;
              setState(() => backend = value);
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: view,
            decoration: const InputDecoration(labelText: 'View'),
            items: _views
                .map(
                  (String v) =>
                  DropdownMenuItem<String>(value: v, child: Text(v.toUpperCase())),
            )
                .toList(),
            onChanged: (String? value) {
              if (value == null) return;
              setState(() => view = value);
            },
          ),
          TextField(
            controller: windowController,
            decoration: const InputDecoration(labelText: 'Window (seconds)'),
          ),
          TextField(
            controller: channelController,
            decoration:
            const InputDecoration(labelText: 'Channel (name or all)'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final String channel = channelController.text.trim();
            widget.onSave(<String, dynamic>{
              'backend': backend,
              'view': view,
              'window_sec': double.tryParse(windowController.text) ?? 5.0,
              'channel': channel.isEmpty ? 'all' : channel,
            });
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
