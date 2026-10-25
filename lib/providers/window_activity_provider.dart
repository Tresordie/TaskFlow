import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// True while the window is on screen; false once it is minimized or hidden.
///
/// The perpetual ambient animations (drifting orbs, breathing empty boxes)
/// watch this: while a repeat() controller is scheduled, the Flutter Windows
/// engine keeps producing frames — an idle, minimized app was measured at
/// ~17% CPU / ~34% GPU. Rendering the same backdrop statically lets the
/// vsync pipeline park instead.
final windowActiveProvider = StateProvider<bool>((ref) => true);

/// Mount once above MaterialApp (TaskFlowApp). Listens to window_manager
/// events and re-queries the authoritative minimized/hidden state on each;
/// minimize/restore events on Windows don't fire uniformly (a taskbar
/// restore may only surface as a focus event), so no event itself is
/// trusted to carry state.
class WindowActivityObserver extends ConsumerStatefulWidget {
  final Widget child;

  const WindowActivityObserver({super.key, required this.child});

  @override
  ConsumerState<WindowActivityObserver> createState() =>
      _WindowActivityObserverState();
}

class _WindowActivityObserverState
    extends ConsumerState<WindowActivityObserver> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _refresh() async {
    try {
      final active =
          !await windowManager.isMinimized() && await windowManager.isVisible();
      if (!mounted) return;
      if (ref.read(windowActiveProvider) != active) {
        ref.read(windowActiveProvider.notifier).state = active;
      }
    } catch (_) {
      // No window plugin (mobile, widget tests) — stay "active".
    }
  }

  @override
  void onWindowEvent(String eventName) => _refresh();

  @override
  void onWindowMinimize() => _refresh();

  @override
  void onWindowBlur() => _refresh();

  @override
  void onWindowFocus() => _refresh();

  @override
  Widget build(BuildContext context) => widget.child;
}
