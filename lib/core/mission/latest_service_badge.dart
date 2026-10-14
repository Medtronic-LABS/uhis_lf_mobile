// Badge label + programme colour key from the patient's **latest** assessment
// service kind (strict latest-service rule). Pure Dart — shared by Home
// worklist and Patients roster.

import '../constants/app_strings.dart';
import '../models/programme.dart';

/// Picks the newer of synced vs local latest service rows.
String? pickLatestServiceKind({
  String? syncedKind,
  int? syncedAtMs,
  String? localKind,
  int? localAtMs,
}) {
  final syncedAt = syncedAtMs ?? 0;
  final localAt = localAtMs ?? 0;
  if (localKind != null &&
      localKind.trim().isNotEmpty &&
      localAt >= syncedAt) {
    return localKind.trim();
  }
  final sk = syncedKind?.trim();
  return (sk != null && sk.isNotEmpty) ? sk : null;
}

String _compact(String kind) =>
    kind.toUpperCase().replaceAll('_', '').replaceAll(' ', '');

bool isPregnancyOutcomeKind(String kind) {
  final c = _compact(kind);
  return c == 'PREGNANCYOUTCOME' || c == 'OUTCOME';
}

bool isPwRegistrationKind(String kind) =>
    _compact(kind).contains('PWPROFILE');

bool isAncVisitKind(String kind) {
  if (kind.isEmpty || isPregnancyOutcomeKind(kind)) return false;
  if (isPwRegistrationKind(kind)) return false;
  final u = kind.toUpperCase();
  return u.contains('ANC') ||
      u.contains('ANTENATAL') ||
      u.contains('PRENATAL');
}

bool isPncMotherKind(String kind) {
  final u = kind.toUpperCase();
  if (!u.contains('PNC') && !u.contains('POSTNATAL')) return false;
  return !u.contains('CHILD') && !u.contains('NEONAT');
}

bool isNcdServiceKind(String kind) {
  final c = _compact(kind);
  if (c == 'ENROLLMENT' || c == 'MENUREGISTRATION') return true;
  if (c.contains('NCDMEDICALREVIEW') || c == 'MEDICALREVIEW') return true;
  final u = kind.toUpperCase();
  return u.contains('NCD') ||
      u.contains('HYPERTENSION') ||
      u.contains('HTN') ||
      u.contains('DIABETES') ||
      u.contains('DIABETESMELLITUS') ||
      u.contains('DM') ||
      u.contains('CVD') ||
      u.contains('MEDICALREVIEW') ||
      u.contains('MEDICAL_REVIEW');
}

bool isFamilyPlanningKind(String kind) {
  final c = _compact(kind);
  return c.contains('FAMILYPLANNING') || c == 'FP';
}

bool isTbKind(String kind) {
  final c = _compact(kind);
  return c == 'TB' ||
      c.contains('TUBERCULOSIS') ||
      c.contains('PRESUMPTIVETB');
}

bool isChildImmunisationKind(String kind) {
  final u = kind.toUpperCase();
  if (u.contains('CHILDHOOD') || u == 'CHILD_MENU') return true;
  if (u.contains('IMMUN') || u == 'EPI') return true;
  if (u.contains('PNC') && (u.contains('CHILD') || u.contains('NEONAT'))) {
    return true;
  }
  final p = Programme.fromTag(kind);
  return p == Programme.imci || p == Programme.epi;
}

Programme _programmeForBadgeColour(Programme programme) => programme;

