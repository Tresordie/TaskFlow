import 'package:markdown/markdown.dart' as md;

import 'latex_support.dart';
import 'line_breaks.dart';
import 'table_support.dart';

/// GFM extension wiring shared by BOTH rendering chains — the block-level
/// [AppMarkdownBody] (flutter_markdown) and the flattened
/// [SelectableMarkdownBody] — plus the source-preparation pipeline that
/// feeds them. Registering the same syntaxes in both keeps the input
/// Preview and the saved-record display on one WYSIWYG contract (v1.5.3:
/// GFM tables, task lists, alerts, LaTeX).
class GfmExtensions {
  GfmExtensions._();

  /// Block syntaxes for both chains. [GfmAlertSyntax] comes first: custom
  /// block syntaxes are tried before the package defaults (so it wins
  /// over `BlockquoteSyntax` for `> [!TYPE]` openers), and alerts must be
  /// matched before any generic blockquote handling kicks in.
  static final List<md.BlockSyntax> blockSyntaxes = [
    GfmAlertSyntax(),
    const md.FencedCodeBlockSyntax(),
    const md.TableSyntax(),
    const TaskListUnorderedSyntax(),
    const TaskListOrderedSyntax(),
    const md.FootnoteDefSyntax(),
  ];

  /// Inline syntaxes for both chains. The custom syntaxes MUST precede
  /// `StrikethroughSyntax` in the registration order (pitfall 8.14) — the
  /// package's strikethrough greedily consumes single-tilde runs.
  static List<md.InlineSyntax> inlineSyntaxes() => [BrSyntax()];

  /// Normalises raw user/AI markdown before parsing:
  ///  1. multi-line `$$` blocks are joined onto one line (the inline LaTeX
  ///     syntax only matches single-line `$$…$$`);
  ///  2. multi-line pipe-table rows are merged back into single rows
  ///     (pitfall 8.10 — AI models break table cells across lines);
  ///  3. optionally hardens single newlines into hard breaks for free-form
  ///     user input (table rows / alert openers / `$$` lines are exempt —
  ///     see [hardenMarkdownLineBreaks]).
  static String prepare(String data, {required bool hardenLineBreaks}) {
    var out = flattenDisplayMath(data);
    out = normalizeMultilineTableRows(out);
    if (hardenLineBreaks) out = hardenMarkdownLineBreaks(out);
    return out;
  }
}

/// Case-sensitive GitHub-flavoured alert opener: `> [!NOTE]` /
/// `[!TIP]` / `[!IMPORTANT]` / `[!WARNING]` / `[!CAUTION]` (uppercase,
/// exact, per the GFM spec).
final gfmAlertPattern = RegExp(
  r'^\s{0,3}>\s{0,3}\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$',
);

/// The five canonical GFM alert types (lowercase, AST attribute form).
const gfmAlertTypes = ['note', 'tip', 'important', 'warning', 'caution'];

/// Returns the alert type ('note' | 'tip' | 'important' | 'warning' |
/// 'caution') of a `div` element emitted by [GfmAlertSyntax], or null for
/// any other element (e.g. the footnotes appendix `div`).
String? alertTypeOf(md.Element el) {
  if (el.tag != 'div') return null;
  final cls = el.attributes['class'] ?? '';
  if (!cls.contains('markdown-alert')) return null;
  return el.attributes['data-alert'];
}

/// Parses GFM alert blocks (`> [!TYPE]`). Adapted from the package's
/// `AlertBlockSyntax` (markdown 7.3.1) with two deliberate differences:
///  * the type match is CASE-SENSITIVE (GitHub's spec requires uppercase);
///  * no synthetic title paragraph is emitted — each renderer draws its own
///    type label, and the raw alert type travels on `data-alert`.
///
/// The element carries the inner content as regular children AND the
/// original alert body (leading `>` stripped) in `data-source`, so the
/// block-level renderer can re-render the rich content (lists, math,
/// inline styles) inside a themed container.
class GfmAlertSyntax extends md.BlockSyntax {
  GfmAlertSyntax();

  static final _contentLineRegExp = RegExp(r'>?\s?(.*)*');
  // Local mirrors of the package-private codeFencePattern / indentPattern.
  static final _codeFenceRe = RegExp(r'^ {0,3}(?:`{3,}|~{3,})');
  static final _indentRe = RegExp(r'^(?:    | {0,3}\t)');

  bool _lazyContinuation = false;

  @override
  RegExp get pattern => gfmAlertPattern;

  @override
  bool canParse(md.BlockParser parser) =>
      pattern.hasMatch(parser.current.content);

