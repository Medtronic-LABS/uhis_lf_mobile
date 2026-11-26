import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/widgets/hidden_tap_trigger.dart';

void main() {
  late DateTime now;
  late int fired;
  const key = Key('trigger-child');

  Future<void> pump(
    WidgetTester tester, {
    int taps = 10,
    Widget child = const SizedBox(key: key, width: 200, height: 100),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HiddenTapTrigger(
              taps: taps,
              clock: () => now,
              onTriggered: () => fired++,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tapN(WidgetTester tester, int n, {Duration gap = Duration.zero}) async {
    for (var i = 0; i < n; i++) {
      now = now.add(gap);
      await tester.tapAt(tester.getTopLeft(find.byKey(key)) + const Offset(2, 2));
    }
  }

  setUp(() {
    now = DateTime(2026, 1, 1);
    fired = 0;
  });

  testWidgets('9 taps do not fire', (tester) async {
    await pump(tester);
    await tapN(tester, 9, gap: const Duration(milliseconds: 100));
    expect(fired, 0);
  });

  testWidgets('10 taps fire exactly once', (tester) async {
    await pump(tester);
    await tapN(tester, 10, gap: const Duration(milliseconds: 100));
    expect(fired, 1);
  });

  testWidgets('counter resets after firing; 20th tap fires again', (tester) async {
    await pump(tester);
    await tapN(tester, 19, gap: const Duration(milliseconds: 100));
    expect(fired, 1);
    await tapN(tester, 1, gap: const Duration(milliseconds: 100));
    expect(fired, 2);
  });

  testWidgets('gap over the window resets the count', (tester) async {
    await pump(tester);
    await tapN(tester, 5, gap: const Duration(milliseconds: 100));
    // 2.1 s gap: this tap restarts the count at 1.
    await tapN(tester, 1, gap: const Duration(milliseconds: 2100));
    await tapN(tester, 8, gap: const Duration(milliseconds: 100));
    expect(fired, 0, reason: '1 + 8 = 9 taps since the reset');
    await tapN(tester, 1, gap: const Duration(milliseconds: 100));
    expect(fired, 1, reason: '10th tap since the reset');
  });

  testWidgets('gap is measured between consecutive taps, not from the first',
      (tester) async {
    await pump(tester);
    // 10 taps, 1.5 s apart: 13.5 s total but every gap is within window.
    await tapN(tester, 10, gap: const Duration(milliseconds: 1500));
    expect(fired, 1);
  });

  testWidgets('a gap of exactly the window does not reset', (tester) async {
    await pump(tester);
    // Documented choice: only a gap greater than the window resets.
    await tapN(tester, 10, gap: const Duration(seconds: 2));
    expect(fired, 1);
  });

  testWidgets('tap on the empty area of the child counts (opaque)', (tester) async {
    await pump(tester);
    await tapN(tester, 10);
    expect(fired, 1);
  });

  testWidgets('custom taps value is honoured', (tester) async {
    await pump(tester, taps: 3);
    await tapN(tester, 2);
    expect(fired, 0);
    await tapN(tester, 1);
    expect(fired, 1);
  });

  testWidgets('interactive child keeps its own tap and does not bubble',
      (tester) async {
    // Callers must pass non-interactive children: a child that handles taps
    // wins the gesture arena, so the trigger never counts those taps.
    var childTaps = 0;
    await pump(
      tester,
      taps: 2,
      child: TextButton(
        key: key,
        onPressed: () => childTaps++,
        child: const Text('x'),
      ),
    );
    await tester.tap(find.byKey(key));
    await tester.tap(find.byKey(key));
    expect(childTaps, 2);
    expect(fired, 0);
  });

  testWidgets('is excluded from semantics and opaque', (tester) async {
    await pump(tester);
    final detector = tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(HiddenTapTrigger),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(detector.excludeFromSemantics, isTrue);
    expect(detector.behavior, HitTestBehavior.opaque);
  });
}
