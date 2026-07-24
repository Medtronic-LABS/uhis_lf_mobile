import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../models/programme.dart';
import '../theme/app_theme.dart';

/// A compact programme pill with icon and Material 3 surface color coding.
/// Used in worklist cards, patient context screens, and referral rows.
class ProgrammeTag extends StatelessWidget {
  const ProgrammeTag({
    super.key,
    required this.programme,
  });

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = _styleFor(programme);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _labelFor(programme),
            style: AppTextStyles.chip.copyWith(color: fg, fontSize: 11),
          ),
        ],
      ),
    );
  }

  static (Color bg, Color fg, IconData icon) _styleFor(Programme p) {
    switch (p) {
      case Programme.imci:
        return (AppColors.imciSurface, AppColors.imciText, Icons.child_care);
      case Programme.pw:
      case Programme.anc:
        return (AppColors.ancSurface, AppColors.ancText, Icons.pregnant_woman);
      case Programme.pnc:
        return (AppColors.pncSurface, AppColors.pncText, Icons.pregnant_woman);
      case Programme.ncd:
        return (AppColors.ncdSurface, AppColors.ncdText, Icons.monitor_heart_outlined);
      case Programme.tb:
        return (AppColors.tbSurface, AppColors.tbText, Icons.sick_outlined);
      case Programme.epi:
        return (AppColors.canvas, AppColors.textMuted, Icons.vaccines);
      case Programme.nutrition:
        return (AppColors.canvas, AppColors.textMuted, Icons.restaurant);
      case Programme.familyPlanning:
        return (AppColors.pncSurface, AppColors.pncText, Icons.family_restroom);
      case Programme.cataract:
        return (AppColors.canvas, AppColors.textMuted, Icons.visibility_outlined);
      case Programme.eyeCare:
        return (AppColors.canvas, AppColors.textMuted, Icons.remove_red_eye_outlined);
      case Programme.unknown:
        return (AppColors.canvas, AppColors.textMuted, Icons.person);
    }
  }

  static String _labelFor(Programme p) {
    switch (p) {
      case Programme.imci:
        return WorklistStrings.programmeImci;
      case Programme.pw:
      case Programme.anc:
        return WorklistStrings.programmeAnc;
      case Programme.pnc:
        return WorklistStrings.programmePnc;
      case Programme.ncd:
        return WorklistStrings.programmeNcd;
      case Programme.tb:
        return WorklistStrings.programmeTb;
      case Programme.epi:
        return WorklistStrings.programmeEpi;
      case Programme.nutrition:
        return WorklistStrings.programmeNutrition;
      case Programme.familyPlanning:
        return WorklistStrings.programmeFamilyPlanning;
      case Programme.cataract:
        return WorklistStrings.programmeCataract;
      case Programme.eyeCare:
        return WorklistStrings.programmeEyeCare;
      case Programme.unknown:
        return WorklistStrings.programmeUnknown;
    }
  }
}
