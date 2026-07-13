import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/models/programme.dart';
import 'visit_controller.dart';

/// Single entry point for starting a visit across every "Visit now"/"Start
/// visit" call site in the app. Wraps [VisitController.startVisit] with a
/// same-day resume check: if the patient has an assessment draft last
/// touched today, the SK is asked to resume it or start over; a draft from
/// any earlier day is discarded silently (see
/// [EncounterRepository.findTodayDraft]) and a fresh visit starts as normal.
///
/// Returns the same contract as [VisitController.startVisit] — the
/// encounter ID to navigate to, or null (error, or the SK dismissed the
/// resume prompt without choosing).
Future<String?> startOrResumeVisit(
  BuildContext context, {
  required VisitController controller,
  required String patientId,
  required Programme programme,
  String? patientName,
  int? patientAge,
  String? patientGender,
  String? householdId,
}) async {
  final draft = await controller.checkTodayDraft(patientId);
  if (!context.mounted) return null;

  if (draft != null) {
    final resume = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(ComposerStrings.resumeDraftTitle),
        content: const Text(ComposerStrings.resumeDraftMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(ComposerStrings.startOverButton),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(ComposerStrings.resumeButton),
          ),
        ],
      ),
    );
    if (!context.mounted || resume == null) return null;
    if (resume) return draft.encounterId;
    await controller.discardDraft(draft.encounterId);
    if (!context.mounted) return null;
  }

  return controller.startVisit(
    patientId: patientId,
    programme: programme,
    patientName: patientName,
    patientAge: patientAge,
    patientGender: patientGender,
    householdId: householdId,
  );
}
