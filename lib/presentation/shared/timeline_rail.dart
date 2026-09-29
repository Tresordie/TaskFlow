import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// v1.12.39: ONE timeline rail shared by the Timeline page and the task
/// Execution Log, so both read as the same design system instead of two
/// hand-drawn variants.
///
/// Three layers give it depth (the "carved channel" look):
/// 1. a recessed groove the event sits in;
/// 2. a soft accent-coloured light bleed behind the connector;
/// 3. a crisp gradient core that fades toward the next event.
///
/// The node is a glyph chip: surface fill + accent ring + accent glow, so the
/// emoji stays readable instead of becoming a flat dot.
///
/// Alignment contract: the node always sits exactly [nodeInset] logical pixels
/// below the top of the row, whether it is the first event of a group or not —
/// so a label placed beside the spine (the time column, the log meta row) can
/// centre itself on the node with [nodeCenterY]. The rail must live in a row
/// that resolves a definite height (IntrinsicHeight + a stretched sibling),
/// which is how both pages build their rows.
class TimelineRail extends StatelessWidget {
  /// Width of the recessed groove column.
  final double grooveWidth;

  /// The event marker (usually [TimelineNode]).
  final Widget node;

  /// Accent colour for the connector and the node ring/glow.
  final Color accentColor;

  /// Last event of the run: draws a short fading tail instead of a full
  /// connector so the line ends cleanly instead of running on.
  final bool isLast;

  const TimelineRail({
    super.key,
    this.grooveWidth = 26,
    required this.node,
    required this.accentColor,
    this.isLast = false,
  });

  /// Width of the groove's hairline border — it insets the column, so it
  /// counts toward where the node lands.
  static const double grooveBorderWidth = 1;

  /// Distance from the top of the row to the top of the node.
  static const double nodeInset = grooveBorderWidth + 8;

  /// Diameter of a normal / emphasized node (mirrors [TimelineNode]).
  static const double nodeDiameter = 22;
  static const double nodeDiameterEmphasized = 26;

  /// Vertical centre of the node inside the row — side labels align to this.
  static double nodeCenterY({bool emphasized = false}) =>
      nodeInset + (emphasized ? nodeDiameterEmphasized : nodeDiameter) / 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: grooveWidth,
      child: Container(
        width: grooveWidth,
        decoration: BoxDecoration(
          // Recessed channel: a touch darker at the top, a lit hairline
          // toward the bottom — the carved look.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // v1.12.42: the old light recipe ended in 50% WHITE, which
            // rendered as a bright blob on a paper canvas. A recessed
            // channel on light is just a touch of ink.
            colors: isDark
                ? [
                    Colors.white.withOpacity(0.045),
                    Colors.black.withOpacity(0.10),
                  ]
                : [
                    Colors.black.withOpacity(
                        AppColors.grooveFillOpacity(Brightness.light)),
                    Colors.black.withOpacity(
                        AppColors.grooveFillOpacity(Brightness.light) * 0.55),
                  ],
            stops: const [0.0, 0.75],
          ),
          borderRadius: BorderRadius.circular(grooveWidth / 2),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(isDark ? 0.14 : 0.55),
          ),
        ),
        child: Column(
          // A group-ending rail hugs its own content: without this the groove
          // stretches down the whole row and leaves an empty channel under the
          // fading tail.
          mainAxisSize: isLast ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8), // + the 1px groove border = nodeInset
            node,
            if (isLast)
              // Terminating tail: short, fading out downward.
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Container(
                  width: 2,
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accentColor.withOpacity(0.28),
                        accentColor.withOpacity(0.0),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: _Connector(accentColor: accentColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Soft light bleed + crisp core: two stacked gradients read as one lit line.
class _Connector extends StatelessWidget {
  final Color accentColor;

  const _Connector({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accentColor.withOpacity(0.10),
                  accentColor.withOpacity(0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Container(
            width: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accentColor.withOpacity(0.38),
                  accentColor.withOpacity(0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Event marker for a [TimelineRail]: an accent-ringed chip carrying a glyph.
///
/// Pass [glyph] for emoji (status / entry type), or [icon] for a Material
/// glyph. [emphasized] grows the chip and its glow — used for the newest log
/// entry so "where am I now" is obvious at a glance.
class TimelineNode extends StatelessWidget {
  final String? glyph;
  final IconData? icon;
  final Color accentColor;
  final bool emphasized;

  const TimelineNode({
    super.key,
    this.glyph,
    this.icon,
    required this.accentColor,
    this.emphasized = false,
  });

  double get _diameter => emphasized
      ? TimelineRail.nodeDiameterEmphasized
      : TimelineRail.nodeDiameter;

  double get _glyphSize => emphasized ? 14 : 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = _diameter;
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          // Filled with the card surface so the ring + glyph stay legible on
          // any page background.
          color: theme.colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: accentColor.withOpacity(emphasized ? 0.85 : 0.55),
            width: emphasized ? 2.4 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(emphasized ? 0.38 : 0.22),
              blurRadius: emphasized ? 12 : 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: icon != null
              ? Icon(icon,
                  size: _glyphSize,
                  color: accentColor.withOpacity(emphasized ? 1.0 : 0.9))
              : Text(
                  glyph ?? '',
                  style: TextStyle(fontSize: _glyphSize, height: 1.0),
                ),
        ),
      ),
    );
  }
}
