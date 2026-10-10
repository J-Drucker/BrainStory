import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ViewerControlStripDivider extends StatelessWidget {
  const ViewerControlStripDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 16,
        thickness: 2,
        color: Colors.white.withValues(alpha: 0.22),
      ),
    );
  }
}

class ViewerTraceSurface extends StatelessWidget {
  const ViewerTraceSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(padding: const EdgeInsets.all(10), child: child),
    );
  }
}

class ViewerChoiceOption {
  const ViewerChoiceOption({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Key? key;
}

class ViewerChoiceGroup extends StatelessWidget {
  const ViewerChoiceGroup({
    super.key,
    required this.label,
    required this.options,
  });

  final String label;
  final List<ViewerChoiceOption> options;

  @override
  Widget build(BuildContext context) {
    final String selectedLabel = options
        .firstWhere(
          (ViewerChoiceOption option) => option.selected,
          orElse: () => options.first,
        )
        .label;
    return RadioGroup<String>(
      groupValue: selectedLabel,
      onChanged: (String? value) {
        if (value == null) return;
        for (final ViewerChoiceOption option in options) {
          if (option.label == value) {
            option.onPressed();
            return;
          }
        }
      },
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(label, style: const TextStyle(color: Colors.white70)),
          for (final ViewerChoiceOption option in options)
            InkWell(
              key: option.key,
              borderRadius: BorderRadius.circular(999),
              onTap: option.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Radio<String>(
                      value: option.label,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      fillColor: WidgetStateProperty.resolveWith<Color?>(
                        (Set<WidgetState> states) =>
                            option.selected ? Colors.white : Colors.white70,
                      ),
                    ),
                    Text(
                      option.label,
                      style: TextStyle(
                        color: option.selected ? Colors.white : Colors.white70,
                        fontWeight: option.selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ViewerScaleCluster extends StatelessWidget {
  const ViewerScaleCluster({
    super.key,
    required this.timeSeconds,
    required this.timeOptionsSeconds,
    required this.onTimeSelected,
    required this.rangeLabel,
    required this.rangeValue,
    required this.rangeOptions,
    required this.rangeValueText,
    required this.rangeItemText,
    required this.onRangeSelected,
    required this.spacingFactor,
    required this.spacingOptions,
    required this.onSpacingSelected,
  });

  final double timeSeconds;
  final List<double> timeOptionsSeconds;
  final ValueChanged<double> onTimeSelected;
  final String rangeLabel;
  final double rangeValue;
  final List<double> rangeOptions;
  final String Function(double value) rangeValueText;
  final String Function(double value) rangeItemText;
  final ValueChanged<double> onRangeSelected;
  final double spacingFactor;
  final List<double> spacingOptions;
  final ValueChanged<double> onSpacingSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const Text('Scale:', style: TextStyle(color: Colors.white70)),
        ViewerScalePillMenu<double>(
          label: 'Time',
          currentValue: timeSeconds,
          valueText: '${timeSeconds.toStringAsFixed(0)}s',
          tooltip: 'Time span',
          options: timeOptionsSeconds,
          itemLabelBuilder: (double option) => '${option.toStringAsFixed(0)} s',
          onSelected: onTimeSelected,
        ),
        ViewerScalePillMenu<double>(
          label: rangeLabel,
          currentValue: rangeValue,
          valueText: rangeValueText(rangeValue),
          tooltip: '$rangeLabel scale',
          options: rangeOptions,
          itemLabelBuilder: rangeItemText,
          onSelected: onRangeSelected,
        ),
        ViewerScalePillMenu<double>(
          label: 'Spacing',
          currentValue: spacingFactor,
          valueText: _factorText(spacingFactor),
          tooltip: 'Trace spacing',
          options: spacingOptions,
          itemLabelBuilder: _factorText,
          onSelected: onSpacingSelected,
        ),
      ],
    );
  }
}

String _factorText(double value) {
  return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}x';
}

class ViewerScalePillMenu<T> extends StatelessWidget {
  const ViewerScalePillMenu({
    super.key,
    required this.label,
    required this.currentValue,
    required this.valueText,
    required this.tooltip,
    required this.options,
    required this.itemLabelBuilder,
    required this.onSelected,
  });

  final String label;
  final T currentValue;
  final String valueText;
  final String tooltip;
  final List<T> options;
  final String Function(T value) itemLabelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    void stepByWheel(PointerSignalEvent event) {
      if (event is! PointerScrollEvent || options.isEmpty) return;
      final int currentIndex = options.indexOf(currentValue);
      if (currentIndex < 0) return;
      final int nextIndex = event.scrollDelta.dy > 0
          ? math.min(options.length - 1, currentIndex + 1)
          : math.max(0, currentIndex - 1);
      if (nextIndex != currentIndex) onSelected(options[nextIndex]);
    }

    return Tooltip(
      message: tooltip,
      child: Listener(
        onPointerSignal: stepByWheel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: PopupMenuButton<T>(
            tooltip: '',
            onSelected: onSelected,
            itemBuilder: (BuildContext context) => options
                .map(
                  (T option) => PopupMenuItem<T>(
                    value: option,
                    child: Text(itemLabelBuilder(option)),
                  ),
                )
                .toList(growable: false),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  '$label: $valueText',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ViewerTimeAxisBar extends StatelessWidget {
  const ViewerTimeAxisBar({
    super.key,
    required this.controller,
    required this.pixelsPerSecond,
    required this.viewportWidth,
    required this.durationSeconds,
  });

  final ScrollController controller;
  final double pixelsPerSecond;
  final double viewportWidth;
  final double durationSeconds;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final double offset = controller.hasClients ? controller.offset : 0;
          final double startSeconds = offset / pixelsPerSecond;
          final double endSeconds = (offset + viewportWidth) / pixelsPerSecond;
          final int firstTick = math.max(0, startSeconds.floor());
          final int lastTick = math.min(
            durationSeconds.ceil(),
            endSeconds.ceil(),
          );
          return Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (int second = firstTick; second <= lastTick; second++)
                  ..._timeTick(
                    second: second,
                    x: (second * pixelsPerSecond) - offset,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

List<Widget> _timeTick({required int second, required double x}) {
  const double labelWidth = 44;
  return <Widget>[
    Positioned(
      left: x - 0.5,
      top: 0,
      child: Container(
        width: 1,
        height: 8,
        color: Colors.white.withValues(alpha: 0.28),
      ),
    ),
    Positioned(
      left: x - (labelWidth / 2),
      top: 10,
      child: SizedBox(
        width: labelWidth,
        child: Text(
          '${second}s',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ),
    ),
  ];
}

class ViewerTimelineBar extends StatelessWidget {
  const ViewerTimelineBar({
    super.key,
    required this.controller,
    required this.totalWidth,
    required this.viewportWidth,
    required this.durationSeconds,
    this.accentColor = Colors.cyanAccent,
  });

  final ScrollController controller;
  final double totalWidth;
  final double viewportWidth;
  final double durationSeconds;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double barWidth = constraints.maxWidth;
              final double windowFraction = totalWidth <= 0
                  ? 1
                  : (viewportWidth / totalWidth).clamp(0.02, 1.0);
              final double thumbWidth = math.max(18, barWidth * windowFraction);
              final double maxOffset = math.max(0, totalWidth - viewportWidth);
              final double offset = controller.hasClients
                  ? controller.offset
                  : 0;
              final double normalized = maxOffset == 0
                  ? 0
                  : (offset / maxOffset).clamp(0.0, 1.0);
              final double travel = math.max(0, barWidth - thumbWidth);
              final double thumbLeft = travel * normalized;
              final double startSeconds = durationSeconds * normalized;
              final double visibleSeconds = durationSeconds * windowFraction;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (DragUpdateDetails details) {
                  if (!controller.hasClients || maxOffset == 0 || travel == 0) {
                    return;
                  }
                  final double left = (thumbLeft + details.delta.dx).clamp(
                    0.0,
                    travel,
                  );
                  controller.jumpTo((left / travel) * maxOffset);
                },
                onTapDown: (TapDownDetails details) {
                  if (!controller.hasClients || maxOffset == 0 || travel == 0) {
                    return;
                  }
                  final double left =
                      (details.localPosition.dx - (thumbWidth / 2)).clamp(
                        0.0,
                        travel,
                      );
                  controller.jumpTo((left / travel) * maxOffset);
                },
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: thumbWidth,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: <Widget>[
                            Text(
                              '${startSeconds.toStringAsFixed(1)} s',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${visibleSeconds.toStringAsFixed(1)} s window / ${durationSeconds.toStringAsFixed(1)} s total',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
