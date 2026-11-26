import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/net_log/native_network_event_source.dart';
import 'package:uhis_next/core/net_log/network_log_entry.dart';
import 'package:uhis_next/core/net_log/network_log_repository.dart';
import 'package:uhis_next/core/net_log/service_classifier.dart';
import 'package:uhis_next/features/debug/network_log_screen.dart';

NetworkLogEntry _e(
  int t,
  String service, {
  int? status = 200,
  String? errorType,
  String timing = 'total',
  String source = 'dart',
}) => NetworkLogEntry(
  startedAtMs: t,
  source: source,
  service: service,
  method: 'GET',
  url: 'https://example.test/$service/r$t',
  statusCode: status,
  errorType: errorType,
  durationMs: 12,
  timing: timing,
);

/// In-memory stand-in for the repository: newest first, 200 per page.
class _FakeRepo implements NetworkLogRepository {
  _FakeRepo(this.all, {this.native = NativeNetworkStatus.ok, this.dropped = 0});

  List<NetworkLogEntry> all;
  final NativeNetworkStatus native;
  final int dropped;
  int clears = 0;

  /// Makes [copyRows] and [clear] throw, like a failing database.
  bool failing = false;

  List<NetworkLogEntry> _filtered(String? s) =>
      (s == null ? all : all.where((e) => e.service == s).toList())
        ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));

  @override
  Future<NetworkLogPage> load({String? service, int offset = 0}) async {
    final rows = _filtered(service);
    final counts = <String, int>{};
    for (final e in all) {
      counts[e.service] = (counts[e.service] ?? 0) + 1;
    }
    return NetworkLogPage(
      rows: rows.skip(offset).take(200).toList(),
      counts: counts,
      nativeStatus: native,
      droppedCount: dropped,
      hasMore: rows.length > offset + 200,
    );
  }

  @override
  Future<List<NetworkLogEntry>> copyRows({String? service}) async {
    if (failing) throw Exception('copy failed');
    return _filtered(service).take(200).toList();
  }

  @override
  Future<void> clear() async {
    if (failing) throw Exception('clear failed');
    clears++;
    all = [];
  }
}

