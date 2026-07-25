import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../../providers/font_provider.dart';
import '../../providers/ai_provider.dart';
import '../../providers/sync_providers.dart';
import '../../providers/task_providers.dart';
import '../../data/services/ai_service.dart';
import '../../data/services/sync_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(themeModeProvider);
    final currentFont = ref.watch(fontProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text('Settings', style: theme.textTheme.headlineLarge),
        const SizedBox(height: 32),

        // ─── Theme Selection ───
        Text('Theme', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Choose a color scheme',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        ...AppThemeMode.values.map((mode) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ThemeCard(
                mode: mode,
                isSelected: currentTheme == mode,
                onTap: () =>
                    ref.read(themeModeProvider.notifier).setTheme(mode),
              ),
            )),

        const SizedBox(height: 36),

        // ─── Font Selection ───
        Text('Font', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Choose your preferred typeface',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),

        // Preset fonts (Google Fonts)
        Text('PRESETS',
            style: theme.textTheme.labelSmall
                ?.copyWith(fontSize: 10, letterSpacing: 1.0)),
        const SizedBox(height: 8),
        ...AppFonts.presets.map((font) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FontCard(
                font: font,
                isSelected: currentFont.id == font.id,
                onTap: () => ref.read(fontProvider.notifier).setFont(font),
              ),
            )),

        const SizedBox(height: 20),

        // Custom font input
        _CustomFontInput(),

        const SizedBox(height: 36),

        // ─── Font Size ───
        Text('Font Size', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Adjust the global text size (80% – 140%)',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const _FontSizeCard(),

        const SizedBox(height: 36),

        // ─── Font Weight ───
        Text('Font Weight', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Adjust the global text weight — heavier text is easier to read',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const _FontWeightCard(),

        const SizedBox(height: 36),

        // ─── AI Assistant ───
        Text('AI Assistant', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Connect an OpenAI-compatible API (OpenAI / DeepSeek / Qwen / Ollama…) to power the AI Parse feature',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const _AiConfigCard(),

        const SizedBox(height: 36),

        // ─── Backup & Sync ───
        Text('Backup & Sync', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Export / restore JSON snapshots, or sync through a Google Drive folder',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const _BackupSyncCard(),

        const SizedBox(height: 36),

        // ─── Data Storage Info ───
        Text('Data Storage', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storage_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Local Database (Isar)',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'All tasks, execution logs, and sub-steps are stored locally '
                'in an Isar NoSQL database file in your Documents folder. '
                'Data persists offline and survives app updates.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'JSON snapshots, backup/restore and Google Drive folder sync '
                'are available in the Backup & Sync section above.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),

        // ─── About ───
        Text('About', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TaskFlow v1.0.0', style: theme.textTheme.titleMedium),
                  Text('Phase 1 · Flutter 3.44 · Isar · Riverpod',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppThemeMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = mode.palette;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.primary.withOpacity(0.06)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? palette.primary
                : theme.colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Color dots
            ...[
              palette.primary,
              palette.primaryLight,
              palette.bg,
              palette.textPrimary
            ].map((c) => Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.black.withOpacity(0.08), width: 0.5),
                  ),
                )),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.labelZh,
                      style:
                          theme.textTheme.titleMedium?.copyWith(fontSize: 13)),
                  Text(mode.label,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(fontSize: 11)),
                ],
              ),
            ),
            // Check
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? palette.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? palette.primary
                      : theme.colorScheme.onSurface.withOpacity(0.25),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FontCard extends StatelessWidget {
  final FontOption font;
  final bool isSelected;
  final VoidCallback onTap;

  const _FontCard({
    required this.font,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.06)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Font preview (rendered in the actual font)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  'Ag',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                    fontFamily: font.fontFamily,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(font.labelZh,
                      style:
                          theme.textTheme.titleMedium?.copyWith(fontSize: 13)),
                  Text(font.labelEn,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(fontSize: 11)),
                ],
              ),
            ),
            // Check
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.25),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomFontInput extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CustomFontInput> createState() => _CustomFontInputState();
}

