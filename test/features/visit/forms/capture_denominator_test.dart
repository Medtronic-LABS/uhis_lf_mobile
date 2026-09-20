/// The capture denominator counts the same unit the numerator does.
///
/// `aiFilled` records leaf values — `systolic`, `diastolic`, `pulse`,
/// `glucose` — while the denominator used to count rendered widgets:
/// `bpLogDetails`, `glucoseType`. One widget writes several distinct values,
/// so the numerator could exceed the denominator and the capture rate was
/// arithmetic on two different units. A real visit reported 9 fields filled
/// against 7 visible.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

void main() {
  test('a BP container contributes its three measurements, not itself', () {
    // systolic, diastolic and pulse are separate clinical readings, and the
    // container is not a value the SK ever sees.
    final leaves = UnifiedFormNotifier.captureLeavesForTesting('bpLogDetails');
    expect(leaves, {'systolic', 'diastolic', 'pulse'});
    expect(leaves, isNot(contains('bpLogDetails')));
  });

  test('the glucose widget contributes both the qualifier and the reading', () {
    // One widget, one fieldRef, two distinct values — and `glucose` has no
    // fieldRef of its own, so nothing else can put it in the denominator.
    expect(
      UnifiedFormNotifier.captureLeavesForTesting('glucoseType'),
      {'glucoseType', 'glucose'},
    );
  });

  test('an ordinary field contributes only itself', () {
    expect(UnifiedFormNotifier.captureLeavesForTesting('weight'), {'weight'});
  });
}
