import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/scribe_api_service.dart';
import '../../core/constants/app_strings.dart';
import '../../core/db/encounter_dao.dart';
import '../../core/db/local_assessment_dao.dart';
import '../../core/db/member_dao.dart';
import '../../core/db/patient_dao.dart';
import '../../core/db/patient_programmes_dao.dart';
import '../../core/db/pregnancy_episode_dao.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../../core/mission/mission_pregnancy_facts.dart';
import '../../core/models/programme.dart';
import '../scribe/scribe_controller.dart';
import '../scribe/scribe_permission_service.dart';
import '../scribe/scribe_session.dart';
import '../scribe/widgets/scribe_review_sheet.dart';
import '../referral/referral_repository.dart';
import '../worklist/worklist_repository.dart';
import 'assessment_repository.dart';
import 'forms/canonical_visit_data.dart';
import 'forms/form_type_resolver.dart';
import 'forms/pregnancy_outcome_side_effects.dart';
import 'forms/unified_form_notifier.dart';
import 'forms/unified_form_screen.dart';
import 'triage/service_selection_resolver.dart';
import 'visit_controller.dart';
import 'visit_session.dart';

/// Step 2 of the visit flow: sectioned assessment driven by the programme
/// set Step 1 already finalized via `ServiceSelectionResolver`.
///
/// Receives [activatedPathways] (programme name strings, already priority-
/// ordered by `ServiceSelectionResolver.finalize`) from `VisitFlowScreen`,
/// resolves them to formTypes via [FormTypeResolver], and delegates to
/// [UnifiedFormScreen] for field rendering and CDS. Submission fans out one
/// `LocalAssessmentEntity` per programme via [UnifiedFormNotifier.submit].
class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({
    super.key,
    required this.visitId,
    this.patientId,
    this.memberId,
    this.householdId,
    this.villageId,
    this.householdMemberLocalId,
    this.patientAge,
    this.ageInMonths,
    this.gestationalWeeks,
    this.lmpMs,
    this.eddMs,
    this.activatedPathways,
    this.isDeliveryVisit = false,
    this.triageNotes,
    this.origin,
    this.onAdvance,
    this.enrolledProgrammes = const {},
    this.confirmedSymptoms = const [],
    this.aiPickedSymptoms = const {},
  });

  final String visitId;
  final String? patientId;
  final String? memberId;
  final String? householdId;
  final String? villageId;
  final int? householdMemberLocalId;
  final int? patientAge;

  /// Whole months from DOB — childhood visit age bands / weight validation.
  final int? ageInMonths;
  final int? gestationalWeeks;

  /// LMP / EDD epoch-ms from pregnancy snapshot (VisitFlow) — seeds the ANC
  /// gestational-age card on Step 2.
  final int? lmpMs;
  final int? eddMs;

  /// Programme name strings from triage. Non-empty ⇒ sectioned assessment.
  final List<String>? activatedPathways;

  /// When true, pregnancyOutcome sections are included alongside PNC sections.
  /// Set only when the SK explicitly confirmed a delivery visit in Step 1.
  final bool isDeliveryVisit;

  /// Free-text extra symptoms the SK entered in Step 1 not in the symptom list.
  final String? triageNotes;

  final String? origin;

  /// When non-null the screen calls this with the primary programme,
  /// referral flag, and the list of detected clinical referral conditions.
  /// Used by [VisitFlowScreen] to keep the SK on the same route for all 3 steps.
  final void Function(
    Programme primaryProgramme,
    bool referralRecommended,
    List<String> referredReasons,
    String? referralFacility,
  )? onAdvance;

  /// Programmes the patient is already enrolled in (from [PatientProgrammesDao]).
  /// Used to order enrolled sections before pathway-recommended sections.
  final Set<Programme> enrolledProgrammes;

  /// Symptom codes selected in Step 1 (triage). Carried over to Step 2 for
  /// display and conditional section logic.
  final List<String> confirmedSymptoms;

  /// Subset of [confirmedSymptoms] pre-selected by the AI Scribe.
  final Set<String> aiPickedSymptoms;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  bool _scribeInitialized = false;
  late ScribeController _scribeCtrl;

  /// Set by [_buildSectionedScreen]'s onReferNow callback when a CDS alert
  /// fires a referral recommendation.
  bool _sectionedReferralTriggered = false;

