/// Unit test for [CoachingRepository.clear] — the in-memory training-progress
/// cache-clear added alongside AuthState.registerLogoutHook (GitHub issue
/// #37 follow-up: CoachingRepository is a single long-lived instance for the
/// app's whole process, so its cached module list must be reset on logout).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
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

  late AppDatabase db;
  late CoachingRepository repo;

  setUp(() async {
    db = await _openInMemoryDb();
    final dao = CoachingDao(db);
    await dao.upsertModule(
      id: 'm-1',
      domain: 'anc',
      titleEn: 'Danger signs',
      titleBn: 'বিপদ চিহ্ন',
      estimatedMinutes: 5,
      rawJson: '{"id":"m-1","domain":"anc","title":{"en":"Danger signs"}}',
      priorityToday: true,
    );
    repo = CoachingRepository(dao, await ApiClient.create(), AuthRepository(await ApiClient.create()));
    await repo.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  test('initialize() populates the in-memory module cache', () {
    expect(repo.modules, isNotEmpty,
        reason: 'sanity check — clear() below must actually be clearing something');
  });

  test('clear() drops the cached modules so a new session starts empty',
      () {
    repo.clear();

    expect(repo.modules, isEmpty);
    expect(repo.todaysPriorities, isEmpty);
  });
}
