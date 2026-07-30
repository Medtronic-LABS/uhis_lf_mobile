import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/household/enrollment/patient_lookup_repository.dart';

void main() {
  group('PatientLookupRepository.firstMatch', () {
    // A spice-service /patient/search hit, using the field aliases
    // Patient.fromApiJson probes for (idCode → nationalId, etc.).
    final spiceHit = {
      'id': 'pat-001',
      'patientId': 'pat-001',
      'firstName': 'Noor',
      'lastName': 'Alam',
      'gender': 'Male',
      'dateOfBirth': '1983-11-25',
      'phoneNumber': '01711223344',
      'idCode': '6004589963',
      'villageId': 'v-12',
    };

    test('maps the first patient out of an entityList envelope', () {
      final patient =
          PatientLookupRepository.firstMatch({'entityList': [spiceHit]});
      expect(patient, isNotNull);
      expect(patient!.id, 'pat-001');
      expect(patient.name, 'Noor Alam');
      expect(patient.gender, 'Male');
      expect(patient.dob, startsWith('1983-11-25'));
      expect(patient.nationalId, '6004589963');
    });

    test('maps out of a data envelope', () {
      final patient = PatientLookupRepository.firstMatch({
        'data': [spiceHit]
      });
      expect(patient?.nationalId, '6004589963');
    });

    test('maps out of a bare list', () {
      final patient = PatientLookupRepository.firstMatch([spiceHit]);
      expect(patient?.name, 'Noor Alam');
    });

    test('returns the first mappable entry, skipping unmappable ones', () {
      final patient = PatientLookupRepository.firstMatch([
        {'noIdentifier': true},
        spiceHit,
      ]);
      expect(patient?.id, 'pat-001');
    });

    test('returns null for an empty result set', () {
      expect(PatientLookupRepository.firstMatch({'entityList': []}), isNull);
      expect(PatientLookupRepository.firstMatch(const []), isNull);
    });

    test('returns null for an unexpected body shape', () {
      expect(PatientLookupRepository.firstMatch('not-json'), isNull);
      expect(PatientLookupRepository.firstMatch(null), isNull);
    });
  });
}
