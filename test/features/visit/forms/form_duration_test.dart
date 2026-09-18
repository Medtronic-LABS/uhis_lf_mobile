/// Form-completion timing.
///
/// The reported figure used to be measured from the encounter's `startedAt`,
/// stamped when "start visit" is tapped on the dashboard — several screens
/// before the form exists. Triage, the symptom picker and the AI briefing
/// cards all sit in between, so a column labelled form-completion time
/// reported whole-visit time and ran one to two minutes long.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_form_deps.dart';

void main() {
  test('duration is measured from the form opening, not the visit starting',
      () async {
    final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
    n.markFormOpened();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final ms = await n.visitDurationMsForTesting();
    expect(ms, isNotNull);
    expect(ms, greaterThanOrEqualTo(25));
    // Generous ceiling: this asserts the clock starts at markFormOpened and
    // not at some earlier moment, not that the test machine is fast.
    expect(ms, lessThan(5000));
  });

  test('a form never marked open reports nothing rather than guessing',
      () async {
    // Null is deliberate. Falling back to the encounter stamp would silently
    // mix whole-visit time into a form-completion column — the original bug.
    final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
    expect(await n.visitDurationMsForTesting(), isNull);
  });

  test('the stamp is set once, so a form rebuild cannot shorten the measure',
      () async {
    final n = buildTestNotifier(draftDao: FakeAssessmentDraftDao());
    n.markFormOpened();
    final first = n.formOpenedAtMsForTesting;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    n.markFormOpened();

    expect(n.formOpenedAtMsForTesting, first);
  });
}
