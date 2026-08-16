import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'attachment_service.dart';
import 'backup_service.dart';

/// Google Drive sync strategy (Phase 4):
///
/// Full OAuth against the Drive API requires shipping an OAuth client id,
/// which cannot be bundled in an open, credential-free build. Instead,
/// TaskFlow syncs through the *Google Drive for Desktop* mirror folder:
/// a single snapshot file (`TaskFlow/taskflow_sync.json`) is written into
/// the Drive folder and the desktop client transparently uploads it to
/// every machine signed into the same Google account. Pulling works the
/// same way — if the file on disk is newer than the last sync, it is
/// merged into the local database (upsert by task uid).
///
/// This gives real bidirectional sync across machines with zero extra
/// credentials, and the snapshot format is identical to manual backups.
class SyncState {
  final String folderPath;
  final bool enabled;
  final DateTime? lastSyncAt;
  final String? lastMessage;
  final bool busy;

  const SyncState({
    this.folderPath = '',
    this.enabled = false,
    this.lastSyncAt,
    this.lastMessage,
    this.busy = false,
  });

  bool get configured => folderPath.trim().isNotEmpty;

  SyncState copyWith({
    String? folderPath,
    bool? enabled,
    DateTime? lastSyncAt,
    String? lastMessage,
    bool? busy,
    bool clearLastSync = false,
  }) =>
      SyncState(
        folderPath: folderPath ?? this.folderPath,
        enabled: enabled ?? this.enabled,
        lastSyncAt: clearLastSync ? null : (lastSyncAt ?? this.lastSyncAt),
        lastMessage: lastMessage ?? this.lastMessage,
        busy: busy ?? this.busy,
      );
}

class SyncNotifier extends StateNotifier<SyncState> {
  static const _kFolder = 'settings.sync.folder';
  static const _kEnabled = 'settings.sync.enabled';
  static const _kLastSync = 'settings.sync.lastSyncAt';

  final BackupService _backup;

  SyncNotifier(this._backup) : super(const SyncState()) {
    _restore();
  }

  /// The snapshot lives in a TaskFlow sub-folder of the Drive folder so
  /// it does not clutter the Drive root.
  String get _syncFilePath =>
      p.join(state.folderPath, 'TaskFlow', 'taskflow_sync.json');

  /// v1.4.83: attachment binaries are mirrored next to the snapshot so other
  /// devices can actually DISPLAY the synced images/files. Attachment DB
  /// records store relative file names (v1.4.83), so once the file exists
  /// in the local attachments dir it resolves automatically.
  String get _driveAttachmentsDir =>
      p.join(state.folderPath, 'TaskFlow', 'attachments');

  /// Copies local attachment files into the Drive mirror (only files that
  /// are not there yet — attachments are immutable uuid-named files, so
  /// copy-if-missing is safe and idempotent). Returns (copied, failed).
  Future<(int, int)> _pushAttachments() async {
    final local = await AttachmentService.attachmentsDir();
    final remote = Directory(_driveAttachmentsDir);
    if (!remote.existsSync()) remote.createSync(recursive: true);
    var copied = 0, failed = 0;
    await for (final entity in local.list()) {
      if (entity is! File) continue;
      final dest = File(p.join(remote.path, p.basename(entity.path)));
      if (dest.existsSync()) continue;
      try {
        await entity.copy(dest.path);
        copied++;
      } catch (_) {
        failed++;
      }
    }
    return (copied, failed);
  }

