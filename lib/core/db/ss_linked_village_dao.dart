import 'package:sqflite/sqflite.dart';

import '../auth/user_hierarchy_service.dart';
import 'app_database.dart';

/// Spice `ShasthyaShebikaLinkedVillageEntity` — SS worker → sub-village links
/// for dashboard geography filters.
class SsLinkedVillageDao {
  SsLinkedVillageDao(this._db);

  final AppDatabase _db;

  static const String tableName = 'shasthya_shebika_linked_villages';

  Future<void> replaceFromSsWorkers(List<SsWorker> workers) async {
    await _db.db.transaction((tx) async {
      await tx.delete(tableName);
      for (final ss in workers) {
        for (final sv in ss.subVillages) {
          await tx.insert(
            tableName,
            {
              'shasthya_shebika_id': ss.id,
              'sub_village_id': sv.id,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }
}
