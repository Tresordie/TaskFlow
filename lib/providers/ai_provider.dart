import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for the OpenAI-compatible LLM endpoint used by the
/// AI note-parsing feature. Works with any provider that exposes the
/// standard `/chat/completions` API (DeepSeek, Qwen/DashScope, OpenAI,
/// Ollama, etc.).
class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  /// Default model pre-filled for fresh installs (DeepSeek V4 Pro).
  static const defaultModel = 'deepseek-v4-pro';

  const AiConfig(
      {this.baseUrl = '', this.apiKey = '', this.model = defaultModel});

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  AiConfig copyWith({String? baseUrl, String? apiKey, String? model}) =>
      AiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}

final aiConfigProvider =
    StateNotifierProvider<AiConfigNotifier, AiConfig>((ref) {
  return AiConfigNotifier();
});

class AiConfigNotifier extends StateNotifier<AiConfig> {
  static const _kBaseUrl = 'settings.ai.baseUrl';
  static const _kApiKey = 'settings.ai.apiKey';
  static const _kModel = 'settings.ai.model';

  /// v1.8.0: false until [_restore] has landed. The restore is async while
  /// the notifier is created lazily on first read — the Settings card must
  /// not latch the empty default it sees before this turns true, or the
  /// fields would stay blank (and the next autosave could overwrite the
  /// stored config with blanks).
  bool restored = false;

  AiConfigNotifier() : super(const AiConfig()) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedModel = prefs.getString(_kModel);
      restored = true;
      state = AiConfig(
        baseUrl: prefs.getString(_kBaseUrl) ?? '',
        apiKey: prefs.getString(_kApiKey) ?? '',
        // Fall back to the default model when nothing was saved yet (or an
        // older version persisted an empty string).
        model: (savedModel == null || savedModel.trim().isEmpty)
            ? AiConfig.defaultModel
            : savedModel,
      );
    } catch (_) {
      // Best-effort.
      restored = true;
    }
  }

  Future<void> save(AiConfig config) async {
    state = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBaseUrl, config.baseUrl);
      await prefs.setString(_kApiKey, config.apiKey);
      await prefs.setString(_kModel, config.model);
    } catch (_) {
      // Best-effort.
    }
  }
}
