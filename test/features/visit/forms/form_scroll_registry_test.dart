import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/form_scroll_registry.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

void main() {
  group('FormFieldScrollRegistry', () {
    test('resolveOwner maps composite aliases to driver field', () {
      final registry = FormFieldScrollRegistry();
      expect(registry.resolveOwner('diastolic'), 'systolic');
      expect(registry.resolveOwner('glucose'), 'glucoseType');
      expect(registry.resolveOwner('randomBloodSugar'), 'fastingBloodSugar');
      expect(registry.resolveOwner('newbornDetails_1_sex'), 'newbornDetails_1');
    });

    test('registerScrollTarget overrides static aliases at build time', () {
      final registry = FormFieldScrollRegistry();
      registry.registerScrollTarget(
        ownerFieldId: 'weight',
        aliasIds: {'weight', 'height'},
      );
      expect(registry.resolveOwner('weight'), 'weight');
      expect(registry.resolveOwner('height'), 'weight');
    });

    test('firstErrorInDocumentOrder follows annotated section order', () {
      final registry = FormFieldScrollRegistry();
      final annotated = [
        AnnotatedFormSection(
          section: FormSection(
            sectionId: 'vitals',
            title: 'Vitals',
            formType: 'anc',
            fieldRefs: [
              const FieldRef(id: 'systolic', isMandatory: false, inputType: 0),
              const FieldRef(id: 'diastolic', isMandatory: false, inputType: 0),
            ],
          ),
          group: SectionGroup.vitals,
        ),
        AnnotatedFormSection(
          section: FormSection(
            sectionId: 'labInvestigations',
            title: 'Lab',
            formType: 'anc',
            fieldRefs: [
              const FieldRef(id: 'hemoglobin', isMandatory: true, inputType: 0),
              const FieldRef(id: 'glucoseType', isMandatory: true, inputType: 0),
            ],
          ),
          group: SectionGroup.recommended,
        ),
      ];

      expect(
        registry.firstErrorInDocumentOrder({'hemoglobin'}, annotated),
        'hemoglobin',
      );
      expect(
        registry.firstErrorInDocumentOrder({'glucose', 'systolic'}, annotated),
        'systolic',
      );
      expect(
        registry.firstErrorInDocumentOrder({'glucose'}, annotated),
        'glucose',
      );
    });
  });
}
