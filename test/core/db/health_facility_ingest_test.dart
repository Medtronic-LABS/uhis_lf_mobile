import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/db/health_facility_dao.dart';

void main() {
  group('HealthFacilityIngest.fromUserDataEntity', () {
    test('filters nearest facilities by villages ∩ linkedVillages', () {
      final rows = HealthFacilityIngest.fromUserDataEntity({
        'villages': [
          {'id': 10, 'name': 'A'},
          {'id': 20, 'name': 'B'},
        ],
        'defaultHealthFacility': {'id': 1, 'name': 'Default CC', 'fhirId': 'org-1'},
        'nearestHealthFacilities': [
          {
            'id': 1,
            'name': 'Default CC',
            'fhirId': 'org-1',
            'linkedVillages': [
              {'id': 10, 'name': 'A'},
            ],
          },
          {
            'id': 2,
            'name': 'Other district PHU',
            'fhirId': 'org-2',
            'linkedVillages': [
              {'id': 99, 'name': 'Elsewhere'},
            ],
          },
          {
            'id': 3,
            'name': 'Linked PHU',
            'fhirId': 'org-3',
            'phuFocalPersonNumber': 1712345678,
            'linkedVillages': [
              {'id': 20, 'name': 'B'},
            ],
          },
        ],
        'userHealthFacilities': [
          {
            'id': 4,
            'name': 'User site only',
            'fhirId': 'org-4',
            'linkedVillages': [
              {'id': 10, 'name': 'A'},
            ],
          },
        ],
      });

      final ids = rows.map((r) => r.id).toSet();
      expect(ids, containsAll(['1', '3', '4']));
      expect(ids, isNot(contains('2')));

      final defaultRow = rows.firstWhere((r) => r.id == '1');
      expect(defaultRow.isDefault, isTrue);
      expect(defaultRow.fhirId, 'org-1');

      final userOnly = rows.firstWhere((r) => r.id == '4');
      expect(userOnly.isUserSite, isTrue);

      final linked = rows.firstWhere((r) => r.id == '3');
      expect(linked.phoneNumber, '1712345678');
      expect(linked.isDefault, isFalse);
    });

    test('keeps all nearest facilities when villages list is empty', () {
      final rows = HealthFacilityIngest.fromUserDataEntity({
        'nearestHealthFacilities': [
          {
            'id': 1,
            'name': 'A',
            'fhirId': 'a',
            'linkedVillages': [
              {'id': 1},
            ],
          },
          {
            'id': 2,
            'name': 'B',
            'fhirId': 'b',
            'linkedVillages': [
              {'id': 2},
            ],
          },
        ],
        'defaultHealthFacility': {'id': 2},
      });

      expect(rows.length, 2);
      expect(rows.firstWhere((r) => r.id == '2').isDefault, isTrue);
    });
  });
}
