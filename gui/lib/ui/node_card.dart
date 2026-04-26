import 'package:flutter/material.dart';

class NodeOutputHandleViewData {
  const NodeOutputHandleViewData({
    required this.portIndex,
    required this.color,
    required this.filled,
    required this.label,
    this.badgeText = '',
    this.tooltip = '',
  });

  final int portIndex;
  final Color color;
  final bool filled;
  final String label;
  final String badgeText;
  final String tooltip;
}

class NodeProcessViewData {
  const NodeProcessViewData({
    required this.label,
    required this.color,
    this.active = false,
  });

  final String label;
  final Color color;
  final bool active;
}

class NodeCard extends StatelessWidget {
  final double width;
  final double height;
  final String title;
  final int nodeNumber;
  final Offset position;
  final bool highlighted;
  final Color? highlightColor;
  final bool done;
  final NodeProcessViewData? processIndicator;
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
    this.highlighted = false,
    this.highlightColor,
    this.done = false,
    this.processIndicator,
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
    bool hovering = false;
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setHoverState) {
          final bool showOutputHandles =
              hovering || selectedOutputPortIndex != null;
          final bool hasVisibleOutputHandles =
              showOutputHandles && outputHandles.isNotEmpty && onOutputTap != null;
          return MouseRegion(
            onEnter: (_) => setHoverState(() => hovering = true),
            onExit: (_) => setHoverState(() => hovering = false),
            child: SizedBox(
              width: width,
              height: hasVisibleOutputHandles ? height + 28 : height,
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
                  if (processIndicator != null)
                    Positioned(
                      left: 0,
                      top: -18,
                      child: _NodeProcessIndicator(data: processIndicator!),
                    ),
                  ..._buildOutputHandles(showOutputHandles: hasVisibleOutputHandles),
                ],
              ),
            ),
          );
        },
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
              ? <BoxShadow>[
                  BoxShadow(
                    color: processIndicator?.active == true
                        ? processIndicator!.color.withValues(alpha: 0.62)
                        : const Color(0x663FD37A),
                    blurRadius: 12,
                    spreadRadius: 1.5,
                  ),
                ]
              : processIndicator?.active == true
                  ? <BoxShadow>[
                      BoxShadow(
                        color: processIndicator!.color.withValues(alpha: 0.58),
                        blurRadius: 14,
                        spreadRadius: 2,
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
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
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

  List<Widget> _buildOutputHandles({required bool showOutputHandles}) {
    if (!showOutputHandles || outputHandles.isEmpty || onOutputTap == null) {
      return const <Widget>[];
    }

    const double handleWidth = 58;
    const double handleHeight = 22;
    const double handleGap = 8;
    final int visualSlotCount =
        outputHandles.length.isOdd ? outputHandles.length + 1 : outputHandles.length;
    final double totalWidth =
        (visualSlotCount * handleWidth) + ((visualSlotCount - 1) * handleGap);
    final double startLeft = (width - totalWidth) / 2;
    final List<int> visualSlots = outputHandles.length.isOdd
        ? List<int>.generate(
            outputHandles.length,
            (int index) => index >= (outputHandles.length / 2).floor() ? index + 1 : index,
            growable: false,
          )
        : List<int>.generate(outputHandles.length, (int index) => index, growable: false);

    return outputHandles.asMap().entries.map((MapEntry<int, NodeOutputHandleViewData> entry) {
      final int visualIndex = entry.key;
      final NodeOutputHandleViewData handle = entry.value;
      final double left = startLeft + (visualSlots[visualIndex] * (handleWidth + handleGap));
      return Positioned(
        left: left,
        top: height - 4,
        child: _NodeOutputHandle(
          width: handleWidth,
          height: handleHeight,
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

class _NodeProcessIndicator extends StatelessWidget {
  const _NodeProcessIndicator({required this.data});

  final NodeProcessViewData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 78),
      padding: const EdgeInsets.only(left: 8, right: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: data.active ? 0.30 : 0.18),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(7),
        ),
        border: Border.all(
          color: data.color.withValues(alpha: data.active ? 0.70 : 0.42),
          width: 1,
        ),
        boxShadow: data.active
            ? <BoxShadow>[
                BoxShadow(
                  color: data.color.withValues(alpha: 0.28),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: data.color,
              shape: BoxShape.circle,
              boxShadow: data.active
                  ? <BoxShadow>[
                      BoxShadow(
                        color: data.color.withValues(alpha: 0.76),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            data.label,
            style: TextStyle(
              color: data.color,
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeOutputHandle extends StatefulWidget {
  const _NodeOutputHandle({
    required this.width,
    required this.height,
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final double height;
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
    final Widget handle = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.data.filled
            ? widget.data.color
            : widget.data.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: emphasized
              ? Colors.white
              : widget.data.filled
                  ? Colors.black.withValues(alpha: 0.18)
                  : widget.data.color.withValues(alpha: 0.8),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          widget.data.label,
          style: TextStyle(
            color: widget.data.filled
                ? Colors.white.withValues(alpha: 0.96)
                : widget.data.color.withValues(alpha: 0.96),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            height: 1.0,
            letterSpacing: -0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
          child: handle,
        ),
      ),
    );
  }
}
