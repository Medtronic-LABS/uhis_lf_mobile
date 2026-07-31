import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/triage/child_assessment_section.dart';

void main() {
  group('childWeightRangeError', () {
    test('null weight has no error', () {
      expect(childWeightRangeError(null), isNull);
    });

    test('in-range weight has no error', () {
      expect(childWeightRangeError(6.5), isNull);
      expect(childWeightRangeError(0), isNull);
      expect(childWeightRangeError(30), isNull);
    });

    test('out-of-range weight surfaces an error', () {
      expect(childWeightRangeError(-1), isNotNull);
      expect(childWeightRangeError(30.1), isNotNull);
    });
  });

  group('ChildAssessmentData.copyWith', () {
    test('clearing anyIllness to false also clears referral answers', () {
      final withReferral = ChildAssessmentData(
        anyIllness: true,
        referralMade: true,
        referralPlace: 'hwc',
      );

      final cleared = withReferral.copyWith(
        anyIllness: false,
        clearReferralMade: true,
        clearReferralPlace: true,
      );

      expect(cleared.anyIllness, false);
      expect(cleared.referralMade, isNull);
      expect(cleared.referralPlace, isNull);
    });

    test('feedLast24h defaults to empty and round-trips via copyWith', () {
      final data = ChildAssessmentData();
      expect(data.feedLast24h, isEmpty);

      final updated = data.copyWith(feedLast24h: ['mothersBreastMilk']);
      expect(updated.feedLast24h, ['mothersBreastMilk']);
    });
  });

  group('ChildAssessmentSection widget', () {
    Widget wrap(ChildAssessmentData data, ValueChanged<ChildAssessmentData> onChanged) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChildAssessmentSection(data: data, onChanged: onChanged),
          ),
        ),
      );
    }

    testWidgets('referral question (Q14) is hidden when anyIllness is unset',
        (tester) async {
      await tester.pumpWidget(wrap(ChildAssessmentData(), (_) {}));
      expect(
        find.textContaining('Has referral been made?', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('referral question (Q14) is shown when anyIllness is Yes',
        (tester) async {
      await tester.pumpWidget(
        wrap(ChildAssessmentData(anyIllness: true), (_) {}),
      );
      expect(
        find.textContaining('Has referral been made?', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets(
        'tapping a "what was fed" chip reports the option id, not the label',
        (tester) async {
      ChildAssessmentData? emitted;
      await tester.pumpWidget(
        wrap(ChildAssessmentData(), (d) => emitted = d),
      );

      await tester.tap(find.text("Mother's breast milk"));
      await tester.pump();

      expect(emitted?.feedLast24h, ['mothersBreastMilk']);
    });
  });
}
