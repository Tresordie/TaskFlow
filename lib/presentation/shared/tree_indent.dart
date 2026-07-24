import 'package:flutter/material.dart';

/// Wraps [child] with [depth] levels of vertical indent guide lines so a
/// flat sub-step list renders as a visual tree. Each level adds a thin
/// left rail; consecutive sibling rows produce a near-continuous line.
/// Depth 0 returns the child unchanged.
Widget wrapWithTreeGuides(
  Widget child, {
  required int depth,
  required Color guideColor,
}) {
  Widget result = child;
  for (var level = 0; level < depth; level++) {
    result = Padding(
      padding: const EdgeInsets.only(left: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: guideColor, width: 1.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: result,
        ),
      ),
    );
  }
  return result;
}