/// Prevents concurrent submit calls — set on first tap, cleared only if
  /// submit throws so the SK can retry; successful submit navigates away.
  bool _isSubmitting = false;

  /// Cached across rebuilds — recreating [UnifiedFormNotifier] on every
  /// [build] wiped LMP/EDD loaded from the pregnancy snapshot (finished PW
  /// looked empty on the Step 2 GA card).
  UnifiedFormNotifier? _formNotifier;
  List<String>? _notifierFormTypes;
  String? _notifierEncounterId;

  bool get _hasActivatedPathways =>
      widget.activatedPathways != null && widget.activatedPathways!.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_scribeInitialized) {
      _scribeCtrl = ScribeController(
        api: context.read<ScribeApiService>(),
        permissionService: ScribePermissionService(),
      );
      _scribeInitialized = true;
    }
  }

  @override
  void dispose() {
    _formNotifier?.dispose();
    _formNotifier = null;
    if (_scribeInitialized) _scribeCtrl.dispose();
    debugPrint('[_VisitFormScreenState] dispose');
    super.dispose();
  }

  bool get _referralRecommended => _sectionedReferralTriggered;

  int _nextDueForProgramme(Programme programme, DateTime now) {
    final Duration interval;
    switch (programme) {
      case Programme.anc:
      case Programme.pnc:
        interval = const Duration(days: 28);
        break;
      case Programme.ncd:
        interval = const Duration(days: 30);
        break;
      case Programme.tb:
        interval = const Duration(days: 14);
        break;
      default:
        interval = const Duration(days: 30);
    }
    return now.add(interval).millisecondsSinceEpoch;
  }

  /// Extract vital signs from raw field values so they can be persisted to
  /// the encounter row for offline display in VitalsRepository.
  static Map<String, dynamic> _extractVitals(Map<String, dynamic> fv) {
    final out = <String, dynamic>{};
    void pick(String outKey, List<String> aliases) {
      for (final k in aliases) {
        if (fv.containsKey(k) && fv[k] != null) {
          out[outKey] = fv[k];
          return;
        }
      }
    }

    pick('systolic', ['systolic', 'systolicBp', 'bloodPressureSystolic']);
    pick('diastolic', ['diastolic', 'diastolicBp', 'bloodPressureDiastolic']);
    pick('pulse', ['pulse', 'heartRate', 'pulseRate']);
    pick('glucose', ['glucose', 'bloodGlucose', 'glucoseValue', 'bg', 'fbs', 'rbs']);
    pick('weight', ['weight', 'weightInKg']);
    pick('height', ['height', 'heightInCm']);
    pick('bmi', ['bmi', 'bodyMassIndex']);
    pick('temperature', ['temperature', 'temp', 'bodyTemperature']);
    pick('spO2', ['spO2', 'spo2', 'oxygenSaturation', 'oxygenLevel']);
    pick('respiratoryRate', ['respiratoryRate', 'respiratoryRateValue', 'rr']);
    return out;
  }

  Programme _getPrimaryProgramme() =>
      ServiceSelectionResolver.primaryFrom(widget.activatedPathways ?? const []);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_scribeInitialized) return const SizedBox.shrink();

    _scribeCtrl.bindContext(context);

    // In-flow hosting (VisitFlowScreen wraps us) suppresses our own AppBars
    // — the wrapper owns the navy patient + step header.
    final bool embedded = widget.onAdvance != null;

    return ChangeNotifierProvider<ScribeController>.value(
      value: _scribeCtrl,
      child: Consumer<VisitController>(
        builder: (ctx, visitCtrl, _) {
          final session = visitCtrl.session;

          if (session == null || session.id != widget.visitId) {
            return Scaffold(
              appBar: embedded
                  ? null
                  : AppBar(title: Text(VisitFormStrings.appBarTitle)),
              body: Center(child: Text(VisitFormStrings.sessionNotFound)),
            );
          }

          // Auto-show SOAP review sheet when AI Scribe finishes transcription.
          final scribeState = _scribeCtrl.session.state;
          final scribeMode = _scribeCtrl.session.mode;
          if (scribeState == ScribeState.reviewReady &&
              scribeMode == ScribeMode.soap &&
              ModalRoute.of(ctx)?.isCurrent == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _scribeCtrl.session.state == ScribeState.reviewReady &&
                  _scribeCtrl.session.mode == ScribeMode.soap) {
                showScribeReviewSheet(ctx);
              }
            });
          }

          if (_hasActivatedPathways) {
            return _buildSectionedScreen(ctx, visitCtrl, session, embedded);
          }

          return Scaffold(
            appBar: embedded
                ? null
                : AppBar(title: Text(VisitFormStrings.routineVisitTitle)),
            body: Center(
              child: Text(VisitFormStrings.noPathwaysActivated),
            ),
          );
        },
      ),
    );
  }

  // ── Sectioned assessment ───────────────────────────────────────────────────

  Widget _buildSectionedScreen(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
    bool embedded,
  ) {
    final rawPathways = widget.activatedPathways ?? const [];
    final formTypes = FormTypeResolver.resolve(
      rawPathways,
      isDelivery: widget.isDeliveryVisit,
    );
    final enrolledFormTypes = FormTypeResolver.resolve(
      widget.enrolledProgrammes
          .where((p) => p != Programme.unknown)
          .map((p) => p.name)
          .toList(),
    );

    debugPrint('[VisitForm] ── form-type resolution ──────────────────────');
    debugPrint('[VisitForm]   isDeliveryVisit    : ${widget.isDeliveryVisit}');
    debugPrint('[VisitForm]   activated pathways : ${rawPathways.join(', ')}');
    debugPrint('[VisitForm]   activeFormTypes    : ${formTypes.join(', ')}');
    debugPrint('[VisitForm]   enrolledFormTypes  : ${enrolledFormTypes.join(', ')}');
    debugPrint('[VisitForm] ────────────────────────────────────────────────');

    final reuseNotifier = _formNotifier != null &&
        _notifierEncounterId == widget.visitId &&
        _listEquals(_notifierFormTypes, formTypes);
    late final UnifiedFormNotifier notifier;
    if (reuseNotifier) {
      notifier = _formNotifier!;
    } else {
      _formNotifier?.dispose();
      notifier = UnifiedFormNotifier(
        encounterId: widget.visitId,
        patientId: widget.patientId ?? '',
        activeFormTypes: formTypes,
        draftDao: ctx.read<AssessmentDraftDao>(),
        assessmentRepo: ctx.read<AssessmentRepository>(),
        patientDao: ctx.read<PatientDao>(),
        pregnancySnapshotDao: ctx.read<PregnancySnapshotDao>(),
        pregnancyEpisodeDao: ctx.read<PregnancyEpisodeDao>(),
        memberId: widget.memberId,
        householdId: widget.householdId,
        villageId: widget.villageId,
        householdMemberLocalId: widget.householdMemberLocalId ?? 0,
        defaultReferralSiteId: ctx.read<ApiClient>().organizationFhirId,
        referralRepo: ctx.read<ReferralRepository>(),
      );
      _formNotifier = notifier;
      _notifierFormTypes = List<String>.from(formTypes);
      _notifierEncounterId = widget.visitId;
    }

    return ChangeNotifierProvider<UnifiedFormNotifier>.value(
      value: notifier,
      child: UnifiedFormScreen(
        activeFormTypes: formTypes,
        gestationalWeeks: widget.gestationalWeeks,
        lmpMs: widget.lmpMs,
        eddMs: widget.eddMs,
        ageInMonths: widget.ageInMonths,
        enrolledFormTypes: enrolledFormTypes,
        confirmedSymptoms: widget.confirmedSymptoms,
        aiPickedSymptoms: widget.aiPickedSymptoms,
        onSubmitComplete: () =>
            _onSectionedSubmit(ctx, visitCtrl, session, notifier),
      ),
    );
  }

  static bool _listEquals(List<String>? a, List<String> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _onSectionedSubmit(
    BuildContext ctx,
    VisitController visitCtrl,
    VisitSession session,
    UnifiedFormNotifier formNotifier,
  ) async {
    if (_isSubmitting) {
      debugPrint('[VisitForm] _onSectionedSubmit — already submitting, ignoring duplicate tap');
      return;
    }
    _isSubmitting = true;
    debugPrint('[VisitForm] _onSectionedSubmit — visitId=${widget.visitId}');
    // Capture all services synchronously before any await — ctx is invalid after async gaps.
    final draftDao = ctx.read<AssessmentDraftDao>();
    final encounterDao = ctx.read<EncounterDao>();
    final assessmentRepo = ctx.read<AssessmentRepository>();
    final patientDao = ctx.read<PatientDao>();
    final memberDao = ctx.read<MemberDao>();
    final worklistRepo = ctx.read<WorklistRepository>();
    final progDao = ctx.read<PatientProgrammesDao>();
    final pregnancyEpisodeDao = ctx.read<PregnancyEpisodeDao>();
    // Read referral result computed by UnifiedFormNotifier.submit() so
    // _referralRecommended propagates correctly to Step-3's onAdvance callback.
    setState(() => _sectionedReferralTriggered = formNotifier.lastIsReferred);
    try {
      final draft = await draftDao.getDraft(widget.visitId);
      debugPrint('[VisitForm] draft=${draft != null ? "found" : "null"}');
      if (draft != null) {
        await draftDao.deleteDraft(draft.encounterId);
        debugPrint('[VisitForm] draft deleted, sync will pick up pending assessments');

        // Persist confirmed programme enrolment NOW — only on successful submit.
        // Doing this earlier (at visit start) would leave the patient showing as
        // enrolled even if the SK abandons the form mid-way.
        final patientId = widget.patientId;
        if (patientId != null) {
          final newProgs = (widget.activatedPathways ?? [])
              .map(Programme.fromString)
              .where((p) => p != Programme.unknown)
              .toSet();
          // Enrolment must live under patients.id (member PK), not the route
          // server id — otherwise the next visit cannot see it.
          final local =
              await patientDao.byAnyId(patientId);
          final localId = local?.id ?? patientId;
          debugPrint(
            '[VisitForm] programme enrolment — activatedPathways=${widget.activatedPathways} '
            'newProgs=${newProgs.map((p) => p.name).toList()} patientId=$localId',
          );
          if (newProgs.isNotEmpty) {
            final current = await progDao.programmesFor(localId);
            final merged = {...current, ...newProgs};
            await progDao.replaceFor(localId, merged);
            debugPrint(
              '[VisitForm] programme enrolment written: '
              'previous=${current.map((p) => p.name).toList()} '
              'merged=${merged.map((p) => p.name).toList()}',
            );
          } else {
            debugPrint('[VisitForm] programme enrolment skipped — no active pathways');
          }
        }

        final fieldValues = jsonDecode(draft.fieldValues) as Map<String, dynamic>;
        final vitalsMap = _extractVitals(fieldValues);
        final encounterId = draft.encounterId;
        final primaryProgramme = _getPrimaryProgramme();
        final now = DateTime.now();

        // Fire housekeeping in background — navigate immediately, these finish async.
        unawaited(Future(() async {
          try {
            if (vitalsMap.isNotEmpty) {
              await encounterDao.updateVitals(encounterId, vitalsMap);
              debugPrint('[VisitForm] encounter vitals written: $vitalsMap');
            }

            // After PREGNANCY_OUTCOME submission: flip snapshot to postpartum
            // so next visit correctly shows PNC (not ANC).
            // Mirrors Android PregnancyCohortRules: dateOfDelivery set → isPostpartum.
            final hasPregnancyOutcome =
                fieldValues.containsKey('deliveryOutcomeType') ||
                    widget.isDeliveryVisit;
            if (patientId != null && hasPregnancyOutcome) {
              final deliveryRaw = fieldValues['dateOfDelivery']
                  ?? fieldValues['deliveryDate'];
              final deliveryMs = deliveryRaw is String
                  ? DateTime.tryParse(deliveryRaw)?.millisecondsSinceEpoch
                  : null;
              final local =
                  await patientDao.byAnyId(patientId);
              final localId = local?.id ?? patientId;
              await pregnancyEpisodeDao.closeEpisode(
                patientId: localId,
                deliveryDateMillis:
                    deliveryMs ?? DateTime.now().millisecondsSinceEpoch,
                facts: const PregnancyFacts(
                  isPostpartumWindow: true,
                  highRiskPregnantWoman: false,
                  hasGapsInAnc: false,
                  isNearTermAnc: false,
                  hadDeliveryComplications: false,
                  hasPncIllness: false,
                ),
              );
              debugPrint('[VisitForm] pregnancy episode closed → postpartum '
                  'deliveryMs=$deliveryMs patientId=$localId');
            }

            // Android AssessmentViewModel.savePregnancyOutcomeDetails:
            // register live babies + mark mother inactive on maternal death.
            if (hasPregnancyOutcome) {
              try {
                await PregnancyOutcomeSideEffects(
                  memberDao: memberDao,
                  patientDao: patientDao,
                ).apply(
                  data: CanonicalVisitData(fieldValues),
                  motherMemberId: widget.memberId,
                  motherPatientId: widget.patientId,
                  householdId: widget.householdId,
                );
              } catch (e) {
                debugPrint('[VisitForm] pregnancy outcome side effects ✗ $e');
              }
            }

            // Spice: form save leaves the row NotSynced; sync is started after
            // the summary screen Done. When embedded in the visit flow, skip
            // the explicit push here — Step 3 Accept stamps summary then syncs.
            // No hold flag: if the SK abandons Step 3, reconnect/background
            // sync can still upload (same tradeoff as Spice).
            if (widget.onAdvance == null) {
              debugPrint('[VisitForm] triggering syncPendingAssessments');
              await assessmentRepo.syncPendingAssessments().then(
                (n) => debugPrint(
                    '[VisitForm] syncPendingAssessments → synced $n'),
                onError: (e) =>
                    debugPrint('[VisitForm] syncPendingAssessments ✗ $e'),
              );
            } else {
              debugPrint(
                '[VisitForm] sync deferred until Step 3 Accept (Spice parity)',
              );
            }
            if (patientId != null) {
              // Fallback schedule when Step 3 is skipped; Step 3 Accept
              // overwrites next_due_at with the summary follow-up date.
              await patientDao.updateVisitSchedule(
                patientId: patientId,
                lastVisitAt: now.millisecondsSinceEpoch,
                nextDueAt: _nextDueForProgramme(primaryProgramme, now),
                missedVisitCount: 0,
              );
              debugPrint('[VisitForm] schedule updated');
              await worklistRepo.recomputeAllAfterSync();
              debugPrint('[VisitForm] worklist recomputed');
            }
          } catch (e) {
            debugPrint('[VisitForm] background housekeeping error: $e');
          }
        }));
      }

      // Navigate immediately — background tasks continue independently.
      debugPrint('[VisitForm] mounted=$mounted ctx.mounted=${ctx.mounted}');
      if (mounted && ctx.mounted) {
        final onAdvance = widget.onAdvance;
        if (onAdvance != null) {
          debugPrint('[VisitForm] calling onAdvance');
          debugPrint('[ReferralFacility] onAdvance — facility=${formNotifier.lastReferralFacility} referralRecommended=$_referralRecommended reasons=${formNotifier.lastReferredReasons}');
          onAdvance(
            _getPrimaryProgramme(),
            _referralRecommended,
            formNotifier.lastReferredReasons,
            formNotifier.lastReferralFacility,
          );
        } else {
          ctx.go(
            '/patients/visit/${widget.visitId}/complete',
            extra: {
              'patientLabel': widget.patientId ?? 'Patient',
              'primaryProgramme': _getPrimaryProgramme().name,
              'referralRecommended': _referralRecommended,
              'memberId': widget.memberId,
              'householdId': widget.householdId,
              'origin': widget.origin ?? 'patients',
            },
          );
        }
      }
    } catch (e, st) {
      _isSubmitting = false;
      debugPrint('[VisitForm] assessment save failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(VisitFormStrings.saveFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }


}
