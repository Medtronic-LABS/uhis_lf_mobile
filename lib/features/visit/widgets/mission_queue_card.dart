import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/mission/programme_reason.dart';
import '../../../core/models/dashboard_tier.dart';
import '../../../core/models/mission_queue_item.dart';
import '../../../core/models/programme.dart';

String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// Formats age and gender initial into "22/F", "22", or "F" depending on
/// which values are available.
String _ageGender(int? age, String? genderInitial) {
  if (age != null && genderInitial != null) return '$age/$genderInitial';
  if (age != null) return '$age';
  return genderInitial!;
}

/// Shared patient card widget for mission queue items.
/// Used by both Dashboard (home) and Tasks screens.
class MissionQueueCard extends StatelessWidget {
  const MissionQueueCard({
    super.key,
    required this.item,
    this.isCompleted = false,
    this.onTap,
    this.onAction,
    this.showActionButton = true,
    this.compact = false,
    this.embedded = false,
  });

  final MissionQueueItem item;
  final bool isCompleted;
  final VoidCallback? onTap;
  final VoidCallback? onAction;
  final bool showActionButton;
  final bool compact;

  /// When true, renders as a flush row with no card chrome of its own (no
  /// background/shadow/rounded corners/left border) — for embedding inside
  /// another surface that already provides the card boundary (e.g. a
  /// household card's primary-member slot), matching the v13 mockup's
  /// member row, which has no shadow/border of its own either.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final urgency = Theme.of(context).extension<UrgencyTheme>()!;
    final (dotLabel, dotColor) = isCompleted
        ? ('Done', tokens.statusSuccess)
        : _statusDotStyle(item.tier, tokens, urgency);

