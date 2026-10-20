import 'dart:async';
import 'dart:ffi' hide Size; // Size collides with dart:ui's Size
import 'dart:io';

import 'package:ffi/ffi.dart';
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

final String _lockFilePath =
    '${Directory.systemTemp.path}${Platform.pathSeparator}taskflow.instance.lock';

Future<bool> _acquireSingleInstanceLock() async {
  try {
    final raf = await File(_lockFilePath).open(mode: FileMode.append);
    if (await raf.length() == 0) {
      await raf.writeByte(0);
      await raf.flush();
    }
    await raf.lock(FileLock.exclusive, 0, 1);
    // v1.12.63: once the lock is ours, record our PID. The second instance
    // reads the LAST digit run (append-only file, so the newest writer wins)
    // and raises that process's window instead of showing a dead-end notice.
    await raf.writeString('$pid\n');
    await raf.flush();
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

/// Last digit run in the lock file = the PID of the instance that holds the
/// lock (the file is append-only, so the newest writer wins; the digit-run
/// scan also skips the legacy 0x00 sentinel written by v1.12.62).
Future<int?> _readLockPid() async {
  try {
    final text = await File(_lockFilePath).readAsString();
    final runs = RegExp(r'\d+').allMatches(text);
    return runs.isEmpty ? null : int.tryParse(runs.last.group(0)!);
  } catch (_) {
    return null;
  }
}

// --- minimal user32 bindings (Windows only; opened lazily so the file still
// imports cleanly on iOS/Android) -------------------------------------------

const int _gwChild = 5;
const int _gwHwndNext = 2;
const int _swHide = 0;
const int _swShow = 5;
const int _swRestore = 9;

/// First top-level window owned by [targetPid] (visible ones preferred).
int? _findWindowOfPid(int targetPid, {bool requireVisible = true}) {
  final user32 = DynamicLibrary.open('user32.dll');
  final getDesktopWindow =
      user32.lookupFunction<Handle Function(), int Function()>(
          'GetDesktopWindow');
  final getWindow = user32
      .lookupFunction<Handle Function(Handle, Uint32), int Function(int, int)>(
          'GetWindow');
  final isVisible = user32
      .lookupFunction<Int32 Function(Handle), int Function(int)>(
          'IsWindowVisible');
  final getWindowThreadProcessId = user32
      .lookupFunction<Uint32 Function(Handle, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
  final pidBuf = calloc<Uint32>();
  try {
    int? firstAny;
    for (var hwnd = getWindow(getDesktopWindow(), _gwChild);
        hwnd != 0;
        hwnd = getWindow(hwnd, _gwHwndNext)) {
      pidBuf.value = 0;
      getWindowThreadProcessId(hwnd, pidBuf);
      if (pidBuf.value != targetPid) continue;
      if (isVisible(hwnd) != 0) return hwnd;
      firstAny ??= hwnd;
    }
    return requireVisible ? null : firstAny;
  } finally {
    calloc.free(pidBuf);
  }
}

bool _raiseWindowOfPid(int targetPid) {
  final hwnd = _findWindowOfPid(targetPid);
  if (hwnd == null) return false;
  final user32 = DynamicLibrary.open('user32.dll');
  final showWindow = user32
      .lookupFunction<Int32 Function(Handle, Int32), int Function(int, int)>(
          'ShowWindow');
  final setForeground = user32
      .lookupFunction<Int32 Function(Handle), int Function(int)>(
          'SetForegroundWindow');
  showWindow(hwnd, _swRestore);
  return setForeground(hwnd) != 0;
}

void _showWindow(int hwnd, int cmd) {
  final user32 = DynamicLibrary.open('user32.dll');
  user32
      .lookupFunction<Int32 Function(Handle, Int32), int Function(int, int)>(
          'ShowWindow')(hwnd, cmd);
}

void _setWindowTitle(int hwnd, String title) {
  final user32 = DynamicLibrary.open('user32.dll');
  final setWindowText = user32.lookupFunction<
      Int32 Function(Handle, Pointer<Utf16>),
      int Function(int, Pointer<Utf16>)>('SetWindowTextW');
  final buf = title.toNativeUtf16();
  try {
    setWindowText(hwnd, buf);
  } finally {
    calloc.free(buf);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One instance only: the second launch must never reach Isar. v1.12.63:
  // instead of a dead-end notice, it first tries to raise the window of the
  // instance that holds the lock (the common case is a double launch during
  // the first instance's cold-start window period — the user sees "nothing
  // happened" and clicks again). Only when no window can be found does the
  // explanation window appear, under a title that distinguishes it from the
  // real app in Alt+Tab.
  if (!await _acquireSingleInstanceLock()) {
    if (Platform.isWindows) {
      final holderPid = await _readLockPid();
      if (holderPid != null && holderPid != pid) {
        // Hide our own (blank) window while probing, so a slow first
        // instance never leaves a second empty window flashing on screen.
        final self = _findWindowOfPid(pid, requireVisible: false);
        if (self != null) _showWindow(self, _swHide);
        for (var attempt = 0; attempt < 30; attempt++) {
          if (_raiseWindowOfPid(holderPid)) exit(0);
          await Future.delayed(const Duration(milliseconds: 100));
        }
        // No window to raise — explain, with a distinguishable title.
        if (self != null) {
          _setWindowTitle(self, 'TaskFlow — 已在运行');
          _showWindow(self, _swShow);
        }
      }
    }
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
                  '另一个 TaskFlow 实例正在运行，但它的窗口未能自动唤起。\n'
                  '请用 Alt+Tab 找到已打开的 TaskFlow 窗口；若找不到，\n'
                  '在任务管理器中结束所有 taskflow.exe 后重新打开。\n'
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
