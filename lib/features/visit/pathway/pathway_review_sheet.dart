import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';
import 'pathway_engine.dart';

/// A pathway that was skipped by the SK during review.
///
/// Used to create a deferred-screening follow-up so the pathway
/// surfaces in the next visit.
class SkippedPathway {
  const SkippedPathway({
    required this.programme,
    required this.trigger,
    required this.rationaleKey,
    required this.timestamp,
  });

  final Programme programme;
  final PathwayTrigger trigger;
  final String rationaleKey;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'programme': programme.wireTag,
        'trigger': trigger.name,
        'rationaleKey': rationaleKey,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Pathway review sheet — "Today's assessment plan".
///
/// Shows activated pathways with rationales. SKs can:
/// - Confirm and start the assessment
/// - Remove rule-activated pathways (with skip alert)
/// - Add programmes manually
class PathwayReviewSheet extends StatefulWidget {
  const PathwayReviewSheet({
    super.key,
    required this.patientName,
    required this.activatedPathways,
    required this.selectedSymptoms,
    required this.onConfirm,
    this.onSkip,
  });

  final String patientName;
  final List<ActivatedPathway> activatedPathways;
  final Set<String> selectedSymptoms;

  /// Called when SK confirms the assessment plan.
  /// Returns the final list of pathways and any skipped ones.
  final void Function(
    List<ActivatedPathway> confirmed,
    List<SkippedPathway> skipped,
  ) onConfirm;

  /// Called when SK wants to skip a pathway.
  /// If null, skip is not allowed.
  final void Function(ActivatedPathway pathway)? onSkip;

  @override
  State<PathwayReviewSheet> createState() => _PathwayReviewSheetState();
}

class _PathwayReviewSheetState extends State<PathwayReviewSheet> {
  late List<ActivatedPathway> _confirmedPathways;
  final List<SkippedPathway> _skippedPathways = [];

  @override
  void initState() {
    super.initState();
    _confirmedPathways = List.from(widget.activatedPathways);
  }

  String _programmeName(Programme programme, int priority) {
    // Special case for neonate
    if (programme == Programme.imci && priority == 1) {
      return PathwayStrings.programmeNeonate;
    }
    // Special case for nutrition
    if (programme == Programme.imci && priority == 50) {
      return PathwayStrings.programmeNutrition;
    }

    switch (programme) {
      case Programme.imci:
        return PathwayStrings.programmeImci;
      case Programme.anc:
        return PathwayStrings.programmeAnc;
      case Programme.pnc:
        return PathwayStrings.programmePnc;
      case Programme.ncd:
        return PathwayStrings.programmeNcd;
      case Programme.tb:
        return PathwayStrings.programmeTb;
      case Programme.unknown:
        return PathwayStrings.programmeUnknown;
    }
  }

  String _formatTriggerSymptoms(ActivatedPathway pathway) {
    if (pathway.triggerSymptoms.isNotEmpty) {
      return pathway.triggerSymptoms
          .map((s) => TriageStrings.symptomLabel(s))
          .join(', ');
    }
    if (pathway.triggerConditions.isNotEmpty) {
      return pathway.triggerConditions.join(', ');
    }
    if (pathway.triggerFlags.isNotEmpty) {
      return pathway.triggerFlags.join(', ');
    }
    return PathwayStrings.rationale(pathway.rationaleKey);
  }

  Future<void> _showSkipDialog(ActivatedPathway pathway) async {
    final programmeName = _programmeName(pathway.programme, pathway.priority);
    final trigger = _formatTriggerSymptoms(pathway);

    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(PathwayStrings.confirmRemoveTitle),
        content: Text(
          PathwayStrings.confirmRemoveBody(programmeName, trigger),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(PathwayStrings.keepButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text(PathwayStrings.skipAnywayButton),
          ),
        ],
      ),
    );

