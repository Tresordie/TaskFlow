import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';

/// Handles picking images/files and copying them into the app's attachments
/// directory so execution-log entries keep valid, persistent references even
/// if the original files are moved or deleted.
///
/// v1.4.83 cross-device: NEW attachments store a RELATIVE path (file name
/// inside the attachments dir) so syncing the TaskFlow data folder (OneDrive,
/// NAS, backup/restore) makes them resolvable on any machine. Legacy
/// absolute paths keep working and are re-resolved by basename.
class AttachmentService {
  AttachmentService._();

  static const _uuid = Uuid();

  /// Cached attachments directory (warmed by [init] at startup so
  /// [resolvePathSync] can run without awaiting).
  static Directory? _cachedDir;

  static const _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.bmp',
    '.webp',
    '.ico',
    '.tif',
    '.tiff',
  };

  /// Directory where attachment copies are stored
  /// (<Documents>/TaskFlow/attachments).
  static Future<Directory> attachmentsDir() async {
    if (_cachedDir != null && await _cachedDir!.exists()) return _cachedDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'TaskFlow', 'attachments'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// Warms the directory cache — call once at startup.
  static Future<void> init() async {
    await attachmentsDir();
  }

  /// Resolves a stored attachment path to a path that exists on THIS
  /// machine. Handles: relative names (portable), legacy absolute paths,
  /// and cross-device moves (basename lookup inside the attachments dir).
  static String resolvePathSync(String stored) {
    if (stored.isEmpty) return stored;
    if (File(stored).existsSync()) return stored;
    final dir = _cachedDir;
    if (dir != null) {
      final asRelative = p.join(dir.path, stored);
      if (File(asRelative).existsSync()) return asRelative;
      final byBase = p.join(dir.path, p.basename(stored));
      if (File(byBase).existsSync()) return byBase;
    }
    return stored;
  }

  /// Opens the image picker and returns stored [Attachment]s.
  static Future<List<Attachment>> pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return [];
    return _storeFiles(result);
  }

  /// Opens the file picker (any type) and returns stored [Attachment]s.
  static Future<List<Attachment>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null) return [];
    return _storeFiles(result);
  }

  /// Copies each picked file into the attachments directory and builds an
  /// [Attachment] pointing at the stored copy.
  static Future<List<Attachment>> _storeFiles(FilePickerResult result) async {
    final dir = await attachmentsDir();
    final attachments = <Attachment>[];

    for (final picked in result.files) {
      final sourcePath = picked.path;
      if (sourcePath == null) continue;
      final source = File(sourcePath);
      if (!await source.exists()) continue;

      final name = picked.name;
      final ext = p.extension(name);
      final destName = '${_uuid.v4()}$ext';
      final destPath = p.join(dir.path, destName);
      await source.copy(destPath);

      attachments.add(Attachment()
        ..uid = _uuid.v4()
        ..name = name
        // Relative (portable) path — see class doc on cross-device sync.
        ..path = destName
        ..size = picked.size
        ..type =
            isImagePath(name) ? AttachmentType.image : AttachmentType.file);
    }
    return attachments;
  }

  /// v1.4.83: grabs an image from the system clipboard (e.g. a copied
  /// screenshot) and stores it like a picked file. Returns null when the
  /// clipboard holds no image. Windows-only (desktop app).
  static Future<Attachment?> pasteClipboardImage() async {
    if (!Platform.isWindows) return null;
    final tempPath = p.join(
        Directory.systemTemp.path, 'taskflow_clip_${_uuid.v4()}.png');
    final script = 'Add-Type -AssemblyName System.Windows.Forms,System.Drawing; '
        '\$i=[System.Windows.Forms.Clipboard]::GetImage(); '
        'if(\$i){\$i.Save(\'$tempPath\',[System.Drawing.Imaging.ImageFormat]::Png); '
        'Write-Output \'OK\'}';
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-Command', script],
        runInShell: false,
      );
      if ((result.stdout as String?)?.contains('OK') != true) return null;
      final source = File(tempPath);
      if (!await source.exists()) return null;

      final dir = await attachmentsDir();
      final destName = '${_uuid.v4()}.png';
      final destPath = p.join(dir.path, destName);
      await source.copy(destPath);
      final size = await source.length();
      try {
        await source.delete();
      } catch (_) {}

      return Attachment()
        ..uid = _uuid.v4()
        ..name = 'clipboard-image.png'
        ..path = destName
        ..size = size
        ..type = AttachmentType.image;
    } catch (_) {
      return null;
    }
  }

  /// Whether a file name refers to a displayable image.
  static bool isImagePath(String name) {
    return _imageExtensions.contains(p.extension(name).toLowerCase());
  }

  /// Opens an attachment with the system default application.
  static Future<void> openAttachment(Attachment attachment) async {
    final path = resolvePathSync(attachment.path);
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {
      // Silently ignore failures to launch an external viewer.
    }
  }

  /// Human-readable file size (e.g. "1.2 MB").
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