/// Maps [latestServiceKind] → display label + badge colour programme.
({String reason, Programme badgeProgramme}) badgeFromLatestServiceKind(
  String latestServiceKind, {
  int ancVisitCount = 0,
  int pncVisitCount = 0,
}) {
  final kind = latestServiceKind.trim();

  if (isPregnancyOutcomeKind(kind)) {
    return (
      reason: MissionDashboardStrings.pregnancyOutcomeBadge,
      badgeProgramme: Programme.pnc,
    );
  }
  if (isPwRegistrationKind(kind)) {
    return (
      reason: PatientProfileStrings.pregnancyRegistered,
      badgeProgramme: Programme.pw,
    );
  }
  if (isAncVisitKind(kind)) {
    final n = ancVisitCount + 1;
    return (
      reason: '${MissionDashboardStrings.ancVisitLabel} $n '
          '${MissionDashboardStrings.dueSuffix}',
      badgeProgramme: Programme.anc,
    );
  }
  if (isPncMotherKind(kind)) {
    final n = pncVisitCount + 1;
    return (
      reason: '${MissionDashboardStrings.pncVisitLabel} $n '
          '${MissionDashboardStrings.dueSuffixTitleCase}',
      badgeProgramme: Programme.pnc,
    );
  }
  if (isNcdServiceKind(kind)) {
    return (
      reason: MissionDashboardStrings.ncdCheckup,
      badgeProgramme: Programme.ncd,
    );
  }
  if (isFamilyPlanningKind(kind)) {
    return (
      reason: ProgrammeLabels.of(Programme.familyPlanning),
      badgeProgramme: Programme.familyPlanning,
    );
  }
  if (isTbKind(kind)) {
    return (
      reason: MissionDashboardStrings.tbCheck,
      badgeProgramme: Programme.tb,
    );
  }
  if (isChildImmunisationKind(kind)) {
    return (
      reason: MissionDashboardStrings.childImmunisation,
      badgeProgramme: Programme.imci,
    );
  }

  final mapped = Programme.fromString(kind);
  switch (mapped) {
    case Programme.cataract:
      return (
        reason: ProgrammeLabels.of(Programme.cataract),
        badgeProgramme: _programmeForBadgeColour(Programme.cataract),
      );
    case Programme.eyeCare:
      return (
        reason: ProgrammeLabels.of(Programme.eyeCare),
        badgeProgramme: _programmeForBadgeColour(Programme.eyeCare),
      );
    case Programme.nutrition:
      return (
        reason: ProgrammeLabels.of(Programme.nutrition),
        badgeProgramme: _programmeForBadgeColour(Programme.nutrition),
      );
    case Programme.ncd:
      return (
        reason: MissionDashboardStrings.ncdCheckup,
        badgeProgramme: Programme.ncd,
      );
    case Programme.familyPlanning:
      return (
        reason: ProgrammeLabels.of(Programme.familyPlanning),
        badgeProgramme: Programme.familyPlanning,
      );
    case Programme.tb:
      return (
        reason: MissionDashboardStrings.tbCheck,
        badgeProgramme: Programme.tb,
      );
    case Programme.imci:
    case Programme.epi:
      return (
        reason: MissionDashboardStrings.childImmunisation,
        badgeProgramme: Programme.imci,
      );
    case Programme.anc:
      final n = ancVisitCount + 1;
      return (
        reason: '${MissionDashboardStrings.ancVisitLabel} $n '
            '${MissionDashboardStrings.dueSuffix}',
        badgeProgramme: Programme.anc,
      );
    case Programme.pw:
      return (
        reason: PatientProfileStrings.pregnancyRegistered,
        badgeProgramme: Programme.pw,
      );
    case Programme.pnc:
      final n = pncVisitCount + 1;
      return (
        reason: '${MissionDashboardStrings.pncVisitLabel} $n '
            '${MissionDashboardStrings.dueSuffixTitleCase}',
        badgeProgramme: Programme.pnc,
      );
    case Programme.unknown:
      break;
  }

  final fallback = ProgrammeLabels.forServiceKind(kind);
  final label = fallback.isNotEmpty
      ? fallback
      : MissionDashboardStrings.newVisit;
  final colourProg = mapped != Programme.unknown ? mapped : Programme.unknown;
  return (reason: label, badgeProgramme: colourProg);
}
