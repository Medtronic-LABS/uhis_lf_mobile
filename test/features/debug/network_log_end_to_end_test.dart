import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/db/app_database.dart';
import 'package:uhis_next/core/net_log/db_network_request_recorder.dart';
import 'package:uhis_next/core/net_log/native_network_event_source.dart';
import 'package:uhis_next/core/net_log/network_log_dao.dart';
import 'package:uhis_next/core/net_log/network_log_repository.dart';
import 'package:uhis_next/features/debug/network_log_screen.dart';

import '../../core/api/scripted_adapter.dart';

/// One request through the real ApiClient, recorder, DAO, repository and
/// screen: the sanitised url and the status are what the user sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a scripted request shows up on the Network page sanitised', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late final NetworkLogRepository repo;
    late final AppDatabase db;
    await tester.runAsync(() async {
      final raw = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onCreate: AppDatabase.createSchema,
        ),
      );
      db = AppDatabase.forTesting(raw);
      final dao = NetworkLogDao(db, retention: const Duration(days: 36500));
      final recorder = DbNetworkRequestRecorder(dao);
      final api = await ApiClient.create(networkRecorder: recorder);
      api.dio.httpClientAdapter = ScriptedAdapter(const {})
        ..successStatus = 404;
      await api.dio.get<dynamic>(
        'https://example.test/x/jane@example.org?token=abc',
      );
      repo = NetworkLogRepository(
        dao: dao,
        recorder: recorder,
        native: const UnavailableNativeNetworkEventSource(),
      );
    });
    addTearDown(() => tester.runAsync(db.close));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        Provider<NetworkLogRepository>.value(
          value: repo,
          child: const MaterialApp(home: NetworkLogScreen(endpoints: [])),
        ),
      );
      // The controller loads through real I/O, so let it finish for real.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    expect(find.text('https://example.test/x/{id}'), findsOneWidget);
    expect(find.text('404'), findsOneWidget);
    expect(find.textContaining('token'), findsNothing);
    expect(find.textContaining('jane'), findsNothing);
    expect(find.text(NetworkLogStrings.empty), findsNothing);
  });
}