  /// Copies attachment files from the Drive mirror into the local
  /// attachments dir. IMPORTANT: the source existence check is skipped —
  /// Google Drive for Desktop lists cloud-only placeholder files whose
  /// existsSync() is false (large files especially), and pre-filtering on
  /// it silently skipped them forever. The copy is attempted for every
  /// listed file; placeholders that are not materialized yet fail and are
  /// reported as pending so the next Sync Now retries them (by then Google
  /// Drive usually has them, or the copy triggers the download).
  /// Returns (copied, pending).
  Future<(int, int)> _pullAttachments() async {
    final remote = Directory(_driveAttachmentsDir);
    if (!remote.existsSync()) return (0, 0);
    final local = await AttachmentService.attachmentsDir();
    var copied = 0, pending = 0;
    await for (final entity in remote.list()) {
      if (entity is! File) continue;
      final dest = File(p.join(local.path, p.basename(entity.path)));
      if (dest.existsSync()) continue;
      try {
        await entity.copy(dest.path);
        if (dest.existsSync()) {
          copied++;
        } else {
          pending++;
        }
      } catch (_) {
        pending++;
      }
    }
    return (copied, pending);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = state.copyWith(
        folderPath: prefs.getString(_kFolder) ?? '',
        enabled: prefs.getBool(_kEnabled) ?? false,
        lastSyncAt: _parse(prefs.getString(_kLastSync)),
      );
    } catch (_) {}
  }

  DateTime? _parse(String? v) =>
      (v == null || v.isEmpty) ? null : DateTime.tryParse(v);

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFolder, state.folderPath);
      await prefs.setBool(_kEnabled, state.enabled);
      if (state.lastSyncAt != null) {
        await prefs.setString(_kLastSync, state.lastSyncAt!.toIso8601String());
      }
    } catch (_) {}
  }

  Future<void> setFolder(String path) async {
    state = state.copyWith(folderPath: path.trim(), busy: true);
    await _persist();
    state = state.copyWith(busy: false);
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await _persist();
  }

  /// Best-effort detection of a local Google Drive mirror folder.
  static String? detectDriveFolder() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (home.isEmpty) return null;
    final candidates = <String>[
      // macOS: Google Drive for Desktop FUSE mount
      '/Volumes/GoogleDrive',
      '/Volumes/Google Drive',
      p.join(home, 'Google Drive'),
      p.join(home, 'GoogleDrive'),
      // Windows
      'C:\\Google Drive',
      'D:\\Google Drive',
      p.join(home, 'OneDrive', 'Google Drive'),
    ];
    for (final c in candidates) {
      if (Directory(c).existsSync()) return c;
    }
    return null;
  }

  /// Pushes the local database to the sync file.
  Future<void> push() async {
    if (!state.configured) {
      state = state.copyWith(lastMessage: 'No sync folder configured.');
      return;
    }
    state = state.copyWith(busy: true);
    try {
      final file = File(_syncFilePath);
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      await file.writeAsString(await _backup.buildSnapshot());
      final (files, failed) = await _pushAttachments();
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage: files > 0 || failed > 0
            ? 'Pushed tasks + $files attachment file(s) → Drive'
                '${failed > 0 ? ' ($failed failed)' : ''}'
            : 'Pushed local tasks → ${file.path}',
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastMessage: 'Push failed: $e');
    }
    await _persist();
  }

  /// Pulls the sync file into the local database (merge by uid).
  Future<void> pull() async {
    if (!state.configured) {
      state = state.copyWith(lastMessage: 'No sync folder configured.');
      return;
    }
    state = state.copyWith(busy: true);
    try {
      final file = File(_syncFilePath);
      if (!file.existsSync()) {
        state = state.copyWith(
            busy: false,
            lastMessage: 'No sync file yet — push first from this or '
                'another machine.');
        await _persist();
        return;
      }
      final count =
          await _backup.restoreSnapshot(await file.readAsString(), merge: true);
      final (files, pending) = await _pullAttachments();
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage: 'Pulled $count task(s)'
            '${files > 0 ? ' + $files attachment file(s)' : ''}'
            '${pending > 0 ? ' · $pending file(s) still uploading on Drive — Sync again shortly' : ''}'
            ' from Drive (merged by uid).',
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastMessage: 'Pull failed: $e');
    }
    await _persist();
  }

  /// Two-PHASE sync for multi-device use (v1.4.86 wording matches the
  /// order):
  ///   PHASE 1 (Pull):  read the remote snapshot from Drive, merge those
  ///                    tasks into the local DB (by uid) AND pull every
  ///                    attachment file this machine still lacks.
  ///   PHASE 2 (Push):  write the merged local state (tasks + attachment
  ///                    files) back to Drive so it holds the union.
  ///
  /// The shared file always converges to the union of every device's data,
  /// so nothing is clobbered when two machines sync around the same time.
  Future<void> syncNow() async {
    if (!state.configured) {
      state = state.copyWith(lastMessage: 'No sync folder configured.');
      return;
    }
    state = state.copyWith(busy: true);
    try {
      final file = File(_syncFilePath);
      var pulled = 0;
      var pulledFiles = 0;
      var pendingFiles = 0;

      // ── PHASE 1 · PULL: remote tasks + missing attachments ──
      if (file.existsSync()) {
        pulled = await _backup.restoreSnapshot(await file.readAsString(),
            merge: true);
      }
      (pulledFiles, pendingFiles) = await _pullAttachments();

      // ── PHASE 2 · PUSH: merged local tasks + local attachments ──
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsString(await _backup.buildSnapshot());
      final (pushedFiles, pushFailed) = await _pushAttachments();

      final changed = pulled > 0 ||
          pulledFiles > 0 ||
          pushedFiles > 0 ||
          pendingFiles > 0 ||
          pushFailed > 0;
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage: changed
            ? 'Synced · Pull: $pulled task(s) + $pulledFiles file(s); '
                'Push: tasks + $pushedFiles file(s).'
                '${pendingFiles > 0 ? ' $pendingFiles file(s) still uploading on Drive — press Sync Now again shortly.' : ''}'
                '${pushFailed > 0 ? ' $pushFailed push(es) failed.' : ''}'
            : 'Synced · already up to date, pushed local state to Drive.',
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastMessage: 'Sync failed: $e');
    }
    await _persist();
  }
}
