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
class AppMarkdownBody extends StatelessWidget {
  final String data;
  final bool selectable;
  final bool hardenLineBreaks;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownTapLinkCallback? onTapLink;

  const AppMarkdownBody({
    super.key,
    required this.data,
    this.selectable = true,
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
        md.FootnoteDefSyntax(),
      ],
      inlineSyntaxes: [
        md.StrikethroughSyntax(),
        md.AutolinkExtensionSyntax(),
        ...LatexMarkdown.syntaxes(),
        ...RichMarkdown.syntaxes(),
      ],
      builders: {
        ...LatexMarkdown.builders(baseStyle),
        ...RichMarkdown.builders(baseStyle),
      },
      onTapLink: onTapLink,
    );
  }
}
