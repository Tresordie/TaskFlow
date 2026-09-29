import '../../data/models/task.dart';

/// v1.12.39: one source of truth for the emoji vocabulary used on the
/// Timeline page and the task Execution Log. The glyphs deliberately match
/// what the AI reports already emit (✅ completed / 🚧 in progress / ⚠️
/// blocked watch), so the same meaning reads the same way from the board
/// through to an exported report.
String statusGlyph(TaskStatus status) => switch (status) {
      TaskStatus.planned => '🗓',
      TaskStatus.inProgress => '🚧',
      TaskStatus.completed => '✅',
      TaskStatus.archived => '📦',
      TaskStatus.blocked => '⛔',
    };

/// Marker glyph for an execution-log entry type.
String entryGlyph(EntryType type) => switch (type) {
      EntryType.note => '📝',
      EntryType.pass => '✅',
      EntryType.fail => '❌',
      EntryType.blocked => '⛔',
    };
