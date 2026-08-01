import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/canonical_visit_data.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormConfig config;

  setUpAll(() async {
    config = await FormConfig.load(rootBundle);
  });

  bool hasNcdEyeCare(List<AnnotatedFormSection> sections) => sections.any(
        (a) => a.section.formType == 'ncd' && a.section.sectionId == 'eyeCare',
      );

  List<AnnotatedFormSection> ncdSections({int? ageInMonths}) =>
      UnifiedSectionRules.activeSections(
        config: config,
        activeFormTypes: const ['ncd'],
        currentData: const CanonicalVisitData(),
        ageInMonths: ageInMonths,
      );

  group('NCD Eye Care age gate (Spice BDNCDAssessmentFragment parity)', () {
    test('hides Eye Care when age is under 35 years', () {
      expect(hasNcdEyeCare(ncdSections(ageInMonths: 34 * 12)), isFalse);
      expect(hasNcdEyeCare(ncdSections(ageInMonths: 34 * 12 + 11)), isFalse);
    });

    test('shows Eye Care when age is 35 or older', () {
      expect(hasNcdEyeCare(ncdSections(ageInMonths: 35 * 12)), isTrue);
      expect(hasNcdEyeCare(ncdSections(ageInMonths: 40 * 12)), isTrue);
    });

    test('shows Eye Care when age is unknown', () {
      expect(hasNcdEyeCare(ncdSections()), isTrue);
    });

    test('standalone eye_care form is not age-gated', () {
      final sections = UnifiedSectionRules.activeSections(
        config: config,
        activeFormTypes: const ['eye_care'],
        currentData: const CanonicalVisitData(),
        ageInMonths: 20 * 12,
      );
      expect(
        sections.any((a) => a.section.sectionId == 'eyeCare'),
        isTrue,
      );
    });
  });
}
