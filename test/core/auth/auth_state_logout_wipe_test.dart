/// Unit tests for [AuthState.logout] orchestration.
///
/// Originally covered the truncate-on-logout hook (GitHub issue #37). Sign-out
/// is now soft — local data is retained so an SK's unsynced work survives, and
/// clearing is Android Settings → Clear Data — so these assert that the wipe
/// callback is supplied but never invoked, and that the flush runs while the
/// session is still valid.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';

/// Bypasses the real network/secure-storage logout implementation so this
/// test can isolate AuthState's orchestration.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.api, {this.onLogout});

  bool logoutCalled = false;
  final void Function()? onLogout;

  @override
  Future<void> logout() async {
    logoutCalled = true;
    onLogout?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthRepository repo;
  late BiometricService biometric;

  setUp(() async {
    repo = _FakeAuthRepository(await ApiClient.create());
    biometric = BiometricService();
  });

  test('logout() does NOT call the local-data wipe callback', () async {
    var wipeCalled = false;
    final authState = AuthState(
      repo,
      biometric,
      onWipeLocalData: () async {
        wipeCalled = true;
      },
    );

    await authState.logout();

    expect(repo.logoutCalled, isTrue);
    expect(wipeCalled, isFalse,
        reason: 'sign-out is soft — an SK who logs out offline must still find '
            'their unsynced work on the device afterwards');
    expect(authState.status, AuthStatus.signedOut);
  });

  test('logout() still completes and signs out if the wipe callback throws',
      () async {
    final authState = AuthState(
      repo,
      biometric,
      onWipeLocalData: () async {
        throw Exception('DB wipe failed');
      },
    );

    await authState.logout();

    expect(repo.logoutCalled, isTrue);
    expect(authState.status, AuthStatus.signedOut,
        reason: 'sign-out must not be blocked by a wipe failure');
  });

  test('logout() with no wipe callback configured still signs out', () async {
    final authState = AuthState(repo, biometric);

    await authState.logout();

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

  test('logout() flushes pending work BEFORE ending the server session',
      () async {
    final order = <String>[];
    final orderedRepo = _FakeAuthRepository(
      await ApiClient.create(),
      onLogout: () => order.add('endSession'),
    );
    final authState = AuthState(orderedRepo, biometric);
    authState.registerPreWipeHook(() async {
      order.add('flush');
    });

    await authState.logout();

    expect(order, ['flush', 'endSession'],
        reason: 'the flush needs the Bearer token that ending the session '
            'clears — reversed, every pending assessment 401s and is marked '
            'failed, a state AutomaticSync never retries');
  });

  test('logout() still completes and signs out if a pre-wipe hook throws',
      () async {
    final authState = AuthState(repo, biometric);
    authState.registerPreWipeHook(() => throw Exception('flush failed'));

    await authState.logout();

    expect(authState.status, AuthStatus.signedOut,
        reason: 'sign-out must not be blocked by a flush failure');
  });

  test('logout() still completes and signs out if a pre-wipe hook hangs',
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
