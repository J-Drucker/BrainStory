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
    lowController = TextEditingController(text: widget.initialParams['low']?.toString() ?? '');
    highController = TextEditingController(text: widget.initialParams['high']?.toString() ?? '');
    steepController = TextEditingController(text: widget.initialParams['steepness']?.toString() ?? '');
    notchController = TextEditingController(text: widget.initialParams['notch']?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bandpass Filter Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: lowController, decoration: const InputDecoration(labelText: 'Low Cut (Hz)')),
          TextField(controller: highController, decoration: const InputDecoration(labelText: 'High Cut (Hz)')),
          TextField(controller: steepController, decoration: const InputDecoration(labelText: 'Steepness')),
          TextField(controller: notchController, decoration: const InputDecoration(labelText: 'Notch (Hz, optional)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            widget.onSave({
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
