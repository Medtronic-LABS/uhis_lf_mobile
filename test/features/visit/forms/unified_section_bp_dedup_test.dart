import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ANC+NCD visit renders shared vitals once at top', () async {
    final config = await FormConfig.load(rootBundle);
    final sections = UnifiedSectionRules.activeSections(
      config: config,
      activeFormTypes: const ['anc', 'ncd'],
      enrolledFormTypes: const ['anc', 'ncd'],
      currentData: const CanonicalVisitData(),
    );

    final vitalsSections = sections
        .where((a) => a.group == SectionGroup.vitals)
        .toList();
    expect(vitalsSections, hasLength(1));
    expect(vitalsSections.single.section.formType, 'commonVitals');

    final commonIds = vitalsSections.single.section.fieldRefs
        .map((r) => r.id)
        .toSet();
    expect(commonIds, containsAll(['height', 'weight', 'bmi']));
    expect(commonIds, contains('bpLogDetails'));
    expect(commonIds, contains('glucoseType'));
    expect(commonIds, isNot(contains('glucose')));

    final byForm = <String, Set<String>>{};
    for (final a in sections) {
      byForm.putIfAbsent(a.section.formType, () => <String>{});
      for (final r in a.section.fieldRefs) {
        byForm[a.section.formType]!.add(r.id);
      }
    }

    final anc = byForm['anc'] ?? {};
    final ncd = byForm['ncd'] ?? {};

    expect(anc, isNot(contains('height')));
    expect(anc, isNot(contains('weight')));
    expect(anc, isNot(contains('bmi')));
    expect(anc, isNot(contains('systolic')));
    expect(anc, isNot(contains('diastolic')));
    expect(anc, isNot(contains('bloodPressure')));
    expect(anc, isNot(contains('glucoseType')));

    expect(ncd, isNot(contains('height')));
    expect(ncd, isNot(contains('weight')));
    expect(ncd, isNot(contains('bmi')));
    expect(ncd, isNot(contains('bpLogDetails')));
    expect(ncd, isNot(contains('glucoseType')));
    expect(ncd, isNot(contains('glucose')));

    // Programme-specific fields remain under each programme.
    expect(anc, contains('fundalHeight'));
    expect(ncd, contains('isBeforeHtnDiagnosis'));
  });

  test('NCD+PNC visit renders shared vitals once at top', () async {
    final config = await FormConfig.load(rootBundle);
    final sections = UnifiedSectionRules.activeSections(
      config: config,
      activeFormTypes: const ['ncd', 'pncMother'],
      enrolledFormTypes: const ['ncd', 'pncMother'],
      currentData: const CanonicalVisitData(),
    );

    final vitalsSections = sections
        .where((a) => a.group == SectionGroup.vitals)
        .toList();
    expect(vitalsSections, hasLength(1));

    final commonIds = vitalsSections.single.section.fieldRefs
        .map((r) => r.id)
        .toSet();
    expect(commonIds, containsAll(['height', 'weight', 'bmi', 'bpLogDetails']));
    expect(commonIds, contains('glucoseType'));

    final byForm = <String, Set<String>>{};
    for (final a in sections) {
      byForm.putIfAbsent(a.section.formType, () => <String>{});
      for (final r in a.section.fieldRefs) {
        byForm[a.section.formType]!.add(r.id);
      }
    }

    final pnc = byForm['pncMother'] ?? {};
    expect(pnc, isNot(contains('weight')));
    expect(pnc, isNot(contains('systolic')));
    expect(pnc, isNot(contains('diastolic')));
    expect(pnc, isNot(contains('bloodPressure')));
    expect(pnc, isNot(contains('bloodSugar')));
    expect(pnc, contains('postpartumDangerSigns'));
  });

  test('single-programme NCD visit keeps vitals under NCD', () async {
    final config = await FormConfig.load(rootBundle);
    final sections = UnifiedSectionRules.activeSections(
      config: config,
      activeFormTypes: const ['ncd'],
      enrolledFormTypes: const ['ncd'],
      currentData: const CanonicalVisitData(),
    );

    expect(
      sections.any((a) => a.section.formType == 'commonVitals'),
      isFalse,
    );

    final ncdIds = <String>{};
    for (final a in sections.where((s) => s.section.formType == 'ncd')) {
      for (final r in a.section.fieldRefs) {
        ncdIds.add(r.id);
      }
    }
    expect(ncdIds, containsAll(['height', 'weight', 'bmi', 'bpLogDetails']));
  });
}
