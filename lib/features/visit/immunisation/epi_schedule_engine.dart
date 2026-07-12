import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/db/immunisation_dao.dart';

/// Vaccine status within a milestone group.
enum VaccineStatus {
  completed,
  dueNow,
  upcoming,
  notYetDue,
  locked,
}

/// Single vaccine entry in the timeline.
class VaccineEntry {
  const VaccineEntry({
    required this.code,
    required this.display,
    required this.category,
    required this.description,
    required this.route,
    required this.cardGroup,
    required this.scheduledDate,
    this.givenDate,
    required this.status,
  });

  final String code;
  final String display;
  final String category;
  final String description;
  final String route;
  final int cardGroup;
  final DateTime scheduledDate;
  final DateTime? givenDate;
  final VaccineStatus status;

  bool get isOverdue =>
      (status == VaccineStatus.dueNow) &&
      DateTime.now().isAfter(scheduledDate);
}

/// A milestone group (e.g. "6 Weeks") with its vaccines.
class VaccineMilestone {
  const VaccineMilestone({
    required this.label,
    required this.scheduledDate,
    required this.vaccines,
    required this.offsetType,
    required this.offsetValue,
  });

  final String label;
  final DateTime scheduledDate;
  final List<VaccineEntry> vaccines;

  /// Offset type from the EPI schedule — 'day' | 'week' | 'month'.
  /// Matches the Android VaccinationDetail.type field (uppercased on send).
  final String offsetType;

  /// Offset value (e.g. 6 for "6 Weeks", 9 for "9 Months", 0 for "At Birth").
  final int offsetValue;

  bool get allCompleted =>
      vaccines.every((v) => v.status == VaccineStatus.completed);

  bool get hasDueNow =>
      vaccines.any((v) => v.status == VaccineStatus.dueNow);

  bool get hasUpcoming =>
      vaccines.any((v) => v.status == VaccineStatus.upcoming);

  int get overdueCount =>
      vaccines.where((v) => v.isOverdue).length;

  int get dueNowCount =>
      vaccines.where((v) => v.status == VaccineStatus.dueNow).length;

  /// Vaccines grouped by [VaccineEntry.cardGroup] for the update sheet.
  List<List<VaccineEntry>> get vaccineCards {
    final groups = <int, List<VaccineEntry>>{};
    for (final v in vaccines) {
      (groups[v.cardGroup] ??= []).add(v);
    }
    return groups.values.toList();
  }
}

/// Pure-Dart engine — merges EPI schedule asset with synced DB rows.
class EpiScheduleEngine {
  const EpiScheduleEngine._();

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

    final scheduleJson = await rootBundle
        .loadString('assets/forms/epi_schedule.json');
    final schedule =
        (jsonDecode(scheduleJson) as List).cast<Map<String, dynamic>>();

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
          description: v['description'] as String? ?? '',
          route: v['route'] as String? ?? '',
          cardGroup: (v['cardGroup'] as num?)?.toInt() ?? 1,
          scheduledDate: scheduledDate,
          givenDate: givenDate,
          status: status,
        );
      }).toList();

      final milestone = VaccineMilestone(
        label: group['milestone'] as String,
        scheduledDate: scheduledDate,
        vaccines: vaccines,
        offsetType: group['offsetType'] as String,
        offsetValue: (group['offsetValue'] as num).toInt(),
      );
      milestones.add(milestone);
      priorGroupComplete = milestone.allCompleted;
    }

    return milestones;
  }

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
