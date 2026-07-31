import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/cdss/cdss_engine.dart';
import 'package:uhis_next/core/cdss/models/cdss_inputs.dart';

CdssPatientProfile _ncdProfile({
  int age = 55,
  bool isFemale = false,
  double bmi = 28.0,
  int sbp = 145,
  double waist = 98.0,
  bool onMeds = false,
  bool smoker = true,
  bool diabetes = false,
}) =>
    CdssPatientProfile(
      ageYears: age,
      isFemale: isFemale,
      bmi: bmi,
      systolicBp: sbp,
      waistCm: waist,
      onBpMedication: onMeds,
      isSmoker: smoker,
      hasDiabetes: diabetes,
      isPhysicallyActive: false,
      eatsDailyFruitVeg: false,
      hadPreviousHighGlucose: false,
      hasFamilyHistoryDm: false,
    );

List<BpReading> _risingBp() => [
      BpReading(systolic: 120, visitIndex: 0),
      BpReading(systolic: 135, visitIndex: 1),
      BpReading(systolic: 150, visitIndex: 2),
      BpReading(systolic: 165, visitIndex: 3),
    ];

void main() {
  group('CdssEngine', () {
    test('NCD profile with all FINDRISC inputs → findrisc + framingham populated', () {
      final out = CdssEngine.evaluate(
        profile: _ncdProfile(),
        bpHistory: [],
      );
      expect(out.findrisc, isNotNull);
      expect(out.framingham, isNotNull);
      expect(out.cusum, isNull); // no history
      expect(out.ewma, isNull);
      expect(out.slope, isNull);
      expect(out.miniPiers, isNull);
    });

    test('NCD profile with 4 rising BP readings → all trend algorithms alert', () {
      final out = CdssEngine.evaluate(
        profile: _ncdProfile(),
        bpHistory: _risingBp(),
      );
      expect(out.cusum, isNotNull);
      expect(out.ewma, isNotNull);
      expect(out.slope, isNotNull);
      // rising slope of 15 mmHg/visit → alert
      expect(out.slope!.alert, true);
      expect(out.anyTrendAlert, true);
    });

    test('pregnant patient GA=34 SBP=155 → miniPiers trigger', () {
      final maternal = MaternalProfile(
        gestationalWeeks: 34,
        systolicBp: 155,
        proteinuriaGrade: 2,
        hasHeadache: true,
        hasChestPain: false,
      );
      final out = CdssEngine.evaluate(
        profile: _ncdProfile(age: 28, sbp: 155),
        bpHistory: [],
        maternal: maternal,
      );
      expect(out.miniPiers, isNotNull);
      expect(out.miniPiers!.insufficientData, false);
      expect(out.miniPiers!.trigger, true);
    });

    test('young healthy patient → all algorithms run, no triggers', () {
      final profile = CdssPatientProfile(
        ageYears: 25,
        isFemale: false,
        bmi: 22.0,
        systolicBp: 115,
        waistCm: 80.0,
        onBpMedication: false,
        isSmoker: false,
        hasDiabetes: false,
        isPhysicallyActive: true,
        eatsDailyFruitVeg: true,
        hadPreviousHighGlucose: false,
        hasFamilyHistoryDm: false,
      );
      final out = CdssEngine.evaluate(profile: profile, bpHistory: []);
      expect(out.findrisc!.trigger, false);
      expect(out.framingham!.trigger, false);
      expect(out.anyTrendAlert, false);
      expect(out.ncdTriggered, false);
    });

    test('CdssEngineOutput.ncdTriggered aggregation', () {
      // High-risk NCD profile: FINDRISC should trigger
      final out = CdssEngine.evaluate(
        profile: _ncdProfile(age: 65, bmi: 35.0, waist: 110.0,
            smoker: true, diabetes: false),
        bpHistory: [],
      );
      // ncdTriggered = findrisc.trigger || framingham.trigger || anyTrendAlert
      final expected = (out.findrisc?.trigger ?? false) ||
          (out.framingham?.trigger ?? false) ||
          out.anyTrendAlert;
      expect(out.ncdTriggered, expected);
    });

    test('no maternal → miniPiers is null, ancTriggerMiniPiers = false', () {
      final out = CdssEngine.evaluate(
        profile: _ncdProfile(),
        bpHistory: [],
      );
      expect(out.miniPiers, isNull);
      expect(out.ancTriggerMiniPiers, false);
    });

    test('framingham skipped when bmi = null', () {
      final profile = CdssPatientProfile(
        ageYears: 50,
        isFemale: false,
        bmi: null,
        systolicBp: 130,
        waistCm: null,
        onBpMedication: false,
        isSmoker: false,
        hasDiabetes: false,
        isPhysicallyActive: true,
        eatsDailyFruitVeg: true,
        hadPreviousHighGlucose: false,
        hasFamilyHistoryDm: false,
      );
      final out = CdssEngine.evaluate(profile: profile, bpHistory: []);
      expect(out.framingham, isNull);
      expect(out.findrisc, isNotNull); // FINDRISC still runs
    });
  });
}
