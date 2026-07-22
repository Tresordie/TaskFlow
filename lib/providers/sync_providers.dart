import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/backup_service.dart';
import '../data/services/sync_service.dart';
import 'task_providers.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(taskRepositoryProvider));
});

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref.watch(backupServiceProvider));
});
