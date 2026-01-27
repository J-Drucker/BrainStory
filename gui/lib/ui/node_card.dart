import 'package:flutter/material.dart';
import '../nodes/node_type.dart';

class NodeCard extends StatelessWidget {
  final String title;
  final Offset position;

  final void Function(Offset) onDragEnd;
  final void Function()? onTap;
  final void Function()? onDoubleTap;
  final void Function()? onLongPress;

  final List<PortSpec> inputPorts;
  final List<PortSpec> outputPorts;

  final ValueChanged<int>? onInputPortTap;
  final ValueChanged<int>? onOutputPortTap;

  const NodeCard({
    super.key,
    required this.title,
    required this.position,
    required this.onDragEnd,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    required this.inputPorts,
    required this.outputPorts,
    this.onInputPortTap,
    this.onOutputPortTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTap: onLongPress,
        child: Draggable(
          feedback: _buildCard(),
          childWhenDragging: Opacity(opacity: 0.5, child: _buildCard()),
          onDragEnd: (details) => onDragEnd(details.offset),
          child: _buildCard(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (inputPorts.isNotEmpty) _buildPortRow(inputPorts, isInput: true),
        Card(
          elevation: 6,
          color: Colors.blueGrey[800],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Text(
              title,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        if (outputPorts.isNotEmpty) _buildPortRow(outputPorts, isInput: false),
      ],
    );
  }

  Widget _buildPortRow(List<PortSpec> ports, {required bool isInput}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < ports.length; i++)
            _PortWidget(
              spec: ports[i],
              isInput: isInput,
              onTap: () {
                if (isInput) {
                  onInputPortTap?.call(i);
                } else {
                  onOutputPortTap?.call(i);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _PortWidget extends StatelessWidget {
  final PortSpec spec;
  final bool isInput;
  final VoidCallback? onTap;

  const _PortWidget({
    required this.spec,
    required this.isInput,
    this.onTap,
  });

  String get _symbol {
    switch (spec.type) {
      case PortType.signal:
        return '●';
      case PortType.metadata:
        return '■';
      case PortType.markers:
        return '▲';
    }
  }

  String get _label {
    switch (spec.type) {
      case PortType.signal:
        return 'sig';
      case PortType.metadata:
        return 'meta';
      case PortType.markers:
        return 'mark';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onTap?.call(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _symbol,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.orange,
            ),
          ),
          Text(
            _label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
