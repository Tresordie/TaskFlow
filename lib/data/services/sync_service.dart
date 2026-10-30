import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'attachment_service.dart';
import 'backup_service.dart';

/// Git sync strategy (v1.13.0, replaces the Google Drive folder mirror):
///
/// The sync folder is a plain git clone of the `taskflow_database`
/// repository (private on Gitee AND GitHub). Inside it lives the same
/// layout the Drive era used — `TaskFlow/taskflow_sync.json` plus
/// `TaskFlow/attachments/` — so migrating means copying files once.
/// A sync round is: commit local changes → `pull --rebase` against the
/// remotes → merge the snapshot into the local DB by uid (newer
/// `updatedAt` wins, deletions are not propagated) → write the merged
/// union back → commit → `push` to every remote.
///
/// Dual-push (one repo, two hosts) is a property of the clone itself:
/// `origin` carries two `pushurl` entries, so a single push writes Gitee
/// and GitHub at once. TaskFlow stores no remote URLs and no
/// credentials — authentication is left to the OS Git credential manager
/// (GCM / macOS Keychain) after a one-time manual clone + login per
/// machine, and every command runs non-interactive
/// (`GIT_TERMINAL_PROMPT=0`) so it can never hang waiting for a prompt.
///
/// If a rebase conflict hits the snapshot JSON, the REMOTE version wins
/// at file level (`-X ours` — "ours" is the upstream during rebase):
/// the local machine's newer edits are still ahead in its own database,
/// and the task-level merge right after re-absorbs them into the next
/// pushed snapshot, so all machines converge to the union.
class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}

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

  bool get isGitRepo => SyncNotifier.isGitRepo(folderPath);

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

  /// Background auto-sync cadence while the feature is enabled.
  static const autoSyncInterval = Duration(minutes: 5);

  /// Per-git-command timeout for local plumbing commands.
  static const _gitTimeout = Duration(seconds: 60);

  /// Network commands get more headroom: pushing a repo that carries tens
  /// of MB of attachments through a proxy legitimately takes minutes
  /// (measured ~90 s on the first push of a 54 MB file).
  static const _netTimeout = Duration(seconds: 300);

  /// GitHub hard-rejects single files >100 MB; keep well under the cap.
  static const _maxAttachmentBytes = 95 * 1024 * 1024;

  final BackupService _backup;
  Timer? _autoTimer;
  Timer? _kickoffTimer;

  /// Resolved git executable, cached once found.
  String? _gitBin;

  SyncNotifier(this._backup) : super(const SyncState()) {
    _restore();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _kickoffTimer?.cancel();
    super.dispose();
  }

  /// The snapshot lives in a TaskFlow sub-folder of the sync repo so it
  /// does not clutter the repository root (and so the old Drive-era file
  /// layout migrates 1:1).
  String get _syncFilePath =>
      p.join(state.folderPath, 'TaskFlow', 'taskflow_sync.json');

  /// Attachment binaries mirrored next to the snapshot so other devices
  /// can actually DISPLAY synced images/files. Attachment DB records
  /// store relative file names, so once the file exists in the local
  /// attachments dir it resolves automatically.
  String get _repoAttachmentsDir =>
      p.join(state.folderPath, 'TaskFlow', 'attachments');

  // ──────────────────────────── git plumbing ────────────────────────────

  static bool isGitRepo(String path) =>
      path.trim().isNotEmpty && Directory(p.join(path, '.git')).existsSync();

  /// Finds a usable git executable. GUI launches (especially on macOS and
  /// freshly-installed Windows) often have a reduced PATH, so probe the
  /// standard install locations too.
  Future<String?> _resolveGit() async {
    if (_gitBin != null) return _gitBin;
    final candidates = Platform.isWindows
        ? ['git', r'C:\Program Files\Git\cmd\git.exe', r'C:\Program Files\Git\bin\git.exe']
        : ['git', '/usr/bin/git', '/opt/homebrew/bin/git', '/usr/local/bin/git'];
    for (final c in candidates) {
      try {
        final r = await Process.run(c, ['--version']);
        if (r.exitCode == 0) return _gitBin = c;
      } catch (_) {}
    }
    return null;
  }

  /// Runs one git command in the repo, non-interactive, with a hard
  /// timeout. A timed-out command is KILLED and reported as a plain
  /// failure (exit 124) — an abandoned-but-alive git would keep pushing in
  /// the background and race the next sync round (observed: "cannot lock
  /// ref … reference already exists" on GitHub after a 60 s timeout let a
  /// 90 s push finish on its own).
  Future<ProcessResult> _git(List<String> args,
      {Duration timeout = _gitTimeout}) async {
    final bin = await _resolveGit();
    if (bin == null) {
      throw const SyncException(
          'git executable not found — install Git for Windows / Xcode '
          'Command Line Tools first.');
    }
    final proc = await Process.start(
      bin,
      args,
      workingDirectory: state.folderPath,
      environment: {'GIT_TERMINAL_PROMPT': '0', 'GCM_INTERACTIVE': 'never'},
      includeParentEnvironment: true,
    );
    final stdoutF =
        proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    final stderrF =
        proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();
    var timedOut = false;
    int code;
    try {
      code = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      proc.kill();
      code = 124;
    }
    return ProcessResult(
      proc.pid,
      code,
      await stdoutF,
      timedOut
          ? 'git ${args.first} timed out after ${timeout.inSeconds}s'
          : await stderrF,
    );
  }

  static String _errLine(ProcessResult r) {
    final lines =
        (r.stderr as String? ?? '').split('\n').where((l) => l.trim().isNotEmpty);
    final last = lines.isEmpty ? 'unknown error' : lines.last.trim();
    return last.length > 120 ? last.substring(0, 120) : last;
  }

  /// Keeps git from rewriting line endings so Windows and macOS machines
  /// produce byte-identical snapshots instead of CRLF churn polluting the
  /// history. Written once, never touched again.
  Future<void> _ensureGitAttributes() async {
    final f = File(p.join(state.folderPath, '.gitattributes'));
    if (!f.existsSync()) {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('* -text\n');
    }
  }

  /// All configured remotes, `gitee` first (domestic network is the more
  /// reliable one; a plain single `origin` with dual pushurls is ordered
  /// trivially).
  Future<List<String>> _remotes() async {
    final r = await _git(['remote']);
    final names = (r.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    return [
      ...names.where((n) => n == 'gitee'),
      ...names.where((n) => n != 'gitee'),
    ];
  }

  /// Commits whatever is in the working tree. An empty result is normal
  /// (exit != 0 on "nothing to commit") and ignored.
  Future<void> _commitAll(String reason) async {
    await _git(['add', '-A']);
    await _git([
      '-c', 'user.name=TaskFlow',
      '-c', 'user.email=sync@taskflow.local',
      'commit',
      '-m',
      '$reason ${DateTime.now().toIso8601String()} @ ${Platform.localHostname}',
    ]);
  }

  /// Rebases onto the first reachable remote. Returns null on success
  /// (including "nothing to pull yet"), or a summarized error string.
  Future<String?> _pull() async {
    // A freshly cloned EMPTY repo has no commits yet — nothing to pull;
    // the first push will seed the remote branch.
    final hasHead =
        (await _git(['rev-parse', '--verify', 'HEAD'])).exitCode == 0;
    if (!hasHead) return null;
    final remotes = await _remotes();
    if (remotes.isEmpty) return null;
    final branch = (await _git(['symbolic-ref', '--short', 'HEAD']))
        .stdout
        .toString()
        .trim();
    final errs = <String>[];
    for (final remote in remotes) {
      final r = await _git(['pull', '--rebase', '-X', 'ours', remote, branch],
          timeout: _netTimeout);
      if (r.exitCode == 0) return null;
      // Leave no half-finished rebase behind before trying the next remote.
      await _git(['rebase', '--abort']);
      errs.add('$remote: ${_errLine(r)}');
    }
    return 'pull failed (${errs.join('; ')})';
  }

  /// Pushes HEAD to every remote — with a dual-pushurl `origin`, one push
  /// writes Gitee AND GitHub. Returns (pushed, per-remote errors).
  Future<(int, List<String>)> _push() async {
    var pushed = 0;
    final errs = <String>[];
    for (final remote in await _remotes()) {
      final r = await _git(['push', remote, 'HEAD'], timeout: _netTimeout);
      if (r.exitCode == 0) {
        pushed++;
      } else {
        errs.add('$remote: ${_errLine(r)}');
      }
    }
    return (pushed, errs);
  }

  // ──────────────────────── state ↔ repository ────────────────────────

  /// Copies every file in [from] that is missing in [to] (copy-if-missing
  /// is safe: attachments are immutable uuid-named files), skipping
  /// oversized files that would be rejected by the remotes. Runs with
  /// bounded concurrency. Returns (copied, skipped).
  Future<(int, int)> _copyMissing({
    required Directory from,
    required Directory to,
  }) async {
    if (!from.existsSync()) return (0, 0);
    if (!to.existsSync()) to.createSync(recursive: true);
    final files = <File>[];
    await for (final entity in from.list()) {
      if (entity is File) files.add(entity);
    }
    var copied = 0;
    var skipped = 0;
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= files.length) return;
        final src = files[i];
        final dest = File(p.join(to.path, p.basename(src.path)));
        if (dest.existsSync()) continue;
        try {
          if (src.lengthSync() > _maxAttachmentBytes) {
            skipped++;
            continue;
          }
          await src.copy(dest.path);
          if (dest.existsSync()) {
            copied++;
          } else {
            skipped++;
          }
        } catch (_) {
          skipped++;
        }
      }
    }

    const concurrency = 4;
    await Future.wait([
      for (var k = 0; k < concurrency && k < files.length; k++) worker(),
    ]);
    return (copied, skipped);
  }

  /// PHASE 1 helper: merge the repository snapshot into the local DB and
  /// copy attachment files the repo has but this machine lacks.
  Future<(int tasks, int files, int skipped)> _pullFromRepo() async {
    var tasks = 0;
    final file = File(_syncFilePath);
    if (file.existsSync()) {
      tasks =
          await _backup.restoreSnapshot(await file.readAsString(), merge: true);
    }
    final local = await AttachmentService.attachmentsDir();
    final (files, skipped) =
        await _copyMissing(from: Directory(_repoAttachmentsDir), to: local);
    return (tasks, files, skipped);
  }

  /// PHASE 2 helper: write the merged local database back as the snapshot
  /// and copy attachment files this machine has but the repo lacks.
  Future<(int files, int skipped)> _pushToRepo() async {
    final file = File(_syncFilePath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    await file.writeAsString(await _backup.buildSnapshot());
    final local = await AttachmentService.attachmentsDir();
    return _copyMissing(from: local, to: Directory(_repoAttachmentsDir));
  }

  /// Verifies the configured folder is a git clone and git is runnable.
  /// Returns an error message, or null when ready to sync.
  Future<String?> _preflight() async {
    if (!Directory(state.folderPath).existsSync()) {
      return 'Sync folder not found — point TaskFlow at your '
          'taskflow_database clone in settings.';
    }
    if (!isGitRepo(state.folderPath)) {
      return 'That folder is not a git repository — clone the '
          'taskflow_database repo into it first (see README, Git Sync).';
    }
    if (await _resolveGit() == null) {
      return 'git executable not found — install Git for Windows / '
          'Xcode Command Line Tools.';
    }
    return null;
  }

  static String _issueSuffix(
          {String? pullErr,
          List<String> pushErrs = const [],
          int pushed = -1,
          int skipped = 0}) =>
      '${pullErr != null ? ' · ⚠ Pull $pullErr' : ''}'
      '${pushErrs.isNotEmpty ? ' · ⚠ Push failed: ${pushErrs.join('; ')}' : ''}'
      '${pushed == 0 && pushErrs.isEmpty ? ' · (no remotes configured)' : ''}'
      '${skipped > 0 ? ' · $skipped attachment(s) skipped (>95 MB)' : ''}';

  // ────────────────────────────── lifecycle ──────────────────────────────

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = state.copyWith(
        folderPath: prefs.getString(_kFolder) ?? '',
        enabled: prefs.getBool(_kEnabled) ?? false,
        lastSyncAt: _parse(prefs.getString(_kLastSync)),
      );
      _updateAutoTimer();
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
    _updateAutoTimer();
    state = state.copyWith(busy: false);
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await _persist();
    _updateAutoTimer();
  }

  /// Starts/stops the background timers to match the current settings.
  /// Enabled users get a catch-up round shortly after the app starts, then
  /// a periodic one, so two open machines converge without anyone
  /// pressing "Sync Now".
  void _updateAutoTimer() {
    _autoTimer?.cancel();
    _kickoffTimer?.cancel();
    if (!state.enabled || !state.configured) return;
    _kickoffTimer = Timer(const Duration(seconds: 30), syncNow);
    _autoTimer = Timer.periodic(autoSyncInterval, (_) => syncNow());
  }

  /// Best-effort detection of a local taskflow_database clone, looking in
  /// the places the README tells users to put it.
  static Future<String?> detectGitRepo() async {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final bases = <String>[
      if (home.isNotEmpty) p.join(home, 'gitee'),
      if (home.isNotEmpty) home,
      r'F:\gitee',
      r'C:\gitee',
    ];
    for (final base in bases) {
      final candidate = p.join(base, 'taskflow_database');
      if (isGitRepo(candidate)) return candidate;
    }
    return null;
  }

  // ─────────────────────────────── actions ───────────────────────────────

  /// Pushes the local database to the repository and every remote.
  Future<void> push() async {
    if (!state.configured) {
      state = state.copyWith(lastMessage: 'No sync folder configured.');
      return;
    }
    if (state.busy) return;
    state = state.copyWith(busy: true);
    final err = await _preflight();
    if (err != null) {
      state = state.copyWith(busy: false, lastMessage: err);
      return;
    }
    try {
      await _ensureGitAttributes();
      final (files, skipped) = await _pushToRepo();
      await _commitAll('sync');
      final (pushed, pushErrs) = await _push();
      final base = files > 0
          ? 'Pushed tasks + $files attachment file(s) → git'
          : 'Pushed local tasks → git';
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage:
            base + _issueSuffix(pushed: pushed, pushErrs: pushErrs, skipped: skipped),
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastMessage: 'Push failed: $e');
    }
    await _persist();
  }

  /// Pulls the repository snapshot into the local database (merge by uid).
  Future<void> pull() async {
    if (!state.configured) {
      state = state.copyWith(lastMessage: 'No sync folder configured.');
      return;
    }
    if (state.busy) return;
    state = state.copyWith(busy: true);
    final err = await _preflight();
    if (err != null) {
      state = state.copyWith(busy: false, lastMessage: err);
      return;
    }
    try {
      await _ensureGitAttributes();
      // Fold any leftover working-tree changes into a commit so the tree
      // is pull-ready; they are old derived snapshots, never lost data.
      await _commitAll('sync');
      final pullErr = await _pull();
      final (tasks, files, skipped) = await _pullFromRepo();
      final base = 'Pulled $tasks task(s)'
          '${files > 0 ? ' + $files attachment file(s)' : ''}'
          ' from git (merged by uid).';
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage:
            base + _issueSuffix(pullErr: pullErr, skipped: skipped),
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastMessage: 'Pull failed: $e');
    }
    await _persist();
  }

  /// Two-PHASE git sync for multi-device use:
  ///   PHASE 1 (Pull):  rebase onto the remotes, merge the snapshot into
  ///                    the local DB (by uid, newer updatedAt wins) and
  ///                    pull every attachment file this machine lacks.
  ///   PHASE 2 (Push):  write the merged local state (tasks + work logs +
  ///                    attachment files) back and push it to all remotes
  ///                    (Gitee + GitHub via the dual pushurl).
  ///
  /// The shared snapshot always converges to the union of every device's
  /// data, so nothing is clobbered when two machines sync in parallel.
  Future<void> syncNow() async {
    if (!state.configured) {
      state = state.copyWith(lastMessage: 'No sync folder configured.');
      return;
    }
    // The auto timer and manual clicks share this method — one round at
    // a time.
    if (state.busy) return;
    state = state.copyWith(busy: true);
    final err = await _preflight();
    if (err != null) {
      state = state.copyWith(busy: false, lastMessage: err);
      return;
    }
    try {
      await _ensureGitAttributes();

      // ── PHASE 1 · PULL: commit leftovers, rebase, merge into the DB ──
      await _commitAll('sync');
      final pullErr = await _pull();
      final (tasks, pullFiles, pullSkipped) = await _pullFromRepo();

      // ── PHASE 2 · PUSH: write the merged union and publish it ──
      final (pushFiles, pushSkipped) = await _pushToRepo();
      await _commitAll('sync');
      final (pushed, pushErrs) = await _push();

      final quiet = tasks == 0 && pullFiles == 0 && pushFiles == 0;
      final base = quiet
          ? 'Synced via git · already up to date'
          : 'Synced via git · Pull: $tasks task(s) + $pullFiles '
              'file(s); Push: tasks + $pushFiles file(s).';
      state = state.copyWith(
        busy: false,
        lastSyncAt: DateTime.now(),
        lastMessage: base +
            _issueSuffix(
                pullErr: pullErr,
                pushed: pushed,
                pushErrs: pushErrs,
                skipped: pullSkipped + pushSkipped),
      );
    } catch (e) {
      state = state.copyWith(busy: false, lastMessage: 'Sync failed: $e');
    }
    await _persist();
  }
}
