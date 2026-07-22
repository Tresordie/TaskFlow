import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';

/// Handles picking images/files and copying them into the app's attachments
/// directory so execution-log entries keep valid, persistent references even
/// if the original files are moved or deleted.
class AttachmentService {
  AttachmentService._();

  static const _uuid = Uuid();

  static const _imageExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.ico', '.tif', '.tiff',
  };

  /// Directory where attachment copies are stored
  /// (<Documents>/TaskFlow/attachments).
  static Future<Directory> attachmentsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'TaskFlow', 'attachments'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
      final destPath = p.join(dir.path, '${_uuid.v4()}$ext');
      await source.copy(destPath);

      attachments.add(Attachment()
        ..uid = _uuid.v4()
        ..name = name
        ..path = destPath
        ..size = picked.size
        ..type = isImagePath(name)
            ? AttachmentType.image
            : AttachmentType.file);
    }
    return attachments;
  }

  /// Whether a file name refers to a displayable image.
  static bool isImagePath(String name) {
    return _imageExtensions.contains(p.extension(name).toLowerCase());
  }

  /// Opens an attachment with the system default application.
  static Future<void> openAttachment(Attachment attachment) async {
    final path = attachment.path;
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
