import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ANC+NCD visit keeps BP and BG widgets in both programmes', () async {
    final config = await FormConfig.load(rootBundle);
    final sections = UnifiedSectionRules.activeSections(
      config: config,
      activeFormTypes: const ['anc', 'ncd'],
      enrolledFormTypes: const ['anc', 'ncd'],
      currentData: const CanonicalVisitData(),
    );

    final byForm = <String, Set<String>>{};
    for (final a in sections) {
      byForm.putIfAbsent(a.section.formType, () => <String>{});
      for (final r in a.section.fieldRefs) {
        byForm[a.section.formType]!.add(r.id);
      }
    }

    final anc = byForm['anc'] ?? {};
    final ncd = byForm['ncd'] ?? {};

    // ANC clinical examination BP pair.
    expect(anc.contains('systolic') || anc.contains('bloodPressure'), isTrue);
    expect(anc.contains('diastolic') || anc.contains('bloodPressure'), isTrue);
    // NCD BP log widget — must not be swallowed by ANC BP claim.
    expect(ncd, contains('bpLogDetails'));

    // BG appears under both programmes (same field id, per-programme claim).
    expect(anc, contains('glucoseType'));
    expect(ncd, contains('glucoseType'));
    // Bare `glucose` still collapsed next to BloodGlucoseEntry inside NCD.
    expect(ncd, isNot(contains('glucose')));

    // NCD keeps its own biometrics card (not swallowed by ANC height/weight).
    expect(ncd, contains('height'));
    expect(ncd, contains('weight'));
    expect(ncd, contains('bmi'));
  });
}
