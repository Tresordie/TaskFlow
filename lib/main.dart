import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'app/app.dart';
import 'data/services/attachment_service.dart';

/// v1.12.62: held for the whole process lifetime. Isar opens ONE MDBX
/// environment at `Documents/taskflow.isar`; a second app instance cannot
/// open it and the board shows a raw `MdbxError (5)` — which reads like a
/// broken build but is only a double launch. A file lock in the temp dir is
/// released automatically by Windows when the process exits (even on a
/// crash), so it is safer than a stale `.isar-lck` marker.
RandomAccessFile? _instanceLock;
Timer? _instanceLockKeepAlive;

Future<bool> _acquireSingleInstanceLock() async {
  try {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}taskflow.instance.lock';
    final raf = await File(path).open(mode: FileMode.append);
    if (await raf.length() == 0) {
      await raf.writeByte(0);
      await raf.flush();
    }
    await raf.lock(FileLock.exclusive, 0, 1);
    _instanceLock = raf;
    // Reading the handle from a long-lived timer is load-bearing: in an AOT
    // release build an assigned-but-never-read global can be tree-shaken,
    // the RandomAccessFile becomes unreachable and its finalizer closes it —
    // which silently releases the lock while the app is still running (this
    // is exactly why the first v1.12.62 build let a second instance through).
    _instanceLockKeepAlive ??= Timer.periodic(
        const Duration(minutes: 10), (_) => _instanceLock?.length());
    return true;
  } catch (_) {
    // FileSystemException / PathAccessException (lock busy) — a second copy.
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One instance only: the second launch must never reach Isar. It gets a
  // clear explanation window instead of the database error.
  if (!await _acquireSingleInstanceLock()) {
    runApp(const _AlreadyRunningApp());
    return;
  }

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

/// Shown by the second instance. Deliberately does not touch
/// attachments / window_manager / Isar — its only job is to explain why the
/// app did not open.
class _AlreadyRunningApp extends StatelessWidget {
  const _AlreadyRunningApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 44),
                const SizedBox(height: 14),
                const Text(
                  'TaskFlow 已在运行',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请先关闭另一个 TaskFlow 窗口，再重新打开。\n'
                  '（同一个数据库只能被一个实例打开，这是保护数据，不是安装问题。）',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => exit(0),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
