import 'package:flutter/material.dart';

class NodeCard extends StatelessWidget {
  final double width;
  final double height;
  final String title;
  final int nodeNumber;
  final Offset position;
  final String? statusLabel;
  final bool highlighted;
  final Color? highlightColor;
  final bool done;

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
    required this.width,
    required this.height,
    required this.title,
    required this.nodeNumber,
    required this.position,
    required this.onDragEnd,
    required this.color,
    this.statusLabel,
    this.highlighted = false,
    this.highlightColor,
    this.done = false,
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
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: done
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x663FD37A),
                    blurRadius: 12,
                    spreadRadius: 1.5,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Card(
          color: color,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: highlighted
                  ? (highlightColor ?? const Color(0xFFC3B15C))
                  : Colors.transparent,
              width: highlighted ? 2 : 0,
            ),
          ),
          child: Stack(
            children: <Widget>[
            Positioned(
              left: 8,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF30343A),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 4,
                      offset: Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Text(
                  '$nodeNumber',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.1,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (statusLabel != null) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          statusLabel!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            height: 1.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
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
