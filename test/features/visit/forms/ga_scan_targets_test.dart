import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/unified_form_notifier.dart';

/// GA card-scan targets are read off the scan field maps themselves
/// (review of #768): a field added to a map shows up here automatically.
void main() {
  test('ANC and NCD scan targets match the scan field maps', () {
    final t = UnifiedFormNotifier.gaScanTargetsForTesting;
    expect(t['anc'], {
      'weight', 'systolic', 'diastolic', 'pulse', 'temperature',
      'hemoglobin', 'glucose', 'fundalHeight', 'edema', 'urinaryAlbumin',
      'urinaryBilirubin', 'ultrasound', 'ttTdCompleted',
    });
    // NCD blood pressure is nested in bpLogDetails; it counts as its leaves.
    expect(t['ncd'],
        {'weight', 'height', 'systolic', 'diastolic', 'glucose', 'glucoseType'});
  });
}
