/// Clinical Decision Support rules — pure, deterministic, no I/O.
///
/// All CDS logic lives in [CdsRules.evaluate], a pure static function.
/// No network calls, no clock access, no Flutter dependencies.
///
/// Engineering Design Standards:
///   - Pure function: result depends only on [fieldValues] + [activePathways].
///   - No string literals: all copy keys are [CdsStrings] constants.
///   - Narrow error surfaces: no bare catch; this module has no I/O to fail.
///   - Conflict precedence: if referNow and treatAtCommunity both fire,
///     treatAtCommunity alerts are suppressed and a note is added.
library;

import '../../../core/cdss/models/cdss_results.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/programme.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────

/// Severity tier of a CDS alert.
enum CdsSeverity {
  /// Immediate clinical action required (referral, emergency treatment).
  urgent,

  /// Clinically significant but not immediately life-threatening.
  warning,

  /// Informational — suggested addition to the assessment.
  info,
}

/// Recommended action for a CDS alert.
enum CdsAction {
  /// Refer the patient to a higher-level facility now.
  referNow,

  /// Add a pathway/programme to the current assessment.
  addPathway,

  /// Treat the patient at the community level.
  treatAtCommunity,

  /// Continue the assessment — no additional action required.
  continueAssessment,
}

// ── Alert model ────────────────────────────────────────────────────────────────

/// A single CDS alert produced by [CdsRules.evaluate].
class CdsAlert {
  const CdsAlert({
    required this.alertId,
    required this.severity,
    required this.messageKey,
    required this.action,
    this.addPathway,
    this.rationaleKey,
  });

  /// Stable, unique identifier for this alert — used in tests and logging.
  final String alertId;

  /// Severity tier.
  final CdsSeverity severity;

  /// Key into [CdsStrings.message] — never a raw string.
  final String messageKey;

  /// Recommended clinical action.
  final CdsAction action;

  /// If [action] == [CdsAction.addPathway], which programme to add.
  final Programme? addPathway;

  /// Explainability — WHO guideline reference key into [CdsStrings.rationale].
  final String? rationaleKey;

  /// Return a copy of this alert with [rationaleKey] replaced.
  CdsAlert withRationaleKey(String key) => CdsAlert(
        alertId: alertId,
        severity: severity,
        messageKey: messageKey,
        action: action,
        addPathway: addPathway,
        rationaleKey: key,
      );

  @override
  String toString() =>
      'CdsAlert($alertId, ${severity.name}, ${action.name})';

  @override
  bool operator ==(Object other) =>
      other is CdsAlert && other.alertId == alertId;

  @override
  int get hashCode => alertId.hashCode;
}

// ── Rules engine ───────────────────────────────────────────────────────────────

/// Clinical Decision Support rule evaluator.
///
/// All rules are pure, deterministic, and WHO-sourced.
/// Call [evaluate] after each section save to get the current alert set.
class CdsRules {
  CdsRules._();

  // ── Internal rule definitions ───────────────────────────────────────────────

