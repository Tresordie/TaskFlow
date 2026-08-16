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

  /// Copies local attachment files into the Drive mirror. Returns
  /// (copied, failed).
  Future<(int, int)> _pushAttachments() async {
    final local = await AttachmentService.attachmentsDir();
    return _copyMissing(
      from: local,
      to: Directory(_driveAttachmentsDir),
      pinOnFailure: false,
    );
  }

  /// Copies attachment files from the Drive mirror into the local
  /// attachments dir. Cloud-only placeholders whose copy fails get PINNED
  /// for offline use (triggering the Drive download) and the whole pass is
  /// retried once after a short wait, so a single Sync Now usually pulls
  /// everything. Returns (copied, pending).
  Future<(int, int)> _pullAttachments() async {
    final remote = Directory(_driveAttachmentsDir);
    if (!remote.existsSync()) return (0, 0);
    final local = await AttachmentService.attachmentsDir();
    var (copied, failed) = await _copyMissing(
      from: remote,
      to: local,
      pinOnFailure: true,
    );
    if (failed > 0) {
      // Give Google Drive a moment to fetch the pinned files, then retry.
      await Future.delayed(const Duration(seconds: 3));
      final (more, stillFailed) = await _copyMissing(
        from: remote,
        to: local,
        pinOnFailure: true,
      );
      copied += more;
      failed = stillFailed;
    }
    return (copied, failed);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = state.copyWith(
        folderPath: prefs.getString(_kFolder) ?? '',
        enabled: prefs.getBool(_kEnabled) ?? false,
        lastSyncAt: _parse(prefs.getString(_kLastSync)),
      );
      // v1.4.87: the Google Drive mount (drive letter / mount point) can
      // change after a reboot, leaving the persisted absolute path stale.
      // Self-heal at startup by relocating onto the current Drive mount.
      if (state.folderPath.isNotEmpty &&
          !Directory(state.folderPath).existsSync()) {
        final relocated = _relocateDriveFolder();
        if (relocated != null && relocated != state.folderPath) {
          state = state.copyWith(folderPath: relocated);
          await _persist();
        }
      }
    } catch (_) {}
  }

  /// Scans the drive letters for the current Google Drive for Desktop
  /// mount and returns the folder that holds (or should hold) the TaskFlow
  /// sync data. Preference: a mount that already contains the `TaskFlow`
  /// sync folder; otherwise the first recognized Drive root.
  static String? _relocateDriveFolder() {
    if (!Platform.isWindows) return detectDriveFolder();
    String? firstDriveRoot;
    for (var letter = 'D'.codeUnitAt(0); letter <= 'Z'.codeUnitAt(0);
        letter++) {
      final root = '${String.fromCharCode(letter)}:\\';
      if (!Directory(root).existsSync()) continue;
      for (final base in [
        root,
        p.join(root, 'My Drive'),
        p.join(root, '我的云端硬盘'),
      ]) {
        if (!Directory(base).existsSync()) continue;
        // Strong marker: TaskFlow sync data already lives here.
        if (Directory(p.join(base, 'TaskFlow')).existsSync()) return base;
        firstDriveRoot ??= base == root ? null : base;
      }
    }
    return firstDriveRoot ?? detectDriveFolder();
  }

  /// Makes sure the sync folder exists before a transfer — Google Drive
  /// may still be mounting right after boot, so poll briefly and try to
  /// relocate onto the current mount if the saved path went stale.
  Future<bool> _ensureFolderReady() async {
    if (state.configured && Directory(state.folderPath).existsSync()) {
      return true;
    }
    for (var i = 0; i < 6; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final relocated = _relocateDriveFolder();
      if (relocated != null && relocated != state.folderPath) {
        state = state.copyWith(folderPath: relocated);
        await _persist();
      }
      if (state.configured && Directory(state.folderPath).existsSync()) {
        return true;
      }
    }
    return state.configured && Directory(state.folderPath).existsSync();
  }

  /// Asks Google Drive for Desktop to make [path] available offline
  /// (`attrib +P` pins the file), which actively TRIGGERS the download of
  /// cloud-only placeholders instead of waiting for Drive to materialize
  /// them on its own schedule — this is why large attachments previously
  /// needed many Sync Now rounds.
  Future<void> _pinForOffline(String path) async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('attrib', ['+P', '-U', path]);
    } catch (_) {}
  }

  /// Copies every file in [from] that is missing in [to] (copy-if-missing
  /// is safe: attachments are immutable uuid-named files). Copies run with
  /// bounded concurrency; failures (cloud placeholders not materialized
  /// yet) optionally pin the source for offline use. Returns
  /// (copied, failed).
  Future<(int, int)> _copyMissing({
    required Directory from,
    required Directory to,
    required bool pinOnFailure,
  }) async {
    if (!from.existsSync()) return (0, 0);
    if (!to.existsSync()) to.createSync(recursive: true);
    final files = <File>[];
    await for (final entity in from.list()) {
      if (entity is File) files.add(entity);
    }
    var copied = 0;
    var failed = 0;
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= files.length) return;
        final src = files[i];
        final dest = File(p.join(to.path, p.basename(src.path)));
        if (dest.existsSync()) continue;
        try {
          await src.copy(dest.path);
          if (dest.existsSync()) {
            copied++;
          } else {
            failed++;
            if (pinOnFailure) await _pinForOffline(src.path);
          }
        } catch (_) {
          failed++;
          if (pinOnFailure) await _pinForOffline(src.path);
        }
      }
    }

    const concurrency = 4;
    await Future.wait([
      for (var k = 0; k < concurrency && k < files.length; k++) worker(),
    ]);
    return (copied, failed);
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
    if (!await _ensureFolderReady()) {
      state = state.copyWith(
          busy: false,
          lastMessage: 'Google Drive folder not found — make sure Google '
              'Drive for Desktop is running, then re-select the folder.');
      await _persist();
      return;
    }
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
    if (!await _ensureFolderReady()) {
      state = state.copyWith(
          busy: false,
          lastMessage: 'Google Drive folder not found — make sure Google '
              'Drive for Desktop is running, then re-select the folder.');
      await _persist();
      return;
    }
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
    if (!await _ensureFolderReady()) {
      state = state.copyWith(
          busy: false,
          lastMessage: 'Google Drive folder not found — make sure Google '
              'Drive for Desktop is running, then re-select the folder.');
      await _persist();
      return;
    }
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
