import 'package:flutter/material.dart';

/// v1.12.23: the Today-TaskCard skin in miniature, shared by the Timeline,
/// Calendar and Activity lists — a bright theme-aware card fill with a
/// subtle top-lit gradient, a left accent bar that fades toward the
/// bottom, and a border that highlights on hover (the lift/shadow come
/// from the wrapping HoverLift).
class TaskListCard extends StatelessWidget {
  final Color accentColor;
  final bool highlighted;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const TaskListCard({
    super.key,
    required this.accentColor,
    required this.highlighted,
    required this.borderRadius,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.cardTheme.color ?? theme.colorScheme.surface;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        // Top-lit fill: a whisper of white toward the top edge gives the
        // card a lit, slightly domed surface.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(Colors.white.withOpacity(0.05), base),
            base,
          ],
        ),
        borderRadius: borderRadius,
        border: Border.all(
          color: highlighted
              ? accentColor.withOpacity(0.5)
              : theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      // v1.12.24: IntrinsicHeight bounds the stretch Row so the card also
      // renders inside UNBOUNDED-height containers (ListView day panels,
      // non-scrolling columns) — without it the stretched bar + Expanded
      // collapsed to nothing and the task list appeared empty.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent bar, fading downward — the Today TaskCard
            // signature.
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accentColor,
                    accentColor.withOpacity(0.30),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
