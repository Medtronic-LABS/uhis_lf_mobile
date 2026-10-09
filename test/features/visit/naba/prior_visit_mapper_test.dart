/// Prior visit history as NABA receives it.
///
/// The app sent `priorVisits: []` on every request for a month, so the
/// backend's prompt always read the literal "No prior visit history" and the
/// model reasoned as though every patient were a first-ever contact. These
/// pin the mapping, and in particular the three ways the synced
/// `observations` map can poison the payload: everything in it is a string,
/// `bp` is one combined field, and `bg` carries no unit of its own.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:uhis_next/core/models/assessment_history_item.dart';
import 'package:uhis_next/features/visit/naba/prior_visit_mapper.dart';

AssessmentHistoryItem _item({
  String encounterId = 'e1',
  DateTime? visitDate,
  String? programme = 'ANC',
  String? referralStatus,
  String? referralReason,
  DateTime? nextFollowUpDate,
  List<String> customStatus = const [],
  Map<String, dynamic>? observations,
}) =>
    AssessmentHistoryItem(
      householdMemberId: 'm1',
      encounterId: encounterId,
      visitDate: visitDate ?? DateTime(2026, 9, 12, 14, 30),
      serviceProvided: programme,
      referralStatus: referralStatus,
      referralReason: referralReason,
      nextFollowUpDate: nextFollowUpDate,
      customStatus: customStatus,
      observations: observations,
    );

void main() {
  group('blood pressure is one field holding two readings', () {
    test('"144/91" becomes a systolic and a diastolic', () {
      final (systolic, diastolic) =
          PriorVisitMapper.splitBloodPressure('144/91');
      expect(systolic, 144);
      expect(diastolic, 91);
    });

    test('anything that is not two parts yields nulls, not the raw string', () {
      // "144/91" reaching the server's int field is a 422 on the whole
      // request, so a shape we cannot split must produce nothing at all.
      expect(PriorVisitMapper.splitBloodPressure('144'), (null, null));
      expect(PriorVisitMapper.splitBloodPressure(''), (null, null));
      expect(PriorVisitMapper.splitBloodPressure(null), (null, null));
    });
  });

  group('every observation value is a string', () {
    test('a numeric string parses', () {
      expect(PriorVisitMapper.toDouble('55'), 55.0);
      expect(PriorVisitMapper.toInt('120'), 120);
    });

    test('a non-numeric or empty value becomes null, never an empty string',
        () {
      // "" into a float field 422s; null is simply omitted from the payload.
      for (final raw in ['', '   ', 'N/A', '--', 'unknown']) {
        expect(PriorVisitMapper.toDouble(raw), isNull, reason: raw);
        expect(PriorVisitMapper.toInt(raw), isNull, reason: raw);
      }
    });

    test('a fractional value is rounded for the server int fields', () {
      // bloodPressureSystolic is declared `int`; a float 422s.
      expect(PriorVisitMapper.toInt('120.6'), 121);
    });
  });

  group('glucose carries no unit of its own', () {
    test('FBS routes to fasting, anything else to random', () {
      expect(PriorVisitMapper.isFastingGlucose('FBS'), isTrue);
      expect(PriorVisitMapper.isFastingGlucose('fasting'), isTrue);
      expect(PriorVisitMapper.isFastingGlucose('RBS'), isFalse);
      expect(PriorVisitMapper.isFastingGlucose('PPBS'), isFalse);
      expect(PriorVisitMapper.isFastingGlucose(null), isFalse);
    });

    test('a reading is always qualified with its unit', () {
      // mmol/L and mg/dL differ by ~18x, so an unqualified 4.0 is a
      // confidently wrong recommendation waiting to happen.
      final v = PriorVisitMapper.from(
        _item(observations: const {'bg': '7.2', 'bgType': 'FBS'}),
      );
      expect(v.vitals!.glucoseFasting, 7.2);
      expect(v.vitals!.glucoseRandom, isNull);
      expect(v.vitals!.glucoseUnit, 'mmol/L');
    });

    test('no reading means no unit is asserted either', () {
      final v = PriorVisitMapper.from(
        _item(observations: const {'weight': '58'}),
      );
      expect(v.vitals!.glucoseUnit, isNull);
    });
  });

  group('the whole visit', () {
    test('maps dates, findings and actions', () {
      final v = PriorVisitMapper.from(_item(
        referralStatus: 'Referred',
        referralReason: 'High BP',
        customStatus: const ['Referred'],
        nextFollowUpDate: DateTime(2026, 10, 10),
        observations: const {'bp': '144/91', 'weight': '58'},
      ));

      // Date-only, and a string: the server declares `date: str` and does not
      // coerce an int, so an epoch value 422s the request.
      expect(v.date, '2026-09-12');
      expect(v.programme, 'ANC');
      expect(v.keyFindings, ['Referred', 'High BP']);
      expect(v.actionsTaken, ['Referred', 'Follow-up due 2026-10-10']);
      expect(v.vitals!.bloodPressureSystolic, 144);
      expect(v.vitals!.weight, 58.0);
    });

    test('a visit that measured nothing omits the vitals key entirely', () {
      // An immunisation visit records vaccines, not vitals. Sending an empty
      // object would assert measurements that were never taken.
      final v = PriorVisitMapper.from(_item(programme: 'EPI'));
      expect(v.vitals, isNull);
      expect(v.toJson().containsKey('vitals'), isFalse);
    });

    test('unparseable readings keep the vitals key off the wire', () {
      final v = PriorVisitMapper.from(
        _item(observations: const {'bp': 'N/A', 'weight': ''}),
      );
      expect(v.toJson().containsKey('vitals'), isFalse);
    });

    test('a duplicate finding is not repeated', () {
      final v = PriorVisitMapper.from(_item(
        referralReason: 'High BP',
        customStatus: const ['High BP'],
      ));
      expect(v.keyFindings, ['High BP']);
    });
  });
}
