import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clinical/assessment_thresholds.dart';
import '../../../core/clinical/referral_evaluator.dart';
import '../../../core/db/local_assessment_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../../core/debug/console_log.dart';
import '../../../core/mission/mission_pregnancy_facts.dart';
import '../../../core/models/json_read.dart';
import '../../../core/models/referral.dart';
import '../../../core/risk/anc_status.dart';
import '../../../core/risk/cataract_status.dart';
import '../../../core/risk/eye_care_status.dart';
import '../../../core/risk/ncd_status.dart';
import '../../../core/risk/pregnancy_outcome_status.dart';
import '../../../core/risk/pw_risk_factors.dart';
import '../../../core/time/calendar_day.dart';
import '../../referral/referral_repository.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../assessment_repository.dart';
import '../models/anc_assessment.dart';
import 'canonical_visit_data.dart';
import 'childhood_visit.dart';
import 'form_config.dart';
import 'rmnch_follow_up_calculator.dart';
import 'unified_payload_mapper.dart';
import 'unified_section_rules.dart';
import 'vitals_trend.dart';

/// Manages in-progress canonical form state for a single visit.
///
/// Autosaves field changes to [assessment_draft] via [AssessmentDraftDao].
/// On submit, decomposes to per-programme payloads and enqueues as
/// [local_assessments] rows for offline sync.
class UnifiedFormNotifier extends ChangeNotifier {
  UnifiedFormNotifier({
    required String encounterId,
    required String patientId,
    required List<String> activeFormTypes,
    required AssessmentDraftDao draftDao,
    required AssessmentRepository assessmentRepo,
    required PatientDao patientDao,
    required PregnancySnapshotDao pregnancySnapshotDao,
    String? memberId,
    String? householdId,
    String? villageId,
    int householdMemberLocalId = 0,
    String? pregnancyEpisodeId,
    String? defaultReferralSiteId,
    ReferralRepository? referralRepo,
  })  : _encounterId = encounterId,
        _patientId = patientId,
        _activeFormTypes = activeFormTypes,
        _draftDao = draftDao,
        _assessmentRepo = assessmentRepo,
        _patientDao = patientDao,
        _pregnancySnapshotDao = pregnancySnapshotDao,
        _memberId = memberId,
        _householdId = householdId,
        _villageId = villageId,
        _householdMemberLocalId = householdMemberLocalId,
        _pregnancyEpisodeId = pregnancyEpisodeId,
        _defaultReferralSiteId = defaultReferralSiteId,
        _referralRepo = referralRepo;

  final String _encounterId;
  final String _patientId;
  final List<String> _activeFormTypes;
  final AssessmentDraftDao _draftDao;
  final AssessmentRepository _assessmentRepo;
  final PatientDao _patientDao;
  final PregnancySnapshotDao _pregnancySnapshotDao;
  final String? _memberId;
  final String? _householdId;
  final String? _villageId;
  final int _householdMemberLocalId;
  final String? _pregnancyEpisodeId;
  final String? _defaultReferralSiteId;
  final ReferralRepository? _referralRepo;

  DateTime? _lmpDate;
  DateTime? _eddDate;
  int? _gestationalWeeks;

  /// LMP date loaded from patient raw JSON at init.
  DateTime? get lmpDate => _lmpDate;

  /// Estimated delivery date (LMP + 280 days).
  DateTime? get eddDate => _eddDate;

  /// Gestational weeks loaded from patient raw JSON at init.
  int? get gestationalWeeks => _gestationalWeeks;

  CanonicalVisitData _data = const CanonicalVisitData();
  bool _submitting = false;
  String? _submitError;
  Set<String> _validationErrors = const {};

  /// Debounces [_saveDraft] so rapid keystrokes coalesce into one DB write
  /// instead of persisting every intermediate value (e.g. "1", "12", "120").
  Timer? _saveDraftTimer;

  bool _lastIsReferred = false;
  List<String> _lastReferredReasons = const [];
  String? _lastReferralFacility;

  /// Provenance per fieldId — who last set the value (SK vs AI scribe).
  /// Fields never touched have no entry (treated as manual-owned once typed).
  final Map<String, FieldSource> _fieldSources = {};

  /// Verbatim transcript quote backing an AI-filled value (null when the
  /// server didn't supply one). Keyed by fieldId, AI-filled fields only.
  final Map<String, String?> _fieldSourceSegments = {};

  /// When true, height was taken from a prior NCD/Cataract visit and must not
  /// be edited — mirrors Spice `view.isEnabled = false` after prefill.
  bool _heightLockedFromPrior = false;

  /// Field library, supplied by the form screen once `field_library.json` is
  /// parsed. Used at submit time to translate stored option ids into the wire
  /// `value` codes Spice sends (see [_withWireOptionValues]), and to clear
  /// fields a condition has just hidden (see [_clearHiddenDependents]).
  Map<String, FieldDef> _fieldDefs = const {};
  Map<String, List<FieldVisibilityRule>> _visibilityRules = const {};

  /// driver fieldId → every fieldId its `condition` array targets.
  final Map<String, Set<String>> _conditionTargets = {};

  set formConfig(FormConfig config) {
    _fieldDefs = config.fields;
    _visibilityRules = config.visibilityRulesByTargetId;
    _conditionTargets.clear();
    for (final def in config.fields.values) {
      for (final condition in def.conditions) {
        _conditionTargets
            .putIfAbsent(def.id, () => <String>{})
            .add(condition.targetId);
      }
    }
  }
  /// `value` codes Spice sends (see [_withWireOptionValues]).
  set fieldDefs(Map<String, FieldDef> defs) => _fieldDefs = defs;

  CanonicalVisitData get data => _data;
  bool get submitting => _submitting;

  /// Referral result computed during the most-recent [submit] call.
  /// Read by [visit_form_screen] after submit to propagate to the Step-3 card.
  bool get lastIsReferred => _lastIsReferred;
  List<String> get lastReferredReasons => _lastReferredReasons;
  String? get lastReferralFacility => _lastReferralFacility;
  String? get submitError => _submitError;
  Set<String> get validationErrors => _validationErrors;

  /// Provenance for [fieldId], or null when the field was never set.
  FieldSource? fieldSource(String fieldId) => _fieldSources[fieldId];

  /// Transcript quote backing an AI-filled [fieldId], when available.
  String? fieldSourceSegment(String fieldId) => _fieldSourceSegments[fieldId];

  /// True when height was prefilled from a prior visit and is hard-locked.
  bool get isHeightLockedFromPrior => _heightLockedFromPrior;

