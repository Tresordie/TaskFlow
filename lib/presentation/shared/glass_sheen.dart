import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// v1.12.33: the specular layer shared by every iOS-style glass surface on the
/// Today dashboard (task cards, KPI stat cards, quick-add bar).
///
/// Apple's liquid glass reads as a lit slab: light lands on the top face and
/// the bottom edge catches a thin refraction highlight. One gradient does the
/// top wash, a second does the bottom rim, and both sit UNDER the content
/// inside an [IgnorePointer] so text stays crisp and hit-testing is untouched.
///
/// Hosts paint it as the first child of a Stack that is already clipped to
/// the same corner radius as the glass fill.
class GlassSheen extends StatelessWidget {
  /// Corner radius of the glass surface this sheen is clipped into.
  final double borderRadius;

  /// Alpha of the top wash (light from above).
  /// v1.12.34: dialed back from 0.32 — a strong wash plus a bright bottom rim
  /// read as a curved lens bulging out of the card (user: 弯曲立体感太强).
  /// Glass should be a flat lit slab: a whisper of top light, no bottom glow.
  final double topAlpha;

  /// Alpha of the bottom refraction rim (0 = off).
  final double bottomAlpha;

  /// Where the top wash fades out (fraction of the surface height).
  /// v1.12.34: fades sooner (0.45) so the light stays a thin edge glow rather
  /// than a gradient across the whole face.
  final double topFade;

  /// Alpha of the 1px inner rim light (0 = off). A bright inner edge is the
  /// other half of what makes a slab read as glass rather than as a
  /// translucent rectangle.
  final double rimAlpha;

  /// Render as a `Positioned.fill` (the default, for direct Stack children).
  /// Hosts that need their own positioning/clipping pass false and take the
  /// bare visual from [build].
  final bool asPositioned;

  const GlassSheen({
    super.key,
    this.borderRadius = 14,
    this.topAlpha = 0.14,
    this.bottomAlpha = 0.03,
    this.topFade = 0.45,
    this.rimAlpha = 0.0,
    this.asPositioned = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final layer = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: gradient,
        ),
        child: rimAlpha > 0
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular((borderRadius - 1).clamp(0, 999)),
                  border: Border.all(
                    color: Colors.white.withOpacity(rimAlpha),
                    width: 1,
                  ),
                ),
              )
            : null,
      ),
    );
    if (!asPositioned) return layer;
    return Positioned.fill(child: layer);
  }

  /// The specular gradient itself, exposed so hosts that already paint a
  /// translucent fill in a `BoxDecoration` (the quick-add bar) can use the
  /// identical recipe instead of a second Stack layer.
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(topAlpha),
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(bottomAlpha),
        ],
        stops: [0.0, topFade, 1.0],
      );

  /// [base] (a translucent glass fill) with the specular profile composited
  /// over it — the same wash [GlassSheen] paints, folded into the fill.
  static LinearGradient fillOver(Color base,
      {double topAlpha = 0.14,
      double bottomAlpha = 0.03,
      double topFade = 0.45}) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.alphaBlend(Colors.white.withOpacity(topAlpha), base),
        base,
        Color.alphaBlend(Colors.white.withOpacity(bottomAlpha), base),
      ],
      stops: [0.0, topFade, 1.0],
    );
  }
}

/// v1.12.35: the frosted-glass shell shared by every glass surface on the
/// Today dashboard (task cards, KPI stat strip). One place owns the recipe:
/// clip → backdrop blur → translucent fill → [GlassSheen] specular → content.
///
/// It also pins [content] to the surface's full width, and that is load-bearing.
/// A [Stack] sizes itself to its non-positioned children under *loosened*
/// constraints, so the moment a host wraps its content in this shell the
/// content's `Positioned(right: …)` children stop resolving against the card and
/// start resolving against the text column — which is exactly how the KPI
/// accent icon ended up printed over "IN PROGRESS" (v1.12.34, user screenshot).
/// The shell is the only place those constraints get loosened, so it is the only
/// place that has to undo it.
class GlassSurface extends StatelessWidget {
  /// Corner radius of the clip, the fill and the inner rim light.
  final double borderRadius;

  /// Backdrop blur sigma (user-adjustable via the glass style settings).
  final double blur;

  /// Opaque-ish fill under the content; use [color] or [gradient].
  final Color? color;
  final Gradient? gradient;

  /// Inner rim light. Null paints no rim at all.
  final double? rimAlpha;

  final Widget content;

  const GlassSurface({
    super.key,
    this.borderRadius = 14,
    this.blur = 14,
    this.color,
    this.gradient,
    this.rimAlpha,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    assert(color == null || gradient == null,
        'GlassSurface takes either a fill color or a fill gradient');
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration:
              BoxDecoration(color: color, gradient: gradient, borderRadius: radius),
          child: Stack(
            children: [
              // Specular layer behind the content: text stays crisp and
              // hit-testing is untouched (GlassSheen is Positioned.fill).
              if (rimAlpha != null)
                GlassSheen(borderRadius: borderRadius, rimAlpha: rimAlpha!),
              SizedBox(width: double.infinity, child: content),
            ],
          ),
        ),
      ),
    );
  }
}
