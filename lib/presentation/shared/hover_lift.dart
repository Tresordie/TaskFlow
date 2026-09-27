import 'package:flutter/material.dart';

/// v1.12.13: shared hover micro-interaction for the task items on the
/// Timeline, Calendar and Activity pages — lift + accent-tinted shadow on
/// hover, matching the Today board's TaskCard language. The [builder]
/// receives the hover state so items can also highlight their border.
class HoverLift extends StatefulWidget {
  final BorderRadius borderRadius;
  final Color accentColor;
  final EdgeInsetsGeometry margin;
  final Widget Function(BuildContext context, bool hovered) builder;

  const HoverLift({
    super.key,
    required this.borderRadius,
    required this.accentColor,
    this.margin = EdgeInsets.zero,
    required this.builder,
  });

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: widget.margin,
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -2.0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          // v1.12.22: layered elevation shadows — a diffuse lift plus a
          // tight contact shadow at rest (the classic two-layer material
          // look), intensifying with the accent glow on hover.
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.accentColor.withOpacity(0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: widget.builder(context, _hovered),
      ),
    );
  }
}
