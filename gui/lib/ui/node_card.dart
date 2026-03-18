import 'package:flutter/material.dart';

class NodeCard extends StatelessWidget {
  final String title;
  final Offset position;
  final String? statusLabel;

  final void Function(Offset) onDragEnd;
  final void Function()? onTap;
  final void Function()? onDoubleTap;

  final void Function()? onRunThis;
  final void Function()? onRunFromStart;
  final void Function()? onRunToEnd;
  final void Function()? onEditParams;
  final void Function()? onDelete;

  final Color color;

  const NodeCard({
    super.key,
    required this.title,
    required this.position,
    required this.onDragEnd,
    required this.color,
    this.statusLabel,
    this.onTap,
    this.onDoubleTap,
    this.onRunThis,
    this.onRunFromStart,
    this.onRunToEnd,
    this.onEditParams,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition);
        },
        child: Draggable(
          dragAnchorStrategy: childDragAnchorStrategy,
          feedback: _buildCard(),
          childWhenDragging: Opacity(
            opacity: 0.5,
            child: _buildCard(),
          ),
          onDragEnd: (details) => onDragEnd(details.offset),
          child: _buildCard(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Card(
      color: color,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(color: Colors.white),
            ),
            if (statusLabel != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                statusLabel!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy,
        pos.dx + 1,
        pos.dy + 1,
      ),
      items: [
        const PopupMenuItem(value: 'run_this', child: Text('Run This Step')),
        const PopupMenuItem(value: 'run_start', child: Text('Run From Start')),
        const PopupMenuItem(value: 'run_end', child: Text('Run To End')),
        const PopupMenuItem(value: 'edit', child: Text('Edit Parameters')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete Node', style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    switch (choice) {
      case 'run_this':
        onRunThis?.call();
        break;
      case 'run_start':
        onRunFromStart?.call();
        break;
      case 'run_end':
        onRunToEnd?.call();
        break;
      case 'edit':
        onEditParams?.call();
        break;
      case 'delete':
        onDelete?.call();
        break;
    }
  }
}
