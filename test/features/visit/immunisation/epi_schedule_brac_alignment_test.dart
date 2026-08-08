import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/db/immunisation_dao.dart';
import 'package:uhis_next/core/i18n/app_locale.dart';
import 'package:uhis_next/features/visit/immunisation/epi_schedule_engine.dart';

/// Pins the childhood immunisation schedule to the table BRAC supplied, and
/// guards the three invariants that make it safe to change:
///   * recorded doses keep matching after the relabelling (`code` is stable),
///   * the transmitted `vaccineName` never becomes locale-dependent,
///   * the server's own vaccine vocabulary resolves onto local codes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 2020-01-01 birth, "today" far enough past 15 months that every milestone
  // is due — so the assertions are about schedule content, not timing.
  final dob = DateTime(2020, 1, 1);
  final today = DateTime(2022, 1, 1);

  tearDown(() => AppLocale.current = AppLanguage.english);

  Future<Map<String, List<String>>> codesByMilestone() async {
    final milestones =
        await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
    return {
      for (final m in milestones) m.label: m.vaccines.map((v) => v.code).toList()
    };
  }

  group('BRAC schedule alignment', () {
    test('every milestone carries exactly the vaccines BRAC specifies',
        () async {
      expect(await codesByMilestone(), {
        'At Birth': ['BCG'],
        '6 Weeks': ['PENTA1', 'PCV1', 'OPV1'],
        '10 Weeks': ['PENTA2', 'PCV2', 'OPV2'],
        '14 Weeks': ['PENTA3', 'PCV3', 'OPV3', 'FIPV1'],
        '9 Months': ['MR1', 'FIPV2'],
        '15 Months': ['MR2', 'TCV'],
      });
    });

    test('TCV moved to 15 Months and is no longer at 9 Months', () async {
      final byMilestone = await codesByMilestone();
      expect(byMilestone['15 Months'], contains('TCV'));
      expect(byMilestone['9 Months'], isNot(contains('TCV')));
    });

    test('vaccines absent from the BRAC sheet are not scheduled', () async {
      final all = (await codesByMilestone()).values.expand((c) => c).toList();
      for (final removed in const ['OPV0', 'HepB0', 'ROTA1', 'ROTA2', 'VITA1']) {
        expect(all, isNot(contains(removed)), reason: '$removed is not on the sheet');
      }
    });

    test('IPV is labelled IPV, keeps two doses, and keeps its FIPV codes',
        () async {
      final milestones =
          await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
      final ipv = milestones
          .expand((m) => m.vaccines)
          .where((v) => v.category == 'ipv')
          .toList();

      expect(ipv.map((v) => v.code), ['FIPV1', 'FIPV2'],
          reason: 'codes stay stable so recorded doses keep matching');
      expect(ipv.map((v) => v.display), ['IPV — Dose 1', 'IPV — Dose 2']);
    });
  });

  group('wire contract', () {
    test('wireName keeps the pre-change strings, so payloads are unchanged',
        () async {
      final milestones =
          await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
      final wireByCode = {
        for (final v in milestones.expand((m) => m.vaccines)) v.code: v.wireName
      };

      // Exactly what the previous build sent as `vaccineName`.
      expect(wireByCode['FIPV1'], 'fIPV — Dose 1');
      expect(wireByCode['FIPV2'], 'fIPV — Dose 2');
      expect(wireByCode['PENTA1'], 'Pentavalent-1');
      expect(wireByCode['OPV2'], 'OPV-2');
      expect(wireByCode['TCV'], 'TCV');
    });

    test('wireName does not change when the UI locale is Bangla', () async {
      AppLocale.current = AppLanguage.english;
      final english =
          await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
      final englishWire =
          english.expand((m) => m.vaccines).map((v) => v.wireName).toList();

      AppLocale.current = AppLanguage.bangla;
      final bangla =
          await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
      final banglaWire =
          bangla.expand((m) => m.vaccines).map((v) => v.wireName).toList();

      expect(banglaWire, englishWire,
          reason: 'a Bangla-locale SK must never POST Bangla vaccine names');
    });
  });

  group('server vocabulary resolves onto local codes', () {
    Future<VaccineEntry> entryFor(String code, String recordedAs) async {
      final milestones = await EpiScheduleEngine.build(
        dob: dob,
        today: today,
        rows: [
          ImmunisationRow(
            id: 'p1_$recordedAs',
            patientId: 'p1',
            vaccineCode: recordedAs,
            givenAt: DateTime(2020, 3, 1).millisecondsSinceEpoch,
            status: 'Vaccinated',
            rawJson: '{}',
          ),
        ],
      );
      return milestones
          .expand((m) => m.vaccines)
          .firstWhere((v) => v.code == code);
    }

    test('the evidenced server spelling Polio-(OPV 2) marks OPV2 completed',
        () async {
      final opv2 = await entryFor('OPV2', 'Polio-(OPV 2)');
      expect(opv2.status, VaccineStatus.completed);
    });

    test('the evidenced server spelling Penta-2 marks PENTA2 completed',
        () async {
      final penta2 = await entryFor('PENTA2', 'Penta-2');
      expect(penta2.status, VaccineStatus.completed);
    });

    test('a dose recorded under the local code still matches', () async {
      expect((await entryFor('FIPV1', 'FIPV1')).status,
          VaccineStatus.completed);
    });

    test('a dose recorded under the frozen wire name still matches', () async {
      expect((await entryFor('FIPV1', 'fIPV — Dose 1')).status,
          VaccineStatus.completed);
    });

    test('an unrecognised identifier resolves to nothing, never a wrong vaccine',
        () async {
      final schedule = (jsonDecode(await rootBundle
              .loadString('assets/forms/epi_schedule.json')) as List)
          .cast<Map<String, dynamic>>();
      final index = EpiScheduleEngine.buildAliasIndex(schedule);

      expect(EpiScheduleEngine.resolveCode('Wibble-9', index), isNull);
      // A de-scheduled vaccine is simply unknown to the schedule now.
      expect(EpiScheduleEngine.resolveCode('ROTA1', index), isNull);
    });
  });

  group('Bangla display names', () {
    test('resolve for every scheduled vaccine, and fall back to English',
        () async {
      final milestones =
          await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
      final vaccines = milestones.expand((m) => m.vaccines).toList();

      AppLocale.current = AppLanguage.english;
      for (final v in vaccines) {
        expect(EpiVaccineStrings.display(v.code, v.display), v.display,
            reason: 'English must be the schedule asset text verbatim');
      }
    });

    test('milestone labels fall back to the asset label when key is unknown',
        () {
      AppLocale.current = AppLanguage.english;
      expect(EpiVaccineStrings.milestone('', '6 Weeks'), '6 Weeks');
      expect(EpiVaccineStrings.milestone('nope', '6 Weeks'), '6 Weeks');
    });

    test('BRAC Bangla is actually served once translations are loaded',
        () async {
      await loadTranslations();
      AppLocale.current = AppLanguage.bangla;

      expect(EpiVaccineStrings.display('BCG', 'BCG'), 'বিসিজি (BCG)');
      expect(EpiVaccineStrings.display('TCV', 'TCV'), 'টিসিভি (TCV)');
      expect(EpiVaccineStrings.display('FIPV1', 'IPV — Dose 1'),
          'আইপিভি (IPV) – প্রথম ডোজ');
      expect(EpiVaccineStrings.milestone('month15', '15 Months'), '১৫ মাসে');

      AppLocale.current = AppLanguage.english;
      expect(EpiVaccineStrings.display('BCG', 'BCG'), 'BCG');
      expect(EpiVaccineStrings.milestone('month15', '15 Months'), '15 Months');
    });
  });
}
