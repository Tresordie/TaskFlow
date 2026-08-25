import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/markdown/latex_support.dart';
import '../../core/markdown/line_breaks.dart';
import '../../core/markdown/rich_markdown.dart';

/// The app-wide Markdown renderer. Wraps [MarkdownBody] with every custom
/// extension the app supports — LaTeX (`$...$` / `$$...$$`), underline
/// (`++text++`), highlight (`==text==`), `<font color>` and `<font size>` —
/// so all screens render user content identically.
///
/// The extension set is pinned to [md.ExtensionSet.none] with the
/// GitHub-flavored syntaxes re-registered manually, deliberately WITHOUT
/// `InlineHtmlSyntax`: raw-HTML pass-through would swallow `<font …>` tags
/// before [FontColorSyntax] / [FontSizeSyntax] could match them (and would
/// display the tags as literal text).
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
    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    return MarkdownBody(
      data: hardenLineBreaks ? hardenMarkdownLineBreaks(data) : data,
      selectable: selectable,
      styleSheet: styleSheet,
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: const [
        md.FencedCodeBlockSyntax(),
        md.TableSyntax(),
        md.UnorderedListWithCheckboxSyntax(),
        md.OrderedListWithCheckboxSyntax(),
        // v1.5.0: footnotes — definitions (`[^1]: text`) are collected and
        // emitted as a trailing appendix; the matching `[^1]` references
        // are turned into sup markers automatically by the link syntax.
        md.FootnoteDefSyntax(),
      ],
      inlineSyntaxes: [
        // v1.5.0: custom rich syntaxes MUST precede StrikethroughSyntax —
        // the package's strikethrough greedily consumes single-tilde runs
        // and would otherwise eat `~subscript~` before our syntax sees it.
        ...RichMarkdown.syntaxes(),
        ...LatexMarkdown.syntaxes(),
        md.StrikethroughSyntax(),
        md.AutolinkExtensionSyntax(),
      ],
      builders: {
        ...LatexMarkdown.builders(baseStyle),
        ...RichMarkdown.builders(baseStyle),
      },
      onTapLink: onTapLink,
    );
  }
}
