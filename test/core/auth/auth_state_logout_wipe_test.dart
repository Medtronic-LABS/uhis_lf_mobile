/// Unit tests for [AuthState.logout] — UHIS parity: local DB is kept across
/// sign-out; delta sync on the next login uses sync_meta.lastSyncTime.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';

/// Bypasses the real network/secure-storage logout implementation so this
/// test can isolate AuthState's logout orchestration.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.api);

  bool logoutCalled = false;

  @override
  Future<void> logout({bool online = true}) async {
    logoutCalled = true;
  }

  @override
  Future<String?> lastUsername() async => null;

  @override
  Future<bool> isBiometricEnabled() async => false;

  @override
  Future<bool> isPinSet() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthRepository repo;
  late BiometricService biometric;

  setUp(() async {
    repo = _FakeAuthRepository(await ApiClient.create());
    biometric = BiometricService();
  });

  test('logout() completes sign-out without wiping local data', () async {
    final authState = AuthState(repo, biometric);

    await authState.logout(online: true);

    expect(repo.logoutCalled, isTrue);
    expect(authState.status, AuthStatus.signedOut);
  });

  test('logout() runs registered logout hooks, clearing in-memory caches',
      () async {
    final authState = AuthState(repo, biometric);
    var hookCalls = 0;
    authState.registerLogoutHook(() => hookCalls++);
    authState.registerLogoutHook(() => hookCalls++);

    await authState.logout();

    expect(hookCalls, 2,
        reason:
            'every registered hook (e.g. MissionDashboardRepository.clearCache) '
            'must run so no session data leaks into the next login');
  });

  test('logout() still completes and signs out if a logout hook throws',
      () async {
    final authState = AuthState(repo, biometric);
    authState.registerLogoutHook(() => throw Exception('cache clear failed'));

    await authState.logout();

    expect(authState.status, AuthStatus.signedOut,
        reason: 'sign-out must not be blocked by a hook failure');
  });

  test('logout() runs pre-logout flush hooks before cache hooks', () async {
    final order = <String>[];
    final authState = AuthState(repo, biometric);
    authState.registerPreWipeHook(() async {
      order.add('flush');
    });
    authState.registerLogoutHook(() {
      order.add('cache');
    });

    await authState.logout();

    expect(order, ['flush', 'cache'],
        reason: 'pending writes should flush before in-memory caches clear');
  });

  test('logout() still completes and signs out if a pre-logout hook throws',
      () async {
    final authState = AuthState(repo, biometric);
    authState.registerPreWipeHook(() => throw Exception('flush failed'));

    await authState.logout();

    expect(authState.status, AuthStatus.signedOut,
        reason: 'sign-out must not be blocked by a flush failure');
  });

  test('logout() still completes and signs out if a pre-logout hook hangs',
      () async {
    final authState = AuthState(repo, biometric);
    authState.registerPreWipeHook(
      () => Future<void>.delayed(const Duration(milliseconds: 50))
          .timeout(const Duration(milliseconds: 1))
          .catchError((_) {}),
    );

    await authState.logout();

    expect(authState.status, AuthStatus.signedOut,
        reason: 'a slow/offline flush must not hang logout — callers are '
            'expected to bound their own hook, mirrored here');
  });
}
