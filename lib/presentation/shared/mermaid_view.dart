import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, PlatformException;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvw;

/// WebView-backed renderers for AI-generated ```mermaid / ```svg code
/// blocks (v1.15.0). mermaid is a JavaScript library with no Dart
/// implementation, so the diagram source is rendered inside the platform
/// WebView:
///  - iOS / macOS: `webview_flutter` (WKWebView, built into the OS),
///  - Windows: `webview_windows` (Edge WebView2 runtime, preinstalled on
///    Win10 2004+/Win11).
///
/// `mermaid.min.js` is bundled as an asset and INLINED into the page HTML —
/// fully offline, no CDN. The page posts its rendered height back through
/// a JS bridge so the widget can size itself to the diagram.
///
/// Degradation contract: any failure (WebView2 runtime missing, mermaid
/// syntax error, WebView init error) falls back to a plain code-block card —
/// never a crash, never a blank hole in the document.
class MermaidView extends StatefulWidget {
  final String code;
  final bool dark;

  const MermaidView({super.key, required this.code, required this.dark});

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView> {
  String? _error;
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    _dark = widget.dark;
  }

  @override
  void didUpdateWidget(covariant MermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Theme flips must re-render inside the WebView.
    if (oldWidget.dark != widget.dark) {
      _dark = widget.dark;
      _error = null;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return MermaidFallback(code: widget.code, dark: widget.dark);
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) {
      return MermaidFallback(code: widget.code, dark: widget.dark);
    }
    return _DiagramWebView(
      kind: _DiagramKind.mermaid,
      payload: widget.code,
      dark: _dark,
      onError: (e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }
}

/// Renders a raw ```svg block (the G_SPEC cover blocks / inline figures)
/// DIRECTLY with flutter_svg — no WebView involved, so there is no runtime
/// to initialize and no silent-failure path (v1.15.0 lesson: the WebView
/// path made svg blocks flaky). Script content is stripped first: the block
/// is painted, never executed.
class SvgBlockView extends StatelessWidget {
  final String svg;
  final bool dark;

  const SvgBlockView({super.key, required this.svg, required this.dark});

  static final _scriptPattern =
      RegExp(r'<script[\s\S]*?</script>', caseSensitive: false);

  /// Root `<svg width="…" height="…">` — used to derive the display aspect
  /// ratio (AI cover blocks carry explicit pixel sizes, e.g. 960×420).
  static final _sizePattern = RegExp(
      r'<svg[^>]*?width\s*=\s*"([\d.]+)"[^>]*?height\s*=\s*"([\d.]+)"',
      caseSensitive: false,
      dotAll: true);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clean = svg.replaceAll(_scriptPattern, '').trim();
    double? aspect;
    final m = _sizePattern.firstMatch(clean);
    if (m != null) {
      final w = double.tryParse(m.group(1)!);
      final h = double.tryParse(m.group(2)!);
      if (w != null && h != null && w > 0 && h > 0) aspect = w / h;
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = (aspect != null && aspect > 0)
          ? (width / aspect).clamp(120.0, 640.0)
          : 320.0;
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withOpacity(0.03),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SvgPicture.string(
          clean,
          width: width,
          height: height,
          fit: BoxFit.contain,
        ),
      );
    });
  }
}

enum _DiagramKind { mermaid }

/// Shared WebView host: builds the page HTML, sizes itself via the JS
/// height bridge, falls back on any initialization failure.
class _DiagramWebView extends StatefulWidget {
  final _DiagramKind kind;
  final String payload;
  final bool dark;
  final void Function(String error) onError;

  const _DiagramWebView({
    required this.kind,
    required this.payload,
    required this.dark,
    required this.onError,
  });

  @override
  State<_DiagramWebView> createState() => _DiagramWebViewState();
}

class _DiagramWebViewState extends State<_DiagramWebView> {
  static Future<String>? _mermaidJsFuture;

  double _height = 220;
  bool _failed = false;
  String? _htmlPayload;
  bool? _htmlDark;
  Future<String>? _htmlFuture;
  Future<String>? _htmlNoJsFuture;

  @override
  void initState() {
    super.initState();
    _ensureHtml();
  }

