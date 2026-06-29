import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';
import '../../../core/models/risk.dart';
import '../../../core/models/worklist_entry.dart';
import '../../../core/widgets/alert_badge.dart';
import '../../../core/widgets/programme_tag.dart';
import '../../../core/widgets/urgency_badge.dart';

class WorklistCard extends StatelessWidget {
  const WorklistCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final WorklistEntry entry;
  final VoidCallback onTap;

  void _showRationaleSheet(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _RationaleSheet(
        entry: entry,
        scheme: scheme,
      ),
    );
  }

  /// Extract initials from display name (up to 2 characters).
  String _getInitials() {
    final name = entry.displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Map spec §2.8.3 band to the SK-facing urgency pill. Modifier is *not*
  /// surfaced — it influences sort order only.
  UrgencyLevel _urgencyLevel() {
    switch (entry.band) {
      case Band.band1:
        return UrgencyLevel.visitNow;
      case Band.band2:
        return UrgencyLevel.today;
      case Band.band3:
        return UrgencyLevel.thisWeek;
      case Band.band4:
        return UrgencyLevel.routine;
    }
  }

  /// Spec §2.6 card border rule: red border only when a Band 1 patient *also*
  /// has a danger sign (or other CCE-style escalation). All other cards use
  /// neutral grey. CCE alert input is deferred — keyed off rationale drivers
  /// for now.
  bool _hasDangerSign() {
    final drivers = entry.rationale?.drivers ?? const <String>[];
    return drivers.any((d) =>
        d == 'anc-danger-sign' ||
        d == 'ncd-stroke-sign' ||
        d == 'clinician-red-flag');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentFor(entry.band, scheme);
    final initials = _getInitials();
    
    // Build the primary alert text from reasons
    final alertText = entry.reasons.isNotEmpty 
        ? entry.reasons.first 
        : _defaultAlertText();
    
    // Build demographics line
    final demographics = <String>[];
    if (entry.age != null) demographics.add('Age ${entry.age}');
    if (entry.householdName != null) {
      demographics.add(entry.householdName!);
    } else if (entry.householdNo != null) {
      demographics.add('House #${entry.householdNo}');
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Spec §2.6: red border only when band1 + danger sign present.
        side: entry.isUrgent && _hasDangerSign()
            ? BorderSide(color: accent.withValues(alpha: 0.6), width: 1.5)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Semantics(
        label: 'Open visit for ${entry.displayName}, ${entry.programmes.isNotEmpty ? entry.programmes.first.name : ''} programme',
        button: true,
        child: InkWell(
          key: const Key('worklist_card_tap'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar with initials
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row 1: Name + Urgency badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          UrgencyBadge(level: _urgencyLevel(), compact: true),
                        ],
                      ),

                      // Row 2: Alert badge with reason
                      if (alertText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        AlertIndicator(
                          reason: alertText,
                          isUrgent: entry.isUrgent,
                        ),
                      ],

                      // Row 3: Demographics + Programme chips inline
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (demographics.isNotEmpty)
                            Flexible(
                              child: Text(
                                demographics.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurface.withValues(alpha: 0.6),
                                    ),
                              ),
                            ),
                          if (demographics.isNotEmpty && entry.programmes.isNotEmpty)
                            Text(
                              ' · ',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.4),
                                fontSize: 11,
                              ),
                            ),
                          // Programme chips inline
                          ...entry.programmes.take(2).map((p) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ProgrammeTag(programme: p),
                          )),
                          if (entry.rationale != null || entry.reasons.length > 1)
                            Semantics(
                              label: 'Show AI rationale for ${entry.displayName}',
                              button: true,
                              child: GestureDetector(
                                key: const Key('worklist_rationale_tap'),
                                onTap: () => _showRationaleSheet(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.help_outline, size: 10, color: scheme.onSurfaceVariant),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Why?',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String _defaultAlertText() {
    // Generate sensible default based on programme
    final progs = entry.programmes;
    if (progs.contains(Programme.anc)) {
      return 'ANC visit due';
    } else if (progs.contains(Programme.imci)) {
      return 'Follow-up needed';
    } else if (progs.contains(Programme.ncd)) {
      return 'Monthly NCD check';
    } else if (progs.contains(Programme.tb)) {
      return 'TB screening due';
    }
    return 'Review needed';
  }

  Color _accentFor(Band band, ColorScheme scheme) {
    switch (band) {
      case Band.band1:
        return scheme.error;
      case Band.band2:
        return scheme.tertiary;
      case Band.band3:
        return scheme.primary;
      case Band.band4:
        return scheme.onSurfaceVariant;
    }
  }
}

/// Bottom sheet showing structured rationale for the risk score.
class _RationaleSheet extends StatelessWidget {
  const _RationaleSheet({
    required this.entry,
    required this.scheme,
  });

  final WorklistEntry entry;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final rationale = entry.rationale;
    final reasons = entry.reasons;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Header with score
            Row(
              children: [
                Text(
                  WorklistStrings.rationaleHeader,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _bandColor(entry.band, scheme).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _bandColor(entry.band, scheme).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _urgencyLabel(entry.band),
                    style: TextStyle(
                      color: _bandColor(entry.band, scheme),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.displayName,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            // Drivers section
            Text(
              WorklistStrings.riskDriversHeader,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            ...reasons.map((reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reason,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
            // Metadata footer (only show if structured rationale exists)
            if (rationale != null) ...[
              Divider(color: scheme.outlineVariant),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MetadataChip(
                    label: WorklistStrings.modelVersionLabel,
                    value: rationale.modelVersion,
                    scheme: scheme,
                  ),
                  const SizedBox(width: 8),
                  _MetadataChip(
                    label: WorklistStrings.computedAtLabel,
                    value: _formatDate(rationale.computedAt),
                    scheme: scheme,
                  ),
                ],
              ),
              if (rationale.humanReviewRequired) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        WorklistStrings.humanReviewRequired,
                        style: TextStyle(
                          color: scheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Color _bandColor(Band band, ColorScheme scheme) {
    switch (band) {
      case Band.band1:
        return scheme.error;
      case Band.band2:
        return scheme.tertiary;
      case Band.band3:
        return scheme.primary;
      case Band.band4:
        return scheme.onSurfaceVariant;
    }
  }

  String _urgencyLabel(Band band) {
    switch (band) {
      case Band.band1:
        return WorklistStrings.urgencyNow;
      case Band.band2:
        return WorklistStrings.urgencyToday;
      case Band.band3:
        return WorklistStrings.urgencyThisWeek;
      case Band.band4:
        return WorklistStrings.urgencyRoutine;
    }
  }

  String _formatDate(DateTime dt) {
    // Simple formatting; production would use intl package
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    required this.label,
    required this.value,
    required this.scheme,
  });

  final String label;
  final String value;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

