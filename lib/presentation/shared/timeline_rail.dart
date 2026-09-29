import 'package:flutter/material.dart';

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
/// emoji/status icon stays readable instead of becoming a flat dot.
/// [height] lets the caller cap the connector when the rail is not inside an
/// IntrinsicHeight row (see TimelineScreen's origin marker).
class TimelineRail extends StatelessWidget {
  /// Width of the recessed groove column.
  final double grooveWidth;

  /// The event marker (usually [TimelineNode]).
  final Widget node;

  /// Accent colour for the connector and the node ring/glow.
  final Color accentColor;

  /// Last event in the list: draws a short fading tail instead of a full
  /// connector so the line ends cleanly.
  final bool isLast;

  /// First event of a run: draws a short fading stub ABOVE the node so the
  /// spine starts as a soft origin instead of a hard cut.
  final bool capTop;

  /// Fixed rail height, or null to stretch with the sibling content
  /// (requires unbounded-height-safe parent + IntrinsicHeight).
  final double? height;

  const TimelineRail({
    super.key,
    this.grooveWidth = 26,
    required this.node,
    required this.accentColor,
    this.isLast = false,
    this.capTop = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: grooveWidth,
      height: height,
      child: _column(theme, isDark),
    );
  }

  Widget _column(ThemeData theme, bool isDark) {
    // Recessed channel: a touch darker than the page at the top, lighter
    // hairline at the bottom-left edge — the carved look.
    return Container(
      width: grooveWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withOpacity(0.045),
                  Colors.black.withOpacity(0.10),
                ]
              : [
                  Colors.black.withOpacity(0.030),
                  Colors.white.withOpacity(0.50),
                ],
          stops: const [0.0, 0.75],
        ),
        borderRadius: BorderRadius.circular(grooveWidth / 2),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(isDark ? 0.14 : 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (capTop)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 2,
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        accentColor.withOpacity(0.30),
                        accentColor.withOpacity(0.0),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          node,
          if (isLast)
            // Terminating tail: short, fading out downward.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Align(
                  alignment: Alignment.topCenter,
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

  double get _diameter => emphasized ? 26 : 22;

  double get _glyphSize => emphasized ? 14 : 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = _diameter;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            // Filled with the card surface so the ring + glyph stay legible
            // on any page background.
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
      ),
    );
  }
}
