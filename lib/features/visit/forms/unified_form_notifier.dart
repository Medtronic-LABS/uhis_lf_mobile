import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/clinical/assessment_thresholds.dart';
import '../../../core/clinical/referral_evaluator.dart';
import '../../../core/db/local_assessment_dao.dart';
import '../../../core/db/patient_dao.dart';
import '../../../core/db/pregnancy_snapshot_dao.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../assessment_repository.dart';
import '../models/anc_assessment.dart';
import 'canonical_visit_data.dart';
import 'form_config.dart';
import 'unified_payload_mapper.dart';
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
        _pregnancyEpisodeId = pregnancyEpisodeId;

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

  /// Provenance per fieldId — who last set the value (SK vs AI scribe).
  /// Fields never touched have no entry (treated as manual-owned once typed).
  final Map<String, FieldSource> _fieldSources = {};

  /// Verbatim transcript quote backing an AI-filled value (null when the
  /// server didn't supply one). Keyed by fieldId, AI-filled fields only.
  final Map<String, String?> _fieldSourceSegments = {};

  CanonicalVisitData get data => _data;
  bool get submitting => _submitting;

  /// Referral result computed during the most-recent [submit] call.
  /// Read by [visit_form_screen] after submit to propagate to the Step-3 card.
  bool get lastIsReferred => _lastIsReferred;
  List<String> get lastReferredReasons => _lastReferredReasons;
  String? get submitError => _submitError;
  Set<String> get validationErrors => _validationErrors;

  /// Provenance for [fieldId], or null when the field was never set.
  FieldSource? fieldSource(String fieldId) => _fieldSources[fieldId];

  /// Transcript quote backing an AI-filled [fieldId], when available.
  String? fieldSourceSegment(String fieldId) => _fieldSourceSegments[fieldId];

  /// All AI-populated fields still pending SK review (drives banner count).
  int get aiPendingCount => _fieldSources.values
      .where((s) => s == FieldSource.aiPending)
      .length;

  /// FHIR encounter id for this visit.
  String get encounterId => _encounterId;

  /// FHIR patient id for this visit (empty when unknown). Exposed so the
  /// vitals-trend card can look up prior-visit history.
  String get patientId => _patientId;

  /// Loads prior ANC visit snapshots for the vitals-trend card, oldest-first.
  Future<List<VisitVitals>> ancVitalsHistory() =>
      _assessmentRepo.ancVitalsHistory(_patientId);

  /// Returns the most-recent weight (kg) recorded for this patient from ANY
  /// prior visit, or `null` when no prior weight exists.
  Future<double?> lastRecordedWeight() =>
      _assessmentRepo.lastRecordedWeight(_patientId);

  /// Marks the given field IDs as having validation errors and notifies
  /// listeners so the form can highlight them.
  void setValidationErrors(Set<String> errors) {
    _validationErrors = errors;
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
      notifyListeners();
    } catch (e) {
      debugPrint('[UnifiedForm] draft parse error: $e');
    }
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
  /// 1. `lmpDate` / `gestationalWeeks` in patient rawJson (from bulk sync).
  /// 2. LMP derived from server-synced past ANC assessments via
  ///    [AssessmentRepository.lmpDateFromHistory].
  Future<void> loadPregnancyData() async {
    try {
      // ── 1. Try patient rawJson ─────────────────────────────────────────────
      final patient = await _patientDao.byId(_patientId);
      if (patient == null) {
        debugPrint('[UnifiedForm] pregnancy data: patient $_patientId not found in DB');
      }
      debugPrint('[UnifiedForm] pregnancy data: rawJson length=${patient?.rawJson.length ?? 0}');

      DateTime? lmp;
      int? weeks;

      if (patient != null) {
        try {
          final json = jsonDecode(patient.rawJson) as Map<String, dynamic>;
          debugPrint('[UnifiedForm] pregnancy data: lmpDate=${json['lmpDate']} '
              'gestationalWeeks=${json['gestationalWeeks']}');
          if (json['lmpDate'] != null) {
            lmp = DateTime.tryParse(json['lmpDate'] as String);
            if (lmp != null) weeks = DateTime.now().difference(lmp).inDays ~/ 7;
          } else if (json['gestationalWeeks'] != null) {
            weeks = (json['gestationalWeeks'] as num).toInt();
            lmp = DateTime.now().subtract(Duration(days: weeks * 7));
          }
        } catch (_) {}
      }

      // ── 2. Fallback: scan server-synced ANC assessment history ────────────
      if (lmp == null) {
        debugPrint('[UnifiedForm] pregnancy data: rawJson had no LMP — '
            'trying assessment history fallback');
        lmp = await _assessmentRepo.lmpDateFromHistory(_patientId);
        if (lmp != null) weeks = DateTime.now().difference(lmp).inDays ~/ 7;
      }

      // ── 3. Fallback: LMP / EDD from pregnancy snapshot stored at sync time ──
      DateTime? edd;
      if (lmp == null) {
        debugPrint('[UnifiedForm] pregnancy data: history had no LMP — '
            'trying pregnancy snapshot');
        final snap = await _pregnancySnapshotDao.byPatient(_patientId);
        debugPrint('[UnifiedForm] pregnancy data: snapshot lmpDate=${snap?.lmpDate} eddDate=${snap?.eddDate}');
        if (snap?.lmpDate != null) {
          lmp = DateTime.fromMillisecondsSinceEpoch(snap!.lmpDate!);
          weeks = DateTime.now().difference(lmp).inDays ~/ 7;
          debugPrint('[UnifiedForm] pregnancy data: from snapshot LMP=$lmp weeks=$weeks');
        } else if (snap?.eddDate != null) {
          edd = DateTime.fromMillisecondsSinceEpoch(snap!.eddDate!);
          lmp = edd.subtract(const Duration(days: 280));
          weeks = DateTime.now().difference(lmp).inDays ~/ 7;
          debugPrint('[UnifiedForm] pregnancy data: derived from snapshot EDD=$edd lmp=$lmp weeks=$weeks');
        }
      }
      edd ??= lmp?.add(const Duration(days: 280));
      _lmpDate = lmp;
      _eddDate = edd;
      _gestationalWeeks = weeks;
      debugPrint('[UnifiedForm] pregnancy data: resolved lmp=$lmp weeks=$weeks edd=$edd');
      notifyListeners();
    } catch (e) {
      debugPrint('[UnifiedForm] pregnancy data load failed: $e');
    }
  }

  /// Update a single field and autosave draft.
  ///
  /// When `height` or `weight` changes, BMI is automatically recomputed and
  /// stored under the `bmi` field so the `_InfoLabelField` stays in sync.
  void updateField(String fieldId, dynamic value) {
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
    notifyListeners();
    _saveDraft();
  }

  void _recomputeBmi() {
    final h = _toDouble(_data.getValue('height'));
    final w = _toDouble(_data.getValue('weight'));
    if (h != null && h > 0 && w != null && w > 0) {
      final bmi = w / ((h / 100) * (h / 100));
      _data = _data.setValue('bmi', double.parse(bmi.toStringAsFixed(1)));
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
  bool _isSkOwned(String fieldId) {
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
  static String? _matchOption(dynamic value, List<FieldOption> options) {
    if (options.isEmpty) return value?.toString();
    final raw = value.toString();
    for (final o in options) {
      if (o.id == raw) return o.id;
    }
    final lower = raw.toLowerCase().trim();
    for (final o in options) {
      if (o.id.toLowerCase() == lower || o.name.toLowerCase() == lower) {
        return o.id;
      }
    }
    return null;
  }

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
    if (_submitting) return const [];
    _submitting = true;
    _submitError = null;
    notifyListeners();

    try {
      final payloads = UnifiedPayloadMapper.decompose(
        _data,
        _activeFormTypes.toSet(),
      );

      final (isReferred, referredReasons) = _computeReferral();
      _lastIsReferred = isReferred;
      _lastReferredReasons = referredReasons;

      final savedIds = <String>[];
      for (final payload in payloads) {
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
          pregnancyEpisodeId: _pregnancyEpisodeId,
        );
        savedIds.add(id);
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

  /// Runs clinical evaluators against current form data and returns
  /// `(isReferred, referredReasons)`.  Called inside [submit] so every
  /// saved [LocalAssessmentEntity] carries the correct referral flag.
  (bool, List<String>) _computeReferral() {
    bool referred = false;
    final reasons = <String>[];

    double? asDouble(String k) {
      final v = _data.getValue(k);
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // The `temperature` field is captured in °F (field_library.json
    // `unitMeasurement: "°F"`), but every referral evaluator's fever
    // thresholds are in °C — convert before evaluating, or a normal 98.6°F
    // reading (>= 38.9 raw) reads as a false high fever on every visit.
    double? temperatureCelsius() {
      final f = asDouble('temperature');
      return f == null ? null : fahrenheitToCelsius(f);
    }

    final sys = asDouble('systolic') ?? asDouble('bloodPressureSystolic');
    final dia = asDouble('diastolic') ?? asDouble('bloodPressureDiastolic');
    final glucoseType = _data.getValue('glucoseType') as String?;
    final glVal = asDouble('glucoseValue') ??
        asDouble('glucose') ??
        asDouble('fastingBloodSugar') ??
        asDouble('randomBloodSugar');
    final isFbs = glucoseType == 'fbs';

    debugPrint('[Referral] inputs: sys=$sys dia=$dia glVal=$glVal glucoseType=$glucoseType isFbs=$isFbs activeTypes=$_activeFormTypes');

    if (_activeFormTypes.contains('ncd')) {
      final result = NcdReferralEvaluator.evaluate(
        systolic: sys,
        diastolic: dia,
        fastingGlucoseMmol: isFbs ? glVal : null,
        randomGlucoseMmol: !isFbs ? glVal : null,
        symptoms:
            (_data.getValue('ncdSymptoms') as List?)?.cast<String>() ??
                const [],
      );
      debugPrint('[Referral][NCD] required=${result.isReferralRequired}  reasons=${result.referralReasons}');
      if (result.isReferralRequired) {
        referred = true;
        reasons.addAll(result.referralReasons);
      }
    }

    if (_activeFormTypes.contains('anc')) {
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
        ),
        gestationalWeeks: asDouble('gestationalAge')?.toInt(),
      );
      final result = AncReferralEvaluator.evaluate(
        ancAssessment,
        temperatureCelsius: temperatureCelsius(),
        pulseBpm: asDouble('pulse')?.toInt(),
      );
      debugPrint('[Referral][ANC] required=${result.isReferralRequired}  emergency=${result.emergencyConditions}  nonEmergency=${result.nonEmergencyConditions}');
      if (result.isReferralRequired) {
        referred = true;
        reasons.addAll([
          ...result.emergencyConditions,
          ...result.nonEmergencyConditions,
        ]);
      }
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
