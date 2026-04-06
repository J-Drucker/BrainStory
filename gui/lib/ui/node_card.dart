import 'package:flutter/material.dart';

class NodeOutputHandleViewData {
  const NodeOutputHandleViewData({
    required this.portIndex,
    required this.color,
    this.badgeText = '',
    this.tooltip = '',
  });

  final int portIndex;
  final Color color;
  final String badgeText;
  final String tooltip;
}

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
  final List<NodeOutputHandleViewData> outputHandles;
  final int? selectedOutputPortIndex;

  final void Function(Offset) onDragEnd;
  final void Function()? onTap;
  final void Function()? onDoubleTap;
  final void Function(int portIndex)? onOutputTap;

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
    this.outputHandles = const <NodeOutputHandleViewData>[],
    this.selectedOutputPortIndex,
    this.onTap,
    this.onDoubleTap,
    this.onOutputTap,
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
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            GestureDetector(
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
            ..._buildOutputHandles(),
          ],
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
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 22),
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

  List<Widget> _buildOutputHandles() {
    if (outputHandles.isEmpty || onOutputTap == null) {
      return const <Widget>[];
    }

    const double handleSize = 18;
    const double handleGap = 6;
    final double totalWidth =
        (outputHandles.length * handleSize) + ((outputHandles.length - 1) * handleGap);
    final double startLeft = (width - totalWidth) / 2;

    return outputHandles.asMap().entries.map((MapEntry<int, NodeOutputHandleViewData> entry) {
      final int visualIndex = entry.key;
      final NodeOutputHandleViewData handle = entry.value;
      final double left = startLeft + (visualIndex * (handleSize + handleGap));
      return Positioned(
        left: left,
        top: height - handleSize - 6,
        child: _NodeOutputHandle(
          size: handleSize,
          data: handle,
          selected: selectedOutputPortIndex == handle.portIndex,
          onTap: () => onOutputTap?.call(handle.portIndex),
        ),
      );
    }).toList(growable: false);
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

class _NodeOutputHandle extends StatefulWidget {
  const _NodeOutputHandle({
    required this.size,
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final double size;
  final NodeOutputHandleViewData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NodeOutputHandle> createState() => _NodeOutputHandleState();
}

class _NodeOutputHandleState extends State<_NodeOutputHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool emphasized = _hovered || widget.selected;
    final Widget square = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.data.color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: emphasized ? Colors.white : Colors.black.withValues(alpha: 0.18),
          width: emphasized ? 2 : 1,
        ),
        boxShadow: emphasized
            ? <BoxShadow>[
                BoxShadow(
                  color: widget.data.color.withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 1.2,
                ),
              ]
            : <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Text(
        widget.data.badgeText,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.96),
          fontSize: widget.data.badgeText.length > 2 ? 7 : 8,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
        maxLines: 1,
        overflow: TextOverflow.visible,
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.data.tooltip,
        waitDuration: const Duration(milliseconds: 350),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: square,
        ),
      ),
    );
  }
}