const _endpoints = [
  ConfiguredEndpoint(
    service: 'api-gateway',
    url: 'https://gw.example.test',
    rule: 'API_BASE_URL',
  ),
  ConfiguredEndpoint(
    service: 'admin-api',
    url: 'https://gw.example.test/admin-api',
    rule: 'API_BASE_URL + /admin-api',
  ),
  ConfiguredEndpoint(
    service: 'secret-api',
    url: 'https://user:pw@api.example.test:8443/x?token=abc#f',
    rule: 'SECRET_URL',
  ),
];

Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Provider<NetworkLogRepository>.value(
      value: repo,
      child: const MaterialApp(home: NetworkLogScreen(endpoints: _endpoints)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('endpoint rows show service, url and rule', (tester) async {
    await _pump(tester, _FakeRepo([_e(1, 'core')]));
    expect(find.text(NetworkLogStrings.endpointsHeading), findsOneWidget);
    expect(find.text('admin-api'), findsWidgets);
    expect(find.text('https://gw.example.test/admin-api'), findsOneWidget);
    expect(find.text('API_BASE_URL + /admin-api'), findsOneWidget);
  });

  testWidgets('endpoint rows never show userinfo, query or fragment', (
    tester,
  ) async {
    await _pump(tester, _FakeRepo([_e(1, 'core')]));
    expect(find.text('https://api.example.test:8443/x'), findsOneWidget);
    expect(find.textContaining('pw'), findsNothing);
    expect(find.textContaining('token'), findsNothing);
  });

  testWidgets('duration comes from the localized string', (tester) async {
    await _pump(tester, _FakeRepo([_e(1, 'core')]));
    expect(find.text(NetworkLogStrings.durationMs(12)), findsOneWidget);
  });

  testWidgets('a failing copy keeps the page usable and says so', (
    tester,
  ) async {
    final repo = _FakeRepo([_e(1, 'core')])..failing = true;
    await _pump(tester, repo);
    await tester.tap(find.byTooltip(NetworkLogStrings.copy));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(NetworkLogStrings.actionFailed), findsOneWidget);
    expect(find.textContaining('example.test/core/r1'), findsOneWidget);
  });

  testWidgets('a failing clipboard write keeps the page usable and says so', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, _FakeRepo([_e(1, 'core')]));
    await tester.tap(find.byTooltip(NetworkLogStrings.copy));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(NetworkLogStrings.actionFailed), findsOneWidget);
    expect(find.text(NetworkLogStrings.copied(1)), findsNothing);
  });

  testWidgets('a failing clear keeps the page usable and says so', (
    tester,
  ) async {
    final repo = _FakeRepo([_e(1, 'core')])..failing = true;
    await _pump(tester, repo);
    await tester.tap(find.byTooltip(NetworkLogStrings.clear));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NetworkLogStrings.clearConfirm));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(NetworkLogStrings.actionFailed), findsOneWidget);
    expect(find.textContaining('example.test/core/r1'), findsOneWidget);
  });

  testWidgets('chips show counts and filter the list', (tester) async {
    await _pump(
      tester,
      _FakeRepo([_e(1, 'core'), _e(2, 'core'), _e(3, 'auth-service')]),
    );
    expect(find.text(NetworkLogStrings.chip('core', 2)), findsOneWidget);
    expect(
      find.text(NetworkLogStrings.chip('auth-service', 1)),
      findsOneWidget,
    );
    expect(find.textContaining('example.test/core/r1'), findsOneWidget);
    expect(find.textContaining('example.test/auth-service/r3'), findsOneWidget);

    await tester.tap(find.text(NetworkLogStrings.chip('auth-service', 1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('example.test/auth-service/r3'), findsOneWidget);
    expect(find.textContaining('example.test/core/r1'), findsNothing);
  });

  testWidgets('status chip shows the code, or the error type when null', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeRepo([
        _e(1, 'core', status: 503),
        _e(2, 'core', status: null, errorType: 'timeout'),
        _e(3, 'core', timing: 'headers', source: 'native'),
      ]),
    );
    expect(find.text('503'), findsOneWidget);
    expect(find.text('timeout'), findsOneWidget);
    expect(find.text(NetworkLogStrings.tagHeaders), findsOneWidget);
    expect(find.text(NetworkLogStrings.tagNative), findsOneWidget);
  });

  testWidgets('Load more appends the next page', (tester) async {
    await _pump(
      tester,
      _FakeRepo([for (var i = 1; i <= 250; i++) _e(i, 'core')]),
    );
    expect(find.textContaining('example.test/core/r50'), findsNothing);
    final more = find.text(NetworkLogStrings.loadMore);
    await tester.scrollUntilVisible(
      more,
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text(NetworkLogStrings.loadMore), findsNothing);
    await tester.scrollUntilVisible(
      find.text('https://example.test/core/r1'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('https://example.test/core/r1'), findsOneWidget);
  });

  for (final (status, text) in [
    (NativeNetworkStatus.unavailable, NetworkLogStrings.nativeUnavailable),
    (
      NativeNetworkStatus.notInitialized,
      NetworkLogStrings.nativeNotInitialized,
    ),
    (NativeNetworkStatus.failed, NetworkLogStrings.nativeFailed),
  ]) {
    testWidgets('native status line for $status', (tester) async {
      await _pump(tester, _FakeRepo([_e(1, 'core')], native: status));
      expect(find.text(text), findsOneWidget);
    });
  }

  testWidgets('no native status line when ok', (tester) async {
    await _pump(tester, _FakeRepo([_e(1, 'core')]));
    expect(find.text(NetworkLogStrings.nativeUnavailable), findsNothing);
    expect(find.text(NetworkLogStrings.nativeNotInitialized), findsNothing);
    expect(find.text(NetworkLogStrings.nativeFailed), findsNothing);
  });

  testWidgets('dropped writes line shows when above zero', (tester) async {
    await _pump(tester, _FakeRepo([_e(1, 'core')], dropped: 7));
    expect(find.text(NetworkLogStrings.droppedWrites(7)), findsOneWidget);
  });

  testWidgets('no dropped writes line at zero', (tester) async {
    await _pump(tester, _FakeRepo([_e(1, 'core')]));
    expect(find.text(NetworkLogStrings.droppedWrites(0)), findsNothing);
  });

  testWidgets('empty state', (tester) async {
    await _pump(tester, _FakeRepo([]));
    expect(find.text(NetworkLogStrings.empty), findsOneWidget);
  });

  testWidgets('copy puts at most 200 filtered lines on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(
      tester,
      _FakeRepo([
        for (var i = 1; i <= 250; i++) _e(i, 'core'),
        _e(1000, 'auth-service'),
      ]),
    );
    await tester.tap(find.text(NetworkLogStrings.chip('core', 250)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(NetworkLogStrings.copy));
    await tester.pumpAndSettle();

    final lines = copied!.split('\n');
    expect(lines, hasLength(200));
    expect(lines.first, contains('https://example.test/core/r250'));
    expect(lines.first, matches(RegExp(r'^\d\d:\d\d:\d\d GET 200 12 ')));
    expect(copied, isNot(contains('auth-service')));
    expect(find.text(NetworkLogStrings.copied(200)), findsOneWidget);
  });

  testWidgets('clear asks for confirmation then empties the list', (
    tester,
  ) async {
    final repo = _FakeRepo([_e(1, 'core')]);
    await _pump(tester, repo);
    await tester.tap(find.byTooltip(NetworkLogStrings.clear));
    await tester.pumpAndSettle();
    expect(find.text(NetworkLogStrings.clearTitle), findsOneWidget);

    await tester.tap(find.text(NetworkLogStrings.cancel));
    await tester.pumpAndSettle();
    expect(repo.clears, 0);
    expect(find.textContaining('example.test/core/r1'), findsOneWidget);

    await tester.tap(find.byTooltip(NetworkLogStrings.clear));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NetworkLogStrings.clearConfirm));
    await tester.pumpAndSettle();
    expect(repo.clears, 1);
    expect(find.textContaining('example.test/core/r1'), findsNothing);
    expect(find.text(NetworkLogStrings.empty), findsOneWidget);
  });
}
