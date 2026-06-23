import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../models/programme.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = _styleFor(programme, scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            _labelFor(programme),
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (Color bg, Color fg, IconData icon) _styleFor(Programme p, ColorScheme scheme) {
    switch (p) {
      case Programme.imci:
        return (scheme.errorContainer, scheme.onErrorContainer, Icons.child_care);
      case Programme.anc:
      case Programme.pnc:
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.pregnant_woman);
      case Programme.ncd:
        return (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.monitor_heart_outlined);
      case Programme.tb:
        return (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.sick_outlined);
      case Programme.epi:
        return (scheme.surfaceContainerHighest, scheme.onSurface, Icons.vaccines);
      case Programme.nutrition:
        return (scheme.surfaceContainerHighest, scheme.onSurface, Icons.restaurant);
      case Programme.familyPlanning:
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.family_restroom);
      case Programme.cataract:
        return (scheme.surfaceContainerHighest, scheme.onSurface, Icons.visibility_outlined);
      case Programme.eyeCare:
        return (scheme.surfaceContainerHighest, scheme.onSurface, Icons.remove_red_eye_outlined);
      case Programme.unknown:
        return (scheme.surfaceContainerHighest, scheme.onSurface, Icons.person);
    }
  }

  static String _labelFor(Programme p) {
    switch (p) {
      case Programme.imci:
        return WorklistStrings.programmeImci;
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
