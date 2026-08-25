import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/font_stack.dart';

/// v1.4.85: separate, persisted typography controls for the two text
/// realms of the app:
///
///  * CONTENT — rendered records / notes / summaries / previews
///  * INPUT   — editor fields (Write mode, raw note input)
///
/// Each offers an optional font family (null = follow the global app font)
/// and an optional base font size (null = app defaults). Settings live in
/// Settings → "Content Font" / "Input Font" cards.

class AreaTypography {
  /// null = inherit the global app font.
  final String? family;

  /// Base body font size in logical pixels; null = app default.
  final double? size;

  const AreaTypography({this.family, this.size});

  static const AreaTypography defaults = AreaTypography();
}

abstract class _AreaTypographyNotifier extends StateNotifier<AreaTypography> {
  final String _familyKey;
  final String _sizeKey;

  _AreaTypographyNotifier(this._familyKey, this._sizeKey)
      : super(AreaTypography.defaults) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final family = prefs.getString(_familyKey);
      final size = prefs.getDouble(_sizeKey);
      state = AreaTypography(
        family: (family == null || family.isEmpty) ? null : family,
        size: size,
      );
    } catch (_) {}
  }

  void setFamily(String? family) {
    state = AreaTypography(
      family: (family == null || family.isEmpty) ? null : family,
      size: state.size,
    );
    _persist();
  }

  void setSize(double? size) {
    state = AreaTypography(family: state.family, size: size);
    _persist();
  }

  void reset() {
    state = AreaTypography.defaults;
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state.family == null) {
        await prefs.remove(_familyKey);
      } else {
        await prefs.setString(_familyKey, state.family!);
      }
      if (state.size == null) {
        await prefs.remove(_sizeKey);
      } else {
        await prefs.setDouble(_sizeKey, state.size!);
      }
    } catch (_) {}
  }
}

final contentTypographyProvider =
    StateNotifierProvider<ContentTypographyNotifier, AreaTypography>(
        (ref) => ContentTypographyNotifier());

class ContentTypographyNotifier extends _AreaTypographyNotifier {
  ContentTypographyNotifier() : super('settings.contentFont', 'settings.contentSize');
}

final inputTypographyProvider =
    StateNotifierProvider<InputTypographyNotifier, AreaTypography>(
        (ref) => InputTypographyNotifier());

class InputTypographyNotifier extends _AreaTypographyNotifier {
  InputTypographyNotifier() : super('settings.inputFont', 'settings.inputSize');
}

/// Applies the user's CONTENT typography to a [MarkdownStyleSheet]: the base
/// paragraph size drives every other block proportionally, and the family
/// (when set) overrides every style. Used by every record / note / summary
/// renderer and every input Preview so the whole realm stays consistent.
MarkdownStyleSheet applyContentTypography(
    BuildContext context, MarkdownStyleSheet sheet) {
  final AreaTypography typo;
  try {
    typo = ProviderScope.containerOf(context, listen: false)
        .read(contentTypographyProvider);
  } catch (_) {
    return sheet; // no ProviderScope (e.g. bare widget tests)
  }
  if (typo.family == null && typo.size == null) return sheet;

  final baseSize = typo.size ?? sheet.p?.fontSize ?? 13.0;
  final family = typo.family;

  TextStyle fix(TextStyle? s, double size, {FontWeight? weight}) {
    // v1.5.2 (D5 fix): a family override MUST carry the CJK fallback
    // chain — fontFamily alone would drop Chinese glyphs onto the system
    // default and break mixed-layout gray uniformity.
    var out = (s ?? const TextStyle()).copyWith(
      fontSize: size,
      fontFamily: family ?? s?.fontFamily,
      fontFamilyFallback:
          family != null ? FontStack.fallback : s?.fontFamilyFallback,
    );
    if (weight != null) out = out.copyWith(fontWeight: weight);
    return out;
  }

  return sheet.copyWith(
    p: fix(sheet.p, baseSize),
    h1: fix(sheet.h1, baseSize + 3.5, weight: FontWeight.w700),
    h2: fix(sheet.h2, baseSize + 1.5, weight: FontWeight.w700),
    h3: fix(sheet.h3, baseSize + 0.5, weight: FontWeight.w600),
    h4: fix(sheet.h4, baseSize, weight: FontWeight.w600),
    h5: fix(sheet.h5, baseSize, weight: FontWeight.w600),
    h6: fix(sheet.h6, baseSize - 0.5, weight: FontWeight.w600),
    em: fix(sheet.em, baseSize),
    strong: fix(sheet.strong, baseSize),
    del: fix(sheet.del, baseSize),
    blockquote: fix(sheet.blockquote, baseSize),
    code: fix(sheet.code, baseSize - 1),
    tableHead: fix(sheet.tableHead, baseSize - 0.5, weight: FontWeight.w700),
    tableBody: fix(sheet.tableBody, baseSize - 1),
  );
}

/// Resolves the style of an INPUT editor field: the user's input typography
/// overrides family / size when set, otherwise the caller's style survives.
TextStyle applyInputTypography(BuildContext context, TextStyle base) {
  final AreaTypography typo;
  try {
    typo = ProviderScope.containerOf(context, listen: false)
        .read(inputTypographyProvider);
  } catch (_) {
    return base; // no ProviderScope (e.g. bare widget tests)
  }
  // v1.5.2 (D5 fix): family overrides always carry the CJK fallback chain.
  return base.copyWith(
    fontFamily: typo.family ?? base.fontFamily,
    fontSize: typo.size ?? base.fontSize,
    fontFamilyFallback:
        typo.family != null ? FontStack.fallback : base.fontFamilyFallback,
  );
}
