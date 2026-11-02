/// Widget tests for [JsonKeyValueView] -- the generic renderer used by
/// `TeleconsultCallDetailScreen` to show a synced-in historical call's raw
/// `clinicalData` JSON without a fixed field list. Confirms the three shapes
/// Shukhee's own payloads use (flat primitives, nested maps, lists of maps)
/// render their labels and values, that camelCase/snake_case keys get
/// humanized, and that null/empty values are skipped rather than shown as
/// blank rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/teleconsult/json_key_value_view.dart';

void main() {
  Future<void> pumpView(WidgetTester tester, Map<String, dynamic> data, {String? title}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: JsonKeyValueView(data: data, title: title)),
      ),
    );
  }

  testWidgets('humanizes camelCase and snake_case keys as labels', (tester) async {
    await pumpView(tester, {
      'chiefComplaints': 'Fever',
      'lab_test': 'CBC',
    });

    expect(find.text('Chief Complaints'), findsOneWidget);
    expect(find.text('Fever'), findsOneWidget);
    expect(find.text('Lab Test'), findsOneWidget);
    expect(find.text('CBC'), findsOneWidget);
  });

  testWidgets('joins a list of primitives inline with commas', (tester) async {
    await pumpView(tester, {
      'diagnosis': ['Fever of unknown origin', 'Dehydration'],
    });

    expect(find.text('Fever of unknown origin, Dehydration'), findsOneWidget);
  });

  testWidgets('renders a nested map as its own indented key-value block', (tester) async {
    await pumpView(tester, {
      'lastVital': {'temperature': '99.5', 'pulseRate': '82'},
    });

    expect(find.text('Last Vital'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('99.5'), findsOneWidget);
    expect(find.text('Pulse Rate'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
  });

  testWidgets('renders a list of maps as repeated nested blocks, one per item', (tester) async {
    await pumpView(tester, {
      'medicine': [
        {'brandName': 'Paracetamol', 'dosage': '500mg'},
        {'brandName': 'ORS', 'dosage': '1 sachet'},
      ],
    });

    expect(find.text('Medicine'), findsOneWidget);
    expect(find.text('Brand Name'), findsNWidgets(2));
    expect(find.text('Paracetamol'), findsOneWidget);
    expect(find.text('ORS'), findsOneWidget);
  });

  testWidgets('skips null, empty string, empty list, and empty map values entirely', (tester) async {
    await pumpView(tester, {
      'followUpComment': null,
      'drugHistory': <String>[],
      'extra': <String, dynamic>{},
      'advice': '',
      'diagnosis': ['Fever'],
    });

    expect(find.text('Follow Up Comment'), findsNothing);
    expect(find.text('Drug History'), findsNothing);
    expect(find.text('Extra'), findsNothing);
    expect(find.text('Advice'), findsNothing);
    expect(find.text('Diagnosis'), findsOneWidget);
  });

  testWidgets('renders nothing at all when every value is absent', (tester) async {
    await pumpView(tester, {'followUpComment': null, 'drugHistory': <String>[]}, title: 'Doctor\'s Summary');

    expect(find.text("Doctor's Summary"), findsNothing);
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('renders the given title above the entries when data is present', (tester) async {
    await pumpView(tester, {'diagnosis': 'Fever'}, title: 'Doctor\'s Summary');

    expect(find.text("Doctor's Summary"), findsOneWidget);
    expect(find.text('Diagnosis'), findsOneWidget);
  });

  testWidgets('renders a raw numeric or boolean value via toString', (tester) async {
    await pumpView(tester, {'followUpDay': 7, 'urgent': true});

    expect(find.text('7'), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
  });
}
