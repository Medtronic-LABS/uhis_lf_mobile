import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/dashboard/widgets/dashboard_search_field.dart';

void main() {
  Widget buildField({required String initialValue, required ValueChanged<String> onChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: DashboardSearchField(initialValue: initialValue, onChanged: onChanged),
      ),
    );
  }

  testWidgets('seeds displayed text from initialValue on first build', (tester) async {
    await tester.pumpWidget(buildField(initialValue: 'Fatima', onChanged: (_) {}));

    expect(find.text('Fatima'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('remounting with a different initialValue updates the displayed text', (
    tester,
  ) async {
    // Simulates DashboardScreen being destroyed and recreated (e.g. after a
    // context.go() round trip into the visit flow and back) while the
    // backing filter state still holds a prior search query.
    await tester.pumpWidget(buildField(initialValue: 'Fatima', onChanged: (_) {}));
    await tester.pumpWidget(buildField(initialValue: '', onChanged: (_) {}));

    expect(find.text('Fatima'), findsNothing);
    expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
  });

  testWidgets('typing does not get clobbered by an unrelated rebuild with the same initialValue', (
    tester,
  ) async {
    var current = '';
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return DashboardSearchField(
                initialValue: current,
                onChanged: (q) => current = q,
              );
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Rah');
    await tester.pump();
    expect(current, 'Rah');

    // Parent rebuilds for an unrelated reason (e.g. notification count
    // changed) without the user's typed text having reached initialValue yet.
    setState(() {});
    await tester.pump();

    expect(find.text('Rah'), findsOneWidget);
  });
}
