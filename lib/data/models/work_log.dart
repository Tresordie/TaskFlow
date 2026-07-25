/// Data models for the Work Log feature (ported from the LinguaFlow
/// Chrome extension's workreport page). Persisted as JSON in
/// shared_preferences — the same key/value approach the extension used
/// with chrome.storage.local / localStorage.

/// A single free-form work record entered by the user.
class WorkLogRecord {
  final String id;
  final String content;

  /// Milliseconds since epoch when the record was created/updated.
  final int timestamp;

  WorkLogRecord({
    required this.id,
    required this.content,
    required this.timestamp,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  WorkLogRecord copyWith({String? content, int? timestamp}) => WorkLogRecord(
        id: id,
        content: content ?? this.content,
        timestamp: timestamp ?? this.timestamp,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'timestamp': timestamp,
      };

  factory WorkLogRecord.fromJson(Map<String, dynamic> json) => WorkLogRecord(
        id: (json['id'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      );
}

/// A previously generated AI summary, kept for quick re-loading.
class WorkLogSummary {
  final String id;
  final String dateRange;
  final String content;
  final String inputLang;
  final String outputLang;
  final int timestamp;

  WorkLogSummary({
    required this.id,
    required this.dateRange,
    required this.content,
    required this.inputLang,
    required this.outputLang,
    required this.timestamp,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateRange': dateRange,
        'content': content,
        'inputLang': inputLang,
        'outputLang': outputLang,
        'timestamp': timestamp,
      };

  factory WorkLogSummary.fromJson(Map<String, dynamic> json) => WorkLogSummary(
        id: (json['id'] ?? '').toString(),
        dateRange: (json['dateRange'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        inputLang: (json['inputLang'] ?? 'zh').toString(),
        outputLang: (json['outputLang'] ?? 'zh').toString(),
        timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      );
}

/// The 30 input/output languages offered by the work-report summarizer
/// (code → English display name). Mirrors the extension's LANG_NAMES_EN.
const Map<String, String> kWorkLogLanguages = {
  'zh': 'Chinese',
  'en': 'English',
  'ja': 'Japanese',
  'ko': 'Korean',
  'fr': 'French',
  'de': 'German',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ar': 'Arabic',
  'it': 'Italian',
  'nl': 'Dutch',
  'th': 'Thai',
  'vi': 'Vietnamese',
  'id': 'Indonesian',
  'ms': 'Malay',
  'tr': 'Turkish',
  'pl': 'Polish',
  'sv': 'Swedish',
  'da': 'Danish',
  'fi': 'Finnish',
  'el': 'Greek',
  'cs': 'Czech',
  'ro': 'Romanian',
  'hu': 'Hungarian',
  'uk': 'Ukrainian',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'he': 'Hebrew',
  'fa': 'Persian',
};
