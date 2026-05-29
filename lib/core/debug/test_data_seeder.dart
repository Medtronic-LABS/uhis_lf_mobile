import 'dart:math';

import '../db/app_database.dart';
import '../models/programme.dart';

/// Seeds the local SQLite database with dummy patients and programme
/// enrollments for testing the worklist UI. Only meant for debug builds.
class TestDataSeeder {
  TestDataSeeder(this._db);

  final AppDatabase _db;
  final _random = Random();

  // Bangladeshi names for realistic data
  static const _firstNamesF = [
    'Fatima', 'Salma', 'Ayesha', 'Khaleda', 'Rashida', 'Sabina', 'Tahmina',
    'Nargis', 'Sumaiya', 'Tania', 'Rumana', 'Sharmin', 'Nasrin', 'Sabrina',
    'Mahmuda', 'Roksana', 'Shirin', 'Hosne', 'Afroza', 'Jamila'
  ];
  static const _firstNamesM = [
    'Mohammad', 'Abdul', 'Karim', 'Rahim', 'Hasan', 'Hussain', 'Rafiq',
    'Asif', 'Aminul', 'Saiful', 'Nazrul', 'Tanvir', 'Faisal', 'Anwar',
    'Kamal', 'Mahbub', 'Rashid', 'Shahin', 'Tareq', 'Yusuf'
  ];
  static const _lastNames = [
    'Rahman', 'Ahmed', 'Khan', 'Hossain', 'Islam', 'Akter', 'Chowdhury',
    'Mia', 'Sarkar', 'Sheikh', 'Talukder', 'Bhuiyan', 'Mollah', 'Mondal',
    'Khatun', 'Begum'
  ];

