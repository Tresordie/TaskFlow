import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/markdown/gfm_extensions.dart';
import '../../core/markdown/latex_support.dart';
import '../../core/markdown/rich_markdown.dart';
import '../../core/theme/app_colors.dart';

/// The app-wide Markdown renderer. Wraps [MarkdownBody] with every custom
/// extension the app supports — LaTeX (`$...$` / `$$...$$`), GFM tables,
/// task lists (`- [ ]` / `- [x]` as ☐ / ☑), GFM alerts (`> [!NOTE]` …),
/// underline (`++text++`), highlight (`==text==`), `<font color>` /
/// `<font size>` and `<br>` — so all screens render user content
/// identically.
///
/// The extension set is pinned to [md.ExtensionSet.none] with the
/// GitHub-flavored syntaxes re-registered manually, deliberately WITHOUT
/// `InlineHtmlSyntax`: raw-HTML pass-through would swallow `<font …>` tags
/// before [FontColorSyntax] / [FontSizeSyntax] could match them (and would
/// display the tags as literal text). The only HTML tag honoured is `<br>`,
/// via the narrow [BrSyntax].
///
/// Set [hardenLineBreaks] for free-form user input (execution logs, work
/// records) where a single newline must stay a visible line break; leave it
/// off for AI-generated content that is already properly paragraphed.
///
/// [selectable] defaults to FALSE on purpose (v1.4.26): with
/// `selectable: true` flutter_markdown emits `SelectableText.rich`, whose
/// per-block gesture detectors win the arena against the app-wide
/// SelectionArea's container gesture — the result is single-block-only
/// selection (no cross-block drag, no Ctrl+A select-all). With
/// `selectable: false` flutter_markdown emits `Text.rich`, and every `Text`
/// registers with the surrounding SelectionArea (installed in AppShell),
/// giving unified cross-block drag selection, select-all and right-click
/// copy. Link taps keep working in both modes (span TapGestureRecognizer).
class AppMarkdownBody extends StatelessWidget {
  final String data;
  final bool selectable;
  final bool hardenLineBreaks;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownTapLinkCallback? onTapLink;

  const AppMarkdownBody({
    super.key,
    required this.data,
    this.selectable = false,
    this.hardenLineBreaks = false,
    this.styleSheet,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyLarge;

    // v1.5.3: table styling rides the style sheet so BOTH the caller's
    // custom sheet and the default keep the same look — bold header,
    // theme-derived borders, padded cells.
    final merged = MarkdownStyleSheet.fromTheme(theme).merge(styleSheet);
    final sheet = merged.copyWith(
      tableHead:
          (merged.tableHead ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
      ),
      tableBorder: TableBorder.all(
        color: theme.colorScheme.outlineVariant,
        width: 1,
      ),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    );

    return MarkdownBody(
      data: GfmExtensions.prepare(data, hardenLineBreaks: hardenLineBreaks),
      selectable: selectable,
      styleSheet: sheet,
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: GfmExtensions.blockSyntaxes,
      inlineSyntaxes: [
        // v1.5.0 lesson (pitfall 8.14): custom rich syntaxes MUST precede
        // StrikethroughSyntax — the package's strikethrough greedily
        // consumes single-tilde runs and would otherwise eat `~subscript~`
        // before our syntax sees it.
        ...RichMarkdown.syntaxes(),
        ...LatexMarkdown.syntaxes(),
        ...GfmExtensions.inlineSyntaxes(),
        md.StrikethroughSyntax(),
        md.AutolinkExtensionSyntax(),
      ],
      builders: {
        ...LatexMarkdown.builders(baseStyle),
        ...RichMarkdown.builders(baseStyle),
        // v1.5.3: GFM alerts render as themed containers. The builder
        // re-renders the alert body from its preserved source so rich
        // content (lists, math, inline styles) survives inside the box —
        // flutter_markdown hands a builder NO access to the already-built
        // children of the element it replaces.
        'div': _DivDispatchBuilder(
          hardenLineBreaks: hardenLineBreaks,
          styleSheet: sheet,
        ),
        // (No 'input' builder: the hoisted checkbox at li.children[0] is
        // still VISITED as an inline node, so a builder here would render
        // a second ☐ / ☑ next to the checkboxBuilder bullet. Unknown
        // inline elements emit nothing, which is exactly right.)
      },
      // v1.5.3: task lists — the hoist syntaxes (GfmExtensions) put the
      // checkbox at the <li>'s first child, so flutter_markdown's list
      // builder takes its checkbox path; skin it as ☐ / ☑ (read-only).
      checkboxBuilder: (checked) => _CheckboxGlyph(checked: checked),
      onTapLink: onTapLink,
    );
  }
}

/// ☐ / ☑ glyphs for task lists. `FontStack`'s fallback chain (Segoe UI
/// Emoji and friends) guarantees the glyphs on Windows; ☑ takes the theme
/// primary color so a checked item reads at a glance.
class _CheckboxGlyph extends StatelessWidget {
  final bool checked;

  const _CheckboxGlyph({required this.checked});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        checked ? '☑' : '☐',
        style: TextStyle(
          fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 14) * 0.95,
          color: checked
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withOpacity(0.55),
        ),
      ),
    );
  }
}

/// Handles every `div` element: GFM alerts (`div.markdown-alert-*`,
/// v1.5.3) get a themed container; anything else (the footnotes appendix
/// `div.footnotes`) falls through to [FootnoteDefBuilder].
class _DivDispatchBuilder extends MarkdownElementBuilder {
  final bool hardenLineBreaks;
  final MarkdownStyleSheet? styleSheet;

  _DivDispatchBuilder({required this.hardenLineBreaks, this.styleSheet});

  final FootnoteDefBuilder _footnotes = FootnoteDefBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final type = alertTypeOf(element);
    if (type == null) {
      return _footnotes.visitElementAfter(element, preferredStyle);
    }

    final theme = Theme.of(context);
    final accent = AppColors.alertAccent(type, theme.brightness);
    final source = element.attributes['data-source'] ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.alertBackground(type, theme.brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: accent, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            type.toUpperCase(),
            style: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.6,
            ),
          ),
          if (source.trim().isNotEmpty)
            // Re-render the alert body with the SAME extension set so rich
            // content (bold, lists, math, links) renders exactly like the
            // surrounding document. The inner body keeps harden parity with
            // the outer one (free-form vs. AI content).
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: AppMarkdownBody(
                data: source,
                hardenLineBreaks: hardenLineBreaks,
                styleSheet: styleSheet,
              ),
            ),
        ],
      ),
    );
  }
}
