import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/form_scroll_registry.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

void main() {
  group('FormFieldScrollRegistry', () {
    test('resolveOwner maps composite aliases to scoped driver field', () {
      final registry = FormFieldScrollRegistry();
      expect(
        registry.resolveOwner('diastolic', formType: 'anc'),
        'anc:systolic',
      );
      expect(
        registry.resolveOwner('glucose', formType: 'anc'),
        'anc:glucoseType',
      );
      expect(
        registry.resolveOwner('randomBloodSugar', formType: 'pncMother'),
        'pncMother:fastingBloodSugar',
      );
      expect(
        registry.resolveOwner('newbornDetails_1_sex', formType: 'pregnancyOutcome'),
        'pregnancyOutcome:newbornDetails_1',
      );
    });

    test('registerScrollTarget overrides static aliases at build time', () {
      final registry = FormFieldScrollRegistry();
      registry.registerScrollTarget(
        ownerFieldId: 'anc:weight',
        aliasIds: {'anc:weight', 'anc:height'},
      );
      expect(registry.resolveOwner('weight', formType: 'anc'), 'anc:weight');
      expect(registry.resolveOwner('height', formType: 'anc'), 'anc:weight');
    });

    test('firstErrorInDocumentOrder returns scoped keys in section order', () {
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
        'anc:hemoglobin',
      );
      expect(
        registry.firstErrorInDocumentOrder({'glucose', 'systolic'}, annotated),
        'anc:systolic',
      );
      expect(
        registry.firstErrorInDocumentOrder({'glucose'}, annotated),
        'anc:glucoseType',
      );
    });

    test('same field id in two programmes gets distinct scoped keys', () {
      final registry = FormFieldScrollRegistry();
      registry.registerScrollTarget(
        ownerFieldId: 'anc:glucoseType',
        aliasIds: {'anc:glucoseType', 'anc:glucose'},
      );
      registry.registerScrollTarget(
        ownerFieldId: 'ncd:glucoseType',
        aliasIds: {'ncd:glucoseType', 'ncd:glucose'},
      );

      expect(
        registry.resolveOwner('glucose', formType: 'anc'),
        'anc:glucoseType',
      );
      expect(
        registry.resolveOwner('glucose', formType: 'ncd'),
        'ncd:glucoseType',
      );
      expect(registry.keyFor('anc:glucoseType'),
          isNot(same(registry.keyFor('ncd:glucoseType'))));
    });
  });
}
