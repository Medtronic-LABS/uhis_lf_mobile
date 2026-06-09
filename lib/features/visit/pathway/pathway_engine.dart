import '../../../core/models/programme.dart';
import '../triage/patient_context_builder.dart';
import 'pathway_rules_v1.dart';

/// Source of the pathway activation.
enum PathwayTrigger {
  /// Activated by rule-based engine (WHO-derived, deterministic).
  rule,

  /// Activated by AI suggestion (server-side, confidence < 1.0).
  ai,

  /// Manually added by the SK.
  manual,
}

/// An activated pathway for the assessment.
class ActivatedPathway {
  const ActivatedPathway({
    required this.programme,
    required this.priority,
    required this.confidence,
    required this.trigger,
    required this.rationaleKey,
    this.triggerSymptoms = const {},
    this.triggerConditions = const {},
    this.triggerFlags = const {},
  });

  /// The programme to assess.
  final Programme programme;

  /// Priority order (lower = higher priority, acute before scheduled).
  final int priority;

  /// Confidence score (1.0 for rules, < 1.0 for AI).
  final double confidence;

  /// What triggered this pathway activation.
  final PathwayTrigger trigger;

  /// Localization key for explaining why this pathway was activated.
  final String rationaleKey;

  /// Symptom codes that triggered this pathway (for explainability).
  final Set<String> triggerSymptoms;

  /// Condition codes from history that triggered this pathway.
  final Set<String> triggerConditions;

  /// Open flags that triggered this pathway.
  final Set<String> triggerFlags;

  /// Whether this is a rule-based activation (not AI or manual).
  bool get isRuleBased => trigger == PathwayTrigger.rule;

  /// Whether this is a scheduled pathway (EPI, FP, etc.) vs acute.
  bool get isScheduled => priority >= 100;

  @override
  bool operator ==(Object other) =>
      other is ActivatedPathway &&
      other.programme == programme &&
      other.priority == priority;

  @override
  int get hashCode => Object.hash(programme, priority);

  @override
  String toString() =>
      'ActivatedPathway(${programme.name}, priority=$priority, '
      'confidence=$confidence, trigger=${trigger.name})';
}

/// Pathway activation engine — pure function.
///
/// Evaluates symptoms and patient context against WHO-derived rules
/// to determine which programmes should be assessed.
///
/// This is a pure function with no I/O or clock access for testability.
/// Pass [now] explicitly for date-based calculations.
class PathwayEngine {
  PathwayEngine._();

