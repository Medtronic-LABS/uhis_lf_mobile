import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/immunisation/child_immunization_dto.dart';

void main() {
  test('Vaccinated record toJson omits reason', () {
    final record = ChildImmunizationVaccinationRecord(
      vaccineName: 'BCG',
      status: 'Vaccinated',
      vaccinatedDate: '2026-01-15T00:00:00+00:00',
    );

    expect(record.toJson(), {
      'vaccineName': 'BCG',
      'vaccinatedDate': '2026-01-15T00:00:00+00:00',
      'status': 'Vaccinated',
    });
  });

  test('Missed record toJson omits vaccinatedDate', () {
    final record = ChildImmunizationVaccinationRecord(
      vaccineName: 'OPV-1',
      status: 'Missed',
      reason: 'Child was sick on scheduled date',
    );

    expect(record.toJson(), {
      'vaccineName': 'OPV-1',
      'status': 'Missed',
      'reason': 'Child was sick on scheduled date',
    });
  });

  test('dateWire formats and zero-pads single-digit month/day', () {
    expect(
      ChildImmunizationVaccinationRecord.dateWire(DateTime(2026, 1, 5)),
      '2026-01-05T00:00:00+00:00',
    );
  });
}
