import 'package:flutter/material.dart';

enum NodeConnectionEdge { right, bottom, left, top }

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
  final bool connectionDraftActive;
  final NodeConnectionEdge? selectedConnectionEdge;
  final bool showConnectionOutputs;
  final bool showConnectionInputs;

  final void Function(Offset) onDragEnd;
  final void Function()? onTap;
  final void Function()? onDoubleTap;
  final void Function(int portIndex)? onOutputTap;
  final ValueChanged<NodeConnectionEdge>? onConnectionOutputTap;
  final ValueChanged<NodeConnectionEdge>? onConnectionInputTap;
  final void Function(Offset globalPosition)? onContextMenuAt;

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
    this.connectionDraftActive = false,
    this.selectedConnectionEdge,
    this.showConnectionOutputs = false,
    this.showConnectionInputs = false,
    this.onTap,
    this.onDoubleTap,
    this.onOutputTap,
    this.onConnectionOutputTap,
    this.onConnectionInputTap,
    this.onContextMenuAt,
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
              showOutputHandles &&
              outputHandles.isNotEmpty &&
              onOutputTap != null;
          return MouseRegion(
            onEnter: (_) => setHoverState(() => hovering = true),
            onExit: (_) => setHoverState(() => hovering = false),
            child: SizedBox(
              width: width,
              height: hasVisibleOutputHandles ? height + 28 : height,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  if (statusLabel != null)
                    Positioned(
                      left: 0,
                      top: -18,
                      child: _NodeStatusStrip(label: statusLabel!),
                    ),
                  GestureDetector(
                    onTap: onTap,
                    onDoubleTap: onDoubleTap,
                    onSecondaryTapDown: (details) {
                      onContextMenuAt?.call(details.globalPosition);
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
                  ..._buildOutputHandles(
                    showOutputHandles: hasVisibleOutputHandles,
                  ),
                  if (showConnectionOutputs) ...<Widget>[
                    _buildConnectionHandle(NodeConnectionEdge.right),
                    _buildConnectionHandle(NodeConnectionEdge.bottom),
                  ],
                  if (showConnectionInputs) ...<Widget>[
                    _buildConnectionHandle(NodeConnectionEdge.left),
                    _buildConnectionHandle(NodeConnectionEdge.top),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionHandle(NodeConnectionEdge edge) {
    const double hitSize = 24;
    final bool output =
        edge == NodeConnectionEdge.right || edge == NodeConnectionEdge.bottom;
    return Positioned(
      left: switch (edge) {
        NodeConnectionEdge.left => -hitSize / 2,
        NodeConnectionEdge.right => width - (hitSize / 2),
        NodeConnectionEdge.top ||
        NodeConnectionEdge.bottom => (width - hitSize) / 2,
      },
      top: switch (edge) {
        NodeConnectionEdge.top => -hitSize / 2,
        NodeConnectionEdge.bottom => height - (hitSize / 2),
        NodeConnectionEdge.left ||
        NodeConnectionEdge.right => (height - hitSize) / 2,
      },
      child: _NodeConnectionHandle(
        selected: output && selectedConnectionEdge == edge,
        onTap: () {
          if (output) {
            onConnectionOutputTap?.call(edge);
          } else {
            onConnectionInputTap?.call(edge);
          }
        },
      ),
    );
  }

  Widget _buildCard() {
    final Color resolvedHighlightColor =
        highlightColor ?? const Color(0xFFC3B15C);
    final Color badgeAccentColor = highlighted
        ? resolvedHighlightColor
        : Colors.transparent;
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
              color: highlighted ? resolvedHighlightColor : Colors.transparent,
              width: highlighted ? 2 : 0,
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 8,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF30343A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: badgeAccentColor,
                      width: highlighted ? 1.4 : 0,
                    ),
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
                      color: highlighted
                          ? resolvedHighlightColor
                          : Colors.white.withValues(alpha: 0.85),
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
    final int visualSlotCount = outputHandles.length.isOdd
        ? outputHandles.length + 1
        : outputHandles.length;
    final double totalWidth =
        (visualSlotCount * handleWidth) + ((visualSlotCount - 1) * handleGap);
    final double startLeft = (width - totalWidth) / 2;
    final List<int> visualSlots = outputHandles.length.isOdd
        ? List<int>.generate(
            outputHandles.length,
            (int index) =>
                index >= (outputHandles.length / 2).floor() ? index + 1 : index,
            growable: false,
          )
        : List<int>.generate(
            outputHandles.length,
            (int index) => index,
            growable: false,
          );

    return outputHandles
        .asMap()
        .entries
        .map((MapEntry<int, NodeOutputHandleViewData> entry) {
          final int visualIndex = entry.key;
          final NodeOutputHandleViewData handle = entry.value;
          final double left =
              startLeft +
              (visualSlots[visualIndex] * (handleWidth + handleGap));
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
        })
        .toList(growable: false);
  }
}

class _NodeConnectionHandle extends StatefulWidget {
  const _NodeConnectionHandle({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NodeConnectionHandle> createState() => _NodeConnectionHandleState();
}

class _NodeConnectionHandleState extends State<_NodeConnectionHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const Color paleBlue = Color(0xFF9EDCF3);
    const Color cerulean = Color(0xFF007BA7);
    final bool visible = _hovered || widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: 24,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: visible ? 12 : 0,
              height: visible ? 12 : 0,
              decoration: BoxDecoration(
                color: widget.selected ? cerulean : paleBlue,
                shape: BoxShape.circle,
                border: visible
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
                boxShadow: visible
                    ? <BoxShadow>[
                        BoxShadow(
                          color: (widget.selected ? cerulean : paleBlue)
                              .withValues(alpha: 0.55),
                          blurRadius: 6,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeStatusStrip extends StatelessWidget {
  const _NodeStatusStrip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (label) {
      'Done' => const Color(0xFF43C26B),
      'Ready' => const Color(0xFF5CC8FF),
      'Partial' => const Color(0xFFC7D85A),
      'Stale' => const Color(0xFFFFB347),
      'Running' => const Color(0xFF7FE36A),
      'Waiting' => const Color(0xFFC0CAD4),
      'Input locked' => const Color(0xFFFFD166),
      _ => const Color(0xFF8C98A4),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.9)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
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
