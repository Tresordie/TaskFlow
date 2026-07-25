import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Lets the mouse wheel scroll the page's main list even when the pointer is
/// over a fixed, non-scrollable region such as a page header, toolbar or the
/// quick-add bar.
///
/// Most screens pin a header above an [Expanded] scrollable list. By default
/// the wheel only scrolls while the pointer is directly over that list, so
/// scrolling right after using the header controls appears to "do nothing".
/// Wrapping the fixed top region in this widget forwards wheel events to the
/// surrounding [PrimaryScrollController] — which the page's list attaches to
/// automatically because it has no explicit controller of its own.
///
/// Only wrap non-scrollable areas: wrapping a region that already contains a
/// scrollable would double-scroll it (both this listener and the scrollable
/// would consume the same wheel event).
class WheelForward extends StatelessWidget {
  final Widget child;

  const WheelForward({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Resolve during build so the inherited-widget dependency is registered
    // correctly; the handler below just uses the captured controller.
    final controller = PrimaryScrollController.maybeOf(context);
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (controller == null || !controller.hasClients) return;
        final pos = controller.position;
        if (pos.maxScrollExtent <= pos.minScrollExtent) return;
        final next = (pos.pixels + event.scrollDelta.dy)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
        controller.jumpTo(next);
      },
      child: child,
    );
  }
}
