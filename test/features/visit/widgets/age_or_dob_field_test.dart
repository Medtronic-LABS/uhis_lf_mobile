import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/household/enrollment/enrollment_dob.dart';
import 'package:uhis_next/features/visit/widgets/form_fields/age_or_dob_field.dart';

void main() {
  testWidgets('typing age emits Jan-1 DOB wire and fills DOB display',
      (tester) async {
    String? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgeOrDobField(
            onChanged: (v) => emitted = v,
            maxAgeYears: 18,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(1), '3');
    await tester.pump();

    final expected = EnrollmentDob.wire(EnrollmentDob.fromAgeYears(3));
    expect(emitted, expected);
    expect(find.text(EnrollmentDob.display(EnrollmentDob.fromAgeYears(3))),
        findsOneWidget);
  });

  testWidgets('incoming DOB string fills age years', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgeOrDobField(
            currentValue: '2020-06-15',
            onChanged: (_) {},
            maxAgeYears: 18,
          ),
        ),
      ),
    );
    await tester.pump();

    final age = EnrollmentAge.from(DateTime(2020, 6, 15));
    expect(find.text(age.years.toString()), findsOneWidget);
    expect(find.text(EnrollmentDob.display(DateTime(2020, 6, 15))),
        findsOneWidget);
  });
}
