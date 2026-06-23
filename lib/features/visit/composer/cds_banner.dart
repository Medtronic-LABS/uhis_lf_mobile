/// CDS alert banner widget.
///
/// Stateless; all state lives in [SectionedAssessmentViewModel].
/// Renders a colour-coded banner for one [CdsAlert] with the appropriate
/// action button.
///
/// Engineering Design Standards:
///   - No string literals — all copy via [CdsStrings].
///   - No business logic — action callbacks are passed in by the screen.
///   - No navigation — the caller (screen) handles routing to the referral flow.
///   - No I/O — pure widget.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import 'cds_rules.dart';

/// A single CDS alert banner.
///
/// [onAddPathway] and [onReferNow] are mutually exclusive depending on the
/// alert's [CdsAlert.action].  The caller supplies whichever is relevant;
/// the other is ignored.
///
/// [onDismiss] is always available — the SK can dismiss any alert.
class CdsBanner extends StatelessWidget {
  const CdsBanner({
    super.key,
    required this.alert,
    this.onAddPathway,
    this.onReferNow,
    this.onDismiss,
  });

  /// The alert to render.
  final CdsAlert alert;

  /// Called when the SK taps "Add to assessment" (addPathway action).
  /// Null if the alert action is not [CdsAction.addPathway].
  final VoidCallback? onAddPathway;

  /// Called when the SK taps "Refer now" (referNow action).
  /// The caller is responsible for opening the referral flow.
  final VoidCallback? onReferNow;

  /// Called when the SK taps "Dismiss".
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (backgroundColor, iconData) = switch (alert.severity) {
      CdsSeverity.urgent => (
          theme.colorScheme.errorContainer,
          Icons.local_hospital_rounded,
        ),
      CdsSeverity.warning => (
          const Color(0xFFFFF3CD), // amber-50 equivalent
          Icons.warning_amber_rounded,
        ),
      CdsSeverity.info => (
          theme.colorScheme.primaryContainer,
          Icons.add_circle_outline_rounded,
        ),
    };

    final iconColor = switch (alert.severity) {
      CdsSeverity.urgent => theme.colorScheme.error,
      CdsSeverity.warning => const Color(0xFFB45309), // amber-700
      CdsSeverity.info => theme.colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: backgroundColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: iconColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Severity icon ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(iconData, color: iconColor, size: 22),
            ),

            // ── Message + rationale ────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CdsStrings.message(alert.messageKey),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                  if (alert.rationaleKey != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      CdsStrings.rationale(alert.rationaleKey!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: iconColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ],

                  // ── Action row ───────────────────────────────────────────────
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (alert.action == CdsAction.referNow &&
                          onReferNow != null)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: iconColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.transfer_within_a_station,
                              size: 16),
                          label: Text(CdsStrings.referNowButton),
                          onPressed: onReferNow,
                        ),
                      if (alert.action == CdsAction.addPathway &&
                          onAddPathway != null)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: iconColor,
                            side: BorderSide(color: iconColor),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: Text(CdsStrings.addPathwayButton),
                          onPressed: onAddPathway,
                        ),
                      if (onDismiss != null)
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: iconColor.withValues(alpha: 0.7),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onDismiss,
                          child: Text(CdsStrings.dismissButton),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