    return Opacity(
      opacity: isCompleted ? 0.6 : 1.0,
      child: Padding(
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Semantics(
          label: 'View patient ${item.patientName}',
          button: true,
          child: Container(
            decoration: embedded
                ? const BoxDecoration()
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    color: tokens.cardSurface,
                    boxShadow: AppShadows.card,
                  ),
            child: Material(
              color: Colors.transparent,
              borderRadius:
                  embedded ? BorderRadius.zero : BorderRadius.circular(AppRadius.button),
              child: InkWell(
                key: const Key('visit_queue_card_tap'),
                onTap: isCompleted
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              MissionDashboardStrings.completedVisitToast(
                                  item.patientName),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        )
                    : onTap,
                borderRadius:
                    embedded ? BorderRadius.zero : BorderRadius.circular(AppRadius.button),
                child: Container(
                  decoration: embedded
                      ? const BoxDecoration()
                      : BoxDecoration(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(AppRadius.button),
                          ),
                          // Left border is always neutral — the mockup never
                          // color-codes it by status; status is conveyed only by
                          // the right-side status pill (_StatusDot below).
                          border: const Border(
                            left: BorderSide(color: AppColors.border, width: 4),
                          ),
                        ),
                  padding: embedded
                      ? const EdgeInsets.symmetric(vertical: 12)
                      : const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Left: patient info ──────────────────────────────
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name + age + badge (baseline-aligned, wraps)
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 3,
                              children: [
                                Text(
                                  item.patientName,
                                  style: AppTextStyles.worklistPatientName.copyWith(
                                    color: isCompleted ? tokens.textMuted : const Color(0xFF111827),
                                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                if (item.age != null || item.genderInitial != null)
                                  Text(
                                    _ageGender(item.age, item.genderInitial),
                                    style: const TextStyle(
                                      fontFamily: 'NunitoSans',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                if (isCompleted)
                                  _VisitedBadge(tokens: tokens)
                                else
                                  MissionReasonBadge(item: item),
                              ],
                            ),

                            // Address
                            Builder(builder: (context) {
                              final address = [
                                item.householdDisplay,
                                _titleCase(item.village ?? ''),
                              ].where((s) => s.isNotEmpty).join(', ');
                              if (address.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.worklistAddress.copyWith(
                                    color: tokens.textMuted,
                                  ),
                                ),
                              );
                            }),

                            // Phone
                            if (item.phoneNumber != null && item.phoneNumber!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  item.phoneNumber!,
                                  style: AppTextStyles.worklistPhone.copyWith(
                                    color: tokens.textMuted,
                                  ),
                                ),
                              ),

                            // Priority signal debug overlay (band/modifier/tier/score/
                            // drivers). Commented out — not deleted — so it can be
                            // restored quickly when investigating dashboard sort
                            // behaviour. To re-enable, uncomment and gate on a local
                            // `const bool _showPatientCardDebug = true;`.
                            //
                            // Padding(
                            //   padding: const EdgeInsets.only(top: 6),
                            //   child: Container(
                            //     padding: const EdgeInsets.symmetric(
                            //         horizontal: 6, vertical: 4),
                            //     decoration: BoxDecoration(
                            //       color: const Color(0xFFFFF3CD),
                            //       borderRadius: BorderRadius.circular(4),
                            //       border: Border.all(
                            //           color: const Color(0xFFFFC107),
                            //           width: 0.5),
                            //     ),
                            //     child: Text(
                            //       'band:${item.band.name}  '
                            //       'mod:${item.modifier.name}  '
                            //       'tier:${item.tier.name}  '
                            //       'score:${item.priorityScore}\n'
                            //       'drivers: ${item.drivers.isEmpty ? "—" : item.drivers.join(", ")}',
                            //       style: const TextStyle(
                            //         fontFamily: 'monospace',
                            //         fontSize: 9,
                            //         color: Color(0xFF374151),
                            //         height: 1.5,
                            //       ),
                            //     ),
                            //   ),
                            // ),
                          ],
                        ),
                      ),

                      // ── Right: status dot ───────────────────────────────
                      const SizedBox(width: 12),
                      _StatusDot(label: dotLabel, color: dotColor),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Status dot style: (label, dotColor) keyed by tier.
  (String, Color) _statusDotStyle(
    DashboardTier tier,
    LeapfrogColors tokens,
    UrgencyTheme urgency,
  ) {
    final label = MissionDashboardStrings.statusPillForTier(tier);
    switch (tier) {
      case DashboardTier.critical:
        return (label, urgency.visitNow);       // red   — "Now"
      case DashboardTier.overdue:
        return (label, urgency.today);           // amber — "Overdue"
      case DashboardTier.dueToday:
        return (label, tokens.statusSuccess);    // green — "Today"
      case DashboardTier.thisWeek:
        return (label, urgency.thisWeek);        // teal  — "This week"
      case DashboardTier.upcoming:
        return (label, urgency.routine);         // grey  — "Routine"
    }
  }
}


// ─── Reason badge ─────────────────────────────────────────────────────────────

/// Service-needed pill shown next to patient name.
class MissionReasonBadge extends StatelessWidget {
  const MissionReasonBadge({super.key, required this.item});

  final MissionQueueItem item;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = programmeBadgeColors(item.primaryProgramme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.flag),
      ),
      child: Text(
        item.reason,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'NunitoSans',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// v13 design palette — badge colour is keyed by programme, not priority, so
/// the label always matches the reason text it's painted around. Public and
/// top-level so `HouseholdListScreen` (a non-queue member has no
/// `MissionQueueItem` to key off) can render an identical badge.
(Color, Color) programmeBadgeColors(Programme programme) {
  switch (programme) {
    case Programme.anc:
      return (const Color(0xFFFDF2F8), const Color(0xFF9D174D));
    case Programme.pnc:
      return (const Color(0xFFEEF0FF), const Color(0xFF4C1D95));
    case Programme.imci:
    case Programme.epi:
    case Programme.ncd:
      return (const Color(0xFFFFFBEB), const Color(0xFF92400E));
    case Programme.tb:
      return (const Color(0xFFF0FDF4), const Color(0xFF065F46));
    default:
      return (const Color(0xFFEEF0FF), const Color(0xFF1B2B5E));
  }
}

/// Flush member row for a patient with no active mission-queue entry —
/// name+age/gender+programme badge, optional address line, optional phone
/// line — no avatar, no card chrome of its own (always embedded inside a
/// caller's own card). Reuses the same `AppTextStyles.worklist*` tokens
/// `MissionQueueCard` uses so the two widgets never visually drift, and the
/// same `programmeReason`/`programmeBadgeColors` inputs so a patient's badge
/// reads identically whether the household list, the household detail
/// screen, or (via `MissionQueueCard`) the dashboard renders them.
///
/// `onTap` is required rather than optional/shared: each caller decides its
/// own tap behavior (e.g. the household list navigates to Patient Details,
/// the household detail screen opens an in-place member sheet) — sharing a
/// default here risks one screen silently adopting another's navigation.
class PatientBadgeRow extends StatelessWidget {
  const PatientBadgeRow({
    super.key,
    required this.name,
    required this.onTap,
    this.age,
    this.gender,
    this.phoneNumber,
    this.programmes = const {},
    this.ancVisitCount = 0,
    this.pncVisitCount = 0,
    this.householdNo,
    this.householdName,
  });

  final String? name;
  final int? age;
  final String? gender;
  final String? phoneNumber;
  final Set<Programme> programmes;
  final int ancVisitCount;
  final int pncVisitCount;

  /// Household-context line (e.g. "House #12, Rafiqul Islam's Household") —
  /// omit both when the caller already shows the member inside a known
  /// household (e.g. the household detail screen's own roster).
  final String? householdNo;
  final String? householdName;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Same shared logic the dashboard's real MissionQueueCard badge uses —
    // visit-count-aware, not an approximation of it.
    final badgeLabel = programmeReason(
      programmes: programmes,
      ancVisitCount: ancVisitCount,
      pncVisitCount: pncVisitCount,
    );
    final (badgeBg, badgeFg) = programmeBadgeColors(
      primaryProgrammeOf(programmes),
    );

    final address = [
      householdNo != null ? 'House #$householdNo' : null,
      householdName,
    ].whereType<String>().join(', ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 3,
                    children: [
                      Text(
                        name ?? CommonStrings.unnamed,
                        style: AppTextStyles.worklistPatientName,
                      ),
                      if (age != null || gender != null)
                        Text(
                          [
                            if (age != null) '$age',
                            if (gender != null)
                              gender!.substring(0, 1).toUpperCase(),
                          ].join('/'),
                          style: AppTextStyles.worklistPatientMeta,
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            fontFamily: 'NunitoSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: badgeFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (address.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.worklistAddress.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  if (phoneNumber != null && phoneNumber!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        phoneNumber!,
                        style: AppTextStyles.worklistPhone.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
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

// ─── Status dot ───────────────────────────────────────────────────────────────

/// Dot + label status indicator.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.worklistStatusPill.copyWith(color: color),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Visited badge ────────────────────────────────────────────────────────────

class _VisitedBadge extends StatelessWidget {
  const _VisitedBadge({required this.tokens});
  final LeapfrogColors tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.statusSuccess.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.flag),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 11, color: tokens.statusSuccess),
          const SizedBox(width: 3),
          Text(
            'Visited',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tokens.statusSuccess,
            ),
          ),
        ],
      ),
    );
  }
}
