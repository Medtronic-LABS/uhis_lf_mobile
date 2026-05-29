import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';
import '../../../core/models/risk.dart';
import '../../../core/models/worklist_entry.dart';

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

  /// Get emoji and label for primary programme/condition
  (String emoji, String label) _conditionInfo() {
    final progs = entry.programmes;
    if (progs.contains(Programme.imci)) {
      return ('🌡️', 'Sick child');
    } else if (progs.contains(Programme.anc)) {
      return ('🤰', 'Pregnant');
    } else if (progs.contains(Programme.ncd)) {
      return ('💊', 'NCD check');
    } else if (progs.contains(Programme.tb)) {
      return ('🫁', 'TB screen');
    }
    return ('👤', 'General');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentFor(entry.band, scheme);
    final (emoji, conditionLabel) = _conditionInfo();
    
    // Build the primary alert text from reasons
    final alertText = entry.reasons.isNotEmpty 
        ? entry.reasons.first 
        : _defaultAlertText();
    
    // Build household display
    final householdDisplay = entry.householdName ?? 
        (entry.householdNo != null ? 'House #${entry.householdNo}' : null);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: entry.isUrgent 
            ? BorderSide(color: accent.withValues(alpha: 0.5), width: 2)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Avatar + Name + Score badge
              Row(
                children: [
                  // Avatar with programme icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name and household
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (entry.age != null) ...[
                              Text(
                                'Age ${entry.age}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurface.withValues(alpha: 0.7),
                                    ),
                              ),
                              if (householdDisplay != null)
                                Text(
                                  ' · ',
                                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
                                ),
                            ],
                            if (householdDisplay != null)
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.home_outlined,
                                      size: 14,
                                      color: scheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        householdDisplay,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: scheme.onSurface.withValues(alpha: 0.7),
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Risk score badge
                  _RiskScoreBadge(score: entry.score, band: entry.band, color: accent),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Row 2: Alert reason chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: entry.isUrgent 
                      ? accent.withValues(alpha: 0.1) 
                      : scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      entry.isUrgent ? Icons.warning_amber_rounded : Icons.schedule_outlined,
                      size: 18,
                      color: entry.isUrgent ? accent : scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alertText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: entry.isUrgent ? accent : scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Row 3: Programme chips + condition label
              const SizedBox(height: 10),
              Row(
                children: [
                  // Programme chips
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final p in entry.programmes)
                          _ProgrammeTag(programme: p),
                        _ConditionTag(label: conditionLabel, emoji: emoji),
                      ],
                    ),
                  ),
                  // Why button
                  if (entry.rationale != null || entry.reasons.length > 1)
                    GestureDetector(
                      onTap: () => _showRationaleSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.help_outline, size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              'Why?',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
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

  Color _accentFor(RiskBand band, ColorScheme scheme) {
    switch (band) {
      case RiskBand.urgent:
        return scheme.error;
      case RiskBand.high:
        return scheme.primary;
      case RiskBand.moderate:
        return scheme.tertiary;
      case RiskBand.low:
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
                    WorklistStrings.riskScoreLabel(entry.score),
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

  Color _bandColor(RiskBand band, ColorScheme scheme) {
    switch (band) {
      case RiskBand.urgent:
        return scheme.error;
      case RiskBand.high:
        return scheme.primary;
      case RiskBand.moderate:
        return scheme.tertiary;
      case RiskBand.low:
        return scheme.onSurfaceVariant;
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

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _UrgentBadge extends StatelessWidget {
  const _UrgentBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        WorklistStrings.urgentBadge,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ProgrammeChip extends StatelessWidget {
  const _ProgrammeChip({required this.programme, required this.colors});

  final Programme programme;
  final ProgrammeColors colors;

  @override
  Widget build(BuildContext context) {
    final fg = colors.of(programme);
    final bg = colors.containerOf(programme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        _labelFor(programme),
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static String _labelFor(Programme p) {
    switch (p) {
      case Programme.imci:
        return WorklistStrings.programmeImci;
      case Programme.anc:
        return WorklistStrings.programmeAnc;
      case Programme.ncd:
        return WorklistStrings.programmeNcd;
      case Programme.tb:
        return WorklistStrings.programmeTb;
    }
  }
}

/// Compact score badge for the new card layout.
class _CompactScoreBadge extends StatelessWidget {
  const _CompactScoreBadge({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Mini programme chip without border for compact display.
class _MiniProgrammeChip extends StatelessWidget {
  const _MiniProgrammeChip({required this.programme});

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = _colorsFor(programme, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _labelFor(programme),
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (Color bg, Color fg) _colorsFor(Programme p, ColorScheme scheme) {
    switch (p) {
      case Programme.imci:
        return (scheme.errorContainer, scheme.onErrorContainer);
      case Programme.anc:
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer);
      case Programme.ncd:
        return (scheme.primaryContainer, scheme.onPrimaryContainer);
      case Programme.tb:
        return (scheme.secondaryContainer, scheme.onSecondaryContainer);
    }
  }

  static String _labelFor(Programme p) {
    switch (p) {
      case Programme.imci:
        return WorklistStrings.programmeImci;
      case Programme.anc:
        return WorklistStrings.programmeAnc;
      case Programme.ncd:
        return WorklistStrings.programmeNcd;
      case Programme.tb:
        return WorklistStrings.programmeTb;
    }
  }
}

/// Material 3 risk score badge with band color coding.
class _RiskScoreBadge extends StatelessWidget {
  const _RiskScoreBadge({
    required this.score,
    required this.band,
    required this.color,
  });

  final int score;
  final RiskBand band;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUrgent = band == RiskBand.urgent;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isUrgent ? color : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: isUrgent ? null : Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUrgent) ...[
            Icon(
              Icons.warning_rounded,
              size: 14,
              color: scheme.onError,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '$score',
            style: TextStyle(
              color: isUrgent ? scheme.onError : color,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Programme tag with Material 3 styling.
class _ProgrammeTag extends StatelessWidget {
  const _ProgrammeTag({required this.programme});

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
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.pregnant_woman);
      case Programme.ncd:
        return (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.medical_services_outlined);
      case Programme.tb:
        return (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.air);
    }
  }

  static String _labelFor(Programme p) {
    switch (p) {
      case Programme.imci:
        return WorklistStrings.programmeImci;
      case Programme.anc:
        return WorklistStrings.programmeAnc;
      case Programme.ncd:
        return WorklistStrings.programmeNcd;
      case Programme.tb:
        return WorklistStrings.programmeTb;
    }
  }
}

/// Condition tag with emoji.
class _ConditionTag extends StatelessWidget {
  const _ConditionTag({required this.label, required this.emoji});

  final String label;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $emoji',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
