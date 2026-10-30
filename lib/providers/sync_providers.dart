import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/backup_service.dart';
import '../data/services/sync_service.dart';
import 'task_providers.dart';
import 'work_log_provider.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
      ref.watch(taskRepositoryProvider), ref.watch(workLogRepositoryProvider));
});

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref.watch(backupServiceProvider));
});
