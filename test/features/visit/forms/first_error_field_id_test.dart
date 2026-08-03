/// Unit coverage for `firstErrorFieldId` — the pure helper that finds the
/// first field in error, in the same visual order the form renders sections
/// and their `fieldRefs`, used to scroll Step 2 to the exact missing field.
///
/// Returns a `formType_sectionId_fieldId`-scoped key (not a bare field id):
/// the same field id can legitimately appear in more than one
/// concurrently-mounted section on a combined-programme visit (e.g. ANC +
/// NCD both touching "weight"), and a bare-id key previously caused
/// "Duplicate GlobalKeys detected in widget tree" once every section stayed
/// mounted (see the `scrollCacheExtent` fix in unified_form_screen.dart).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/form_config.dart';
import 'package:uhis_next/features/visit/forms/unified_form_screen.dart';
import 'package:uhis_next/features/visit/forms/unified_section_rules.dart';

FieldRef _ref(String id) =>
    FieldRef(id: id, isMandatory: true, inputType: 0);

AnnotatedFormSection _section(
  String sectionId,
  String formType,
  List<String> fieldIds,
) =>
    AnnotatedFormSection(
      group: SectionGroup.vitals,
      section: FormSection(
        sectionId: sectionId,
        title: sectionId,
        formType: formType,
        fieldRefs: fieldIds.map(_ref).toList(),
      ),
    );

void main() {
  group('firstErrorFieldId', () {
    test('returns null when there are no errors', () {
      final annotated = [
        _section('vitals', 'ncd', ['systolic', 'diastolic']),
      ];
      expect(firstErrorFieldId(annotated, const {}), isNull);
    });

    test('returns the first errored field within a section, in fieldRefs order', () {
      final annotated = [
        _section('vitals', 'ncd', ['systolic', 'diastolic', 'weight']),
      ];
      expect(
        firstErrorFieldId(annotated, {'weight', 'diastolic'}),
        'ncd_vitals_diastolic',
      );
    });

    test('walks sections in the given (visual) order, not alphabetically', () {
      final annotated = [
        _section('vitals', 'ncd', ['systolic', 'diastolic']),
        _section('chronicConditions', 'ncd', ['stroke', 'heartAttack']),
      ];
      expect(
        firstErrorFieldId(annotated, {'heartAttack', 'stroke'}),
        'ncd_chronicConditions_stroke',
      );
    });

    test('a composite-pair error (e.g. diastolic) still resolves via fieldRefs', () {
      final annotated = [
        _section('vitals', 'ncd', ['systolic', 'diastolic', 'pulse']),
      ];
      // Only the absorbed field (diastolic) is in error — systolic drives the
      // rendered card but isn't itself missing.
      expect(
        firstErrorFieldId(annotated, {'diastolic'}),
        'ncd_vitals_diastolic',
      );
    });

    test('skips the dynamic newborn-details section (no single field anchor)', () {
      final annotated = [
        _section('newbornDetails', 'pregnancyOutcome', const []),
        _section('vitals', 'anc', ['weight']),
      ];
      expect(
        firstErrorFieldId(annotated, {'newbornDetails', 'weight'}),
        'anc_vitals_weight',
      );
    });

    test('returns null when the only error belongs to newbornDetails', () {
      final annotated = [
        _section('newbornDetails', 'pregnancyOutcome', const []),
      ];
      expect(firstErrorFieldId(annotated, {'newbornDetails'}), isNull);
    });

    test(
        'the same field id in two concurrently-active sections resolves to '
        'two distinct scoped keys, not one shared key', () {
      // Regression: a combined ANC+NCD visit where both an ANC-specific
      // section and an NCD section have their own "weight" field — a bare
      // field-id key would collide (and previously crashed with "Duplicate
      // GlobalKeys detected in widget tree" once both sections stayed
      // mounted). Only the ANC one is in error here.
      final annotated = [
        _section('ancSpecificVitals', 'anc', ['weight']),
        _section('bpLog', 'ncd', ['weight']),
      ];
      final result = firstErrorFieldId(annotated, {'weight'});
      expect(result, 'anc_ancSpecificVitals_weight');
      expect(result, isNot('ncd_bpLog_weight'));
    });
  });
}
