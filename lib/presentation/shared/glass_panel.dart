import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// v1.12.5: shared frosted-glass wrapper for app-shell panels. When [glass]
/// is on the child is clipped to [borderRadius] and wrapped in a
/// [BackdropFilter] so the ambient backdrop behind the shell blurs through;
/// the child itself paints the translucent fill (theme surface colors are
/// made translucent by AppTheme.buildTheme when glass is on). When off, the
/// child renders untouched — the historic opaque look.
class GlassPanel extends StatelessWidget {
  final bool glass;
  final double blur;
  final BorderRadius borderRadius;
  final Widget child;

  const GlassPanel({
    super.key,
    required this.glass,
    this.blur = 14,
    this.borderRadius = BorderRadius.zero,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!glass) return child;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }
}