class _CustomFontInputState extends ConsumerState<_CustomFontInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Type any installed font name (e.g. "Source Han Sans")',
              labelText: 'Custom Font',
            ),
            onSubmitted: (_) => _apply(),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  void _apply() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    ref.read(fontProvider.notifier).setCustomFont(name);
    _controller.clear();
  }
}

/// Card with a slider + A-/A+ buttons to adjust the global font scale.
class _FontSizeCard extends ConsumerWidget {
  const _FontSizeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scale = ref.watch(fontScaleProvider);
    final percent = (scale * 100).round();
    final notifier = ref.read(fontScaleProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A- button
              _ScaleButton(
                label: 'A',
                fontSize: 13,
                tooltip: 'Smaller',
                onTap: () => notifier.setScale(scale - 0.05),
              ),
              Expanded(
                child: Slider(
                  value: scale,
                  min: FontScaleNotifier.minScale,
                  max: FontScaleNotifier.maxScale,
                  divisions: 12,
                  label: '$percent%',
                  onChanged: (v) => notifier.setScale(v),
                ),
              ),
              // A+ button
              _ScaleButton(
                label: 'A',
                fontSize: 20,
                tooltip: 'Larger',
                onTap: () => notifier.setScale(scale + 0.05),
              ),
              const SizedBox(width: 12),
              // Percentage badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              // Reset (only when not at 100%)
              if (scale != 1.0) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Reset to 100%',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: notifier.reset,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.restart_alt,
                        size: 18,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Live preview — automatically rendered at the current scale.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Preview 预览: The quick brown fox jumps over the lazy dog · '
              '线束 EVT 测试电流 2.3A · 0123456789',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card with selectable weight chips + a live preview for the global font
/// weight (v1.4.22). The preview line is rendered with the app theme, so it
/// updates the moment a new weight is picked.
class _FontWeightCard extends ConsumerWidget {
  const _FontWeightCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(fontWeightProvider);
    final notifier = ref.read(fontWeightProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...FontWeightNotifier.options.map(
                (option) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _WeightChip(
                    option: option,
                    isSelected: current.id == option.id,
                    onTap: () => notifier.setWeight(option),
                  ),
                ),
              ),
              const Spacer(),
              // Reset (only when not on Regular)
              if (current.id != 'regular')
                Tooltip(
                  message: 'Reset to Regular',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: notifier.reset,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.restart_alt,
                        size: 18,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Live preview — automatically rendered at the current weight.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Preview 预览: The quick brown fox jumps over the lazy dog · '
              '线束 EVT 测试电流 2.3A · 0123456789',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightChip extends StatelessWidget {
  final FontWeightOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _WeightChip({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: option.labelEn,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withOpacity(0.4),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 'Aa' rendered at the actual weight so differences are visible.
              Text(
                'Aa',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: option.weight,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                option.labelZh,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScaleButton extends StatelessWidget {
  final String label;
  final double fontSize;
  final String tooltip;
  final VoidCallback onTap;

  const _ScaleButton({
    required this.label,
    required this.fontSize,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.4),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            // Fixed size on purpose: the buttons themselves must not scale.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// AI Assistant configuration card (Phase 2).
class _AiConfigCard extends ConsumerStatefulWidget {
  const _AiConfigCard();

  @override
  ConsumerState<_AiConfigCard> createState() => _AiConfigCardState();
}

class _AiConfigCardState extends ConsumerState<_AiConfigCard> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  bool _loaded = false;
  bool _obscureKey = true;
  bool _testing = false;
  bool _saving = false;

  static const _presets = [
    ('DeepSeek', 'https://api.deepseek.com', 'deepseek-v4-pro'),
    ('OpenAI', 'https://api.openai.com', 'gpt-4o-mini'),
    (
      'DashScope',
      'https://dashscope.aliyuncs.com/compatible-mode',
      'qwen-plus'
    ),
  ];

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_loaded) return;
    final config = ref.read(aiConfigProvider);
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(aiConfigProvider.notifier).save(AiConfig(
          baseUrl: _baseUrlController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
          model: _modelController.text.trim(),
        ));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI configuration saved'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _test() async {
    // Save first so the test uses exactly what will be persisted.
    await _save();
    setState(() => _testing = true);
    try {
      final result = await AiService(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        model: _modelController.text.trim(),
      ).testConnection();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection OK · $result'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final theme = Theme.of(context);
    final config = ref.watch(aiConfigProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: config.isConfigured ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                config.isConfigured ? 'Configured' : 'Not configured',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (config.isConfigured && config.model.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    config.model,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Quick presets
          Wrap(
            spacing: 8,
            children: [
              for (final (name, url, model) in _presets)
                ActionChip(
                  label: Text(name, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _baseUrlController.text = url;
                    _modelController.text = model;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _baseUrlController,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.deepseek.com',
              isDense: true,
              prefixIcon: Icon(Icons.link, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-…',
              isDense: true,
              prefixIcon: const Icon(Icons.key_outlined, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'deepseek-v4-pro / gpt-4o-mini / qwen-plus',
              isDense: true,
              prefixIcon: Icon(Icons.smart_toy_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: (_testing || _saving) ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering, size: 16),
                label: Text(_testing ? 'Testing…' : 'Test Connection'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Your key is stored locally on this device only (Windows registry / '
            'macOS preferences) and is sent solely to the endpoint above.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.45),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Backup / restore / Google-Drive-folder sync card (Phase 4).
class _BackupSyncCard extends ConsumerStatefulWidget {
  const _BackupSyncCard();

  @override
  ConsumerState<_BackupSyncCard> createState() => _BackupSyncCardState();
}

class _BackupSyncCardState extends ConsumerState<_BackupSyncCard> {
  final _folderController = TextEditingController();
  bool _backupBusy = false;
  bool _restoreBusy = false;

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── Backup ──

  Future<void> _backupNow() async {
    setState(() => _backupBusy = true);
    try {
      final file = await ref.read(backupServiceProvider).exportToBackupsDir();
      _snack('Backup saved: ${file.path}');
    } catch (e) {
      _snack('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _exportAs() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export TaskFlow backup',
      fileName: 'taskflow_backup.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    setState(() => _backupBusy = true);
    try {
      final content = await ref.read(backupServiceProvider).buildSnapshot();
      await File(path).writeAsString(content);
      _snack('Backup saved: $path');
    } catch (e) {
      _snack('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  // ── Restore ──

  Future<void> _restoreFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a TaskFlow backup (.json)',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final picked = result?.files.single;
    if (picked == null || picked.path == null) return;

    setState(() => _restoreBusy = true);
    String jsonText;
    int count;
    try {
      final service = ref.read(backupServiceProvider);
      jsonText = await File(picked.path!).readAsString();
      count = service.countTasksInSnapshot(jsonText);
    } catch (e) {
      setState(() => _restoreBusy = false);
      _snack('Not a valid TaskFlow backup: $e', error: true);
      return;
    }
    setState(() => _restoreBusy = false);

    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup'),
        content: Text(
          'This file contains $count task(s).\n\n'
          'Full restore replaces EVERYTHING in the current database.\n'
          'Merge keeps your local tasks and only overwrites tasks '
          'with matching ids (recommended for Drive sync).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('Merge'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'full'),
            child: const Text('Full Restore'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    setState(() => _restoreBusy = true);
    try {
      final restored = await ref
          .read(backupServiceProvider)
          .restoreSnapshot(jsonText, merge: choice == 'merge');
      await ref.read(taskListProvider.notifier).loadTasks();
      _snack(
          'Restored $restored task(s) (${choice == 'merge' ? 'merge' : 'full restore'})');
    } catch (e) {
      _snack('Restore failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  // ── Drive sync ──

  Future<void> _browseFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your Google Drive folder',
    );
    if (path != null) {
      _folderController.text = path;
      await ref.read(syncProvider.notifier).setFolder(path);
    }
  }

  Future<void> _autoDetect() async {
    final path = SyncNotifier.detectDriveFolder();
    if (path == null) {
      _snack('No Google Drive folder found — select it manually.', error: true);
      return;
    }
    _folderController.text = path;
    await ref.read(syncProvider.notifier).setFolder(path);
    _snack('Detected: $path');
  }

  Future<void> _runSync(Future<void> Function(SyncNotifier) op) async {
    await op(ref.read(syncProvider.notifier));
    await ref.read(taskListProvider.notifier).loadTasks();
    final msg = ref.read(syncProvider).lastMessage;
    if (msg != null) _snack(msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = ref.watch(syncProvider);

    // Keep the controller in sync with persisted state (first build).
    if (_folderController.text.isEmpty && sync.folderPath.isNotEmpty) {
      _folderController.text = sync.folderPath;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Manual backup / restore
          Row(
            children: [
              Icon(Icons.backup_outlined,
                  size: 17, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Local Backup',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: (_backupBusy || _restoreBusy) ? null : _backupNow,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: _backupBusy
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 15),
                label: const Text('Backup Now'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_backupBusy || _restoreBusy) ? null : _exportAs,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.drive_file_move_outlined, size: 15),
                label: const Text('Export As…'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed:
                    (_backupBusy || _restoreBusy) ? null : _restoreFromFile,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: _restoreBusy
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.settings_backup_restore, size: 15),
                label: const Text('Restore From File…'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Snapshots include tasks, execution logs, sub-steps and attachment references. '
            'Default location: Documents/TaskFlow/backups/.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.45),
              height: 1.4,
            ),
          ),

          const Divider(height: 28),

          // Drive sync
          Row(
            children: [
              Icon(Icons.cloud_sync_outlined,
                  size: 17, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Google Drive Sync',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                sync.enabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: sync.enabled ? Colors.green : Colors.orange,
                ),
              ),
              Switch(
                value: sync.enabled,
                onChanged: (v) => ref.read(syncProvider.notifier).setEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Syncs via the Google Drive for Desktop mirror folder '
            '(TaskFlow/taskflow_sync.json) — no API credentials needed. '
            'Install Drive for Desktop and sign in, then point TaskFlow at the folder.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.45),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // Folder row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _folderController,
                  readOnly: true,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'e.g. C:\\Users\\you\\Google Drive',
                    isDense: true,
                    prefixIcon: const Icon(Icons.folder_outlined, size: 17),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _browseFolder,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: const Text('Browse…'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _autoDetect,
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.search, size: 15),
                label: const Text('Auto-detect'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sync actions
          Row(
            children: [
              FilledButton.icon(
                onPressed: (sync.busy || !sync.configured)
                    ? null
                    : () => _runSync((n) => n.syncNow()),
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: sync.busy
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync, size: 15),
                label: Text(sync.busy ? 'Syncing…' : 'Sync Now'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (sync.busy || !sync.configured)
                    ? null
                    : () => _runSync((n) => n.push()),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.cloud_upload_outlined, size: 15),
                label: const Text('Push'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (sync.busy || !sync.configured)
                    ? null
                    : () => _runSync((n) => n.pull()),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.cloud_download_outlined, size: 15),
                label: const Text('Pull'),
              ),
              const Spacer(),
              if (sync.lastSyncAt != null)
                Text(
                  'Last sync: ${DateFormat('MM-dd HH:mm').format(sync.lastSyncAt!)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
            ],
          ),
          if (sync.lastMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              sync.lastMessage!,
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.primary.withOpacity(0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
