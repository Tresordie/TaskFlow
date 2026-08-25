/// The single source of truth for the app's Chinese-English font stack
/// (v1.5.2 font upgrade).
///
/// Order matters — Flutter resolves glyphs per-character against this
/// chain:
///  1. Manrope (Latin primary: letters, ASCII digits, half-width
///     punctuation),
///  2. MiSans (CJK: Chinese characters + full-width punctuation),
///  3. HarmonyOS Sans SC (bundled CJK safety net),
///  4. system CJK faces (YaHei / PingFang),
///  5. Segoe UI Emoji (explicit emoji owner — referencing the OS font is
///     not redistribution, it just pins the existing implicit behavior).
///
/// NEVER set only `fontFamily` on a text style that may render Chinese —
/// always pair it with this fallback chain (rule of the v1.5.2 upgrade).
class FontStack {
  FontStack._();

  /// Latin primary bundled with the app.
  static const String latin = 'Manrope';

  /// CJK primary bundled with the app.
  static const String cjk = 'MiSans';

  /// The shared fallback chain used everywhere mixed text can appear.
  static const List<String> fallback = [
    'MiSans',
    'HarmonyOS Sans SC',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Segoe UI Emoji',
    'sans-serif',
  ];

  /// Fallback chain for pairing presets whose CJK half is [cjkFamily]
  /// (the paired family leads, then the bundled safety nets).
  static List<String> pairingFallback(String cjkFamily) => [
        cjkFamily,
        'HarmonyOS Sans SC',
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'PingFang SC',
        'Segoe UI Emoji',
        'sans-serif',
      ];
}
