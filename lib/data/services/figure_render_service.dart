/// Headless figure renderer for the AI Parse HTML export (v1.15.2,
/// reference parity with voice_transcription `richRender.ts` /
/// `exporters.ts`): ```mermaid blocks become STATIC light-theme SVG and
/// model-written ```svg covers get the reference `fitSvgText` text-overflow
/// repair — so the exported file is a small self-contained document
/// (no 3.5 MB mermaid.js, no JavaScript needed to view/print).
///
/// Mechanism: the vendored webview_windows plugin creates its WebView2
/// OFFSCREEN at `initialize()` time (message-only HWND, composition
/// surface); a controller therefore runs JS without a `Webview` widget in
/// the tree. `setHeadlessSize` fixes the viewport bounds the widget would
/// normally set. One page renders every block and posts the results back
/// through the webMessage bridge.
///
/// Degradation contract: Windows-only; any failure (no WebView2 runtime,
/// init error, timeout, test environment without the plugin) returns null
/// and the caller falls back to inlining mermaid.js (light theme).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show rootBundle, PlatformException;
import 'package:webview_windows/webview_windows.dart' as wvw;

/// One figure block extracted from the exported markdown.
class FigureBlock {
  /// Stable id ('m0', 'm1', … mermaid; 's0', 's1', … svg).
  final String id;

  /// 'mermaid' | 'svg'.
  final String kind;
  final String code;

  const FigureBlock({required this.id, required this.kind, required this.code});
}

/// Rendered figures keyed by [FigureBlock.id].
class FigureRenderResult {
  /// Successfully rendered mermaid SVG / fitted model SVG.
  final Map<String, String> svgById;

  /// Per-block mermaid failure messages (source is kept in the export).
  final Map<String, String> errorById;

  const FigureRenderResult({required this.svgById, required this.errorById});
}

/// Overall budget for one export render pass (a dozen diagrams typically
/// finish in a few seconds; the timeout only guards a wedged WebView).
const Duration _renderTimeout = Duration(seconds: 45);

/// Renders [blocks] headlessly. Returns null when the platform/runtime is
/// unavailable or the pass fails/times out — NEVER throws.
Future<FigureRenderResult?> renderFigures(List<FigureBlock> blocks) async {
  if (blocks.isEmpty || !Platform.isWindows) return null;
  wvw.WebviewController? controller;
  try {
    final version = await wvw.WebviewController.getWebViewVersion();
    if (version == null) return null;
    try {
      await wvw.WebviewController.initializeEnvironment();
    } on PlatformException catch (e) {
      // An in-app MermaidView may have initialized the shared environment
      // already — that is fine, the environment is a singleton.
      if (e.code != 'environment_already_initialized') rethrow;
    }
    controller = wvw.WebviewController();
    await controller.initialize();
    // Viewport for DOM layout / getBBox / canvas text measurement.
    await controller.setHeadlessSize(1280, 900);

    // WebView2 NavigateToString (loadStringContent) silently truncates
    // pages over 2 MB — mermaid.min.js alone is 5.5 MB. Inject the big
    // libraries via addScriptToExecuteOnDocumentCreated (no size limit,
    // runs before page scripts) and keep the navigated page tiny.
    final mermaidJs =
        await rootBundle.loadString('assets/mermaid/mermaid.min.js');
    final svgFitJs = await rootBundle.loadString('assets/mermaid/svg_fit.js');
    await controller.addScriptToExecuteOnDocumentCreated(mermaidJs);
    await controller.addScriptToExecuteOnDocumentCreated(svgFitJs);
    final page = _pageHtml(blocks);
    final completer = Completer<FigureRenderResult>();
    final sub = controller.webMessage.listen((message) {
      if (completer.isCompleted) return;
      try {
        final map = message is Map ? message : jsonDecode(message as String);
        final results = (map as Map)['results'];
        if (results is! List) return;
        final svgById = <String, String>{};
        final errorById = <String, String>{};
        for (final r in results) {
          final m = r as Map;
          final id = m['id'] as String;
          final svg = m['svg'];
          final error = m['error'];
          if (svg is String && svg.isNotEmpty) {
            svgById[id] = svg;
          } else if (error is String) {
            errorById[id] = error;
          }
        }
        completer.complete(
            FigureRenderResult(svgById: svgById, errorById: errorById));
      } catch (_) {
        // Malformed bridge message — keep waiting for the real one.
      }
    });
    try {
      await controller.loadStringContent(page);
      return await completer.future.timeout(_renderTimeout);
    } finally {
      await sub.cancel();
    }
  } catch (_) {
    return null;
  } finally {
    try {
      await controller?.dispose();
    } catch (_) {}
  }
}

String _pageHtml(List<FigureBlock> blocks) {
  final blocksJson = jsonEncode([
    for (final b in blocks) {'id': b.id, 'kind': b.kind, 'code': b.code},
  ]);
  // mermaid.initialize mirrors the reference renderMermaidToSvg config
  // (light 'default' theme, CJK fontFamily kept identical between text
  // measurement and rendering, CJK wrapping width / node padding, gantt
  // compressed to 1100px). ELK layout is a separate ESM package the
  // reference loads dynamically; without it mermaid falls back to dagre —
  // the reference's own fallback path when the ELK import fails.
  // mermaid.min.js + svg_fit.js are injected by the caller via
  // addScriptToExecuteOnDocumentCreated (2 MB NavigateToString limit).
  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:#ffffff;}</style>
</head>
<body>
<script>
  const BRIDGE = window.chrome && window.chrome.webview;
  const BLOCKS = $blocksJson;
  function post(o) { if (BRIDGE) BRIDGE.postMessage(JSON.stringify(o)); }
  mermaid.initialize({
    startOnLoad: false,
    theme: 'default',
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
  (async () => {
    const results = [];
    for (const b of BLOCKS) {
      if (b.kind === 'mermaid') {
        try {
          const out = await mermaid.render('mmd-' + b.id, b.code.trim());
          results.push({ id: b.id, svg: out.svg });
        } catch (e) {
          results.push({ id: b.id, error: String((e && e.message) || e).slice(0, 120) });
        }
      } else {
        try {
          results.push({ id: b.id, svg: fitSvgText(b.code) });
        } catch (e) {
          results.push({ id: b.id, svg: b.code });
        }
      }
    }
    post({ results: results });
  })();
</script>
</body>
</html>''';
}
