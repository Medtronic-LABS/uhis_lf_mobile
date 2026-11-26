import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uhis_next/app/router.dart';
import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';
import 'package:uhis_next/core/net_log/native_network_event_source.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_repository.dart';
import 'package:uhis_next/core/sync/offline_push_service.dart';
import 'package:uhis_next/core/sync/offline_sync_service.dart';
import 'package:uhis_next/features/debug/network_log_screen.dart';
import 'package:uhis_next/features/login/login_screen.dart';
import 'package:uhis_next/features/sync/offline_sync_screen.dart';

class _MemoryStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => values[key] = value;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => values[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => values.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      values.clear();

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(values);
}

class _Repo implements NetworkLogRepository {
  @override
  Future<NetworkLogPage> load({String? service, int offset = 0}) async =>
      const NetworkLogPage(
        rows: <NetworkLogEntry>[],
        counts: {},
        nativeStatus: NativeNetworkStatus.ok,
        droppedCount: 0,
        hasMore: false,
      );

  @override
  Future<List<NetworkLogEntry>> copyRows({String? service}) async => const [];

  @override
  Future<void> clear() async {}
}

class _NoBiometric extends BiometricService {
  @override
  Future<bool> authenticate({String? reason}) async => false;
}

class _FakePush extends ChangeNotifier implements OfflinePushService {
  @override
  OfflinePushCounts get counts => const OfflinePushCounts();
  @override
  bool get isRunning => false;
  @override
  double get progress => 0;
  @override
  Future<OfflinePushCounts> refreshCounts() async => counts;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSync extends ChangeNotifier implements OfflineSyncService {
  @override
  Future<DateTime?> lastSyncedAt() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A signed-in session that has finished onboarding; the splash stays up so
/// the router does not leave for /home on its own.
class _SignedInAuth extends AuthState {
  _SignedInAuth(super.repo, super.biometric);

  @override
  AuthStatus get status => AuthStatus.signedIn;

  @override
  bool get onboardingComplete => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryStorage storage;
  late AuthState auth;

  setUp(() {
    storage = _MemoryStorage();
    FlutterSecureStoragePlatform.instance = storage;
  });

  /// Real I/O (cookie jar, storage reads) needs the real async zone.
  Future<void> bootAuth(WidgetTester tester) async {
    await tester.runAsync(() async {
      auth = AuthState(
        AuthRepository(await ApiClient.create()),
        _NoBiometric(),
      );
      await auth.bootstrap();
    });
  }

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    await bootAuth(tester);
    final router = buildRouter(auth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthState>.value(value: auth),
          Provider<NetworkLogRepository>.value(value: _Repo()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // Let the splash screen's own 2.5 s timer fire so none is left pending.
    await tester.pump(const Duration(seconds: 3));
    return router;
  }

  group('router redirect', () {
    testWidgets('signed-out user reaches /diagnostics/network', (tester) async {
      final router = await pumpApp(tester);
      router.go('/diagnostics/network');
      await tester.pumpAndSettle();
      expect(find.byType(NetworkLogScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('signed-out user is still sent from /home to /login', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(NetworkLogScreen), findsNothing);
    });

    testWidgets('signed-in user reaches /diagnostics/network', (tester) async {
      await tester.runAsync(() async {
        auth = _SignedInAuth(
          AuthRepository(await ApiClient.create()),
          _NoBiometric(),
        );
      });
      final router = buildRouter(auth);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>.value(value: auth),
            Provider<NetworkLogRepository>.value(value: _Repo()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      router.go('/diagnostics/network');
      await tester.pumpAndSettle();
      expect(find.byType(NetworkLogScreen), findsOneWidget);
    });

    testWidgets('allowed from /login?from=lock with re-entry enabled', (
      tester,
    ) async {
      storage.values['pin_enabled'] = 'true';
      storage.values['pin_length'] = '4';
      final router = await pumpApp(tester);
      expect(auth.reentryEnabled, isTrue);
      router.go('/login?from=lock');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      router.go('/diagnostics/network');
      await tester.pumpAndSettle();
      expect(find.byType(NetworkLogScreen), findsOneWidget);
    });
  });

  group('hidden triggers', () {
    Future<void> pumpHarness(WidgetTester tester, Widget screen) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => screen),
          GoRoute(
            path: '/diagnostics/network',
            builder: (_, _) => const Text('network-page'),
          ),
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>.value(value: auth),
            ChangeNotifierProvider<OfflinePushService>.value(
              value: _FakePush(),
            ),
            ChangeNotifierProvider<OfflineSyncService>.value(
              value: _FakeSync(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapTimes(WidgetTester tester, Key key, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    for (final (name, key, screen) in [
      (
        'login logo',
        const Key('networkLog.trigger.login'),
        const LoginScreen(),
      ),
      (
        'offline sync card header',
        const Key('networkLog.trigger.offlineSync'),
        const OfflineSyncScreen(),
      ),
    ]) {
      testWidgets('10 taps on the $name open the page', (tester) async {
        await bootAuth(tester);
        await pumpHarness(tester, screen);
        await tapTimes(tester, key, 10);
        expect(find.text('network-page'), findsOneWidget);
      });

      testWidgets('9 taps on the $name do not', (tester) async {
        await bootAuth(tester);
        await pumpHarness(tester, screen);
        await tapTimes(tester, key, 9);
        expect(find.text('network-page'), findsNothing);
      });
    }
  });
}