  /// Height is locked when prefilled from a prior visit, or on ANC visit 2+
  /// (field is hidden in the UI; value is still kept for payload / BMI).
  bool _isHeightLocked() {
    if (_heightLockedFromPrior) return true;
    final visitNo = _asInt(_data.getValue('ancVisitNumber')) ??
        _asInt(_data.getValue('visitNo'));
    return visitNo != null && visitNo > 1;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// All AI-populated fields still pending SK review (drives banner count).
  int get aiPendingCount => _fieldSources.values
      .where((s) => s == FieldSource.aiPending)
      .length;

  /// FHIR encounter id for this visit.
  String get encounterId => _encounterId;

  /// FHIR patient id for this visit (empty when unknown). Exposed so the
  /// vitals-trend card can look up prior-visit history.
  String get patientId => _patientId;

  /// Household-member id for this visit, when it differs from [patientId].
  /// Pregnancy snapshot rows are sometimes keyed by it.
  String? get memberId => _memberId;

  /// Loads prior ANC visit snapshots for the vitals-trend card, oldest-first.
  Future<List<VisitVitals>> ancVitalsHistory() async =>
      _assessmentRepo.ancVitalsHistory(
        _patientId,
        alsoId: await _localPatientId(),
      );

  /// ANC visits already on file for this patient (local + synced history).
  Future<int> priorAncVisitCount() async =>
      _assessmentRepo.priorAncVisitCount(
        _patientId,
        alsoId: await _localPatientId(),
      );

  /// Returns the most-recent weight (kg) recorded for this patient from ANY
  /// prior visit, or `null` when no prior weight exists.
  Future<double?> lastRecordedWeight() async =>
      _assessmentRepo.lastRecordedWeight(
        _patientId,
        alsoId: await _localPatientId(),
      );

  /// Returns the most-recent height (cm) recorded for this patient from ANY
  /// prior visit, or `null` when no prior height exists.
  Future<double?> lastRecordedHeight() async =>
      _assessmentRepo.lastRecordedHeight(
        _patientId,
        alsoId: await _localPatientId(),
      );

  /// Pre-seeds height and weight from the patient's most-recent prior ANC,
  /// NCD, or Cataract assessment when those fields are not yet filled in this
  /// visit. Called after [loadDraft] so a saved draft always wins over
  /// historical values. Height and weight are resolved independently (latest
  /// non-empty value for each field).
  ///
  /// When a prior height exists, the field is hard-locked (and hidden on
  /// NCD/cataract like ANC visit 2+) even if a draft already held the value.
  Future<void> preloadBiometrics() async {
    var changed = false;
    final alsoId = await _localPatientId();
    final priorHeight = await _assessmentRepo.lastRecordedHeight(
      _patientId,
      alsoId: alsoId,
    );
    if (priorHeight != null) {
      if (_data.getValue('height') == null) {
        _data = _data.setValue('height', priorHeight);
        changed = true;
      }
      if (!_heightLockedFromPrior) {
        _heightLockedFromPrior = true;
        changed = true;
      }
    }
    if (_data.getValue('weight') == null) {
      final w = await _assessmentRepo.lastRecordedWeight(
        _patientId,
        alsoId: alsoId,
      );
      if (w != null) {
        _data = _data.setValue('weight', w);
        changed = true;
      }
    }
    if (changed) {
      _recomputeBmi();
      notifyListeners();
    }
  }

  /// Pre-fills `pregnantWomanExistingIllness` and `pregnantWomanOnTreatment`
  /// from the most recent prior ANC assessment. Only seeds when the SK has not
  /// already entered a value (i.e., field is null in current data).
  Future<void> preloadAncMedicalHistory() async {
    if (_data.getValue('pregnantWomanExistingIllness') != null) return;
    final prior = await _assessmentRepo.lastAncIllnessData(
      _patientId,
      alsoId: await _localPatientId(),
    );
    if (prior == null) return;
    var changed = false;
    for (final entry in prior.entries) {
      if (_data.getValue(entry.key) == null) {
        _data = _data.setValue(entry.key, entry.value);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Pre-fills stable ANC obstetric history fields: previousPregnancyComplications,
  /// ttTdCompleted, facilityIdentifiedForDelivery.
  Future<void> preloadAncChronic() async {
    final prior = await _assessmentRepo.lastAncChronicData(
      _patientId,
      alsoId: await _localPatientId(),
    );
    if (prior == null) return;
    var changed = false;
    for (final entry in prior.entries) {
      if (_data.getValue(entry.key) == null) {
        _data = _data.setValue(entry.key, entry.value);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Prefill ANC/PW fields from the local pregnancy episode snapshot
  /// (Spice `PregnancyDetail` continuity). Does not overwrite SK-entered values.
  Future<void> preloadFromPregnancySnapshot() async {
    PregnancySnapshotRow? snap;
    try {
      snap = await _pregnancySnapshotForPatient();
    } catch (e) {
      debugPrint('[PregnancySnapshot] preload skipped: $e');
      return;
    }
    if (snap == null) return;

    var changed = false;
    void putIfEmpty(String key, dynamic value) {
      if (value == null) return;
      if (_data.getValue(key) != null) return;
      _data = _data.setValue(key, value);
      changed = true;
    }

    putIfEmpty('gravida', snap.gravida);
    putIfEmpty('parity', snap.parity);
    putIfEmpty('livingChildren', snap.livingChildren);
    putIfEmpty('ageOfLastChild', snap.ageOfLastChild);
    putIfEmpty('pregnancyTest', snap.pregnancyTest);
    putIfEmpty(
      'previousPregnancyComplications',
      PregnancySnapshotRow.decodeJsonList(snap.previousPregnancyComplications),
    );
    putIfEmpty(
      'pregnantWomanExistingIllness',
      PregnancySnapshotRow.decodeJsonList(snap.existingIllness),
    );
    putIfEmpty(
      'pregnantWomanOnTreatment',
      PregnancySnapshotRow.decodeJsonList(snap.onTreatment),
    );
    putIfEmpty('ttTdCompleted', snap.ttTdCompleted);
    putIfEmpty(
      'facilityIdentifiedForDelivery',
      snap.facilityIdentifiedForDelivery,
    );
    // Spice PregnancyDetail.ancWeight — prior ANC weight for visit 2+.
    // Fallback when assessment-history lookup missed the dual patient-id path.
    putIfEmpty('weight', snap.ancWeight);

    // Seed in-memory GA from snapshot LMP when not already set (same-page
    // LMP edit wins via _applyPwProfileLmpChange).
    if (_gestationalWeeks == null && snap.lmpDate != null) {
      _lmpDate = DateTime.fromMillisecondsSinceEpoch(snap.lmpDate!);
      if (snap.eddDate != null) {
        _eddDate = DateTime.fromMillisecondsSinceEpoch(snap.eddDate!);
      }
      _gestationalWeeks = snap.gestationalWeeksFromLmp;
      changed = true;
    }

    if (changed) {
      // Weight may have arrived from ancWeight after height prefill.
      _recomputeBmi();
      notifyListeners();
    }
  }

  /// Pre-fills stable NCD diagnosis/medication/lifestyle fields:
  /// isBeforeHtnDiagnosis, medicationFrequencyBp, isBeforeDiabetesDiagnosis,
  /// medicationFrequencyBg, isRegularSmoker.
  Future<void> preloadNcdChronic() async {
    if (_data.getValue('isBeforeHtnDiagnosis') != null) return;
    final prior = await _assessmentRepo.lastNcdChronicData(_patientId);
    if (prior == null) return;
    var changed = false;
    for (final entry in prior.entries) {
      if (_data.getValue(entry.key) == null) {
        _data = _data.setValue(entry.key, entry.value);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Pre-fills stable PNC Mother history fields: gravida, parity,
  /// livingChildren, and comorbidity/treatment flags.
  Future<void> preloadPncMotherChronic() async {
    if (_data.getValue('gravida') != null) return;
    final prior = await _assessmentRepo.lastPncMotherChronicData(_patientId);
    if (prior == null) return;
    var changed = false;
    for (final entry in prior.entries) {
      if (_data.getValue(entry.key) == null) {
        _data = _data.setValue(entry.key, entry.value);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Pre-fills stable Family Planning fields: familyPlanningMethods,
  /// desireForChildrenInFuture, numberOfLivingChildren.
  Future<void> preloadFpChronic() async {
    if (_data.getValue('familyPlanningMethods') != null) return;
    final prior = await _assessmentRepo.lastFpData(_patientId);
    if (prior == null) return;
    var changed = false;
    for (final entry in prior.entries) {
      if (_data.getValue(entry.key) == null) {
        _data = _data.setValue(entry.key, entry.value);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Marks the given field IDs as having validation errors and notifies
  /// listeners so the form can highlight them.
  void setValidationErrors(Set<String> errors) {
    _validationErrors = errors;
    notifyListeners();
  }

  /// Removes [fieldIds] from the canonical data — used right before submit
  /// to strip stale values for fields that are no longer visible (e.g. the
  /// SK entered Parity, then changed Gravida back to 1, hiding Parity).
  /// Without this, a value the SK can no longer see or edit would still be
  /// included in the submitted payload. See [FieldVisibilityRules] in
  /// unified_section_rules.dart — the caller (unified_form_screen.dart)
  /// computes which fields are currently hidden using the same rules the
  /// form itself renders with.
  void clearFields(Set<String> fieldIds) {
    if (fieldIds.isEmpty) return;
    _data = _data.removeFields(fieldIds);
    _saveDraft();
    notifyListeners();
  }

  /// Load existing draft from DB on screen init.
  ///
  /// Merges draft values ON TOP of any values already in [_data] (e.g. triage
  /// pre-fills seeded before this call).  This means the draft wins for any
  /// field it contains, but triage-derived defaults are preserved for fields
  /// not yet saved in the draft.
  Future<void> loadDraft() async {
    final row = await _draftDao.getDraft(_encounterId);
    if (row == null) return;
    try {
      final map = jsonDecode(row.fieldValues) as Map<String, dynamic>;
      _data = _data.merge(CanonicalVisitData(map));
      _restoreFieldSources(row.fieldSources);
      // Recompute EDD / GA from stored LMP (Android LMP callback parity).
      final draftLmp = _data.getValue('lmp');
      if (draftLmp != null) {
        _applyPwProfileLmpChange(draftLmp);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[UnifiedForm] draft parse error: $e');
    }
  }

  /// Android RMNCH summary auto-fills next follow-up; seed when empty so the
  /// SK does not enter it manually. Draft / SK edits always win.
  ///
  /// ANC (community): today + 28 days
  /// (`AssessmentRMNCHSummaryFragment.bindAncSummary`).
  /// PNC mother: bands from `daysSinceDelivery` when that field is set.
  void seedRmnchFollowUpIfNeeded() {
    final existing = _data.getValue('followUpVisit');
    if (existing != null && existing.toString().trim().isNotEmpty) return;

    DateTime? next;
    if (_activeFormTypes.contains('anc')) {
      next = RmnchFollowUpCalculator.ancCommunityDefault();
    } else if (_activeFormTypes.contains('pncMother')) {
      final days = int.tryParse(
        _data.getValue('daysSinceDelivery')?.toString() ?? '',
      );
      if (days != null) {
        next = RmnchFollowUpCalculator.pncFromDaysSinceDelivery(days);
      }
    }
    if (next == null) return;

    final iso = RmnchFollowUpCalculator.toFormDate(next);
    debugPrint('[FollowUp] auto-seed followUpVisit=$iso '
        '(forms=$_activeFormTypes)');
    _data = _data.setValue('followUpVisit', iso);
    notifyListeners();
    _saveDraft();
  }

  /// Restores AI-provenance marking persisted with the draft so restored
  /// AI-filled values are still visibly "AI-filled — verify" rather than
  /// indistinguishable from SK-typed entries.
  void _restoreFieldSources(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final sources = decoded['sources'] as Map<String, dynamic>? ?? const {};
      final segments = decoded['segments'] as Map<String, dynamic>? ?? const {};
      for (final entry in sources.entries) {
        final source = FieldSource.values
            .where((s) => s.name == entry.value)
            .firstOrNull;
        if (source != null) _fieldSources[entry.key] = source;
      }
      for (final entry in segments.entries) {
        _fieldSourceSegments[entry.key] = entry.value as String?;
      }
    } catch (e) {
      debugPrint('[UnifiedForm] field-sources parse error: $e');
    }
  }

  /// Load LMP and EDD for this ANC visit.
  ///
  /// Priority order:
  /// 1. Pregnancy snapshot (`lmp_date` / `edd_date`) written at sync / enroll
  ///    (patientId, then [memberId] if dates still missing).
  /// 2. Optional seed from VisitFlow (already resolved from the same snapshot).
  /// 3. LMP from server-synced past ANC assessments via
  ///    [AssessmentRepository.lmpDateFromHistory].
  /// 4. Nested-aware patient rawJson (bulk member DTO / pregnancyDetails).
  Future<void> loadPregnancyData({
    DateTime? seedLmp,
    DateTime? seedEdd,
    int? seedWeeks,
  }) async {
    try {
      DateTime? lmp;
      DateTime? edd;
      int? weeks;
      var source = 'none';

      // ── 1. Prefer pregnancy snapshot (stable per-patient store) ───────────
      final snap = await _pregnancySnapshotForPatient();
      debugPrint(
        '[LMP] load patient=$_patientId member=$_memberId snapshot='
        '${snap == null ? "missing" : "hit"} '
        'lmpMs=${snap?.lmpDate} eddMs=${snap?.eddDate}',
      );
      if (snap?.lmpDate != null) {
        lmp = DateTime.fromMillisecondsSinceEpoch(snap!.lmpDate!);
        weeks = DateTime.now().difference(lmp).inDays ~/ 7;
        source = 'snapshot.lmp';
      } else if (snap?.eddDate != null) {
        edd = DateTime.fromMillisecondsSinceEpoch(snap!.eddDate!);
        lmp = edd.subtract(const Duration(days: 280));
        weeks = DateTime.now().difference(lmp).inDays ~/ 7;
        source = 'snapshot.edd→lmp';
      }
      if (snap?.eddDate != null) {
        edd ??= DateTime.fromMillisecondsSinceEpoch(snap!.eddDate!);
      }

      // ── 2. Seed from VisitFlow (already resolved before Step 2 mounts) ───
      if (lmp == null && seedLmp != null) {
        lmp = seedLmp;
        weeks = DateTime.now().difference(lmp).inDays ~/ 7;
        source = 'visitFlow.seedLmp';
      }
      if (edd == null && seedEdd != null) {
        edd = seedEdd;
        if (lmp == null) {
          lmp = edd.subtract(const Duration(days: 280));
          weeks = DateTime.now().difference(lmp).inDays ~/ 7;
          source = 'visitFlow.seedEdd';
        }
      }
      if (lmp == null && seedWeeks != null && seedWeeks > 0) {
        weeks = seedWeeks;
        lmp = DateTime.now().subtract(Duration(days: seedWeeks * 7));
        source = 'visitFlow.seedWeeks';
      }

      // ── 3. Fallback: scan server-synced ANC assessment history ────────────
      if (lmp == null) {
        debugPrint('[LMP] load snapshot empty — trying assessment history');
        lmp = await _assessmentRepo.lmpDateFromHistory(_patientId);
        if (lmp != null) {
          weeks = DateTime.now().difference(lmp).inDays ~/ 7;
          source = 'assessmentHistory';
        }
      }

      // ── 4. Fallback: patient rawJson (flatten nested pregnancy DTOs) ─────
      if (lmp == null) {
        final patient = await _patientDao.byAnyId(_patientId);
        if (patient == null) {
          debugPrint('[LMP] load patient $_patientId not found in DB');
        }
        if (patient != null) {
          try {
            final json = jsonDecode(patient.rawJson) as Map<String, dynamic>;
            final flat = _flattenPregnancyRaw(json);
            debugPrint(
              '[LMP] load rawJson keys lmp=${flat['lmpDate']} '
              'lastMenstrualPeriod=${flat['lastMenstrualPeriod']} '
              'ga=${flat['gestationalWeeks'] ?? flat['gestationalAge']}',
            );
            lmp = JsonRead.firstDateTime(flat, const [
              'lmpDate',
              'lastMenstrualPeriod',
              'lastMenstrualPeriodDate',
              'lmp',
              'lmpValue',
              'menstrualDate',
              'lastPeriodDate',
            ]);
            if (lmp != null) {
              weeks = DateTime.now().difference(lmp).inDays ~/ 7;
              source = 'patient.rawJson';
            } else {
              for (final key in const [
                'gestationalWeeks',
                'gestationalAge',
                'gaWeeks',
                'weeksPregnant',
              ]) {
                final v = flat[key];
                int? w;
                if (v is int) w = v;
                if (v is num) w = v.toInt();
                if (v is String) w = int.tryParse(v);
                if (w != null && w > 0 && w < 45) {
                  weeks = w;
                  lmp = DateTime.now().subtract(Duration(days: w * 7));
                  source = 'patient.$key';
                  break;
                }
              }
            }
            edd ??= JsonRead.firstDateTime(flat, const [
              'estimatedDeliveryDate',
              'edd',
              'eddDate',
            ]);
          } catch (_) {}
        }
      }

      edd ??= lmp?.add(const Duration(days: 280));
      _lmpDate = lmp;
      _eddDate = edd;
      _gestationalWeeks = weeks;
      debugPrint(
        '[LMP] card data READY source=$source showLmp=${lmp != null} '
        'lmp=$lmp weeks=$weeks edd=$edd',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[LMP] load FAILED: $e');
    }
  }

  /// Flatten nested pregnancy DTOs so LMP/EDD keys are readable at top level.
  static Map<String, dynamic> _flattenPregnancyRaw(Map<String, dynamic> raw) {
    final flat = <String, dynamic>{...raw};
    for (final sub in const [
      'pregnancyDetails',
      'pregnancyDetail',
      'pwProfile',
      'pregnancyProfile',
      'obstetricHistory',
      'observations',
      'assessmentDetails',
      'pregnancyInfos',
    ]) {
      final nested = raw[sub];
      if (nested is Map) {
        for (final e in nested.entries) {
          flat.putIfAbsent(e.key.toString(), () => e.value);
        }
      } else if (nested is List) {
        for (final item in nested) {
          if (item is! Map) continue;
          for (final e in item.entries) {
            flat.putIfAbsent(e.key.toString(), () => e.value);
          }
        }
      }
    }
    return flat;
  }

  /// Update a single field and autosave draft.
  ///
  /// When `height` or `weight` changes, BMI is automatically recomputed and
  /// stored under the `bmi` field so the `_InfoLabelField` stays in sync.
  void updateField(String fieldId, dynamic value) {
    if (fieldId == 'height' && _isHeightLocked()) {
      debugPrint('[UnifiedForm] height locked — ignoring edit');
      return;
    }
    final valueType = value?.runtimeType ?? 'null';
    if (value is List) {
      ConsoleLog.step('[FormField] $fieldId (List[${value.length}]) = $value');
    } else {
      ConsoleLog.step('[FormField] $fieldId ($valueType) = $value');
    }
    _data = _data.setValue(fieldId, value);
    // SK edit of an AI-filled value → aiModified (audit trail keeps the AI
    // origin); any other SK entry → manual. Either way the field is now
    // SK-owned and later AI extractions must never overwrite it.
    _fieldSources[fieldId] =
        _fieldSources[fieldId] == FieldSource.aiPending
            ? FieldSource.aiModified
            : FieldSource.manual;
    if (fieldId == 'height' || fieldId == 'weight') {
      _recomputeBmi();
    }
    // Android AssessmentPregnantWomenRegistrationFragment: LMP drives EDD,
    // gestational week labels, and clears obstetric fields when too early.
    if (fieldId == 'lmp') {
      _applyPwProfileLmpChange(value);
    }
    // Android resets on-treatment when existing illness changes.
    if (fieldId == 'pregnantWomanExistingIllness') {
      _data = _data.setValue('pregnantWomanOnTreatment', null);
    }
    // PNC summary recalculates follow-up when days-since-delivery changes.
    if (fieldId == 'daysSinceDelivery' &&
        _activeFormTypes.contains('pncMother')) {
      final days = int.tryParse(value?.toString() ?? '');
      if (days != null) {
        final next = RmnchFollowUpCalculator.pncFromDaysSinceDelivery(days);
        _data = _data.setValue(
          'followUpVisit',
          RmnchFollowUpCalculator.toFormDate(next),
        );
      }
    }
    // Cross-programme BP sync: NCD uses `bpLogDetails` list; ANC/PNC use
    // flat systolic/diastolic/pulse. Keep both shapes aligned so filling
    // either widget updates the other (pulse already did this; sys/dia
    // were missing — SK reported only pulse mirrored).
    _mirrorBpAcrossProgrammes(fieldId, value);
    if (fieldId == 'liveBirthNumbers') {
      _resizeNewbornDetails(value);
    }
    if (fieldId == 'deliveryOutcomeType') {
      debugPrint(
          '[DeliveryOutcome] updateField deliveryOutcomeType=$value → notifyListeners');
      _resetPregnancyOutcomeBranches(value?.toString());
    }
    if (fieldId == 'timeOfDeath') {
      if (value?.toString() == 'beforeDelivery') {
        // Death before delivery hides the whole delivery-outcome branch.
        _clearPregnancyOutcomeFields(_deliveryOutcomeFieldIds);
        _data = _data.setValue('newbornDetails', null);
      } else {
        // Death during/after delivery re-opens delivery + baby cards.
        _resizeNewbornDetails(_data.getValue('liveBirthNumbers'));
      }
    }
    _clearHiddenDependents(fieldId);
    notifyListeners();
    _saveDraft();
  }

  /// Drops the values of every field this edit has just hidden, then cascades
  /// into their own dependents.
  ///
  /// Android `FormGenerator.setViewVisibility(resetValue = true)` calls
  /// `resetChildViews` whenever a `condition` hides a view, so a de-selected
  /// branch leaves nothing behind. Without this, switching Eye Test Outcome
  /// from Presbyopia to No Problem would hide the glasses chain but still
  /// submit the Glass Power / Type of Glass / Type of Frame answers.
  void _clearHiddenDependents(String driverId, [Set<String>? seen]) {
    final targets = _conditionTargets[driverId];
    if (targets == null) return;
    final visited = seen ?? <String>{driverId};
    for (final targetId in targets) {
      if (!visited.add(targetId)) continue;
      if (_visibleByConditionRules(targetId)) continue;
      if (_data.getValue(targetId) != null) {
        _data = _data.removeFields({targetId});
        _fieldSources.remove(targetId);
        _fieldSourceSegments.remove(targetId);
      }
      _clearHiddenDependents(targetId, visited);
    }
  }

  /// The `condition`-rule half of [FieldVisibilityRules.isFieldVisible].
  ///
  /// Fields with no rule targeting them are reported visible so the
  /// programme-specific gates evaluated in the widget layer (ANC gestational
  /// age, PW profile LMP, obstetric chain) are never second-guessed here —
  /// those hide fields without a de-selected driver to clear them.
  bool _visibleByConditionRules(String fieldId) {
    // The Gravida → Parity → Living Children → Age of Last Child chain is
    // resolved by its own branch in isFieldVisible, which runs *after* the
    // rules layer — reading the rules alone would under-report it as hidden.
    if (_fieldDefs[fieldId]?.compositeGroup == 'obstetricHistory') return true;
    final rules = _visibilityRules[fieldId];
    if (rules == null || rules.isEmpty) return true;
    for (final rule in rules) {
      if (rule.matches(_data.getValue(rule.driverId))) {
        return rule.visibility == 'visible';
      }
    }
    final anyDriverSet =
        rules.any((r) => _data.getValue(r.driverId) != null);
    if (anyDriverSet && rules.every((r) => r.visibility == 'visible')) {
      return false;
    }
    return _fieldDefs[fieldId]?.visibility != 'gone';
  }

  static const Set<String> _maternalDeathFieldIds = {
    'timeOfDeath',
    'gestationMonthAtDeath',
    'causeOfDeath',
  };

  static const Set<String> _abortionFieldIds = {
    'gestationMonthAtAbortion',
    'typeOfAbortion',
  };

  static const Set<String> _deliveryOutcomeFieldIds = {
    'deliveryOutcome',
    'liveBirthNumbers',
    'stillbirthNumbers',
    'placeOfDelivery',
    'dateOfDelivery',
    'modeOfDelivery',
    'birthAttendant',
    'anyComplicationsDuringDelivery',
    'complicationsDuringDelivery',
  };

  /// Android `AssessmentPregnancyOutcomeFragment` calls
  /// `formGenerator.resetChildViews` on every branch it hides. Values left
  /// behind by a de-selected branch keep driving their own `condition` rules —
  /// `gestationMonthAtAbortion >= 1` and `timeOfDeath == beforeDelivery` both
  /// declare every delivery-outcome field `gone` — so re-selecting "Delivery
  /// outcome" would render the section with no fields at all.
  void _resetPregnancyOutcomeBranches(String? outcome) {
    final stale = <String>{
      if (outcome != 'maternalDeath') ..._maternalDeathFieldIds,
      if (outcome != 'abortion') ..._abortionFieldIds,
      if (outcome == 'abortion') ..._deliveryOutcomeFieldIds,
    };
    _clearPregnancyOutcomeFields(stale);

    if (outcome == 'abortion') {
      _data = _data.setValue('newbornDetails', null);
    } else {
      _resizeNewbornDetails(_data.getValue('liveBirthNumbers'));
    }
  }

  void _clearPregnancyOutcomeFields(Set<String> fieldIds) {
    if (fieldIds.isEmpty) return;
    _data = _data.removeFields(fieldIds);
    for (final id in fieldIds) {
      _fieldSources.remove(id);
    }
  }

  /// Android `AssessmentPregnancyOutcomeFragment.updateBabySections` — keep
  /// `newbornDetails` list length in sync with `liveBirthNumbers` (max 4).
  static const int maxNewbornCards = 4;

  void _resizeNewbornDetails(dynamic rawCount) {
    final parsed = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString().trim() ?? '') ?? 0;
    final count = parsed.clamp(0, maxNewbornCards);

    final existingRaw = _data.getValue('newbornDetails');
    final existing = <Map<String, dynamic>>[];
    if (existingRaw is List) {
      for (final e in existingRaw) {
        if (e is Map) {
          existing.add(Map<String, dynamic>.from(e));
        }
      }
    }

    if (count == 0) {
      _data = _data.setValue('newbornDetails', null);
      return;
    }

    while (existing.length < count) {
      existing.add(<String, dynamic>{});
    }
    if (existing.length > count) {
      existing.removeRange(count, existing.length);
    }
    _data = _data.setValue('newbornDetails', existing);
  }

  /// Updates one baby entry inside `newbornDetails` and notifies listeners.
  void updateNewbornField(int babyIndex, String key, dynamic value) {
    final existingRaw = _data.getValue('newbornDetails');
    final list = <Map<String, dynamic>>[];
    if (existingRaw is List) {
      for (final e in existingRaw) {
        if (e is Map) {
          list.add(Map<String, dynamic>.from(e));
        }
      }
    }
    while (list.length <= babyIndex) {
      list.add(<String, dynamic>{});
    }
    final entry = Map<String, dynamic>.from(list[babyIndex]);
    if (value == null || (value is String && value.trim().isEmpty)) {
      entry.remove(key);
    } else {
      entry[key] = value;
    }
    // Spice clears cause when baby is marked alive.
    if (key == 'isBabyAlive' &&
        value?.toString().toLowerCase() == 'yes') {
      entry.remove('causeOfNeonatalDeath');
    }
    list[babyIndex] = entry;
    _data = _data.setValue('newbornDetails', list);
    notifyListeners();
    _saveDraft();
  }

  /// Keeps NCD `bpLogDetails` and ANC/PNC flat BP keys in sync.
  void _mirrorBpAcrossProgrammes(String fieldId, dynamic value) {
    const flatKeys = {'systolic', 'diastolic', 'pulse'};

    if (fieldId == 'bpLogDetails' && value is List && value.isNotEmpty) {
      final last = value.last;
      if (last is! Map) return;
      for (final key in flatKeys) {
        final v = last[key];
        if (v != null) _data = _data.setValue(key, v);
      }
      return;
    }

    if (!flatKeys.contains(fieldId)) return;

    final readings = _data.getValue('bpLogDetails');
    final List<dynamic> updated;
    final Map<String, dynamic> last;
    if (readings is List && readings.isNotEmpty) {
      updated = List<dynamic>.from(readings);
      last = Map<String, dynamic>.from(
        updated.last is Map ? updated.last as Map : const {},
      );
    } else {
      // Seed a reading so NCD's BP widget can show ANC/PNC entries.
      updated = <dynamic>[];
      last = <String, dynamic>{};
    }
    if (value == null) {
      last.remove(fieldId);
    } else {
      last[fieldId] = value;
    }
    // Drop empty seed rows (no sys/dia yet) — pulse-only still kept so NCD
    // can show a mirrored pulse before BP is entered.
    final hasSysDia = last['systolic'] != null || last['diastolic'] != null;
    final hasPulse = last['pulse'] != null;
    if (!hasSysDia && !hasPulse) {
      if (readings is List && readings.isNotEmpty) {
        updated[updated.length - 1] = last;
        _data = _data.setValue('bpLogDetails', updated);
      }
      return;
    }
    if (updated.isEmpty) {
      updated.add(last);
    } else {
      updated[updated.length - 1] = last;
    }
    _data = _data.setValue('bpLogDetails', updated);
  }

  void _recomputeBmi() {
    final h = _toDouble(_data.getValue('height'));
    final w = _toDouble(_data.getValue('weight'));
    if (h != null && h > 0 && w != null && w > 0) {
      final bmi = w / ((h / 100) * (h / 100));
      _data = _data.setValue('bmi', double.parse(bmi.toStringAsFixed(1)));
    }
  }

  static final _eddDisplayFormat = DateFormat('dd MMMM yyyy');

  /// Fields Android resets when LMP is cleared or is < 6 weeks ago.
  static const _pwLmpClearedFieldIds = {
    'EDD',
    'gestationalWeek',
    'pregnancyTest',
    'gravida',
    'parity',
    'livingChildren',
    'ageOfLastChild',
  };

  /// Mirrors Android LMP callback: compute EDD + GA when ≥ 42 days; otherwise
  /// clear the rest of the pregnancy-details fields (too-early path).
  ///
  /// Also updates [_gestationalWeeks] / [_lmpDate] / [_eddDate] so ANC
  /// show/hide on the same combined PW+ANC form reacts immediately.
  void _applyPwProfileLmpChange(dynamic value) {
    final raw = value?.toString();
    final lmp = (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);
    if (lmp == null) {
      _data = _data.removeFields(_pwLmpClearedFieldIds);
      _lmpDate = null;
      _eddDate = null;
      _gestationalWeeks = null;
      return;
    }

    final days = CalendarDay.daysBetween(lmp, DateTime.now());
    if (days < FieldVisibilityRules.lmpThresholdDays) {
      _data = _data.removeFields(_pwLmpClearedFieldIds);
      _lmpDate = lmp;
      _eddDate = null;
      _gestationalWeeks = null;
      return;
    }

    final edd = lmp.add(const Duration(days: 280));
    final weeks = days ~/ 7;
    final remDays = days % 7;
    _lmpDate = lmp;
    _eddDate = edd;
    _gestationalWeeks = weeks;
    _data = _data.setValue('EDD', _eddDisplayFormat.format(edd));
    // Android formatGestationalAge(Pair): "X weeks Y days "
    _data = _data.setValue(
      'gestationalWeek',
      '$weeks weeks $remDays days',
    );

    if (days > FieldVisibilityRules.pregnancyTestMaxGestationalDays) {
      _data = _data.setValue('pregnancyTest', null);
    }
  }

  static double? _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Merge AI Scribe pre-filled fields into canonical data.
  ///
  /// Legacy path (batch SOAP prefill). Skips SK-owned fields but performs no
  /// schema validation — prefer [applyAiPrefill] for realtime ASR fills.
  void applyScribePrefill(Map<String, dynamic> fields) {
    final accepted = <String, dynamic>{};
    for (final entry in fields.entries) {
      if (_isSkOwned(entry.key)) continue;
      accepted[entry.key] = entry.value;
      _fieldSources[entry.key] = FieldSource.aiPending;
    }
    if (accepted.isEmpty) return;
    _data = _data.merge(CanonicalVisitData(accepted));
    notifyListeners();
    _saveDraft();
  }

  /// Apply realtime-ASR extracted fields with validation + provenance.
  ///
  /// The safety gate between the AI service and the form:
  /// - **SK always wins** — fields whose source is `manual` or `aiModified`
  ///   are never overwritten (AI-over-AI refresh of `aiPending` is allowed:
  ///   a later extraction legitimately corrects an earlier one).
  /// - **Schema validation** — each value is checked against the canonical
  ///   [FieldDef] from `field_library.json` ([fieldDefs]); enum values must
  ///   match an `optionsList` id (display names are mapped to ids), numerics
  ///   must parse. Anything invalid is skipped and reported back.
  ///
  /// Returns human-readable descriptions of rejected fields so the banner
  /// can surface them as unmapped findings instead of dropping silently.
  List<String> applyAiPrefill(
    List<AIExtractedField> fields, {
    required Map<String, FieldDef> fieldDefs,
  }) {
    final rejected = <String>[];
    var appliedAny = false;

    debugPrint(
        '<==================== ASR FORM FILL: ${fields.length} field(s) '
        'incoming ====================>');

    for (final field in fields) {
      if (_isSkOwned(field.fieldId)) {
        debugPrint('<----- asr SKIPPED  [${field.fieldId}] SK-owned '
            '(${_fieldSources[field.fieldId]?.name}) — value "${field.value}" '
            'NOT applied ----->');
        continue;
      }

      final def = fieldDefs[field.fieldId];
      if (def == null) {
        debugPrint('<----- asr REJECTED [${field.fieldId}] unknown field — '
            'value "${field.value}" ----->');
        rejected.add('${field.fieldId}: unknown field');
        continue;
      }

      final validated = _validateAgainstDef(field.value, def);
      if (validated == null) {
        debugPrint('<----- asr REJECTED [${field.fieldId}] "${field.value}" '
            'failed ${def.widgetHint.name} validation '
            '(allowed: ${def.options.map((o) => o.id).join('/')}) ----->');
        rejected.add('${def.label}: "${field.value}" not a valid value');
        continue;
      }

      // Flicker guard: if this field was already set by AI from the same source
      // segment, the LLM is re-processing unchanged context — skip to prevent
      // urinaryAlbumin / urineProtein-style oscillation across rounds.
      final storedSegment = _fieldSourceSegments[field.fieldId];
      final incomingSegment = field.sourceSegment;
      if (_fieldSources[field.fieldId] == FieldSource.aiPending &&
          storedSegment != null &&
          incomingSegment != null &&
          storedSegment == incomingSegment &&
          _data.getValue(field.fieldId) != null) {
        continue;
      }

      final previous = _data.getValue(field.fieldId);
      _data = _data.setValue(field.fieldId, validated);
      _fieldSources[field.fieldId] = FieldSource.aiPending;
      _fieldSourceSegments[field.fieldId] = field.sourceSegment;
      appliedAny = true;
      debugPrint('<----- asr APPLIED  [${field.fieldId}] = $validated '
          '${previous == null ? '' : '(was: $previous) '}'
          'src="${field.sourceSegment ?? '-'}" ----->');
      if (field.fieldId == 'height' || field.fieldId == 'weight') {
        _recomputeBmi();
      }
      if (field.fieldId == 'lmp') {
        _applyPwProfileLmpChange(validated);
      }
      // The BP card renders from the flat systolic/diastolic/pulse keys,
      // not the bpLogDetails array (which the payload mapper consumes) —
      // mirror the latest reading so the fill is visible on-screen.
      if (field.fieldId == 'bpLogDetails' &&
          validated is List &&
          validated.isNotEmpty) {
        final last = validated.last as Map<String, dynamic>;
        for (final key in const ['systolic', 'diastolic', 'pulse']) {
          final v = last[key];
          if (v == null || _isSkOwned(key)) continue;
          _data = _data.setValue(key, v);
          _fieldSources[key] = FieldSource.aiPending;
          _fieldSourceSegments[key] = field.sourceSegment;
          debugPrint('<----- asr APPLIED  [$key] = $v '
              '(mirrored from bpLogDetails) ----->');
        }
      }
      // Inverse of the BP case: the ANC screen renders deliveryFacilityType
      // but the payload mapper reads facilityIdentifiedForDelivery (identical
      // option ids) — mirror so the submitted payload carries the value too.
      if (field.fieldId == 'deliveryFacilityType' &&
          !_isSkOwned('facilityIdentifiedForDelivery')) {
        _data = _data.setValue('facilityIdentifiedForDelivery', validated);
        _fieldSources['facilityIdentifiedForDelivery'] = FieldSource.aiPending;
        _fieldSourceSegments['facilityIdentifiedForDelivery'] =
            field.sourceSegment;
        debugPrint('<----- asr APPLIED  [facilityIdentifiedForDelivery] = '
            '$validated (mirrored from deliveryFacilityType) ----->');
      }
    }

    debugPrint('<==================== ASR FORM FILL done: '
        '${fields.length - rejected.length} applied, '
        '${rejected.length} rejected ====================>');
    _logAsrCoverage(fieldDefs);

    if (appliedAny) {
      notifyListeners();
      _saveDraft();
    }
    return rejected;
  }

  /// Widget kinds that carry a voice-fillable value — mirrors the server
  /// generator's skip rules (layout labels, computed BMI, date pickers and
  /// composite widgets are never ASR targets).
  static const Set<WidgetHint> _extractableHints = {
    WidgetHint.radioGroup,
    WidgetHint.dialogCheckbox,
    WidgetHint.spinner,
    WidgetHint.bloodGlucoseEntry,
    WidgetHint.numeric,
    WidgetHint.bpField,
  };

  /// Per-programme ASR coverage snapshot after each extraction:
  ///   <---- asr COVERAGE [anc]: 8/24 AI-filled · 2 manual · 14 empty ---->
  ///   <---- asr MISSING  [anc]: hemoglobin, fundalHeight, … ---->
  void _logAsrCoverage(Map<String, FieldDef> fieldDefs) {
    for (final programme in _activeFormTypes) {
      final targets = fieldDefs.values
          .where((d) =>
              d.programmeIds.contains(programme) &&
              _extractableHints.contains(d.widgetHint) &&
              d.id != 'bmi')
          .toList();
      if (targets.isEmpty) continue;

      final aiFilled = <String>[];
      final manual = <String>[];
      final empty = <String>[];
      for (final d in targets) {
        final hasValue = _data.getValue(d.id) != null;
        final source = _fieldSources[d.id];
        if (hasValue &&
            (source == FieldSource.aiPending ||
                source == FieldSource.aiModified)) {
          aiFilled.add(d.id);
        } else if (hasValue) {
          manual.add(d.id);
        } else {
          empty.add(d.id);
        }
      }
      debugPrint('<---- asr COVERAGE [$programme]: '
          '${aiFilled.length}/${targets.length} AI-filled · '
          '${manual.length} manual · ${empty.length} empty ---->');
      if (empty.isNotEmpty) {
        debugPrint('<---- asr MISSING  [$programme]: ${empty.join(', ')} ---->');
      }
    }
  }

  /// True when the SK typed or edited this field — AI must never overwrite.
  /// Also true for height locked from a prior visit / ANC visit 2+.
  bool _isSkOwned(String fieldId) {
    if (fieldId == 'height' && _isHeightLocked()) return true;
    final source = _fieldSources[fieldId];
    return source == FieldSource.manual || source == FieldSource.aiModified;
  }

  /// Validates and canonicalises [value] against [def].
  ///
  /// Returns the value to store, or null when invalid. Enum-backed widgets
  /// accept either the option id or its display name (mapped to the id —
  /// the server extracts display names for non-mnemonic ids like the PNC
  /// danger-sign codes "1".."8").
  dynamic _validateAgainstDef(dynamic value, FieldDef def) {
    if (value == null) return null;

    // Any option-backed field is enum-matched regardless of widget kind —
    // e.g. glucoseType renders as BloodGlucoseEntry but carries fbs/rbs
    // options that the widget matches by id.
    if (def.options.isNotEmpty && def.widgetHint != WidgetHint.bpField) {
      if (def.widgetHint == WidgetHint.dialogCheckbox || value is List) {
        final list = value is List ? value : [value];
        final matched = <String>[];
        for (final item in list) {
          final m = _matchOption(item, def.options);
          if (m == null) return null; // one bad entry invalidates the set
          matched.add(m);
        }
        return matched.isEmpty ? null : matched;
      }
      return _matchOption(value, def.options);
    }

    switch (def.widgetHint) {
      case WidgetHint.radioGroup:
      case WidgetHint.spinner:
        return _matchOption(value, def.options);
      case WidgetHint.dialogCheckbox:
        final list = value is List ? value : [value];
        final matched = <String>[];
        for (final item in list) {
          final m = _matchOption(item, def.options);
          if (m == null) return null; // one bad entry invalidates the set
          matched.add(m);
        }
        return matched.isEmpty ? null : matched;
      case WidgetHint.bpField:
        // Expect [{systolic, diastolic, pulse?}, ...] with numeric entries.
        if (value is! List || value.isEmpty) return null;
        final readings = <Map<String, dynamic>>[];
        for (final item in value) {
          if (item is! Map) return null;
          final systolic = _asNum(item['systolic']);
          final diastolic = _asNum(item['diastolic']);
          if (systolic == null && diastolic == null) return null;
          readings.add(<String, dynamic>{
            if (systolic != null) 'systolic': systolic,
            if (diastolic != null) 'diastolic': diastolic,
            if (_asNum(item['pulse']) != null) 'pulse': _asNum(item['pulse']),
          });
        }
        return readings;
      case WidgetHint.numeric:
      case WidgetHint.bloodGlucose:
      case WidgetHint.bloodGlucoseEntry:
        // Numeric when parseable; EditText also carries free text (notes).
        if (value is num) return value;
        if (value is String) return _asNum(value) ?? value;
        return null;
      default:
        // Layout-only or unsupported widgets never receive AI fills.
        return null;
    }
  }

  /// Matches [value] against option ids first, then display names → id.
  /// Also accepts bool / 1|0 aliases for Yes/No options (see [FieldOption.matchId]).
  static String? _matchOption(dynamic value, List<FieldOption> options) =>
      FieldOption.matchId(value, options);

  static num? _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  /// Decompose canonical data into per-programme payloads and save as
  /// [local_assessments] rows (sync_status=pending).
  ///
  /// Draft deletion is left to [_VisitFormScreenState._onSectionedSubmit] so it
  /// can extract vitals from [field_values] before deleting the draft row.
  ///
  /// Returns list of saved local IDs. Throws on DB error.
  Future<List<String>> submit() async {
    if (_submitting) {
      debugPrint('[SubmitBlocked] submit() ignored — a save is already running');
      return const [];
    }
    _submitting = true;
    _submitError = null;
    notifyListeners();

    try {
      // Spice: pregnancyDetail.ancVisitNo / pncVisitNo → next visit number
      // stamped onto the payload before save, then written back.
      int? assignedAncVisitNo;
      if (_activeFormTypes.contains('anc') &&
          _data.getValue('ancVisitNumber') == null &&
          _data.getValue('visitNo') == null) {
        assignedAncVisitNo = await _pregnancySnapshotDao
            .nextAncVisitNo(_patientId, memberId: _memberId);
        _data = _data.setValue('ancVisitNumber', assignedAncVisitNo);
        debugPrint(
            '[AncVisitNo] assigned visitNo=$assignedAncVisitNo '
            'patient=$_patientId');
      }

      final willEmitPnc = _activeFormTypes.contains('pncMother') &&
          (!_activeFormTypes.contains('pregnancyOutcome') ||
              _data.getValue('deliveryOutcomeType')?.toString() == 'liveBirth');
      int? assignedPncVisitNo;
      if (willEmitPnc && _data.getValue('pncVisitNumber') == null) {
        assignedPncVisitNo = await _pregnancySnapshotDao
            .nextPncVisitNo(_patientId, memberId: _memberId);
        _data = _data.setValue('pncVisitNumber', assignedPncVisitNo);
        debugPrint(
            '[PncVisitNo] assigned visitNo=$assignedPncVisitNo '
            'patient=$_patientId');
      }

      // BD NCD: first visit uses threshold referral; follow-up uses color band.
      // Facility type is "Community Clinic" / "Upazila Health Complex" — never
      // the org FHIR id (that belongs in summary.referredSiteId for CC only).
      final isNcdFollowUp = (_activeFormTypes.contains('ncd') ||
              (_activeFormTypes.contains('cataract') &&
                  _data.getValue('ncdServiceProvided')
                          ?.toString()
                          .toLowerCase() ==
                      'yes'))
          ? await _assessmentRepo.hasPriorNcdAssessment(_patientId)
          : false;

      final (isReferred, referredReasons) =
          _computeReferral(isNcdFollowUp: isNcdFollowUp);

      Map<String, dynamic>? ncdOtherDetails;
      final cataractNcdProvided = _activeFormTypes.contains('cataract') &&
          _data.getValue('ncdServiceProvided')?.toString().toLowerCase() ==
              'yes';
      if ((_activeFormTypes.contains('ncd') || cataractNcdProvided) &&
          isReferred) {
        final avg = UnifiedPayloadMapper.ncdAvgBp(_data);
        final glVal = _asDoubleField('glucoseValue') ??
            _asDoubleField('glucose') ??
            _asDoubleField('fastingBloodSugar') ??
            _asDoubleField('randomBloodSugar');
        final facilityType = NcdStatus.resolveFacilityType(
          isFollowUpVisit: isNcdFollowUp,
          referredReasons: referredReasons,
          avgSystolic: avg.systolic,
          avgDiastolic: avg.diastolic,
          glucoseMmol: glVal,
        );
        _data = _data.setValue('referralFacilityType', facilityType);
        ncdOtherDetails = NcdStatus.referredSummary(
          referralFacilityType: facilityType,
          referredSiteId: _defaultReferralSiteId,
        );
      }

      // Spice BDEyeCareAssessmentSummaryFragment stamps the reporting
      // organisation onto every eye care assessment, referred or not.
      final eyeCareOtherDetails = _defaultReferralSiteId?.isNotEmpty == true
          ? {'referredSite': _defaultReferralSiteId}
          : null;

      // Childhood visit: Spice stamps summary.nextVisitDate from birth + age
      // band (AssessmentViewModel, ChildHood_Visit menu).
      Map<String, dynamic>? childhoodOtherDetails;
      if (_activeFormTypes.contains('pncChild')) {
        if (_data.getValue('childVisitNumber') == null) {
          // Spice pregnancyDetail.childVisitNo + 1 → pncChild.visitNo.
          final prior =
              await _assessmentRepo.priorChildhoodVisitCount(_patientId);
          _data = _data.setValue('childVisitNumber', prior + 1);
          debugPrint('[ChildVisitNo] assigned visitNo=${prior + 1} '
              'patient=$_patientId');
        }
        final dob = await _patientDateOfBirth();
        if (dob != null) {
          final months = ChildhoodVisit.ageInMonths(dob);
          if (months <= ChildhoodVisit.maxVisitMonth) {
            final next = ChildhoodVisit.nextVisitDate(
              ageInMonths: months,
              birthDate: dob,
            );
            if (next != null) {
              childhoodOtherDetails = {
                'nextVisitDate': ChildhoodVisit.formatNextVisitDate(next),
              };
            }
          }
        }
      }

      final payloads = UnifiedPayloadMapper.decompose(
        _withWireOptionValues(_data),
        _activeFormTypes.toSet(),
      );
      if (payloads.isEmpty) {
        debugPrint(
            '[SubmitBlocked] no assessment payloads produced for form types '
            '${_activeFormTypes.toList()} — nothing will be saved or synced');
      }

      _lastIsReferred = isReferred;
      _lastReferredReasons = referredReasons;
      _lastReferralFacility = _data.getValue('referralFacility') as String? ??
          _data.getValue('referralFacilityType') as String?;
      ConsoleLog.step('[ReferralFacility] form submit — referralFacility=${_data.getValue('referralFacility')} referralFacilityType=${_data.getValue('referralFacilityType')} → _lastReferralFacility=$_lastReferralFacility');

      final savedIds = <String>[];
      final pwStatus = payloads.any((p) => p.assessmentType == 'PWPROFILE')
          ? PwRiskFactors.status(
              pregnancyHistory: payloads
                  .firstWhere((p) => p.assessmentType == 'PWPROFILE')
                  .details,
              dateOfBirth: await _patientDateOfBirth(),
            )
          : null;
      final poStatus = payloads.any((p) =>
              p.assessmentType == 'PREGNANCY_OUTCOME' ||
              p.assessmentType == 'PREGNANCYOUTCOME')
          ? PregnancyOutcomeStatus.status(
              payloads
                  .firstWhere((p) =>
                      p.assessmentType == 'PREGNANCY_OUTCOME' ||
                      p.assessmentType == 'PREGNANCYOUTCOME')
                  .details,
            )
          : null;
      // Spice's NCD branch appends the eye problem / glasses tokens after the
      // BP/BG ones, dropping NO_EYE_PROBLEM so a clean eye check doesn't
      // dilute the NCD statuses.
      final ncdStatus = payloads.any((p) => p.assessmentType == 'NCD')
          ? [
              ...NcdStatus.status(
                isReferred: isReferred,
                referredReasons: referredReasons,
              ),
              ...EyeCareStatus.status(
                _eyeCareCardOf(payloads, 'NCD'),
                skipNoProblem: true,
              ),
            ]
          : null;
      final eyeCareStatus = payloads.any((p) => p.assessmentType == 'EYE_CARE')
          ? EyeCareStatus.status(_eyeCareCardOf(payloads, 'EYE_CARE'))
          : null;
      final cataractStatus = payloads.any((p) => p.assessmentType == 'CATARACT')
          ? CataractStatus.status(
              _cataractCardOf(payloads),
              referredReasons: referredReasons,
            )
          : null;
      final ancStatus = payloads.any((p) => p.assessmentType == 'ANC')
          ? AncStatus.status(
              payloads.firstWhere((p) => p.assessmentType == 'ANC').details,
            )
          : null;

      // One pregnancy episode across PO + PNC assessments in the same visit.
      final sharedPregnancyEpisodeId = _pregnancyEpisodeId ??
          (payloads.any((p) {
            final t = p.assessmentType.toUpperCase();
            return t == 'PREGNANCY_OUTCOME' ||
                t == 'PREGNANCYOUTCOME' ||
                t == 'PNC_MOTHER' ||
                t == 'PNC_NEONATE' ||
                t == 'PNC_CHILD' ||
                t == 'ANC' ||
                t == 'PWPROFILE';
          })
              ? const Uuid().v4()
              : null);

      for (final payload in payloads) {
        ConsoleLog.banner(
          '[PayloadDebug] submit — ${payload.assessmentType} payload:\n'
          '${const JsonEncoder.withIndent("  ").convert(payload.details)}',
        );
        final id = await _assessmentRepo.saveAssessment(
          assessmentType: payload.assessmentType,
          assessmentDetails: payload.details,
          householdMemberLocalId: _householdMemberLocalId,
          memberId: _memberId,
          householdId: _householdId,
          patientId: _patientId,
          villageId: _villageId,
          encounterId: _encounterId,
          isReferred: isReferred,
          referredReasons: referredReasons.isEmpty ? null : referredReasons,
          customStatus: payload.assessmentType == 'PWPROFILE'
              ? pwStatus
              : (payload.assessmentType == 'PREGNANCY_OUTCOME' ||
                      payload.assessmentType == 'PREGNANCYOUTCOME')
                  ? (poStatus == null || poStatus.isEmpty ? null : poStatus)
                  : payload.assessmentType == 'NCD'
                      ? (ncdStatus == null || ncdStatus.isEmpty
                          ? null
                          : ncdStatus)
                      : payload.assessmentType == 'ANC'
                          ? ancStatus
                          : payload.assessmentType == 'EYE_CARE'
                              ? (eyeCareStatus == null || eyeCareStatus.isEmpty
                                  ? null
                                  : eyeCareStatus)
                              : payload.assessmentType == 'CATARACT'
                                  ? (cataractStatus == null ||
                                          cataractStatus.isEmpty
                                      ? null
                                      : cataractStatus)
                                  : null,
          pregnancyEpisodeId: sharedPregnancyEpisodeId,
          otherDetails: switch (payload.assessmentType) {
            'NCD' => ncdOtherDetails,
            'CATARACT' => cataractNcdProvided ? ncdOtherDetails : null,
            'EYE_CARE' => eyeCareOtherDetails,
            'CHILDHOOD_VISIT' => childhoodOtherDetails,
            _ => null,
          },
        );
        savedIds.add(id);
      }

      // Persist completed ANC / PNC counts (Spice PregnancyDetail.*VisitNo)
      // and merge episode clinical fields captured on this visit.
      try {
        await _persistPregnancyEpisodeAfterSubmit(
          payloads: payloads,
          assignedAncVisitNo: assignedAncVisitNo,
          assignedPncVisitNo: assignedPncVisitNo,
        );
      } catch (e) {
        debugPrint('[PregnancySnapshot] persist after submit skipped: $e');
      }

      // CCE: bridge referred assessments into the local referrals table so
      // the dashboard bell / drawer see the case without waiting for sync.
      if (isReferred && savedIds.isNotEmpty) {
        await _ensureLocalReferral(
          assessmentId: savedIds.first,
          reasons: referredReasons,
          assessmentType: payloads.isNotEmpty
              ? payloads.first.assessmentType
              : null,
        );
      }
      return savedIds;
    } catch (e) {
      _submitError = e.toString();
      rethrow;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  static int? _asPositiveInt(Object? raw) {
    final n = switch (raw) {
      final int v => v,
      final num v => v.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (n == null || n <= 0) return null;
    return n;
  }

  /// Write PW + ANC episode fields back to the local pregnancy snapshot
  /// (Spice `savePregnancyDetails` / `saveAncPregnancyDetails`).
  Future<void> _persistPregnancyEpisodeAfterSubmit({
    required List<ProgrammePayload> payloads,
    int? assignedAncVisitNo,
    int? assignedPncVisitNo,
  }) async {
    final types = payloads.map((p) => p.assessmentType.toUpperCase()).toSet();
    final hasPw = types.contains('PWPROFILE') ||
        types.contains('PW') ||
        _activeFormTypes.contains('pwProfile');
    final hasAnc = types.contains('ANC');
    final hasPnc = types.contains('PNC_MOTHER');

    if (!hasPw && !hasAnc && !hasPnc) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    int? ancNo;
    if (hasAnc) {
      ancNo = _asPositiveInt(
        assignedAncVisitNo ??
            _data.getValue('ancVisitNumber') ??
            _data.getValue('visitNo'),
      );
    }
    int? pncNo;
    if (hasPnc) {
      pncNo = _asPositiveInt(
        assignedPncVisitNo ?? _data.getValue('pncVisitNumber'),
      );
    }

    // Prefer in-memory LMP/EDD from this session; fall back to form LMP.
    int? lmpMs = _lmpDate?.millisecondsSinceEpoch;
    int? eddMs = _eddDate?.millisecondsSinceEpoch;
    if (lmpMs == null) {
      final raw = _data.getValue('lmp')?.toString();
      final parsed = raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
      if (parsed != null) {
        lmpMs = parsed.millisecondsSinceEpoch;
        eddMs ??= parsed.add(const Duration(days: 280)).millisecondsSinceEpoch;
      }
    }

    final weight = PregnancySnapshotRow.asDouble(_data.getValue('weight'));

    final localId = await _localPatientId();
    final patch = PregnancySnapshotRow(
      patientId: localId,
      facts: PregnancyFacts.empty,
      updatedAt: nowMs,
      lmpDate: hasPw || hasAnc ? lmpMs : null,
      eddDate: hasPw || hasAnc ? eddMs : null,
      ancVisitNo: ancNo,
      pncVisitNo: pncNo,
      gravida: hasPw || hasAnc
          ? PregnancySnapshotRow.asInt(_data.getValue('gravida'))
          : null,
      parity: hasPw || hasAnc
          ? PregnancySnapshotRow.asInt(_data.getValue('parity'))
          : null,
      livingChildren: hasPw || hasAnc
          ? PregnancySnapshotRow.asInt(_data.getValue('livingChildren'))
          : null,
      ageOfLastChild: hasPw || hasAnc
          ? _data.getValue('ageOfLastChild')?.toString()
          : null,
      pregnancyTest: hasPw ? _data.getValue('pregnancyTest')?.toString() : null,
      previousPregnancyComplications: hasAnc
          ? PregnancySnapshotRow.encodeJsonList(
              _data.getValue('previousPregnancyComplications'),
            )
          : null,
      existingIllness: hasAnc
          ? PregnancySnapshotRow.encodeJsonList(
              _data.getValue('pregnantWomanExistingIllness'),
            )
          : null,
      onTreatment: hasAnc
          ? PregnancySnapshotRow.encodeJsonList(
              _data.getValue('pregnantWomanOnTreatment'),
            )
          : null,
      ttTdCompleted:
          hasAnc ? _data.getValue('ttTdCompleted')?.toString() : null,
      facilityIdentifiedForDelivery: hasAnc
          ? _data.getValue('facilityIdentifiedForDelivery')?.toString()
          : null,
      ancWeight: hasAnc ? weight : null,
      lastAncVisitDateMs: hasAnc ? nowMs : null,
    );

    // Preserve existing mission facts when we only have empty defaults here.
    final existing = await _pregnancySnapshotDao.byPatientOrMember(
      localId,
      memberId: _memberId,
    );
    final withFacts = existing == null
        ? patch
        : patch.copyWith(facts: existing.facts);
    await _pregnancySnapshotDao.mergeUpsert(withFacts);
    if (ancNo != null) {
      debugPrint('[AncVisitNo] persisted ancVisitNo=$ancNo patient=$localId');
    }
    if (pncNo != null) {
      debugPrint('[PncVisitNo] persisted pncVisitNo=$pncNo patient=$localId');
    }
  }

  /// The `eyeCare` card body of a programme payload — the standalone eye care
  /// details and the NCD details both nest it under the same key.
  static Map<String, dynamic>? _eyeCareCardOf(
    List<ProgrammePayload> payloads,
    String assessmentType,
  ) {
    for (final payload in payloads) {
      if (payload.assessmentType != assessmentType) continue;
      final card = payload.details['eyeCare'];
      if (card is Map<String, dynamic>) return card;
    }
    return null;
  }

  /// Inner Eye Problems card from a CATARACT programme payload
  /// (`details.cataract` before the outer menu wrap is applied at sync).
  static Map<String, dynamic>? _cataractCardOf(
    List<ProgrammePayload> payloads,
  ) {
    for (final payload in payloads) {
      if (payload.assessmentType != 'CATARACT') continue;
      final card = payload.details['cataract'];
      if (card is Map<String, dynamic>) return card;
    }
    return null;
  }

  /// Multi-select fields Spice sends as option `value` codes (e.g.
  /// `"shortnessOfBreath"`) rather than the numeric option ids the widgets
  /// store. Translation happens only on the way to the payload so form
  /// visibility rules keyed on option ids/names keep working.
  static const Set<String> _wireOptionValueFields = {'ncdSymptoms'};

  CanonicalVisitData _withWireOptionValues(CanonicalVisitData data) {
    var out = data;
    for (final fieldId in _wireOptionValueFields) {
      final raw = data.getValue(fieldId);
      if (raw is! List || raw.isEmpty) continue;
      final options = _fieldDefs[fieldId]?.options ?? const <FieldOption>[];
      if (options.isEmpty) continue;
      final mapped = raw.map((entry) {
        final id = FieldOption.coerceId(entry);
        for (final option in options) {
          if (option.id == id) return option.wireValue;
        }
        return entry;
      }).toList();
      out = out.setValue(fieldId, mapped);
    }
    return out;
  }

  /// Non-empty NCD symptom ids/names for referral (Spice getSymptomsList).
  static List<String> _ncdSymptomIds(Object? raw) {
    if (raw is! List || raw.isEmpty) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is Map) {
        final name = item['name']?.toString() ?? item['id']?.toString();
        if (name != null && name.isNotEmpty) out.add(name);
      } else {
        final s = item.toString().trim();
        if (s.isNotEmpty &&
            s.toLowerCase() != 'none' &&
            s.toLowerCase() != 'nosymptoms') {
          out.add(s);
        }
      }
    }
    return out;
  }

  /// Local `patients.id` for [_patientId]. Snapshot + programmes are keyed by
  /// the member PK; the visit route often carries `members.patient_id`.
  Future<String> _localPatientId() async {
    if (_patientId.isEmpty) return _patientId;
    try {
      final patient = await _patientDao.byAnyId(_patientId);
      return patient?.id ?? _patientId;
    } catch (_) {
      return _patientId;
    }
  }

  /// Pregnancy snapshot under the local PK, with memberId as a secondary key.
  Future<PregnancySnapshotRow?> pregnancySnapshot() =>
      _pregnancySnapshotForPatient();

  /// Pregnancy snapshot under the local PK, with memberId as a secondary key.
  Future<PregnancySnapshotRow?> _pregnancySnapshotForPatient() async {
    final localId = await _localPatientId();
    return _pregnancySnapshotDao.byPatientOrMember(
      localId,
      memberId: _memberId,
    );
  }

  /// Member DOB for the PW age-risk rules. Falls back to the stored age when
  /// no birth date was synced; returns null when neither is known, which makes
  /// [PwRiskFactors] skip the age rules rather than guess.
  Future<DateTime?> _patientDateOfBirth() async {
    if (_patientId.isEmpty) return null;
    try {
      final patient = await _patientDao.byAnyId(_patientId);
      if (patient == null) return null;
      final dob = patient.dob;
      if (dob != null && dob.isNotEmpty) {
        final parsed = DateTime.tryParse(dob);
        if (parsed != null) return parsed;
      }
      final age = patient.age;
      if (age != null && age > 0) {
        final now = DateTime.now();
        return DateTime(now.year - age, now.month, now.day);
      }
    } catch (e) {
      debugPrint('[UnifiedForm] DOB lookup failed: $e');
    }
    return null;
  }

  /// Creates a local [Referral] for CCE when this visit was referred.
  /// Idempotent on `ref-assess-{assessmentId}` so re-submit does not duplicate.
  Future<void> _ensureLocalReferral({
    required String assessmentId,
    required List<String> reasons,
    String? assessmentType,
  }) async {
    final repo = _referralRepo;
    if (repo == null || _patientId.isEmpty) return;
    final referralId = 'ref-assess-$assessmentId';
    try {
      final existing = await repo.byId(referralId);
      if (existing != null) return;
      final label = reasons.where((r) => r.trim().isNotEmpty).join(', ');
      await repo.create(
        id: referralId,
        patientId: _patientId,
        slaTier: SlaTier.inferFromReason(label.isEmpty ? null : label),
        householdId: _householdId,
        villageId: _villageId,
        diagnosisCode: assessmentType,
        diagnosisLabel: label.isEmpty ? null : label,
        facilityName: _lastReferralFacility,
      );
      debugPrint(
        '[Referral] CCE local create id=$referralId reasons=$label',
      );
    } catch (e) {
      // Non-fatal — assessment is already saved; CCE can catch up on next sync.
      debugPrint('[Referral] CCE local create failed: $e');
    }
  }

  double? _asDoubleField(String k) {
    final v = _data.getValue(k);
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Runs clinical evaluators against current form data and returns
  /// `(isReferred, referredReasons)`.  Called inside [submit] so every
  /// saved [LocalAssessmentEntity] carries the correct referral flag.
  (bool, List<String>) _computeReferral({bool isNcdFollowUp = false}) {
    bool referred = false;
    final reasons = <String>[];

    double? asDouble(String k) => _asDoubleField(k);

    // The `temperature` field is captured in °F (field_library.json
    // `unitMeasurement: "°F"`), but every referral evaluator's fever
    // thresholds are in °C — convert before evaluating, or a normal 98.6°F
    // reading (>= 38.9 raw) reads as a false high fever on every visit.
    double? temperatureCelsius() {
      final f = asDouble('temperature');
      return f == null ? null : fahrenheitToCelsius(f);
    }

    final avgBp = UnifiedPayloadMapper.ncdAvgBp(_data);
    final sys = avgBp.systolic?.toDouble() ??
        asDouble('systolic') ??
        asDouble('bloodPressureSystolic');
    final dia = avgBp.diastolic?.toDouble() ??
        asDouble('diastolic') ??
        asDouble('bloodPressureDiastolic');
    final glucoseType = _data.getValue('glucoseType') as String?;
    final glVal = asDouble('glucoseValue') ??
        asDouble('glucose') ??
        asDouble('fastingBloodSugar') ??
        asDouble('randomBloodSugar');
    final isFbs = glucoseType == 'fbs';

    debugPrint('[Referral] inputs: sys=$sys dia=$dia glVal=$glVal glucoseType=$glucoseType isFbs=$isFbs activeTypes=$_activeFormTypes');

    if (_activeFormTypes.contains('ncd') ||
        (_activeFormTypes.contains('cataract') &&
            _data.getValue('ncdServiceProvided')?.toString().toLowerCase() ==
                'yes')) {
      final symptoms = _ncdSymptomIds(_data.getValue('ncdSymptoms'));
      final result = NcdReferralEvaluator.evaluateBdNcd(
        isFollowUpVisit: isNcdFollowUp,
        useNcdRiskAlgorithm: isNcdFollowUp,
        systolic: sys,
        diastolic: dia,
        glucoseMmol: glVal,
        glucoseType: glucoseType,
        hba1cPercent: asDouble('hba1c'),
        symptoms: symptoms,
      );
      debugPrint(
          '[Referral][NCD] followUp=$isNcdFollowUp required=${result.isReferralRequired} '
          'reasons=${result.referralReasons}');
      if (result.isReferralRequired) {
        referred = true;
        reasons.addAll(result.referralReasons);
      }
    }

    if (_activeFormTypes.contains('anc')) {
      // Spice calculateRMNCHReferralResult: refer when summary has high-risk
      // and/or gaps; referredReasons use LABEL_* + " - ANC Visit N".
      final ancAssessment = AncAssessment(
        medicalHistoryPhysicalExamination: MedicalHistoryPhysicalExamination(
          bloodPressureSystolic: sys?.toInt(),
          bloodPressureDiastolic: dia?.toInt(),
          fundalHeight: asDouble('fundalHeight'),
          oedema: (_data.getValue('oedema') ??
              _data.getValue('edema')) as String?,
          weight: asDouble('weight'),
          height: asDouble('height'),
        ),
        pointOfCareInvestigations: PointOfCareInvestigations(
          hemoglobin: asDouble('hemoglobin'),
          urinaryAlbumin: _data.getValue('urinaryAlbumin') as String?,
          urinaryBilirubin: _data.getValue('urinaryBilirubin') as String?,
          urinarySugar: _data.getValue('urinarySugar') as String?,
          bloodSugarFasting: isFbs ? glVal : null,
          bloodSugarRandom: !isFbs ? glVal : null,
        ),
        dangerSignsRiskIdentification: DangerSignsRiskIdentification(
          dangerSignsExperienced12:
              (_data.getValue('dangerSignsExperienced12') as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
          dangerSignsExperienced13To27:
              (_data.getValue('dangerSignsExperienced13To27') as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
          dangerSignsExperienced28To40:
              (_data.getValue('dangerSignsExperienced28To40') as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
        ),
        gestationalWeeks: asDouble('gestationalAge')?.toInt() ??
            asDouble('gestationalWeeks')?.toInt(),
      );
      final result = AncReferralEvaluator.evaluate(
        ancAssessment,
        temperatureCelsius: temperatureCelsius(),
        pulseBpm: asDouble('pulse')?.toInt(),
      );
      final gaps = AncReferralEvaluator.evaluateGaps(
        gestationalAgeWeeks:
            asDouble('gestationalAge') ?? asDouble('gestationalWeeks'),
        ttTdCompleted: _data.getValue('ttTdCompleted') as String?,
        ultrasound: _data.getValue('ultrasound') as String?,
        ancFromMedicalDoctor: _data.getValue('ancFromMedicalDoctor') as String?,
        facilityIdentifiedForDelivery:
            _data.getValue('facilityIdentifiedForDelivery') as String?,
        ifaTotalConsumed: asDouble('ifaTotalConsumed')?.toInt() ??
            asDouble('ifaTabletsConsumed')?.toInt(),
        calciumTotalConsumed: asDouble('calciumTotalConsumed')?.toInt() ??
            asDouble('calciumTabletsConsumed')?.toInt(),
        ancVisitCount: asDouble('ancVisitNumber')?.toInt() ??
            asDouble('visitNo')?.toInt(),
      );
      final hasHighRisk = result.isReferralRequired;
      final hasGaps = gaps.hasGaps;
      debugPrint(
          '[Referral][ANC] highRisk=$hasHighRisk gaps=$hasGaps '
          'emergency=${result.emergencyConditions} '
          'nonEmergency=${result.nonEmergencyConditions} gapsList=${gaps.gaps}');
      if (hasHighRisk || hasGaps) referred = true;
      reasons.addAll(
        AncStatus.referredReasons(
          hasHighRisk: hasHighRisk,
          hasGaps: hasGaps,
          visitNo: _data.getValue('ancVisitNumber') ?? _data.getValue('visitNo'),
        ),
      );
    }

    if (_activeFormTypes.contains('pncMother')) {
      final result = PncReferralEvaluator.evaluate(
        systolic: sys,
        diastolic: dia,
        temperatureCelsius: temperatureCelsius(),
        pulseBpm: asDouble('pulse')?.toInt(),
        hemoglobinGdL: asDouble('hemoglobin'),
        fastingGlucoseMmol: isFbs ? glVal : null,
        randomGlucoseMmol: !isFbs ? glVal : null,
        urinaryAlbumin: _data.getValue('urinaryAlbumin') as String?,
        edema: (_data.getValue('oedema') ??
            _data.getValue('edema')) as String?,
      );
      debugPrint('[Referral][PNC] required=${result.isReferralRequired}  urgent=${result.urgentConditions}  nonUrgent=${result.nonUrgentConditions}');
      if (result.isReferralRequired) {
        referred = true;
        reasons.addAll([
          ...result.urgentConditions,
          ...result.nonUrgentConditions,
        ]);
      }
    }

    // Childhood visit: SK-selected childReferral (Spice anyIllness → referral).
    if (_activeFormTypes.contains('pncChild')) {
      final childRef = _data.getValue('childReferral')?.toString().toLowerCase();
      if (childRef == 'yes') {
        referred = true;
        reasons.add('Child illness referral');
      }
    }

    debugPrint('[Referral] RESULT: isReferred=$referred  reasons=$reasons');
    return (referred, List<String>.unmodifiable(reasons));
  }

  /// Debounced — schedules [_persistDraftNow], coalescing rapid keystrokes
  /// into a single DB write. See [_saveDraftTimer].
  void _saveDraft() {
    _saveDraftTimer?.cancel();
    _saveDraftTimer = Timer(const Duration(milliseconds: 400), _persistDraftNow);
  }

  void _persistDraftNow() {
    _saveDraftTimer = null;
    final row = AssessmentDraftRow(
      encounterId: _encounterId,
      patientId: _patientId,
      memberId: _memberId,
      activatedProgrammes: jsonEncode(_activeFormTypes),
      fieldValues: jsonEncode(_data.values),
      sectionStatus: '{}',
      fieldSources: jsonEncode({
        'sources': _fieldSources.map((k, v) => MapEntry(k, v.name)),
        'segments': _fieldSourceSegments,
      }),
    );
    _draftDao.saveDraft(row).catchError((e) {
      debugPrint('[UnifiedForm] autosave error: $e');
    });
  }

  @override
  void dispose() {
    // Flush any pending debounced save so the last keystroke before
    // navigating away isn't lost — don't just cancel it.
    if (_saveDraftTimer != null) {
      _saveDraftTimer!.cancel();
      _persistDraftNow();
    }
    super.dispose();
  }
}
