import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:uhis_next/app/post_sync_refresher.dart';
import 'package:uhis_next/core/auth/user_hierarchy_service.dart';
import 'package:uhis_next/core/db/spice_dashboard_dao.dart';
import 'package:uhis_next/features/dashboard/sk_kpi_dashboard_tab.dart';
import 'package:uhis_next/features/dashboard/sk_spice_dashboard_repository.dart';

class _CountingRepo extends Fake implements SkSpiceDashboardRepository {
  int loads = 0;

  @override
  Future<SpiceDashboardCounts> load({
    required DateTime from,
    required DateTime to,
    List<String> ssIds = const [],
    List<String> subVillageIds = const [],
  }) async {
    loads++;
    return const SpiceDashboardCounts();
  }
}

class _FakeRefresher extends Fake implements PostSyncRefresher {
  @override
  final ValueNotifier<bool> isRefreshing = ValueNotifier(false);
}

class _NoHierarchy extends ChangeNotifier implements UserHierarchyService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// LEAP-128: the tab read its counts once, so a sync that landed while it was
/// open left the numbers stale.
void main() {
  late _CountingRepo repo;
  late _FakeRefresher refresher;

  Future<void> pumpTab(WidgetTester tester, {bool withRefresher = true}) async {
    repo = _CountingRepo();
    refresher = _FakeRefresher();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SkSpiceDashboardRepository>.value(value: repo),
          ChangeNotifierProvider<UserHierarchyService>.value(
            value: _NoHierarchy(),
          ),
          if (withRefresher)
            Provider<PostSyncRefresher>.value(value: refresher),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SkKpiDashboardTab()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('reloads when the post-sync refresh finishes', (tester) async {
    await pumpTab(tester);
    expect(repo.loads, 1);

    refresher.isRefreshing.value = true;
    await tester.pump();
    expect(repo.loads, 1, reason: 'no reload while the refresh is running');

    refresher.isRefreshing.value = false;
    await tester.pump();
    expect(repo.loads, 2);
  });

  testWidgets('stops listening when the tab is removed', (tester) async {
    await pumpTab(tester);
    await tester.pumpWidget(const SizedBox());

    refresher.isRefreshing.value = true;
    refresher.isRefreshing.value = false;
    await tester.pump();
    expect(repo.loads, 1);
  });

  testWidgets('works where no refresher is provided', (tester) async {
    await pumpTab(tester, withRefresher: false);
    expect(repo.loads, 1);
    expect(tester.takeException(), isNull);
  });
}