  @override
  void didUpdateWidget(covariant _DiagramWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload || oldWidget.dark != widget.dark) {
      _failed = false;
      _height = 220;
      _ensureHtml();
    }
  }

  // The page HTML is rebuilt ONLY when payload/theme change — never on
  // height-driven setState calls (a fresh Future per build would loop).
  void _ensureHtml() {
    if (_htmlPayload == widget.payload && _htmlDark == widget.dark) return;
    _htmlPayload = widget.payload;
    _htmlDark = widget.dark;
    _htmlFuture = _pageHtml(widget.payload, widget.dark);
    // v1.15.2: WebView2 NavigateToString truncates pages over 2 MB —
    // mermaid.min.js (5.5 MB) must be injected via
    // addScriptToExecuteOnDocumentCreated, not inlined into the page.
    _htmlNoJsFuture = _pageHtml(widget.payload, widget.dark, inlineJs: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String>(
      future: defaultTargetPlatform == TargetPlatform.windows
          ? _htmlNoJsFuture
          : _htmlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _scaffoldBox(theme, const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ));
        }
        final html = snapshot.data;
        if (html == null || _failed) {
          return MermaidFallback(code: widget.payload, dark: widget.dark);
        }
        if (defaultTargetPlatform == TargetPlatform.windows) {
          return _WindowsDiagram(
            html: html,
            onHeight: (h) => setState(() => _height = h),
            onFail: () {
              if (!_failed) {
                _failed = true;
                widget.onError('WebView2 不可用');
                setState(() {});
              }
            },
            height: _height,
          );
        }
        return _WkDiagram(
          html: html,
          onHeight: (h) => setState(() => _height = h),
          onFail: () {
            if (!_failed) {
              _failed = true;
              widget.onError('WebView 初始化失败');
              setState(() {});
            }
          },
          height: _height,
        );
      },
    );
  }

  Widget _scaffoldBox(ThemeData theme, Widget child) => Container(
        width: double.infinity,
        height: _height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );

  static Future<String> _pageHtml(String payload, bool dark,
      {bool inlineJs = true}) async {
    final mermaidJs = inlineJs ? await _loadMermaidJs() : '';
    final body = '<div id="container" class="mermaid">${_escapeHtml(payload)}</div>';
    // v1.15.2 reference parity: same mermaid.initialize config as the
    // voice_transcription renderMermaidToSvg (CJK fontFamily shared between
    // measurement and rendering, wrapping width / node padding for long
    // CJK labels, gantt compressed to 1100px, 15px base font). ELK layout
    // is a separate ESM package — without it mermaid uses dagre, the
    // reference's own fallback when the ELK import fails.
    final initScript = '''
      const container = document.getElementById('container');
      mermaid.initialize({
        startOnLoad: false,
        theme: ${dark ? "'dark'" : "'default'"},
        securityLevel: 'loose',
        fontFamily: '"PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif',
        flowchart: { useMaxWidth: true, htmlLabels: true, wrappingWidth: 280, padding: 14 },
        mindmap: { useMaxWidth: true, padding: 12 },
        gantt: { useMaxWidth: true, useWidth: 1100 },
        themeVariables: {
          fontSize: '15px',
          fontFamily: '"PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif'
        }
      });
      try {
        await mermaid.run({ nodes: [container] });
      } catch (e) {
        container.className = 'error';
        container.textContent = 'mermaid 渲染失败：' + (e && e.message ? e.message : String(e));
        postHeight();
        return;
      }
      postHeight();''';
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
  body { padding: 6px 4px; }
  #container { max-width: 100%; }
  #container svg { max-width: 100%; height: auto; }
  #container.error { font: 12px/1.5 monospace; color: #f87171; white-space: pre-wrap; padding: 8px; }
</style>
<script>$mermaidJs</script>
</head>
<body>
$body
<script>
  const BRIDGE = window.BRIDGE || (window.chrome && window.chrome.webview);
  function postHeight() {
    if (!BRIDGE) return;
    const h = Math.max(document.body.scrollHeight, document.body.offsetHeight);
    try { BRIDGE.postMessage(JSON.stringify({ h: h })); } catch (e) {}
  }
  window.addEventListener('resize', postHeight);
  (async () => {
    $initScript
  })();
</script>
</body>
</html>''';
  }

  static Future<String> _loadMermaidJs() {
    return _mermaidJsFuture ??= rootBundle
        .loadString('assets/mermaid/mermaid.min.js');
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// iOS / macOS implementation (WKWebView via webview_flutter).
class _WkDiagram extends StatefulWidget {
  final String html;
  final double height;
  final void Function(double height) onHeight;
  final VoidCallback onFail;

  const _WkDiagram({
    required this.html,
    required this.height,
    required this.onHeight,
    required this.onFail,
  });

  @override
  State<_WkDiagram> createState() => _WkDiagramState();
}

class _WkDiagramState extends State<_WkDiagram> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (_) => widget.onFail(),
        ))
        ..addJavaScriptChannel(
          'BRIDGE',
          onMessageReceived: (message) => _handleMessage(message.message),
        );
      await controller.loadHtmlString(widget.html);
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      widget.onFail();
    }
  }

  void _handleMessage(String message) {
    try {
      final data = jsonDecode(message) as Map;
      final h = (data['h'] as num?)?.toDouble();
      if (h != null && h > 0) widget.onHeight(h.clamp(60, 4000));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return SizedBox(height: widget.height, width: double.infinity);
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: WebViewWidget(controller: controller),
    );
  }
}

/// Windows implementation (WebView2 via webview_windows).
class _WindowsDiagram extends StatefulWidget {
  final String html;
  final double height;
  final void Function(double height) onHeight;
  final VoidCallback onFail;

  const _WindowsDiagram({
    required this.html,
    required this.height,
    required this.onHeight,
    required this.onFail,
  });

  @override
  State<_WindowsDiagram> createState() => _WindowsDiagramState();
}

class _WindowsDiagramState extends State<_WindowsDiagram> {
  wvw.WebviewController? _controller;
  Stream<dynamic>? _messages;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Missing WebView2 runtime → degrade instead of crashing.
      final version = await wvw.WebviewController.getWebViewVersion();
      if (version == null) {
        widget.onFail();
        return;
      }
      try {
        await wvw.WebviewController.initializeEnvironment();
      } on PlatformException catch (e) {
        // v1.15.2 fix: the environment is a shared singleton — a second
        // MermaidView on the page (or the headless export renderer) must
        // NOT fail just because the first one already initialized it.
        if (e.code != 'environment_already_initialized') rethrow;
      }
      final controller = wvw.WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(const Color(0x00000000));
      // Inject mermaid.js outside the page string (2 MB NavigateToString
      // limit — the library alone is 5.5 MB); runs before page scripts.
      final mermaidJs = await _DiagramWebViewState._loadMermaidJs();
      await controller.addScriptToExecuteOnDocumentCreated(mermaidJs);
      await controller.loadStringContent(widget.html);
      _messages = controller.webMessage;
      _messages?.listen((m) {
        if (m is String) _handleMessage(m);
      });
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      widget.onFail();
    }
  }

  void _handleMessage(String message) {
    try {
      final data = jsonDecode(message) as Map;
      final h = (data['h'] as num?)?.toDouble();
      if (h != null && h > 0) widget.onHeight(h.clamp(60, 4000));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return SizedBox(height: widget.height, width: double.infinity);
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      // webview_windows' Webview takes no gestureRecognizers; the diagram
      // is sized to fit, so drags scroll the surrounding document anyway.
      child: wvw.Webview(controller),
    );
  }
}

/// Graceful degradation card: shows the raw source (what the pre-upgrade UI
/// did) plus, on Windows, an install link when WebView2 is missing.
class MermaidFallback extends StatelessWidget {
  final String code;
  final bool dark;

  const MermaidFallback({super.key, required this.code, required this.dark});

  static const _webview2Url =
      'https://developer.microsoft.com/microsoft-edge/webview2/';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowsMissingRuntime = defaultTargetPlatform == TargetPlatform.windows;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schema_outlined,
                  size: 14,
                  color: theme.colorScheme.primary.withOpacity(0.8)),
              const SizedBox(width: 6),
              Text(
                '图表源码',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Text(
              code.trim(),
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                fontFamily: 'Consolas',
              ),
            ),
          ),
          if (windowsMissingRuntime) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(_webview2Url)),
              child: Text(
                '安装 Microsoft Edge WebView2 运行时后可显示图形 →',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
