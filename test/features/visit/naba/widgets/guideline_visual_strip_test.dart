import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:uhis_next/core/api/frappe_client.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/features/visit/naba/guideline_visual_repository.dart';
import 'package:uhis_next/features/visit/naba/guideline_visual_selector.dart';
import 'package:uhis_next/features/visit/naba/naba_models.dart';
import 'package:uhis_next/features/visit/naba/widgets/guideline_visual_strip.dart';
import 'package:uhis_next/features/visit/naba/widgets/guideline_visual_viewer.dart';

import '../naba_visuals_fixtures.dart';

/// Serves pictures from memory; keys in [missing] fail to load.
class _FakeRepository extends GuidelineVisualRepository {
  _FakeRepository({this.missing = const {}})
    : super(FrappeClient(baseUrl: '', authTokenProvider: () async => null));

  final Set<String> missing;

  @override
  Future<GuidelineImageData?> load(NabaVisualImage image) async =>
      missing.contains(image.visualKey)
      ? null
      : GuidelineImageData.raster(Uint8List.fromList(tinyPng));
}

SelectedGuidelineVisual _visual(String key, String caption) =>
    SelectedGuidelineVisual(
      pointerId: key.toUpperCase(),
      caption: caption,
      image: NabaVisualImage.tryParse(imageJson(key, 1))!,
    );

Future<void> _pump(
  WidgetTester tester,
  List<SelectedGuidelineVisual> visuals, {
  Set<String> missing = const {},
}) async {
  await tester.pumpWidget(
    Provider<GuidelineVisualRepository>.value(
      value: _FakeRepository(missing: missing),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GuidelineVisualStrip(visuals: visuals),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A preview tile, found by its screen-reader label (tiles draw no caption).
Finder _tile(String caption) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.properties.label == NabaVisualStrings.openPicture(caption),
);

Finder _inViewer(String text) => find.descendant(
  of: find.byType(GuidelineVisualViewer),
  matching: find.text(text),
);

void main() {
  final three = [
    _visual('a-01', 'Take iron and calcium every day'),
    _visual('b-01', 'No heavy work'),
    _visual('c-01', 'Sleep 8 hours at night'),
  ];

  testWidgets('renders one picture-only tile per visual', (tester) async {
    await _pump(tester, three);

    expect(find.byType(Image), findsNWidgets(3));
    for (final v in three) {
      expect(_tile(v.caption), findsOneWidget);
      expect(find.text(v.caption), findsNothing);
    }
  });

  testWidgets('a picture that fails to load is dropped', (tester) async {
    await _pump(tester, three, missing: {'b-01'});

    expect(_tile('No heavy work'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('takes no space when nothing loads or nothing is selected', (
    tester,
  ) async {
    await _pump(tester, three, missing: {'a-01', 'b-01', 'c-01'});
    expect(find.byType(Image), findsNothing);
    expect(tester.getSize(find.byType(GuidelineVisualStrip)).height, 0);

    await _pump(tester, const []);
    expect(tester.getSize(find.byType(GuidelineVisualStrip)).height, 0);
  });

  testWidgets('tapping a tile opens the viewer with that picture\'s caption', (
    tester,
  ) async {
    await _pump(tester, three);

    await tester.tap(_tile('No heavy work'));
    await tester.pumpAndSettle();

    expect(find.byType(GuidelineVisualViewer), findsOneWidget);
    expect(find.text(NabaVisualStrings.pageOf(2, 3)), findsOneWidget);
    expect(_inViewer('No heavy work'), findsOneWidget);
    expect(_inViewer(three.first.caption), findsNothing);
  });

  testWidgets('long captions are shown in full in the viewer', (tester) async {
    const long =
        'Encourage follow-up after starting treatment so the doctor can '
        'check the medicine is working and adjust the dose if needed.';
    await _pump(tester, [_visual('d-01', long)]);

    await tester.tap(_tile(long));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(_inViewer(long));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('viewer caption follows the page', (tester) async {
    await _pump(tester, three);
    await tester.tap(_tile(three.first.caption));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(NabaVisualStrings.next));
    await tester.pumpAndSettle();

    expect(_inViewer('No heavy work'), findsOneWidget);
  });

  testWidgets('viewer pages with arrows and closes', (tester) async {
    await _pump(tester, three);
    await tester.tap(_tile(three.first.caption));
    await tester.pumpAndSettle();
    expect(find.text(NabaVisualStrings.pageOf(1, 3)), findsOneWidget);

    await tester.tap(find.byTooltip(NabaVisualStrings.next));
    await tester.pumpAndSettle();
    expect(find.text(NabaVisualStrings.pageOf(2, 3)), findsOneWidget);

    await tester.tap(find.byTooltip(NabaVisualStrings.close));
    await tester.pumpAndSettle();
    expect(find.byType(GuidelineVisualViewer), findsNothing);
  });

  testWidgets('single picture: no counter or arrows', (tester) async {
    await _pump(tester, [three.first]);
    await tester.tap(_tile(three.first.caption));
    await tester.pumpAndSettle();

    expect(find.byTooltip(NabaVisualStrings.next), findsNothing);
    expect(find.text(NabaVisualStrings.pageOf(1, 1)), findsNothing);
  });
}
