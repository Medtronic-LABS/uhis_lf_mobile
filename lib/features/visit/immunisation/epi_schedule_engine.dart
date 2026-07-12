import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/db/immunisation_dao.dart';

/// Vaccine status within a milestone group.
enum VaccineStatus {
  /// Dose confirmed given (has given_at date).
  completed,

  /// Scheduled date reached, dose not yet given — action needed today.
  dueNow,

  /// Scheduled date within the next 4 weeks — upcoming.
  upcoming,

  /// Scheduled date more than 4 weeks out — not yet due.
  notYetDue,

  /// Prior milestone group not fully completed — this group locked.
  locked,
}

/// Single vaccine entry in the timeline.
class VaccineEntry {
  const VaccineEntry({
    required this.code,
    required this.display,
    required this.category,
    required this.scheduledDate,
    this.givenDate,
    required this.status,
  });

  final String code;
  final String display;
  final String category;
  final DateTime scheduledDate;
  final DateTime? givenDate;
  final VaccineStatus status;

  bool get isOverdue =>
      status == VaccineStatus.dueNow &&
      DateTime.now().difference(scheduledDate).inDays > 0;
}

/// A milestone group (e.g. "6 Weeks") with its vaccines.
class VaccineMilestone {
  const VaccineMilestone({
    required this.label,
    required this.scheduledDate,
    required this.vaccines,
  });

  final String label;
  final DateTime scheduledDate;
  final List<VaccineEntry> vaccines;

  bool get allCompleted =>
      vaccines.every((v) => v.status == VaccineStatus.completed);

  int get overdueCount =>
      vaccines.where((v) => v.isOverdue).length;

  int get dueNowCount =>
      vaccines.where((v) => v.status == VaccineStatus.dueNow).length;
}

/// Pure-Dart engine that merges the static EPI schedule with synced DB rows
/// and computes status for each vaccine.
class EpiScheduleEngine {
  const EpiScheduleEngine._();

  /// Load the schedule asset and compute the full timeline for [dob].
  ///
  /// [rows] are the synced immunisation rows from [ImmunisationDao.forMany].
  /// Passes today as a parameter so callers can inject for tests.
  static Future<List<VaccineMilestone>> build({
    required DateTime dob,
    required List<ImmunisationRow> rows,
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();
    final givenByCode = <String, DateTime>{};
    for (final r in rows) {
      if (r.vaccineCode != null && r.givenAt != null) {
        givenByCode[r.vaccineCode!] =
            DateTime.fromMillisecondsSinceEpoch(r.givenAt!);
      }
    }

    final scheduleJson = await rootBundle.loadString(
        'assets/forms/epi_schedule.json');
    final schedule = (jsonDecode(scheduleJson) as List).cast<Map<String, dynamic>>();

    final milestones = <VaccineMilestone>[];
    bool priorGroupComplete = true;

    for (final group in schedule) {
      final scheduledDate = _scheduledDate(dob, group);

      final vaccines = (group['vaccines'] as List)
          .cast<Map<String, dynamic>>()
          .map((v) {
        final code = v['code'] as String;
        final givenDate = givenByCode[code];

        final VaccineStatus status;
        if (givenDate != null) {
          status = VaccineStatus.completed;
        } else if (!priorGroupComplete) {
          status = VaccineStatus.locked;
        } else {
          final daysDiff = scheduledDate.difference(now).inDays;
          if (daysDiff <= 0) {
            status = VaccineStatus.dueNow;
          } else if (daysDiff <= 28) {
            status = VaccineStatus.upcoming;
          } else {
            status = VaccineStatus.notYetDue;
          }
        }

        return VaccineEntry(
          code: code,
          display: v['display'] as String,
          category: v['category'] as String,
          scheduledDate: scheduledDate,
          givenDate: givenDate,
          status: status,
        );
      }).toList();

      final milestone = VaccineMilestone(
        label: group['milestone'] as String,
        scheduledDate: scheduledDate,
        vaccines: vaccines,
      );
      milestones.add(milestone);
      priorGroupComplete = milestone.allCompleted;
    }

    return milestones;
  }

  /// Compute overdue vaccine codes from a cached set of DB rows.
  ///
  /// Used to populate [PatientContext.overdueImmunizations] without
  /// loading the full schedule asset (sync-hot path).
  static Future<List<String>> overdueCodesFor({
    required DateTime dob,
    required List<ImmunisationRow> rows,
    DateTime? today,
  }) async {
    final milestones = await build(dob: dob, rows: rows, today: today);
    return milestones
        .expand((m) => m.vaccines)
        .where((v) => v.isOverdue || v.status == VaccineStatus.dueNow)
        .map((v) => v.code)
        .toList();
  }

  static DateTime _scheduledDate(DateTime dob, Map<String, dynamic> group) {
    final type = group['offsetType'] as String;
    final value = (group['offsetValue'] as num).toInt();
    switch (type) {
      case 'day':
        return dob.add(Duration(days: value));
      case 'week':
        return dob.add(Duration(days: value * 7));
      case 'month':
        return DateTime(dob.year, dob.month + value, dob.day);
    }
    return dob;
  }
}
