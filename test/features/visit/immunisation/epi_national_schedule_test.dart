import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/immunisation_dao.dart';
import 'package:uhis_next/features/visit/immunisation/epi_schedule_engine.dart';

/// Pins the schedule to the product immunization workflow table.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dob = DateTime(2020, 1, 1);
  final today = DateTime(2022, 1, 1);

  Future<Map<String, List<String>>> codesByMilestone() async {
    final milestones =
        await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
    return {
      for (final m in milestones)
        m.label: m.vaccines.map((v) => v.code).toList(),
    };
  }

  test('product table vaccines at each milestone', () async {
    expect(await codesByMilestone(), {
      'At Birth': ['BCG'],
      '6 Weeks': ['PENTA1', 'PCV1', 'OPV1'],
      '10 Weeks': ['PENTA2', 'PCV2', 'OPV2'],
      '14 Weeks': ['PENTA3', 'PCV3', 'OPV3', 'FIPV1'],
      '9 Months': ['MR1', 'FIPV2'],
      '15 Months': ['MR2', 'TCV'],
    });
  });

  test('update-status copy carries disease names', () async {
    final milestones =
        await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
    final byCode = {
      for (final v in milestones.expand((m) => m.vaccines)) v.code: v,
    };

    expect(byCode['BCG']!.description, 'Bacillus Calmette–Guérin');
    expect(byCode['BCG']!.route, "Disease Name: Children's Tuberculosis");

    expect(byCode['PENTA1']!.description,
        'Diphtheria, Pertussis, and Tetanus, Hepatitis B, Hib');
    expect(byCode['PCV1']!.description, 'Pneumococcal Conjugate Vaccine (PCV)');
    expect(byCode['OPV1']!.description, 'Oral Polio Vaccine (OPV)');
    expect(byCode['FIPV1']!.description, 'Inactivated Poliovirus Vaccine (IPV)');
    expect(byCode['MR1']!.description, 'Measles-Rubella (MR) Vaccination');
    expect(byCode['TCV']!.description, 'Typhoid Conjugate Vaccine (TCV)');
    expect(byCode['TCV']!.route, 'Disease Name: Typhoid fever');
  });

  test('wire display names stay English (payload-safe)', () async {
    final milestones =
        await EpiScheduleEngine.build(dob: dob, rows: const [], today: today);
    final byCode = {
      for (final v in milestones.expand((m) => m.vaccines)) v.code: v.display,
    };
    expect(byCode['FIPV1'], 'fIPV — Dose 1');
    expect(byCode['FIPV2'], 'fIPV — Dose 2');
    expect(byCode['PENTA1'], 'Pentavalent-1');
    expect(byCode['MR1'], 'MR Vaccine — Dose 1');
  });

  test('OPV0 / HepB0 / Rota / Vitamin A are not scheduled', () async {
    final all =
        (await codesByMilestone()).values.expand((c) => c).toSet();
    for (final removed in const [
      'OPV0',
      'HepB0',
      'ROTA1',
      'ROTA2',
      'VITA1',
    ]) {
      expect(all, isNot(contains(removed)));
    }
  });

  test('server spelling Polio-(OPV 2) marks OPV2 completed', () async {
    final milestones = await EpiScheduleEngine.build(
      dob: dob,
      today: today,
      rows: [
        ImmunisationRow(
          id: 'r1',
          patientId: 'p1',
          vaccineCode: 'Polio-(OPV 2)',
          givenAt: DateTime(2020, 3, 15).millisecondsSinceEpoch,
          status: 'Vaccinated',
          rawJson: '{}',
        ),
      ],
    );
    final opv2 = milestones
        .expand((m) => m.vaccines)
        .firstWhere((v) => v.code == 'OPV2');
    expect(opv2.status, VaccineStatus.completed);
  });
}
