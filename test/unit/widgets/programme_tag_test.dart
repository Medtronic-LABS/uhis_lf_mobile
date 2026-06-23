import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/core/widgets/programme_tag.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('ProgrammeTag', () {
    testWidgets('renders without error for every Programme value', (tester) async {
      for (final programme in Programme.values) {
        await tester.pumpWidget(_wrap(ProgrammeTag(programme: programme)));
        await tester.pump();
        expect(find.byType(ProgrammeTag), findsOneWidget,
            reason: 'Expected ProgrammeTag for $programme');
        // Should contain an Icon and a Text child
        expect(find.byType(Icon), findsOneWidget);
        expect(find.byType(Text), findsOneWidget);
      }
    });

    testWidgets('displays a non-empty label for every Programme', (tester) async {
      for (final programme in Programme.values) {
        await tester.pumpWidget(_wrap(ProgrammeTag(programme: programme)));
        await tester.pump();
        final textWidget = tester.widget<Text>(find.byType(Text));
        expect(textWidget.data, isNotEmpty,
            reason: 'Expected non-empty label for $programme');
      }
    });

    testWidgets('uses Row layout with min main-axis size', (tester) async {
      await tester.pumpWidget(_wrap(const ProgrammeTag(programme: Programme.ncd)));
      await tester.pump();
      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.mainAxisSize, equals(MainAxisSize.min));
    });

    testWidgets('wraps content in a Container with rounded corners', (tester) async {
      await tester.pumpWidget(_wrap(const ProgrammeTag(programme: Programme.anc)));
      await tester.pump();
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, isNotNull);
    });

    testWidgets('accepts a key for e2e testability', (tester) async {
      const testKey = Key('test_programme_tag');
      await tester.pumpWidget(_wrap(
        const ProgrammeTag(key: testKey, programme: Programme.tb),
      ));
      await tester.pump();
      expect(find.byKey(testKey), findsOneWidget);
    });
  });
}
