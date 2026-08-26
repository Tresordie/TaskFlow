# TaskFlow

**English** | [中文](README_CN.md)

Cross-platform task management app for hardware test engineers. Built with Flutter.

## Quick Start

### Prerequisites

- Flutter SDK >= 3.4.0 (https://docs.flutter.dev/get-started/install)
- Dart SDK >= 3.4.0

### Setup

```bash
# 1. Generate platform-specific project files
flutter create . --platforms=windows,macos,ios --org com.taskflow

# 2. Install dependencies
flutter pub get

# 3. Run code generation (Isar + Riverpod)
dart run build_runner build --delete-conflicting-outputs

# 4. Run the app
flutter run -d windows   # or -d macos
```

### Project Structure

```
lib/
├── main.dart                          # Entry point (desktop chrome guarded)
├── app/
│   ├── app.dart                       # MaterialApp + theme + font scaling
│   └── router.dart                    # GoRouter navigation
├── core/
│   ├── theme/
│   │   ├── app_colors.dart            # 7 theme palettes + priority colors
│   │   └── app_theme.dart             # ThemeData per palette
│   └── markdown/
│       ├── latex_support.dart         # $..$ / $$..$$ LaTeX in Markdown
│       ├── rich_markdown.dart         # ++underline++ / ==highlight== / <font …>
│       ├── line_breaks.dart           # hard-breaks, indent preservation,
│       │                              #   list-nesting normalization
│       └── html_export.dart           # Markdown → standalone/email HTML
├── data/
│   ├── models/task.dart               # Task, ExecutionEntry, SubStep (Isar)
│   ├── database/app_database.dart     # Isar instance manager
│   ├── repositories/task_repository.dart  # Data access layer
│   └── services/
│       ├── attachment_service.dart    # Attachment copies on disk
│       ├── ai_service.dart            # OpenAI-compatible chat client
│       ├── report_service.dart        # Period aggregation + MD/HTML
│       ├── backup_service.dart        # JSON snapshot / restore
│       └── sync_service.dart          # Google Drive folder sync
├── providers/
│   ├── task_providers.dart            # Task state + filters
│   ├── theme_provider.dart            # Persisted theme mode
│   ├── font_provider.dart             # Persisted font + scale
│   ├── ai_provider.dart               # Persisted AI endpoint config
│   └── sync_providers.dart            # Backup + sync notifiers
└── presentation/
    ├── shared/                        # App shell, custom title bar,
    │                                  #   MarkdownEditorField (Write/Preview),
    │                                  #   MarkdownToolbar, SelectableMarkdownBody
    ├── task_board/                    # Today board + quick add
    ├── task_detail/                   # Detail, execution log, edit dialog
    ├── timeline/  calendar/  heatmap/ # Chronological views
    ├── ai_parse/                      # Phase 2: notes → tasks
    ├── reports/                       # Phase 3: report builder + preview
    └── settings/                      # Theme/font/AI/backup & sync

test/
├── core_logic_test.dart               # Report periods, AI config, enums
└── widget_test.dart                   # LaTeX rendering, title bar
```

## Features

### Phase 1 — Core task management
- Task CRUD with priority levels (P0-P3) and status tracking
- Execution log: timestamped entries with type (Note/Pass/Fail/Blocked), Markdown + LaTeX rendering, edit/delete entries, file & image attachments
- Sub-step checklists within tasks
- Today board, Timeline, Calendar and Activity (heatmap) views
- Quick-add bar with priority + due date
- 7 color themes, 10 font presets + custom fonts, global font-size scaling (80–140%)
- Responsive: sidebar on desktop, bottom nav on mobile
- Local-first persistence via Isar (NoSQL)

### Phase 2 — AI note parsing
- Configure any OpenAI-compatible endpoint (DeepSeek / OpenAI / Qwen / Ollama…) in Settings → AI Assistant, with connection test
- Paste raw notes (meeting minutes, test logs, chat excerpts) → LLM extracts structured tasks (title, description, priority, tags, sub-steps)
- Optional parsing prompt + file attachments (txt/md/pdf/docx/xlsx/pptx…) → AI summarizes in Markdown; the summary survives page switches, is copyable as Markdown and downloadable as `.md` / `.html`
- Review parsed tasks with checkboxes, then create them all in one click

### Phase 3 — Report generation
- Daily / weekly / monthly / yearly aggregation of tasks + execution logs
- Dashboard stats: touched / completed / in-progress / overdue / completion rate / Pass-Fail-Blocked counts / sub-step progress
- Per-task checkbox picker and project/tag/status/priority filters
- AI-powered full report generation (OpenAI-compatible LLM) with fallback to deterministic template
- Archived tasks are automatically excluded from reports
- Live Markdown preview; export to `.md` or styled standalone `.html`
- Exports land in `Documents/TaskFlow/reports/`

### Phase 4 — Work Log
- Dedicated work-log journal with rich Markdown input (Write/Preview toggle)
- AI key-point summary across all records
- Right-click “Copy as Markdown” on any record
- Filter by date / project / keyword

### Phase 5 — Backup & sync
- One-click JSON backup (tasks, logs, sub-steps, attachment references) to `Documents/TaskFlow/backups/` or any location
- Restore with **Full restore** (replace everything) or **Merge** (upsert by task uid)
- Google Drive sync through the Drive-for-Desktop mirror folder (`TaskFlow/taskflow_sync.json`) — push / pull / auto direction, no API credentials needed

### Phase 6 — Polish
- Staggered entrance animations on the task board (flutter_animate)
- Archived tasks render like Completed (green check + strikethrough) with status label under title
- Robust Markdown rendering for pasted content: normalizes CRLF line endings and invisible Unicode spaces (non-breaking / full-width) so lists copied from browsers or other apps render correctly
- Desktop-only chrome guarded for iOS/Android (custom title bar & window_manager skipped on mobile)
- Unit + widget test suite (`flutter test`): report period math, AI config, LaTeX rendering, title bar

### Phase 7 — Unified rich-text input & record display
- **Every input area** (Work Log, execution log + edit dialog, task description create/edit dialogs, AI Parse notes, Report editor) supports Markdown + rich text with instant **Write/Preview toggle** — the preview uses the SAME style sheet as the saved content (true WYSIWYG "input-as-preview")
- Formatting toolbar: H1–H3, bold / italic / strikethrough, `++underline++`, `==highlight==`, `<font color>` & `<font size>`, quote, hyperlink, task list, bullet/numbered lists, inline code, fenced code block, indent / outdent
- **Tab / Shift+Tab**: Tab inserts two spaces AT the caret (only the content after the cursor shifts right); with a multi-line selection the whole block is (de)indented and stays selected for repeated presses; Shift+Tab removes the line's leading indentation
- Preview fidelity with `workreport.html`: paragraph leading indentation is preserved in rendering (NBSP hardening), and under-indented sub-items are normalized to nest under their parent list item (indent-based nesting semantics)
- **All saved records** (work-log entries, AI summaries, execution-log notes, task descriptions, parsed-task descriptions, report preview, summary history) render as Markdown preview, are **mouse drag-selectable as a whole document**, and offer right-click **“Copy as Markdown”** to grab the original Markdown source

## Data locations

| What | Where |
| --- | --- |
| Database (Isar) | `Documents/taskflow.isar` |
| Attachments | `Documents/TaskFlow/attachments/` |
| Reports | `Documents/TaskFlow/reports/` |
| Backups | `Documents/TaskFlow/backups/` |
| Settings | Windows registry `HKCU\Software\com.taskflow\taskflow` / macOS preferences |

## Roadmap (ideas)

- Full Google Drive OAuth sync (googleapis) as an alternative to folder sync
- Recurring tasks and reminders
- CSV import from test-station exports
