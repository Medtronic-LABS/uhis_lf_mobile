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

    test('non-delivery expands pnc without pregnancyOutcome', () {
      final types = FormTypeResolver.resolve(['pnc', 'ncd']);
      expect(types, ['pncMother', 'pncChild', 'ncd']);
    });
  });
}
