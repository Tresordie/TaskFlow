import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/task.dart';

class AppDatabase {
  static Isar? _instance;

  static Future<Isar> get instance async {
    if (_instance != null && _instance!.isOpen) {
      return _instance!;
    }
    final dir = await getApplicationDocumentsDirectory();
    try {
      _instance = await Isar.open(
        [TaskSchema],
        directory: dir.path,
        name: 'taskflow',
      );
    } catch (_) {
      // The on-disk schema no longer matches the current model (e.g. new
      // fields were added). Move the old database files aside — never
      // delete them, so the user's data is preserved and recoverable —
      // then recreate a fresh database so the app keeps working.
      await _quarantineDbFiles(dir.path, 'taskflow');
      _instance = await Isar.open(
        [TaskSchema],
        directory: dir.path,
        name: 'taskflow',
      );
    }
    return _instance!;
  }

  /// Renames the database files out of the way (instead of deleting
  /// them) so a schema-mismatch recovery never destroys user data.
  static Future<void> _quarantineDbFiles(String dir, String name) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final suffix in ['.isar', '.isar.lock']) {
      final file = File(p.join(dir, '$name$suffix'));
      if (await file.exists()) {
        try {
          await file.rename(p.join(dir, '$name$suffix.corrupt-$stamp'));
        } catch (_) {
          // Ignore cleanup errors; the reopen below will surface any issue.
        }
      }
    }
  }

  static Future<void> close() async {
    await _instance?.close();
    _instance = null;
  }
}
