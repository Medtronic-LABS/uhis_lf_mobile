import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/form_type_resolver.dart';

void main() {
  group('FormTypeResolver.resolve', () {
    test('delivery visit seeds outcome + PNC and keeps other programmes', () {
      final types = FormTypeResolver.resolve(
        ['anc', 'pw', 'ncd', 'pnc', 'tb'],
        isDelivery: true,
      );
      expect(types, [
        'pregnancyOutcome',
        'pncMother',
        'pncChild',
        'ncd',
        'tb',
      ]);
    });

    test(
        'delivery visit with empty programme set still seeds pregnancyOutcome '
        '(Outcome selected, PNC deselected at triage)', () {
      final types = FormTypeResolver.resolve(const [], isDelivery: true);
      expect(types, [
        'pregnancyOutcome',
        'pncMother',
        'pncChild',
      ]);
    });

    test('non-delivery expands pnc to mother only', () {
      final types = FormTypeResolver.resolve(['pnc', 'ncd']);
      expect(types, ['pncMother', 'ncd']);
    });

    test('imci resolves to childhood visit formType', () {
      expect(FormTypeResolver.resolve(['imci']), ['pncChild']);
    });
  });
}
