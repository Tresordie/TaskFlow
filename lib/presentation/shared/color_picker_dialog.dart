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

/// Shows a color-picker dialog and returns the chosen color, or `null`
/// if the user picked "Default" (no custom color) or cancelled.
///
/// Offers both a curated preset palette and a fully custom RGB picker so
/// any color can be chosen. [current] is highlighted so the user can see
/// the active selection (and the custom sliders are seeded from it).
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
        content: SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: _PickerBody(current: current),
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

class _PickerBody extends StatefulWidget {
  final Color? current;

  const _PickerBody({required this.current});

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late int _r;
  late int _g;
  late int _b;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _r = c?.red ?? 30;
    _g = c?.green ?? 136;
    _b = c?.blue ?? 229;
  }

  Color get _custom => Color.fromARGB(255, _r, _g, _b);

  String get _hex => '#${_r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${_g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${_b.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- Preset palette -------------------------------------------
        Wrap(
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

        const SizedBox(height: 16),
        Divider(height: 1, color: theme.colorScheme.outline.withOpacity(0.3)),
        const SizedBox(height: 12),

        // --- Custom RGB picker ----------------------------------------
        Text('Custom color', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        _channelSlider(
            'R', _r, const Color(0xFFE53935), (v) => setState(() => _r = v)),
        _channelSlider(
            'G', _g, const Color(0xFF43A047), (v) => setState(() => _g = v)),
        _channelSlider(
            'B', _b, const Color(0xFF1E88E5), (v) => setState(() => _b = v)),

        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _custom,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withOpacity(0.12)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _hex,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_custom),
              child: const Text('Use this color'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _channelSlider(
      String label, int value, Color activeColor, ValueChanged<int> onChanged) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: activeColor,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
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
