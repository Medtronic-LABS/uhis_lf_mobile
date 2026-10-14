import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/constants/app_strings.dart';
import 'package:uhis_next/core/mission/mission_schedule_urgency.dart';
import 'package:uhis_next/core/models/dashboard_tier.dart';
import 'package:uhis_next/core/models/mission_queue_item.dart';
import 'package:uhis_next/core/models/programme.dart';

MissionQueueItem _item({
  required Set<Programme> programmes,
  required String reason,
  Programme? badgeProgramme,
  DateTime? dueAt,
}) {
  return MissionQueueItem(
    id: '1',
    type: MissionItemType.patientVisit,
    priority: MissionPriority.medium,
    priorityScore: 0,
    patientId: 'p1',
    patientName: 'Test',
    reason: reason,
    badgeProgramme: badgeProgramme,
    aiInsight: '',
    programmes: programmes,
    dueAt: dueAt,
  );
}

void main() {
  final dueThisWeek = DateTime.now().add(const Duration(days: 3));

  test('IMCI does not get schedule urgency tier', () {
    final item = _item(
      programmes: {Programme.imci},
      reason: MissionDashboardStrings.childImmunisation,
      badgeProgramme: Programme.imci,
      dueAt: dueThisWeek,
    );
    expect(missionItemSupportsScheduleUrgency(item), isFalse);
  });

  test('ANC visit due gets calendar tier', () {
    final item = _item(
      programmes: {Programme.anc, Programme.pw},
      reason: '${MissionDashboardStrings.ancVisitLabel} 2 '
          '${MissionDashboardStrings.dueSuffix}',
      badgeProgramme: Programme.anc,
      dueAt: dueThisWeek,
    );
    expect(missionItemSupportsScheduleUrgency(item), isTrue);
    expect(
      missionScheduleTierForDisplay(item),
      DashboardTier.thisWeek,
    );
  });

  test('Pregnancy outcome badge does not get urgency despite PNC colour', () {
    final item = _item(
      programmes: {Programme.anc, Programme.pnc},
      reason: MissionDashboardStrings.pregnancyOutcomeBadge,
      badgeProgramme: Programme.pnc,
      dueAt: dueThisWeek,
    );
    expect(missionItemSupportsScheduleUrgency(item), isFalse);
  });

  test('Pregnancy registered does not get urgency despite ANC enrolment', () {
    final item = _item(
      programmes: {Programme.anc, Programme.pw},
      reason: PatientProfileStrings.pregnancyRegistered,
      badgeProgramme: Programme.pw,
      dueAt: dueThisWeek,
    );
    expect(missionItemSupportsScheduleUrgency(item), isFalse);
  });

  test('NCD checkup is included', () {
    final item = _item(
      programmes: {Programme.ncd},
      reason: MissionDashboardStrings.ncdCheckup,
      badgeProgramme: Programme.ncd,
      dueAt: dueThisWeek,
    );
    expect(missionItemSupportsScheduleUrgency(item), isTrue);
  });

  test('PNC visit due is included', () {
    final item = _item(
      programmes: {Programme.pnc},
      reason: '${MissionDashboardStrings.pncVisitLabel} 1 '
          '${MissionDashboardStrings.dueSuffixTitleCase}',
      badgeProgramme: Programme.pnc,
      dueAt: dueThisWeek,
    );
    expect(missionItemSupportsScheduleUrgency(item), isTrue);
  });
}
