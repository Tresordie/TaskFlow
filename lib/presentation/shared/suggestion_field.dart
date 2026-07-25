import 'package:flutter/material.dart';

/// Case-insensitive substring filter used by [SuggestionField]. Returns up
/// to 8 matches and drops an option that already equals the typed query so
/// the dropdown hides once a value is fully entered.
List<String> filterSuggestions(List<String> options, String query) {
  final q = query.trim().toLowerCase();
  final Iterable<String> result = q.isEmpty
      ? options
      : options
          .where((o) => o.toLowerCase().contains(q) && o.toLowerCase() != q);
  return result.take(8).toList();
}

/// A [TextField] with a floating dropdown of suggestions drawn from
/// previously used values (projects / tags).
///
/// Two modes:
///  * single value (default) — selecting a suggestion replaces the text.
///  * [commaSeparated] — suggestions apply to the token after the last
///    comma; selecting replaces that token and appends ", " so the user
///    can keep adding tags in one field.
///
/// The widget drives the supplied [controller] (it does not create its own),
/// so callers keep full read/write access — important for the quick-add bar
/// where the Project field is "sticky" across creations.
class SuggestionField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> suggestions;
  final InputDecoration? decoration;
  final TextStyle? style;
  final bool commaSeparated;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  /// Icon shown in a tinted chip at the leading edge of each suggestion row.
  final IconData? optionIcon;

  /// Optional header strip label for the dropdown (e.g. "Recent projects").
  final String? headerText;

  const SuggestionField({
    super.key,
    required this.controller,
    required this.suggestions,
    this.decoration,
    this.style,
    this.commaSeparated = false,
    this.onSubmitted,
    this.focusNode,
    this.optionIcon,
    this.headerText,
  });

  @override
  State<SuggestionField> createState() => _SuggestionFieldState();
}

class _SuggestionFieldState extends State<SuggestionField> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  late final FocusNode _focusNode;
  OverlayEntry? _overlay;
  List<String> _matches = [];
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant SuggestionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.suggestions != widget.suggestions) _onTextChanged();
  }

  @override
  void dispose() {
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  /// The fragment of text the dropdown should match against: the whole
  /// field in single mode, or the token after the last comma in
  /// comma-separated mode.
  String get _currentToken {
    final text = widget.controller.text;
    if (!widget.commaSeparated) return text;
    final idx = text.lastIndexOf(',');
    return idx < 0 ? text : text.substring(idx + 1);
  }

  void _onTextChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
      return;
    }
    final matches = filterSuggestions(widget.suggestions, _currentToken);
    _matches = matches;
    _lastQuery = _currentToken.trim();
    if (matches.isEmpty) {
      _removeOverlay();
    } else if (_overlay == null) {
      _showOverlay();
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _onTextChanged();
    } else {
      // Delay so a tap on a suggestion can register before we tear down.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!_focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _select(String value) {
    final controller = widget.controller;
    if (widget.commaSeparated) {
      final text = controller.text;
      final idx = text.lastIndexOf(',');
      final prefix = idx < 0 ? '' : text.substring(0, idx + 1).trimRight();
      controller.text = prefix.isEmpty ? '$value, ' : '$prefix $value, ';
    } else {
      controller.text = value;
    }
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    _removeOverlay();
    _focusNode.requestFocus();
  }

  void _showOverlay() {
    _removeOverlay();
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 200;
    final height = renderBox?.size.height ?? 30;

    _overlay = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        return CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, height + 4),
          child: SizedBox(
            width: width,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, -4 * (1 - t)),
                  child: child,
                ),
              ),
              child: Material(
                elevation: 12,
                shadowColor: primary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.surface,
                surfaceTintColor: theme.colorScheme.surfaceTint,
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.18)),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 264),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.headerText != null)
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
                            color: primary.withOpacity(0.05),
                            child: Row(
                              children: [
                                Icon(
                                  widget.optionIcon ?? Icons.history,
                                  size: 12,
                                  color: primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.headerText!.toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    fontSize: 10,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_matches.length}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Flexible(
                          child: ListView(
                            padding: const EdgeInsets.all(5),
                            shrinkWrap: true,
                            children: [
                              for (final option in _matches)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: InkWell(
                                    onTap: () => _select(option),
                                    borderRadius: BorderRadius.circular(7),
                                    hoverColor: primary.withOpacity(0.08),
                                    splashColor: primary.withOpacity(0.12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 6),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: primary.withOpacity(0.10),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Icon(
                                              widget.optionIcon ??
                                                  Icons.history_rounded,
                                              size: 13,
                                              color: primary,
                                            ),
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Text.rich(
                                              _highlight(option, theme),
                                              style: const TextStyle(
                                                  fontSize: 12.5),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlay!);
  }

  /// TextSpan for [option] with the first case-insensitive occurrence of
  /// the current query highlighted in the primary color.
  InlineSpan _highlight(String option, ThemeData theme) {
    final q = _lastQuery.toLowerCase();
    if (q.isEmpty) return TextSpan(text: option);
    final idx = option.toLowerCase().indexOf(q);
    if (idx < 0) return TextSpan(text: option);
    final primary = theme.colorScheme.primary;
    return TextSpan(
      children: [
        TextSpan(text: option.substring(0, idx)),
        TextSpan(
          text: option.substring(idx, idx + q.length),
          style: TextStyle(
            color: primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(text: option.substring(idx + q.length)),
      ],
    );
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        style: widget.style,
        decoration: widget.decoration,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
