import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app/app.dart';
import 'data/services/attachment_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warm the attachments-dir cache so attachment paths (which are stored
  // relative for cross-device portability) resolve synchronously everywhere.
  await AttachmentService.init();

  // Custom title bar is desktop-only. On iOS/Android we keep the
  // native chrome, so skip window_manager entirely.
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      // 1400px keeps the Reports control row (period + date nav + language
      // + AI summary + Generate button) on one line: content width is the
      // window minus the 210px sidebar, 10px gap and 40px page padding
      // (~260px), and that row needs ~980px.
      size: Size(1400, 880),
      minimumSize: Size(900, 600),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      skipTaskbar: false,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: TaskFlowApp()));
}
