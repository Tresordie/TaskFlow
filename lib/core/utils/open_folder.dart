import 'dart:io';

/// Opens [path] (a file or a folder) with the platform default handler,
/// without ever blocking the Flutter UI thread.
///
/// Why not `launchUrl(Uri.file(...))`: the url_launcher desktop plugins
/// invoke `ShellExecuteW` (Windows) synchronously on the platform/UI
/// thread, and `file:///` URLs are routed through shell URL-association
/// handling, which can block indefinitely — the app freezes and shows
/// "Not responding". Spawning the native handler directly with
/// [Process.start] is fire-and-forget: the call returns immediately and
/// the file manager / associated app runs in its own process.
Future<void> openPath(String path) async {
  try {
    if (Platform.isWindows) {
      // explorer.exe with a plain path argument opens a folder in
      // Explorer, or launches the associated app for a file; either way
      // it returns immediately (hands off to the running shell).
      await Process.start('explorer.exe', [path], runInShell: false);
    } else if (Platform.isMacOS) {
      await Process.start('open', [path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [path]);
    }
  } catch (_) {
    // Best-effort: never let a failed "open" crash or block the app.
    // The path is still visible in the UI for manual copy.
  }
}

/// Opens a folder in the platform file manager (non-blocking).
Future<void> openFolder(String path) => openPath(path);