  @override
  List<md.Line> parseChildLines(md.BlockParser parser) {
    // Grab all of the lines that form the alert, stripping off the ">".
    final childLines = <md.Line>[];
    _lazyContinuation = false;

    while (!parser.isDone) {
      final lineContent = parser.current.content.trimLeft();
      final strippedContent = lineContent.replaceFirst(RegExp(r'^>?\s*'), '');
      final match = strippedContent.isEmpty && !lineContent.startsWith('>')
          ? null
          : _contentLineRegExp.firstMatch(strippedContent);
      if (match != null) {
        childLines.add(md.Line(strippedContent));
        parser.advance();
        _lazyContinuation = false;
        continue;
      }

      final lastLine = childLines.isEmpty ? md.Line('') : childLines.last;

      // A paragraph continuation is OK (lazy continuation, CommonMark
      // 0.30 definition).
      final otherMatched =
          parser.blockSyntaxes.firstWhere((s) => s.canParse(parser));
      if ((otherMatched is md.ParagraphSyntax &&
              !lastLine.isBlankLine &&
              !_codeFenceRe.hasMatch(lastLine.content)) ||
          (otherMatched is md.CodeBlockSyntax &&
              !_indentRe.hasMatch(lastLine.content))) {
        childLines.add(parser.current);
        _lazyContinuation = true;
        parser.advance();
      } else {
        break;
      }
    }

    return childLines;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final type =
        pattern.firstMatch(parser.current.content)!.group(1)!.toLowerCase();
    parser.advance();
    final childLines = parseChildLines(parser);
    // A trailing hard break (e.g. from the line-break hardener's two
    // trailing spaces) carries no meaning at the END of an alert — drop
    // blank tail lines and trim the last one so neither renderer paints a
    // dangling empty quoted line.
    while (childLines.isNotEmpty && childLines.last.isBlankLine) {
      childLines.removeLast();
    }
    if (childLines.isNotEmpty) {
      final lastIdx = childLines.length - 1;
      childLines[lastIdx] =
          md.Line(childLines[lastIdx].content.trimRight());
    }
    final children = md.BlockParser(childLines, parser.document).parseLines(
      // The setext heading underline cannot be a lazy continuation line in
      // a block quote (CommonMark 0.30 example 93).
      disabledSetextHeading: _lazyContinuation,
      parentSyntax: this,
    );
    return md.Element('div', children)
      ..attributes['class'] = 'markdown-alert markdown-alert-$type'
      ..attributes['data-alert'] = type
      ..attributes['data-source'] =
          childLines.map((l) => l.content).join('\n');
  }
}

/// `- [ ]` / `- [x]` task lists with the checkbox HOISTED to be the `<li>`'s
/// first child. The stock package syntax nests the `<input>` inside the
/// item's first `<p>`, where flutter_markdown never notices it — the bullet
/// stays a plain `•` and the checkbox silently disappears. With the input
/// at `li.children[0]`, flutter_markdown's list builder takes its checkbox
/// path (which [AppMarkdownBody] skins as ☐ / ☑).
class TaskListUnorderedSyntax extends md.UnorderedListWithCheckboxSyntax {
  const TaskListUnorderedSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser);
    if (node is md.Element) _hoistTree(node);
    return node;
  }
}

/// Ordered variant of [TaskListUnorderedSyntax] (`1. [ ] item`).
class TaskListOrderedSyntax extends md.OrderedListWithCheckboxSyntax {
  const TaskListOrderedSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser);
    if (node is md.Element) _hoistTree(node);
    return node;
  }
}

void _hoistTree(md.Element el) {
  if (el.tag == 'li') _hoistItem(el);
  for (final c in el.children ?? const <md.Node>[]) {
    if (c is md.Element) _hoistTree(c);
  }
}

/// Moves an `<input type="checkbox">` from the item's first `<p>` up to be
/// the item's first child (idempotent — already-hoisted items are skipped).
void _hoistItem(md.Element li) {
  final kids = li.children;
  if (kids == null || kids.isEmpty) return;
  final first = kids.first;
  if (first is md.Element && first.tag == 'input') return; // done
  if (first is md.Element && first.tag == 'p') {
    final pKids = first.children;
    if (pKids != null &&
        pKids.isNotEmpty &&
        pKids.first is md.Element &&
        (pKids.first as md.Element).tag == 'input') {
      kids.insert(0, pKids.removeAt(0));
    }
  }
}

/// `<br>` (also `<br/>` / `<br />`) as a line break. Deliberately NOT the
/// package's `InlineHtmlSyntax` (prohibition 9.3 — raw-HTML pass-through
/// would swallow the app's `<font …>` tags); this matches ONLY the br tag.
/// flutter_markdown renders the `br` element as `\n` natively, and the
/// flattened renderer has a matching case.
class BrSyntax extends md.InlineSyntax {
  BrSyntax() : super(r'<br\s*/?>', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}
