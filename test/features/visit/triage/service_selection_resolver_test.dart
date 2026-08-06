import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/models/programme.dart';
import 'package:uhis_next/features/visit/triage/service_selection_resolver.dart';

void main() {
  group('ServiceSelectionResolver.finalize — Task 3 (PW once-only)', () {
    test('drops PW silently when registration is blocked', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.pw, Programme.ncd},
        pwRegistrationBlocked: true,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, {Programme.ncd});
      expect(result.blockedReason, isNull);
      expect(result.silentlyEmptied, isFalse);
    });

    test('reports silentlyEmptied when PW was the only selection', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.pw},
        pwRegistrationBlocked: true,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, isEmpty);
      expect(result.silentlyEmptied, isTrue);
      expect(result.blockedReason, isNull);
    });

    test('keeps PW when registration is not blocked', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.pw},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, {Programme.pw});
    });
  });

  group('ServiceSelectionResolver.finalize — Task 2 (ANC blocked postpartum)', () {
    test('removes ANC and reports ancBlockedPostpartum', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.anc, Programme.ncd},
        pwRegistrationBlocked: false,
        isPostpartum: true,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, {Programme.ncd});
      expect(
        result.blockedReason,
        ServiceSelectionBlockReason.ancBlockedPostpartum,
      );
      expect(result.silentlyEmptied, isFalse);
    });
  });

  group('ServiceSelectionResolver.finalize — Task 1 (ANC revisit interval)', () {
    test('removes ANC and reports ancBlockedRevisit', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.anc},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: true,
      );

      expect(result.programmes, isEmpty);
      expect(
        result.blockedReason,
        ServiceSelectionBlockReason.ancBlockedRevisit,
      );
    });

    test('postpartum block takes precedence over revisit block', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.anc},
        pwRegistrationBlocked: false,
        isPostpartum: true,
        ancRevisitBlocked: true,
      );

      expect(
        result.blockedReason,
        ServiceSelectionBlockReason.ancBlockedPostpartum,
      );
    });
  });

  group('ServiceSelectionResolver.finalize — Task 5 (PW auto-add with first ANC)', () {
    test('adds PW alongside a first-time ANC selection', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.anc},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, {Programme.anc, Programme.pw});
    });

    test('does not add PW when the woman is already registered', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.anc},
        pwRegistrationBlocked: true,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      // pwRegistrationBlocked=true with ANC still selected means the ANC
      // itself isn't blocked (only PW registration is) — Task 5 must not
      // re-add PW for an already-registered woman.
      expect(result.programmes, {Programme.anc});
    });

    test('does not add PW when already selected', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.anc, Programme.pw},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, {Programme.anc, Programme.pw});
    });
  });

  group('ServiceSelectionResolver.finalize — delivery visit', () {
    test('always includes PNC on a delivery visit', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.ncd},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: false,
        isDeliveryVisit: true,
      );

      expect(result.programmes, {Programme.ncd, Programme.pnc});
    });
  });

  group('ServiceSelectionResolver.finalize — pilot-scope exclusion', () {
    test('filters out nutrition and tb regardless of how they entered the set',
        () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.ncd, Programme.nutrition, Programme.tb},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, {Programme.ncd});
    });

    test('does not filter epi (handled by the vaccination route, not here)',
        () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.epi},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, {Programme.epi});
    });

    test('reports silentlyEmptied when only excluded programmes were selected',
        () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.tb},
        pwRegistrationBlocked: false,
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(result.programmes, isEmpty);
      expect(result.silentlyEmptied, isTrue);
    });
  });

  group('ServiceSelectionResolver.finalize — ordering', () {
    test('orders the final set by canonical clinical priority', () {
      final result = ServiceSelectionResolver.finalize(
        selected: {
          Programme.familyPlanning,
          Programme.ncd,
          Programme.anc,
        },
        pwRegistrationBlocked: true, // skip Task 5's PW auto-add for clarity
        isPostpartum: false,
        ancRevisitBlocked: false,
      );

      expect(
        result.programmes.toList(),
        [Programme.anc, Programme.ncd, Programme.familyPlanning],
      );
    });
  });

  group('ServiceSelectionResolver.primaryFrom', () {
    test('picks the first known programme, skipping unknown names', () {
      expect(
        ServiceSelectionResolver.primaryFrom(['bogus', 'anc', 'ncd']),
        Programme.anc,
      );
    });

    test('returns unknown for an empty or all-unrecognized list', () {
      expect(ServiceSelectionResolver.primaryFrom([]), Programme.unknown);
      expect(
        ServiceSelectionResolver.primaryFrom(['bogus']),
        Programme.unknown,
      );
    });

    test(
        'end-to-end: a resolved, priority-ordered selection yields the '
        'clinically-correct primary programme (VisitFormScreen._getPrimaryProgramme parity)',
        () {
      final result = ServiceSelectionResolver.finalize(
        selected: {Programme.tb, Programme.ncd, Programme.anc},
        pwRegistrationBlocked: true, // skip PW auto-add for a clean set
        isPostpartum: false,
        ancRevisitBlocked: false,
      );
      // tb is pilot-excluded (change 8) — only ncd/anc survive.
      final names = result.programmes.map((p) => p.name).toList();

      expect(ServiceSelectionResolver.primaryFrom(names), Programme.anc);
    });
  });
}