  /// Seed approximately [patientCount] patients across [householdCount]
  /// households, with random programme enrollments.
  Future<SeedResult> seed({
    int householdCount = 40,
    int membersPerHousehold = 4,
  }) async {
    final patientCount = householdCount * membersPerHousehold;
    final now = DateTime.now();
    int insertedPatients = 0;
    int insertedProgrammes = 0;
    int insertedFollowUps = 0;

    final batch = _db.db.batch();

    for (int h = 0; h < householdCount; h++) {
      final householdId = 'HH-SEED-${h.toString().padLeft(4, '0')}';
      final villageId = (1 + _random.nextInt(3)).toString(); // village 1, 2, or 3

      for (int m = 0; m < membersPerHousehold; m++) {
        final patientId = 'PAT-SEED-${(h * membersPerHousehold + m).toString().padLeft(5, '0')}';
        final isFemale = m == 0 || _random.nextBool(); // head of household + random
        final age = _randomAge(m == 0); // head is adult, others random
        final dob = now.subtract(Duration(days: age * 365 + _random.nextInt(365)));

        final firstName = isFemale
            ? _firstNamesF[_random.nextInt(_firstNamesF.length)]
            : _firstNamesM[_random.nextInt(_firstNamesM.length)];
        final lastName = _lastNames[_random.nextInt(_lastNames.length)];
        final name = '$firstName $lastName';

        // Determine programme enrollments based on demographics
        final programmes = <Programme>[];

        // Under-5 children → IMCI
        if (age < 5) {
          programmes.add(Programme.imci);
        }
        // Pregnant women (15-45, female, 15% chance)
        if (isFemale && age >= 15 && age <= 45 && _random.nextDouble() < 0.15) {
          programmes.add(Programme.anc);
        }
        // NCD (adults over 30, 20% chance)
        if (age >= 30 && _random.nextDouble() < 0.20) {
          programmes.add(Programme.ncd);
        }
        // TB (any age, 5% chance)
        if (_random.nextDouble() < 0.05) {
          programmes.add(Programme.tb);
        }

        // Risk scoring: higher for under-5s and pregnant women
        int riskScore = _random.nextInt(40);
        if (age < 5) riskScore += 30 + _random.nextInt(20);
        if (programmes.contains(Programme.anc)) riskScore += 20 + _random.nextInt(15);
        if (programmes.contains(Programme.tb)) riskScore += 25;
        riskScore = riskScore.clamp(0, 100);

        final riskBand = riskScore >= 70
            ? 'critical'
            : riskScore >= 50
                ? 'high'
                : riskScore >= 30
                    ? 'medium'
                    : 'low';

        final reasons = <String>[];
        if (age < 5) reasons.add('under-5:$age');
        if (programmes.contains(Programme.anc)) reasons.add('pregnancy');
        if (programmes.contains(Programme.tb)) reasons.add('tb-case');
        if (_random.nextDouble() < 0.3) {
          final missedCount = 1 + _random.nextInt(3);
          reasons.add('missed-visits:$missedCount');
        }

        // Dates
        final lastVisitDaysAgo = _random.nextInt(60);
        final lastVisitAt = now.subtract(Duration(days: lastVisitDaysAgo)).millisecondsSinceEpoch;
        final nextDueDaysFromNow = _random.nextInt(30) - 10; // some overdue
        final nextDueAt = now.add(Duration(days: nextDueDaysFromNow)).millisecondsSinceEpoch;

        batch.insert(
          AppDatabase.tablePatients,
          {
            'id': patientId,
            'patient_id': patientId,
            'name': name,
            'gender': isFemale ? 'Female' : 'Male',
            'dob': dob.toIso8601String().substring(0, 10),
            'phone': '93${_random.nextInt(90000000) + 10000000}',
            'national_id': 'NID-SEED-${_random.nextInt(99999999)}',
            'household_id': householdId,
            'village_id': villageId,
            'is_active': 1,
            'updated_at': now.millisecondsSinceEpoch,
            'age': age,
            'risk_score': riskScore,
            'risk_band': riskBand,
            'risk_reasons': reasons.join(','),
            'red_flag': riskScore >= 70 ? 1 : 0,
            'last_visit_at': lastVisitAt,
            'next_due_at': nextDueAt,
            'missed_visit_count': _random.nextInt(4),
          },
        );
        insertedPatients++;

        // Insert programme enrollments
        for (final prog in programmes) {
          batch.insert(
            AppDatabase.tablePatientProgrammes,
            {
              'patient_id': patientId,
              'programme': prog.wireTag,
            },
          );
          insertedProgrammes++;
        }

        // Insert some follow-ups
        if (programmes.isNotEmpty && _random.nextDouble() < 0.6) {
          final followUpId = 'FU-SEED-$patientId-${_random.nextInt(9999)}';
          final kind = programmes.first.wireTag;
          final dueDaysFromNow = _random.nextInt(21) - 7;
          final dueAt = now.add(Duration(days: dueDaysFromNow)).millisecondsSinceEpoch;

          batch.insert(
            AppDatabase.tableFollowUps,
            {
              'id': followUpId,
              'patient_id': patientId,
              'kind': kind,
              'due_at': dueAt,
              'completed_at': null,
              'attempts': _random.nextInt(3),
              'is_lost': 0,
            },
          );
          insertedFollowUps++;
        }
      }
    }

    await batch.commit(noResult: true);

    return SeedResult(
      patients: insertedPatients,
      programmes: insertedProgrammes,
      followUps: insertedFollowUps,
    );
  }

  int _randomAge(bool mustBeAdult) {
    if (mustBeAdult) {
      return 25 + _random.nextInt(35); // 25-59
    }
    // Distribution: 20% under-5, 30% children (5-17), 50% adults
    final roll = _random.nextDouble();
    if (roll < 0.20) return _random.nextInt(5); // 0-4
    if (roll < 0.50) return 5 + _random.nextInt(13); // 5-17
    return 18 + _random.nextInt(52); // 18-69
  }

  /// Clear all seeded data (patients starting with PAT-SEED-)
  Future<int> clearSeededData() async {
    final count = await _db.db.delete(
      AppDatabase.tablePatients,
      where: "id LIKE 'PAT-SEED-%'",
    );
    await _db.db.delete(
      AppDatabase.tablePatientProgrammes,
      where: "patient_id LIKE 'PAT-SEED-%'",
    );
    await _db.db.delete(
      AppDatabase.tableFollowUps,
      where: "patient_id LIKE 'PAT-SEED-%'",
    );
    return count;
  }
}

class SeedResult {
  const SeedResult({
    required this.patients,
    required this.programmes,
    required this.followUps,
  });

  final int patients;
  final int programmes;
  final int followUps;

  @override
  String toString() =>
      'Seeded $patients patients, $programmes programme enrollments, $followUps follow-ups';
}