    if (shouldSkip == true && mounted) {
      setState(() {
        _confirmedPathways.remove(pathway);
        _skippedPathways.add(SkippedPathway(
          programme: pathway.programme,
          trigger: pathway.trigger,
          rationaleKey: pathway.rationaleKey,
          timestamp: DateTime.now(),
        ));
      });
      widget.onSkip?.call(pathway);
    }
  }

  void _addManualProgramme() {
    // Show a bottom sheet with available programmes
    showModalBottomSheet(
      context: context,
      builder: (context) => _ManualProgrammeSheet(
        excludedProgrammes:
            _confirmedPathways.map((p) => p.programme).toSet(),
        onSelect: (programme) {
          setState(() {
            _confirmedPathways = PathwayEngine.addManual(
              _confirmedPathways,
              programme,
            );
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientName),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PathwayStrings.reviewTitle,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  PathwayStrings.reviewSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Pathway list
          Expanded(
            child: _confirmedPathways.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _confirmedPathways.length + 1, // +1 for add button
                    itemBuilder: (context, index) {
                      if (index == _confirmedPathways.length) {
                        return _buildAddButton(context);
                      }
                      return _buildPathwayCard(
                        context,
                        _confirmedPathways[index],
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _confirmedPathways.isEmpty
                ? null
                : () {
                    widget.onConfirm(_confirmedPathways, _skippedPathways);
                  },
            child: const Text(PathwayStrings.startAssessment),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No assessments needed',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This is a routine visit',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _addManualProgramme,
            icon: const Icon(Icons.add),
            label: const Text(PathwayStrings.addProgramme),
          ),
        ],
      ),
    );
  }

  Widget _buildPathwayCard(BuildContext context, ActivatedPathway pathway) {
    final theme = Theme.of(context);
    final programmeName = _programmeName(pathway.programme, pathway.priority);
    final rationale = _formatTriggerSymptoms(pathway);

    // Determine card styling based on trigger
    final isRuleBased = pathway.trigger == PathwayTrigger.rule;
    final isManual = pathway.trigger == PathwayTrigger.manual;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isRuleBased
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getProgrammeIcon(pathway.programme),
            color: isRuleBased
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(programmeName)),
            if (isRuleBased)
              Icon(
                Icons.verified,
                size: 16,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
        subtitle: Text(
          rationale,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isManual || !isRuleBased
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _confirmedPathways.remove(pathway);
                  });
                },
              )
            : IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: theme.colorScheme.error,
                onPressed: () => _showSkipDialog(pathway),
              ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton.icon(
        onPressed: _addManualProgramme,
        icon: const Icon(Icons.add),
        label: const Text(PathwayStrings.addProgramme),
      ),
    );
  }

  IconData _getProgrammeIcon(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return Icons.child_care;
      case Programme.anc:
        return Icons.pregnant_woman;
      case Programme.pnc:
        return Icons.family_restroom;
      case Programme.ncd:
        return Icons.favorite;
      case Programme.tb:
        return Icons.air;
      case Programme.unknown:
        return Icons.medical_services;
    }
  }
}

/// Bottom sheet for manually adding a programme.
class _ManualProgrammeSheet extends StatelessWidget {
  const _ManualProgrammeSheet({
    required this.excludedProgrammes,
    required this.onSelect,
  });

  final Set<Programme> excludedProgrammes;
  final void Function(Programme) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Available programmes (exclude already selected)
    final availableProgrammes = Programme.values
        .where((p) => p != Programme.unknown)
        .where((p) => !excludedProgrammes.contains(p))
        .toList();

    if (availableProgrammes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'All programmes already added',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              PathwayStrings.addProgramme,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ...availableProgrammes.map((programme) {
            return ListTile(
              leading: Icon(_getProgrammeIcon(programme)),
              title: Text(_programmeName(programme)),
              onTap: () => onSelect(programme),
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _programmeName(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return PathwayStrings.programmeImci;
      case Programme.anc:
        return PathwayStrings.programmeAnc;
      case Programme.pnc:
        return PathwayStrings.programmePnc;
      case Programme.ncd:
        return PathwayStrings.programmeNcd;
      case Programme.tb:
        return PathwayStrings.programmeTb;
      case Programme.unknown:
        return PathwayStrings.programmeUnknown;
    }
  }

  IconData _getProgrammeIcon(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return Icons.child_care;
      case Programme.anc:
        return Icons.pregnant_woman;
      case Programme.pnc:
        return Icons.family_restroom;
      case Programme.ncd:
        return Icons.favorite;
      case Programme.tb:
        return Icons.air;
      case Programme.unknown:
        return Icons.medical_services;
    }
  }
}