  /// Activate pathways based on symptoms and patient context.
  ///
  /// Returns a list of [ActivatedPathway] sorted by priority
  /// (lower number = higher priority, assessed first).
  ///
  /// Pure function: pass [now] for date-based calculations.
  static List<ActivatedPathway> activate(
    Set<String> symptoms,
    PatientContext ctx, {
    DateTime? now,
  }) {
    final activated = <ActivatedPathway>[];
    final now_ = now ?? DateTime.now();

    // Evaluate each rule
    for (final rule in PathwayRulesV1.all) {
      final result = _evaluateRule(rule, symptoms, ctx, now_);
      if (result != null) {
        activated.add(result);
      }
    }

    // Add EPI pathway if immunizations are overdue (scheduled pathway)
    if (ctx.isEpiDue && ctx.isUnder5) {
      activated.add(ActivatedPathway(
        programme: Programme.imci, // EPI uses IMCI programme type
        priority: 100, // Scheduled pathways have priority >= 100
        confidence: 1.0,
        trigger: PathwayTrigger.rule,
        rationaleKey: 'pathwayEpiRationale',
        triggerFlags: {'EPI_DUE'},
      ));
    }

    // Check for elevated BP triggering NCD
    if (!activated.any((a) => a.programme == Programme.ncd) && ctx.hasElevatedBp) {
      activated.add(ActivatedPathway(
        programme: Programme.ncd,
        priority: 40,
        confidence: 1.0,
        trigger: PathwayTrigger.rule,
        rationaleKey: 'pathwayNcdHtnRationale',
        triggerConditions: {'ELEVATED_BP'},
      ));
    }

    // Apply suppression rules (neonate suppresses ICCM)
    final suppressed = <ActivatedPathway>[];
    for (final pathway in activated) {
      // Find the rule that activated this pathway
      final rule = PathwayRulesV1.all.firstWhere(
        (r) =>
            r.programme == pathway.programme && r.priority == pathway.priority,
        orElse: () => PathwayRulesV1.all.first,
      );

      if (rule.suppressedBy != null) {
        // Check if the suppressing programme is also activated
        if (activated.any((a) => a.programme == rule.suppressedBy)) {
          suppressed.add(pathway);
        }
      }
    }
    activated.removeWhere((a) => suppressed.contains(a));

    // Special case: neonate (age < 2 months) suppresses ICCM
    if (ctx.isNeonate) {
      // Remove all ICCM pathways with priority > 1 (keep neonate)
      activated.removeWhere(
          (a) => a.programme == Programme.imci && a.priority > 1);
    }

    // Deduplicate by programme (keep lowest priority = highest urgency)
    final deduped = <Programme, ActivatedPathway>{};
    for (final pathway in activated) {
      final existing = deduped[pathway.programme];
      if (existing == null || pathway.priority < existing.priority) {
        deduped[pathway.programme] = pathway;
      }
    }

    // Sort by priority (ascending = higher priority first)
    final result = deduped.values.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));

    return result;
  }

  static ActivatedPathway? _evaluateRule(
    PathwayRule rule,
    Set<String> symptoms,
    PatientContext ctx,
    DateTime now,
  ) {
    // Check demographic gate
    if (!rule.gate.evaluate(ctx)) return null;

    final triggerSymptoms = <String>{};
    final triggerConditions = <String>{};
    final triggerFlags = <String>{};
    var triggered = false;

    // Check anyOf symptoms (OR logic)
    if (rule.anyOf.isNotEmpty) {
      for (final symptom in symptoms) {
        if (rule.anyOf.contains(symptom)) {
          triggerSymptoms.add(symptom);
          triggered = true;
        }
      }
    }

    // Check combinations (all-of within set, OR across sets)
    for (final combo in rule.combinations) {
      if (combo.every((s) => symptoms.contains(s))) {
        triggerSymptoms.addAll(combo);
        triggered = true;
        break; // One combo match is enough
      }
    }

    // Check history triggers
    if (rule.historyTriggers.isNotEmpty) {
      // Check known conditions
      for (final condition in ctx.knownConditions) {
        if (rule.historyTriggers.contains(condition)) {
          triggerConditions.add(condition);
          triggered = true;
        }
      }

      // Check open flags
      for (final flag in ctx.openFlags) {
        if (rule.historyTriggers.contains(flag)) {
          triggerFlags.add(flag);
          triggered = true;
        }
      }

      // Check active programmes
      for (final prog in ctx.activeProgrammes) {
        if (rule.historyTriggers.contains(prog.wireTag)) {
          triggerConditions.add(prog.wireTag);
          triggered = true;
        }
      }
    }

    // Special case: ANC requires pregnancy from context OR symptoms
    if (rule.programme == Programme.anc) {
      if (ctx.isPregnant || symptoms.contains('pregnant')) {
        triggered = true;
        if (ctx.isPregnant) {
          triggerConditions.add('PREGNANCY');
        } else if (symptoms.contains('pregnant')) {
          triggerSymptoms.add('pregnant');
        }
      }
    }

    // Special case: PNC requires postpartum from context
    if (rule.programme == Programme.pnc) {
      if (ctx.isPostpartum) {
        triggered = true;
        triggerConditions.add('POSTPARTUM');
      }
    }

    if (!triggered) return null;

    return ActivatedPathway(
      programme: rule.programme,
      priority: rule.priority,
      confidence: 1.0, // Rules have 100% confidence
      trigger: PathwayTrigger.rule,
      rationaleKey: rule.rationaleKey,
      triggerSymptoms: triggerSymptoms,
      triggerConditions: triggerConditions,
      triggerFlags: triggerFlags,
    );
  }

  /// Add a manually selected pathway to the list.
  static List<ActivatedPathway> addManual(
    List<ActivatedPathway> existing,
    Programme programme,
  ) {
    // Check if already in the list
    if (existing.any((a) => a.programme == programme)) {
      return existing;
    }

    final manual = ActivatedPathway(
      programme: programme,
      priority: 90, // Manual additions go before scheduled but after acute
      confidence: 1.0,
      trigger: PathwayTrigger.manual,
      rationaleKey: 'pathwayManualRationale',
    );

    final result = [...existing, manual];
    result.sort((a, b) => a.priority.compareTo(b.priority));
    return result;
  }

  /// Remove a pathway from the list.
  ///
  /// Returns the removed pathway (for skip tracking) or null if not found.
  static (List<ActivatedPathway>, ActivatedPathway?) remove(
    List<ActivatedPathway> existing,
    Programme programme,
  ) {
    final index = existing.indexWhere((a) => a.programme == programme);
    if (index < 0) {
      return (existing, null);
    }

    final removed = existing[index];
    final result = List<ActivatedPathway>.from(existing)..removeAt(index);
    return (result, removed);
  }
}
