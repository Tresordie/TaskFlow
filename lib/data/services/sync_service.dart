import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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
        await prefs.setString(
            _kLastSync, state.lastSyncAt!.toIso8601String());
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
    final candidates = [
      p.join(home, 'Google Drive'),
      p.join(home, 'GoogleDrive'),
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
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage: 'Pushed local tasks → ${file.path}',
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
      final count = await _backup.restoreSnapshot(await file.readAsString(),
          merge: true);
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage: 'Pulled $count task(s) from Drive (merged by uid).',
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastMessage: 'Pull failed: $e');
    }
    await _persist();
  }

  /// Automatic direction: if the sync file was modified after the last
  /// sync, pull it; otherwise push the local state.
  Future<void> syncNow() async {
    if (!state.configured) {
      state = state.copyWith(lastMessage: 'No sync folder configured.');
      return;
    }
    final file = File(_syncFilePath);
    final last = state.lastSyncAt;
    if (file.existsSync() &&
        (last == null || file.lastModifiedSync().isAfter(last))) {
      await pull();
    } else {
      await push();
    }
  }
}
