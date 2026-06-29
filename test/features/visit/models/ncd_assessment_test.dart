import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/models/ncd_assessment.dart';

void main() {
  group('HtnScreening — spec §5.2.2', () {
    test('hasAnswered is false when all fields null', () {
      const screening = HtnScreening();
      expect(screening.hasAnswered, isFalse);
    });

    test('hasAnswered true when any field set', () {
      const screening = HtnScreening(morningHeadaches: false);
      expect(screening.hasAnswered, isTrue);
    });

    test('round-trips through JSON without losing values', () {
      const screening = HtnScreening(
        morningHeadaches: true,
        chestTightnessOrSob: false,
        highSaltIntake: true,
        familyHistoryHtn: true,
        oneSidedWeakness: false,
      );
      final json = screening.toJson();
      final restored = HtnScreening.fromJson(json);
      expect(restored.morningHeadaches, true);
      expect(restored.chestTightnessOrSob, false);
      expect(restored.highSaltIntake, true);
      expect(restored.familyHistoryHtn, true);
      expect(restored.oneSidedWeakness, false);
    });

    test('toJson omits null fields', () {
      const screening = HtnScreening(oneSidedWeakness: true);
      final json = screening.toJson();
      expect(json.keys, equals(['oneSidedWeakness']));
      expect(json['oneSidedWeakness'], true);
    });

    test('copyWith updates only specified field', () {
      const original = HtnScreening(morningHeadaches: true);
      final updated = original.copyWith(highSaltIntake: true);
      expect(updated.morningHeadaches, true);
      expect(updated.highSaltIntake, true);
      expect(updated.chestTightnessOrSob, isNull);
    });
  });

  group('NcdAssessment carries HtnScreening', () {
    test('round-trips htnScreening through copyWith + toJson', () {
      const screening = HtnScreening(oneSidedWeakness: true);
      const assessment = NcdAssessment(htnScreening: screening);
      expect(assessment.htnScreening, same(screening));
      final json = assessment.toJson();
      expect(json['htnScreening'], isA<Map<String, dynamic>>());
      expect((json['htnScreening'] as Map)['oneSidedWeakness'], true);
    });
  });
}
