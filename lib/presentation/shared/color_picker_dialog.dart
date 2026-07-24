import 'package:flutter/material.dart';

/// A curated, easy-to-distinguish palette offered to the user when they
/// assign a color to a project or a tag.
const List<Color> kColorPalette = [
  Color(0xFFE53935), // red
  Color(0xFFD81B60), // pink
  Color(0xFF8E24AA), // purple
  Color(0xFF5E35B1), // deep purple
  Color(0xFF3949AB), // indigo
  Color(0xFF1E88E5), // blue
  Color(0xFF039BE5), // light blue
  Color(0xFF00ACC1), // cyan
  Color(0xFF00897B), // teal
  Color(0xFF43A047), // green
  Color(0xFF7CB342), // light green
  Color(0xFFC0CA33), // lime
  Color(0xFFFB8C00), // orange
  Color(0xFFF4511E), // deep orange
  Color(0xFF6D4C41), // brown
  Color(0xFF757575), // grey
];

/// Shows a small color-picker dialog and returns the chosen color, or
/// `null` if the user picked "Default" (no custom color) or cancelled.
///
/// [current] is highlighted so the user can see the active selection.
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required String title,
  Color? current,
}) {
  return showDialog<Color?>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 296,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              // "Default" swatch — clears any custom color.
              _Swatch(
                color: null,
                selected: current == null,
                onTap: () => Navigator.of(context).pop(null),
              ),
              for (final c in kColorPalette)
                _Swatch(
                  color: c,
                  selected: current?.value == c.value,
                  onTap: () => Navigator.of(context).pop(c),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}

class _Swatch extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDefault = color == null;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isDefault ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : (isDefault
                    ? theme.colorScheme.outline.withOpacity(0.5)
                    : Colors.black.withOpacity(0.08)),
            width: selected ? 2 : 1,
          ),
        ),
        child: isDefault
            // A tiny slash icon conveys "no color / default".
            ? Icon(
                Icons.format_color_reset,
                size: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              )
            : (selected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null),
      ),
    );
  }
}
