/// Tests for [UnifiedFormNotifier]'s debounced autosave — rapid keystrokes
/// should coalesce into a single draft write instead of persisting every
/// intermediate value (e.g. "1", "12", "120").
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_form_deps.dart';

void main() {
  late FakeAssessmentDraftDao draftDao;

  setUp(() {
    draftDao = FakeAssessmentDraftDao();
  });

  test('a single field change does not persist synchronously', () {
    final notifier = buildTestNotifier(draftDao: draftDao);
    notifier.updateField('systolic', '1');
    expect(draftDao.lastSaved, isNull);
  });

  test('rapid successive keystrokes coalesce into one persisted write with the final value', () async {
    final notifier = buildTestNotifier(draftDao: draftDao);

    // Simulates typing "120" one character at a time.
    notifier.updateField('systolic', '1');
    notifier.updateField('systolic', '12');
    notifier.updateField('systolic', '120');

    // Debounce window (400ms) hasn't elapsed yet.
    expect(draftDao.lastSaved, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(draftDao.lastSaved, isNotNull);
    final saved = jsonDecode(draftDao.lastSaved!.fieldValues) as Map<String, dynamic>;
    expect(saved['systolic'], '120');
  });

  test('dispose() flushes a pending debounced save immediately', () {
    final notifier = buildTestNotifier(draftDao: draftDao);
    notifier.updateField('systolic', '120');

    expect(draftDao.lastSaved, isNull); // still within the debounce window

    notifier.dispose();

    expect(draftDao.lastSaved, isNotNull);
    final saved = jsonDecode(draftDao.lastSaved!.fieldValues) as Map<String, dynamic>;
    expect(saved['systolic'], '120');
  });

  test('dispose() with no pending save is a no-op (does not throw)', () {
    final notifier = buildTestNotifier(draftDao: draftDao);
    expect(() => notifier.dispose(), returnsNormally);
  });
}
