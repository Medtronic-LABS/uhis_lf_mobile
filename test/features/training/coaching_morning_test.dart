/// Unit tests for morning-priority parsing and SQLite rank application.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/features/training/coaching_dao.dart';
import 'package:uhis_next/features/training/coaching_repository.dart';

Future<AppDatabase> _openInMemoryDb() async {
  final rawDb = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppDatabase.schemaVersion,
      onCreate: AppDatabase.createSchema,
    ),
  );
  return AppDatabase.forTesting(rawDb);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CoachingRepository.parseMorningModuleIds', () {
    test('reads string ids from modules', () {
      expect(
        CoachingRepository.parseMorningModuleIds({
          'modules': ['anc-1', 'ncd-2'],
        }),
        ['anc-1', 'ncd-2'],
      );
    });

    test('reads module_id objects and module_ids key', () {
      expect(
        CoachingRepository.parseMorningModuleIds({
          'module_ids': [
            {'module_id': 'a'},
            {'id': 'b'},
            'c',
          ],
        }),
        ['a', 'b', 'c'],
      );
    });

    test('returns empty for null / missing list', () {
      expect(CoachingRepository.parseMorningModuleIds(null), isEmpty);
      expect(CoachingRepository.parseMorningModuleIds({}), isEmpty);
    });
  });

  group('CoachingDao.applyMorningPriorities', () {
    late AppDatabase db;
    late CoachingDao dao;

    setUp(() async {
      db = await _openInMemoryDb();
      dao = CoachingDao(db);
      for (final id in ['low', 'mid', 'high']) {
        await dao.upsertModule(
          id: id,
          domain: 'anc',
          titleEn: id,
          titleBn: id,
          estimatedMinutes: 5,
          rawJson: '{"id":"$id","domain":"anc","title":{"en":"$id"}}',
        );
      }
    });

    tearDown(() async {
      await db.close();
    });

    test('ranks ordered ids highest-first and clears the rest', () async {
      await dao.applyMorningPriorities(['high', 'mid']);

      final rows = await dao.allModulesWithProgress();
      expect(rows.map((r) => r['id']).toList(), ['high', 'mid', 'low']);
      expect(rows[0]['priority_today'], 2);
      expect(rows[1]['priority_today'], 1);
      expect(rows[2]['priority_today'], 0);
    });
  });
}
