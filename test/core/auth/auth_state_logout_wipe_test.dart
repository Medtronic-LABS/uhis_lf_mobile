/// Unit tests for the local-data wipe hook in [AuthState.logout] —
/// GitHub issue #37.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/api/api_client.dart';
import 'package:uhis_next/core/auth/auth_repository.dart';
import 'package:uhis_next/core/auth/auth_state.dart';
import 'package:uhis_next/core/auth/biometric_service.dart';

/// Bypasses the real network/secure-storage logout implementation so this
/// test can isolate AuthState's wipe-callback orchestration.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(super.api);

  bool logoutCalled = false;

  @override
  Future<void> logout() async {
    logoutCalled = true;
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

  test('logout() calls the local-data wipe callback', () async {
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
    expect(wipeCalled, isTrue);
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
}
