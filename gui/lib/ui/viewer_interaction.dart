import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ViewerScrollIntent {
  verticalPan,
  horizontalPan,
  timeZoom,
  amplitudeZoom,
}

class ViewerScrollGesture {
  const ViewerScrollGesture({
    required this.intent,
    required this.delta,
    required this.localPosition,
  });

  final ViewerScrollIntent intent;
  final Offset delta;
  final Offset localPosition;

  double get primaryDelta {
    if (intent == ViewerScrollIntent.horizontalPan) {
      return delta.dy == 0 ? delta.dx : delta.dy;
    }
    return delta.dy;
  }

  bool get zoomingIn => primaryDelta < 0;
}

ViewerScrollGesture? viewerScrollGestureFromPointerSignal(
  PointerSignalEvent event,
) {
  if (event is! PointerScrollEvent) {
    return null;
  }
  final Set<LogicalKeyboardKey> keys =
      HardwareKeyboard.instance.logicalKeysPressed;
  final bool shiftPressed = keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
  final bool controlPressed = keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight) ||
      keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight);
  final bool altPressed = keys.contains(LogicalKeyboardKey.altLeft) ||
      keys.contains(LogicalKeyboardKey.altRight);

  final ViewerScrollIntent intent;
  if (controlPressed) {
    intent = ViewerScrollIntent.timeZoom;
  } else if (altPressed) {
    intent = ViewerScrollIntent.amplitudeZoom;
  } else if (shiftPressed || event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()) {
    intent = ViewerScrollIntent.horizontalPan;
  } else {
    intent = ViewerScrollIntent.verticalPan;
  }
  return ViewerScrollGesture(
    intent: intent,
    delta: event.scrollDelta,
    localPosition: event.localPosition,
  );
}

void scrollControllerBy(ScrollController controller, double delta) {
  if (!controller.hasClients) {
    return;
  }
  controller.jumpTo(
    (controller.offset + delta).clamp(
      0.0,
      controller.position.maxScrollExtent,
    ),
  );
}

double viewerZoomFactor({
  required bool zoomingIn,
  double inFactor = 1.18,
  double outFactor = 0.85,
}) {
  return zoomingIn ? inFactor : outFactor;
}