  /// Evaluate all CDS rules against the current field values.
  ///
  /// Returns alerts ordered by severity (urgent first, then warning, then info),
  /// then by rule registration order within each tier.
  ///
  /// **Conflict precedence:** if any alert has [CdsAction.referNow] AND any
  /// has [CdsAction.treatAtCommunity], all treatAtCommunity alerts are
  /// suppressed and the referNow alert's rationaleKey is set to
  /// [CdsStrings.conflictReferralOverridesKey].
  ///
  /// Pure function: no I/O, no clock, no side effects.
  static List<CdsAlert> evaluate(
    Map<String, dynamic> fieldValues,
    Set<Programme> activePathways, {
    CdssEngineOutput? cdssOutput,
  }) {
    final alerts = <CdsAlert>[];

    // ── BP rules (WHO HEARTS) ────────────────────────────────────────────────
    // Supports both legacy flat keys (bloodPressureSystolic) and SDK flat keys
    // (systolic / diastolic — after DynamicFormController composite expansion).
    final systolic = (fieldValues['bloodPressureSystolic'] ??
        fieldValues['systolic']) as int?;
    final diastolic = (fieldValues['bloodPressureDiastolic'] ??
        fieldValues['diastolic']) as int?;

    if (systolic != null || diastolic != null) {
      final sys = systolic ?? 0;
      final dia = diastolic ?? 0;

      if (sys >= 160 || dia >= 100) {
        // Severe hypertension → referNow (overrides stage-1 alert)
        alerts.add(const CdsAlert(
          alertId: 'bp_severe',
          severity: CdsSeverity.urgent,
          messageKey: 'bpSevereMessage',
          action: CdsAction.referNow,
          rationaleKey: 'rationaleWhoHeartsBpSevere',
        ));
      } else if (sys >= 140 || dia >= 90) {
        // Stage-1 hypertension → add NCD pathway if not already active
        final ncdActive = activePathways.contains(Programme.ncd);
        alerts.add(CdsAlert(
          alertId: 'bp_stage1',
          severity: CdsSeverity.warning,
          messageKey: 'bpStage1Message',
          action: ncdActive ? CdsAction.continueAssessment : CdsAction.addPathway,
          addPathway: ncdActive ? null : Programme.ncd,
          rationaleKey: 'rationaleWhoHeartsStage1',
        ));
      }
    }

    // ── IMCI danger signs (WHO IMCI) ─────────────────────────────────────────
    // Any true boolean in the danger-sign set → urgent referral.
    final dangerSignFields = const [
      'hasConvulsions',
      'lethargicOrUnconscious',
      'chestIndrawing', // NOTE: also triggers severe_pneumonia below
      'stridor',
      'vomitsEverything',
      'unableToBreastfeed',
    ];
    final hasAnyDangerSign =
        dangerSignFields.any((f) => fieldValues[f] == true);

    if (hasAnyDangerSign) {
      alerts.add(const CdsAlert(
        alertId: 'danger_sign_present',
        severity: CdsSeverity.urgent,
        messageKey: 'dangerSignMessage',
        action: CdsAction.referNow,
        rationaleKey: 'rationaleWhoImciDangerSign',
      ));
    }

    // ── Pneumonia classification (WHO IMCI) ───────────────────────────────────
    final hasChestIndrawing = fieldValues['hasChestIndrawing'] == true ||
        fieldValues['chestIndrawing'] == true;
    final hasFastBreathing = fieldValues['hasFastBreathing'] == true;

    if (hasChestIndrawing) {
      // Severe pneumonia: chest indrawing takes precedence
      alerts.add(const CdsAlert(
        alertId: 'severe_pneumonia',
        severity: CdsSeverity.urgent,
        messageKey: 'severePneumoniaMessage',
        action: CdsAction.referNow,
        rationaleKey: 'rationaleWhoImciSeverePneumonia',
      ));
      // Do NOT add the `pneumonia` alert when chest indrawing is present.
    } else if (hasFastBreathing) {
      alerts.add(const CdsAlert(
        alertId: 'pneumonia',
        severity: CdsSeverity.warning,
        messageKey: 'pneumoniaMessage',
        action: CdsAction.referNow,
        rationaleKey: 'rationaleWhoImciPneumonia',
      ));
    }

    // ── Malnutrition by MUAC (WHO) ────────────────────────────────────────────
    final muacRaw = fieldValues['muacCm'];
    final muac = muacRaw is num ? muacRaw.toDouble() : null;

    if (muac != null) {
      if (muac < 11.5) {
        alerts.add(const CdsAlert(
          alertId: 'sam',
          severity: CdsSeverity.urgent,
          messageKey: 'samMessage',
          action: CdsAction.referNow,
          rationaleKey: 'rationaleWhoMuacSam',
        ));
      } else if (muac < 12.5) {
        alerts.add(const CdsAlert(
          alertId: 'mam',
          severity: CdsSeverity.warning,
          messageKey: 'mamMessage',
          action: CdsAction.treatAtCommunity,
          rationaleKey: 'rationaleWhoMuacMam',
        ));
      }
    }

    // ── Haemoglobin / anemia (WHO ANC) ────────────────────────────────────────
    final hbRaw = fieldValues['hemoglobin'];
    final hb = hbRaw is num ? hbRaw.toDouble() : null;

    if (hb != null) {
      if (hb < 7.0) {
        alerts.add(const CdsAlert(
          alertId: 'severe_anemia',
          severity: CdsSeverity.urgent,
          messageKey: 'severeAnemiaMessage',
          action: CdsAction.referNow,
          rationaleKey: 'rationaleWhoAncAnemia',
        ));
      } else if (hb < 11.0) {
        alerts.add(const CdsAlert(
          alertId: 'anemia',
          severity: CdsSeverity.warning,
          messageKey: 'anemiaMessage',
          action: CdsAction.treatAtCommunity,
          rationaleKey: 'rationaleWhoAncMildAnemia',
        ));
      }
    }

    // ── Blood glucose / diabetes (WHO PEN) ────────────────────────────────────
    // 'glucoseValue' = legacy composer key; 'glucose' = SDK field_library key.
    final glucoseRaw = fieldValues['glucoseValue'] ?? fieldValues['glucose'];
    final glucose = glucoseRaw is num ? glucoseRaw.toDouble() : null;
    final glucoseType = fieldValues['glucoseType'] as String?;

    if (glucose != null && glucoseType != null) {
      final isHigh = (glucoseType == 'random' && glucose > 200) ||
          (glucoseType == 'fasting' && glucose > 126);

      if (isHigh) {
        final ncdActive = activePathways.contains(Programme.ncd);
        alerts.add(CdsAlert(
          alertId: 'glucose_high',
          severity: CdsSeverity.warning,
          messageKey: 'glucoseHighMessage',
          action:
              ncdActive ? CdsAction.continueAssessment : CdsAction.addPathway,
          addPathway: ncdActive ? null : Programme.ncd,
          rationaleKey: 'rationaleWhoPenDm',
        ));
      }
    }

    // ── TB screen indicator (WHO 4-symptom screen) ────────────────────────────
    final coughDays = fieldValues['coughDays'] as int?;
    final tbActive = activePathways.contains(Programme.tb);

    if (coughDays != null && coughDays >= 14 && !tbActive) {
      alerts.add(const CdsAlert(
        alertId: 'tb_screen_add',
        severity: CdsSeverity.info,
        messageKey: 'tbScreenAddMessage',
        action: CdsAction.addPathway,
        addPathway: Programme.tb,
        rationaleKey: 'rationaleWhoTb4Symptom',
      ));
    }

    // ── CDSS algorithm alerts ────────────────────────────────────────────────
    if (cdssOutput != null) {
      final ncdActive = activePathways.contains(Programme.ncd);
      final ancActive = activePathways.contains(Programme.anc);

      // FINDRISC
      final fr = cdssOutput.findrisc;
      if (fr != null) {
        if (fr.score >= 21) {
          alerts.add(CdsAlert(
            alertId: 'findrisc_very_high',
            severity: CdsSeverity.urgent,
            messageKey: 'findriscVeryHighMessage',
            action: ncdActive ? CdsAction.continueAssessment : CdsAction.addPathway,
            addPathway: ncdActive ? null : Programme.ncd,
            rationaleKey: 'rationaleFindriscVeryHigh',
          ));
        } else if (fr.score >= 15) {
          alerts.add(CdsAlert(
            alertId: 'findrisc_high',
            severity: CdsSeverity.warning,
            messageKey: 'findriscHighMessage',
            action: ncdActive ? CdsAction.continueAssessment : CdsAction.addPathway,
            addPathway: ncdActive ? null : Programme.ncd,
            rationaleKey: 'rationaleFindriscHigh',
          ));
        } else if (fr.score >= 12) {
          alerts.add(CdsAlert(
            alertId: 'findrisc_moderate',
            severity: CdsSeverity.warning,
            messageKey: 'findriscModerateMessage',
            action: ncdActive ? CdsAction.continueAssessment : CdsAction.addPathway,
            addPathway: ncdActive ? null : Programme.ncd,
            rationaleKey: 'rationaleFindriscModerate',
          ));
        }
      }

      // Framingham
      final fram = cdssOutput.framingham;
      if (fram != null && !fram.insufficientData) {
        if (fram.riskPct >= 20) {
          alerts.add(CdsAlert(
            alertId: 'framingham_high',
            severity: CdsSeverity.urgent,
            messageKey: 'framinghamHighMessage',
            action: ncdActive ? CdsAction.continueAssessment : CdsAction.addPathway,
            addPathway: ncdActive ? null : Programme.ncd,
            rationaleKey: 'rationaleFraminghamHigh',
          ));
        } else if (fram.riskPct >= 10) {
          alerts.add(CdsAlert(
            alertId: 'framingham_trigger',
            severity: CdsSeverity.warning,
            messageKey: 'framinghamTriggerMessage',
            action: ncdActive ? CdsAction.continueAssessment : CdsAction.addPathway,
            addPathway: ncdActive ? null : Programme.ncd,
            rationaleKey: 'rationaleFraminghamTrigger',
          ));
        }
      }

      // BP trends
      final cusum = cdssOutput.cusum;
      if (cusum != null && !cusum.insufficientData && cusum.alert) {
        alerts.add(const CdsAlert(
          alertId: 'bp_trend_cusum',
          severity: CdsSeverity.warning,
          messageKey: 'bpTrendCusumMessage',
          action: CdsAction.continueAssessment,
          rationaleKey: 'rationaleBpTrendCusum',
        ));
      }

      final ewma = cdssOutput.ewma;
      if (ewma != null && !ewma.insufficientData && ewma.alert) {
        alerts.add(const CdsAlert(
          alertId: 'bp_trend_ewma',
          severity: CdsSeverity.warning,
          messageKey: 'bpTrendEwmaMessage',
          action: CdsAction.continueAssessment,
          rationaleKey: 'rationaleBpTrendEwma',
        ));
      }

      final slope = cdssOutput.slope;
      if (slope != null && !slope.insufficientData && slope.alert) {
        alerts.add(const CdsAlert(
          alertId: 'bp_trend_slope',
          severity: CdsSeverity.warning,
          messageKey: 'bpTrendSlopeMessage',
          action: CdsAction.continueAssessment,
          rationaleKey: 'rationaleBpTrendSlope',
        ));
      }

      // miniPIERS
      final mp = cdssOutput.miniPiers;
      if (mp != null && !mp.insufficientData) {
        if (mp.critical) {
          alerts.add(CdsAlert(
            alertId: 'mini_piers_critical',
            severity: CdsSeverity.urgent,
            messageKey: 'miniPiersCriticalMessage',
            action: CdsAction.referNow,
            addPathway: ancActive ? null : Programme.anc,
            rationaleKey: 'rationaleMiniPiersCritical',
          ));
        } else if (mp.trigger) {
          alerts.add(CdsAlert(
            alertId: 'mini_piers_high',
            severity: CdsSeverity.warning,
            messageKey: 'miniPiersHighMessage',
            action: ancActive ? CdsAction.continueAssessment : CdsAction.addPathway,
            addPathway: ancActive ? null : Programme.anc,
            rationaleKey: 'rationaleMiniPiersHigh',
          ));
        }
      }
    }

    // ── Cataract NCD co-enrol ────────────────────────────────────────────────
    final ncdServiceProvided = fieldValues['ncdServiceProvided'] as bool?;
    if (ncdServiceProvided == true) {
      final ncdActive = activePathways.contains(Programme.ncd);
      if (!ncdActive) {
        alerts.add(const CdsAlert(
          alertId: 'cataract_ncd_coenroll',
          severity: CdsSeverity.info,
          messageKey: 'cataractNcdCoenrollMessage',
          action: CdsAction.addPathway,
          addPathway: Programme.ncd,
          rationaleKey: 'rationaleCataractNcdCoenroll',
        ));
      }
    }

    // ── Eye care referral ────────────────────────────────────────────────────
    final eyeTestOutcome = fieldValues['eyeTestOutcome'] as String?;
    if (eyeTestOutcome == 'referral_needed') {
      alerts.add(const CdsAlert(
        alertId: 'eye_care_referral',
        severity: CdsSeverity.warning,
        messageKey: 'eyeCareReferralMessage',
        action: CdsAction.referNow,
        rationaleKey: 'rationaleEyeCareReferral',
      ));
    }

    // ── Conflict precedence ────────────────────────────────────────────────────
    // If ANY referNow alert is present, suppress ALL treatAtCommunity alerts
    // and annotate the first referNow alert's rationaleKey.
    final hasReferNow = alerts.any((a) => a.action == CdsAction.referNow);
    final hasTreatAtCommunity =
        alerts.any((a) => a.action == CdsAction.treatAtCommunity);

    List<CdsAlert> resolved;
    if (hasReferNow && hasTreatAtCommunity) {
      resolved = alerts
          .where((a) => a.action != CdsAction.treatAtCommunity)
          .map((a) {
            if (a.action == CdsAction.referNow &&
                a.rationaleKey != CdsStrings.conflictReferralOverridesKey) {
              // Annotate the first referNow alert; leave others unchanged.
              return a;
            }
            return a;
          })
          .toList();

      // Annotate the first referNow alert with the conflict override note.
      final firstReferIdx =
          resolved.indexWhere((a) => a.action == CdsAction.referNow);
      if (firstReferIdx >= 0) {
        resolved[firstReferIdx] = resolved[firstReferIdx]
            .withRationaleKey(CdsStrings.conflictReferralOverridesKey);
      }
    } else {
      resolved = List.of(alerts);
    }

    // ── Sort: urgent → warning → info, then by rule registration order ────────
    resolved.sort((a, b) {
      final severityOrder = _severityRank(a.severity) -
          _severityRank(b.severity);
      return severityOrder;
    });

    return resolved;
  }

  static int _severityRank(CdsSeverity s) {
    switch (s) {
      case CdsSeverity.urgent:
        return 0;
      case CdsSeverity.warning:
        return 1;
      case CdsSeverity.info:
        return 2;
    }
  }
}
