import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Custom title bar that integrates with the app theme.
/// Replaces the native system title bar for a macOS-like appearance.
/// Rendered only on desktop; on iOS/Android the native chrome is used.
class CustomTitleBar extends StatelessWidget {
  final String title;

  const CustomTitleBar({super.key, this.title = 'TaskFlow'});

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            // App icon (small)
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
            const Spacer(),
            // Window controls (Windows style: minimize, maximize, close)
            _WindowButton(
              icon: Icons.remove,
              onPressed: () => windowManager.minimize(),
              hoverColor: theme.colorScheme.onSurface.withOpacity(0.08),
            ),
            _WindowButton(
              icon: Icons.crop_square,
              iconSize: 14,
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              hoverColor: theme.colorScheme.onSurface.withOpacity(0.08),
            ),
            _WindowButton(
              icon: Icons.close,
              iconSize: 16,
              onPressed: () => windowManager.close(),
              hoverColor: const Color(0xFFE81123),
              hoverIconColor: Colors.white,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color? hoverIconColor;

  const _WindowButton({
    required this.icon,
    this.iconSize = 16,
    required this.onPressed,
    required this.hoverColor,
    this.hoverIconColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 36,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered ? widget.hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hovered && widget.hoverIconColor != null
                ? widget.hoverIconColor
                : theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}
