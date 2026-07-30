/// Unit tests for [UnifiedFormNotifier.clearFields] — the stale-hidden-value
/// guard added after the sync/payload audit found that a field's value
/// (entered while visible) survives in [CanonicalVisitData] even after the
/// field becomes hidden due to a driver-value change, and would otherwise be
/// included unfiltered in the submitted payload.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

import '../../../helpers/fake_form_deps.dart';

void main() {
  late FakeAssessmentDraftDao draftDao;
  late UnifiedFormNotifier notifier;

  setUp(() {
    draftDao = FakeAssessmentDraftDao();
    notifier = buildTestNotifier(draftDao: draftDao);
  });

  group('clearFields', () {
    test('removes stale values for fields no longer visible', () {
      notifier.updateField('gravida', 3);
      notifier.updateField('parity', 2);
      expect(notifier.data.getValue('parity'), 2);

      // SK corrects Gravida back to 1 — Parity is now hidden, but its stale
      // value is still sitting in CanonicalVisitData until clearFields runs.
      notifier.updateField('gravida', 1);
      expect(notifier.data.getValue('parity'), 2);

      notifier.clearFields({'parity'});
      expect(notifier.data.getValue('parity'), isNull);
      expect(notifier.data.getValue('gravida'), 1);
    });

    test('leaves untouched fields intact', () {
      notifier.updateField('gravida', 1);
      notifier.updateField('weight', 68);

      notifier.clearFields({'parity'}); // parity was never set

      expect(notifier.data.getValue('gravida'), 1);
      expect(notifier.data.getValue('weight'), 68);
    });

    test('empty set is a no-op', () {
      notifier.updateField('weight', 68);
      notifier.clearFields(const {});
      expect(notifier.data.getValue('weight'), 68);
    });

    test('persists the cleared state to the draft', () async {
      notifier.updateField('gravida', 3);
      notifier.updateField('parity', 2);
      await pumpMicrotasks();

      notifier.clearFields({'parity'});
      await pumpMicrotasks();

      final saved = draftDao.lastSaved;
      expect(saved, isNotNull);
      final values = jsonDecode(saved!.fieldValues) as Map<String, dynamic>;
      expect(values['parity'], isNull);
      expect(values['gravida'], 3);
    });
  });
}
