import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/member_dao.dart';
import '../../core/models/programme.dart';
import 'visit_controller.dart';

/// RESUME-STASHED: the same-day draft resume/start-over prompt is
/// temporarily disabled — held back for further review, not removed. All
/// underlying plumbing (EncounterRepository.findTodayDraft/discardDraft,
/// VisitController.checkTodayDraft/discardDraft, the dialog below) is intact
/// and unused while this is `false`. Do not restore or modify without direct
/// user instruction. Search `RESUME-STASHED` for the only other marker
/// (there is none elsewhere — this flag is the single gate).
const bool _resumeFeatureEnabled = false;

/// Single entry point for starting a visit across every "Visit now"/"Start
/// visit" call site in the app. Wraps [VisitController.startVisit] with a
/// same-day resume check: if the patient has an assessment draft last
/// touched today, the SK is asked to resume it or start over; a draft from
/// any earlier day is discarded silently (see
/// [EncounterRepository.findTodayDraft]) and a fresh visit starts as normal.
///
/// Outcome of [startOrResumeVisit]. When [messageAlreadyShown] is true
/// (e.g. deceased member), callers must not show a generic failure snackbar.
class VisitStartResult {
  const VisitStartResult({
    this.encounterId,
    this.messageAlreadyShown = false,
  });

  final String? encounterId;
  final bool messageAlreadyShown;

  bool get succeeded => encounterId != null;
}

/// Returns a [VisitStartResult] — navigate when [VisitStartResult.encounterId]
/// is set; on failure, show an error snackbar only if
/// [VisitStartResult.messageAlreadyShown] is false.
Future<VisitStartResult> startOrResumeVisit(
  BuildContext context, {
  required VisitController controller,
  required String patientId,
  required Programme programme,
  String? patientName,
  int? patientAge,
  String? patientGender,
  String? householdId,
}) async {
  final memberDao = context.read<MemberDao>();
  var member = await memberDao.getByPatientId(patientId);
  member ??= await memberDao.getById(patientId);
  if (member != null && !member.isActive) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(MemberDeceasedStrings.cannotStartVisit)),
      );
    }
    return const VisitStartResult(messageAlreadyShown: true);
  }

  final draft = _resumeFeatureEnabled
      ? await controller.checkTodayDraft(patientId)
      : null;
  if (!context.mounted) return const VisitStartResult();

  if (draft != null) {
    final resume = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ComposerStrings.resumeDraftTitle),
        content: Text(ComposerStrings.resumeDraftMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(ComposerStrings.startOverButton),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(ComposerStrings.resumeButton),
          ),
        ],
      ),
    );
    if (!context.mounted || resume == null) return const VisitStartResult();
    if (resume) {
      return VisitStartResult(encounterId: draft.encounterId);
    }
    await controller.discardDraft(draft.encounterId);
    if (!context.mounted) return const VisitStartResult();
  }

  final encounterId = await controller.startVisit(
    patientId: patientId,
    programme: programme,
    patientName: patientName,
    patientAge: patientAge,
    patientGender: patientGender,
    householdId: householdId,
  );
  return VisitStartResult(encounterId: encounterId);
}
