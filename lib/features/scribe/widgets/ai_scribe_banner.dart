import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/realtime_asr_service.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../realtime_asr/models/realtime_clinical_fields.dart';
import '../../realtime_asr/realtime_asr_controller.dart';
import '../form_field_schema_builder.dart';
import '../models/ai_extracted_field.dart';
import '../scribe_controller.dart';
import '../scribe_mic_waveform.dart';
import '../scribe_permission_service.dart';
import '../scribe_session.dart';

/// Gradient AI Scribe banner shared by the triage (Step 1) and assessment
/// (Step 2) visit forms.
///
/// Visual design: rounded purple gradient card, 52×52 circular mic icon on the
/// left, title + subtitle on the right, state-driven (idle / recording /
/// processing / done / error / live).
///
/// When batch recording completes and the session enters [ScribeState.reviewReady],
/// [onReviewReady] is invoked with the live [ScribeController].  Step 1 uses
/// this to auto-apply triage extractions; Step 2 uses it to open the SOAP
/// review sheet (or delegates to the parent screen that already listens for
/// the state change).
///
/// [onLiveFields] is called each time realtime ASR delivers a new extraction.
/// Pass `null` for Step 2 where live fields are not applied to the form.
///
/// [tapStartsLiveAsr] — `true` (Step 1): idle tap activates the realtime ASR
/// listening mode.  `false` (Step 2, default): idle tap starts a batch
/// recording session.
class AiScribeBanner extends StatefulWidget {
  const AiScribeBanner({
    super.key,
    required this.encounterId,
    required this.patientId,
    required this.isFemale,
    required this.onReviewReady,
    this.onLiveFields,
    this.tapStartsLiveAsr = false,
    this.assessmentType,
    this.onFormFill,
  });

  final String encounterId;
  final String patientId;
  final bool isFemale;

  /// Called when the batch scribe session enters [ScribeState.reviewReady].
  /// The [ScribeController] is passed so the caller can read the result and
  /// optionally call [ScribeController.resetSession].
  final void Function(ScribeController controller) onReviewReady;

  /// Optional — called each time live ASR delivers a new [RealtimeClinicalFields]
  /// extraction, along with the current full transcript.
  final void Function(RealtimeClinicalFields fields, String fullTranscript)?
      onLiveFields;

  /// When true, an idle tap starts the realtime ASR (live listening) session
  /// instead of a batch recording.
  final bool tapStartsLiveAsr;

  /// Server assessment type for Step 2 form auto-fill (`ncd`/`anc`) — when
  /// set, live extractions come back as validated [FormPrefillResult]s and
  /// are delivered via [onFormFill] instead of [onLiveFields].
  /// Null (Step 1) keeps the generic symptom-extraction behaviour.
  final String? assessmentType;

  /// Called each time live ASR delivers a form-fill extraction (only fires
  /// when [assessmentType] is set).
  final void Function(FormPrefillResult fill)? onFormFill;

  @override
  State<AiScribeBanner> createState() => _AiScribeBannerState();
}

class _AiScribeBannerState extends State<AiScribeBanner> {
  static const Color _gradStart = AppColors.aiPurpleDark;
  static const Color _gradEnd = AppColors.aiPurple;
  static const Color _iconBg = AppColors.aiPurple;
  static const Color _recordingIconBg = AppColors.aiPurpleLight;
  static const Color _errorGradStart = AppColors.statusCriticalText;
  static const Color _errorGradEnd = AppColors.rangeCritical;

  bool _showDone = false;
  bool _resultConsumed = false;
  ScribeController? _scribe;

  late final RealtimeAsrController _liveCtrl;
  RealtimeClinicalFields? _lastAppliedLiveFields;
  FormPrefillResult? _lastAppliedFormFill;

  @override
  void initState() {
    super.initState();
    _liveCtrl = RealtimeAsrController(
      service: context.read<RealtimeAsrService>(),
      permissionService: ScribePermissionService(),
    );
    _liveCtrl.addListener(_onLiveChanged);
    final assessmentType = widget.assessmentType;
    if (assessmentType != null) {
      _liveCtrl.setFormSchema(
        FormFieldSchemaBuilder.forProgrammeNames([assessmentType]),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<ScribeController>();
    if (!identical(_scribe, next)) {
      _scribe?.removeListener(_onScribeChanged);
      _scribe = next;
      _scribe!.addListener(_onScribeChanged);
      _onScribeChanged();
    }
    _liveCtrl.bindContext(context);
  }

  @override
  void dispose() {
    _scribe?.removeListener(_onScribeChanged);
    _liveCtrl.removeListener(_onLiveChanged);
    _liveCtrl.dispose();
    super.dispose();
  }

  void _onLiveChanged() {
    if (!mounted) return;
    final fields = _liveCtrl.fields;
    if (fields != null && !identical(fields, _lastAppliedLiveFields)) {
      _lastAppliedLiveFields = fields;
      widget.onLiveFields?.call(fields, _liveCtrl.fullTranscript);
    }
    // Step 2 form-fill replies — apply each new extraction exactly once.
    final fill = _liveCtrl.formFill;
    if (fill != null && !identical(fill, _lastAppliedFormFill)) {
      _lastAppliedFormFill = fill;
      try {
        widget.onFormFill?.call(fill);
      } catch (e, st) {
        // Surface loudly — a silent failure here means extracted values
        // never reach the form while the banner keeps looking healthy.
        debugPrint('<----- asr APPLY FAILED: $e ----->\n$st');
      }
    }
    setState(() {});
  }

  void _startAsr() {
    if (_showDone) {
      setState(() {
        _showDone = false;
        _resultConsumed = false;
      });
    }
    if (widget.assessmentType != null) {
      debugPrint('<<========== ASR SESSION START — assessmentType='
          '${widget.assessmentType} ==========>>');
    }
    _liveCtrl.start(assessmentType: widget.assessmentType);
  }

  void _onScribeChanged() {
    if (!mounted || _showDone) return;
    final session = _scribe!.session;
    if (session.state == ScribeState.reviewReady && !_resultConsumed) {
      _resultConsumed = true;
      widget.onReviewReady(_scribe!);
      setState(() => _showDone = true);
    } else if (session.state == ScribeState.error) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    ScribeController controller;
    try {
      controller = context.watch<ScribeController>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    final session = controller.session;
    final liveActive = _liveCtrl.isActive;
    final isRecording = !liveActive && session.state == ScribeState.recording;
    final isError =
        !liveActive && !_showDone && session.state == ScribeState.error;
    final isProcessing = !liveActive &&
        !_showDone &&
        !isError &&
        (session.state == ScribeState.uploading ||
            session.state == ScribeState.processing);
    final idleChoice =
        !liveActive && !isRecording && !isError && !isProcessing;

    final title = liveActive
        ? RealtimeAsrStrings.title
        : _showDone
            ? SymptomPickerStrings.scribeBannerDone
            : isError
                ? SymptomPickerStrings.scribeBannerError
                : isRecording
                    ? SymptomPickerStrings.scribeBannerRecording
                    : isProcessing
                        ? SymptomPickerStrings.scribeBannerProcessing
                        : SymptomPickerStrings.scribeBannerTitleFor(
                            isFemale: widget.isFemale,
                          );

    final subtitle = liveActive
        ? (switch (_liveCtrl.state) {
            RealtimeAsrState.connecting => RealtimeAsrStrings.connecting,
            RealtimeAsrState.stopping => RealtimeAsrStrings.stopping,
            _ => RealtimeAsrStrings.listening,
          })
        : _showDone
            ? SymptomPickerStrings.scribeBannerDoneSubtitle
            : isError
                ? SymptomPickerStrings.scribeBannerErrorSubtitle
                : isRecording
                    ? SymptomPickerStrings.scribeBannerRecordingSubtitle
                    : idleChoice
                        ? ScribeBannerStrings.idleSub
                        : SymptomPickerStrings.scribeBannerSubtitle;

    void onTap() {
      controller.bindContext(context);
      if (idleChoice) {
        if (widget.tapStartsLiveAsr) {
          _startAsr();
        } else {
          controller.startRecording();
        }
      } else if (liveActive) {
        _liveCtrl.stop();
      } else if (isRecording) {
        controller.stopRecording(
          patientId: widget.patientId,
          encounterId: widget.encounterId,
        );
      } else if (isError) {
        setState(() {
          _showDone = false;
          _resultConsumed = false;
        });
        controller.resetSession();
      }
    }

    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: !isProcessing,
        label: liveActive
            ? 'Stop live ASR'
            : isRecording
                ? SymptomPickerStrings.scribeStopRecordingLabel
                : isError
                    ? SymptomPickerStrings.scribeBannerError
                    : _showDone
                        ? SymptomPickerStrings.scribeBannerDone
                        : SymptomPickerStrings.scribeBannerTitleFor(
                            isFemale: widget.isFemale,
                          ),
        child: InkWell(
          onTap: isProcessing ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: liveActive
                    ? const [_gradStart, _gradEnd]
                    : _showDone
                        ? const [
                            AppColors.statusSuccessAction,
                            AppColors.statusSuccess,
                          ]
                        : isError
                            ? const [_errorGradStart, _errorGradEnd]
                            : const [_gradStart, _gradEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: _showDone
                  ? Border.all(
                      color: AppColors.textOnNavy.withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: (_showDone ? AppColors.statusSuccess : _gradStart)
                      .withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: _buildCircleContent(
                          controller: controller,
                          isRecording: isRecording,
                          isProcessing: isProcessing,
                          isError: isError,
                          showDone: _showDone,
                          liveActive: liveActive,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (isRecording) ...[
                                const ScribeRecordingLiveDot(),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textOnNavy,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textOnNavy.withValues(alpha: 0.78),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (liveActive) ...[
                  const SizedBox(height: 10),
                  AiScribeLiveAsrPanel(controller: _liveCtrl),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircleContent({
    required ScribeController controller,
    required bool isRecording,
    required bool isProcessing,
    required bool isError,
    required bool showDone,
    required bool liveActive,
  }) {
    if (liveActive) {
      final busy = _liveCtrl.state == RealtimeAsrState.connecting ||
          _liveCtrl.state == RealtimeAsrState.stopping;
      return Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: _recordingIconBg,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textOnNavy,
                ),
              )
            : const Icon(Icons.podcasts, color: AppColors.textOnNavy, size: 22),
      );
    }
    if (showDone) return const ScribeDoneMicOrb();
    if (isRecording) {
      return ScribeRecordingMicOrb(
        recorderController: controller.waveformRecorder,
        backgroundColor: _recordingIconBg,
      );
    }
    if (isProcessing) {
      return const ScribeProcessingMicOrb(backgroundColor: _iconBg);
    }
    if (isError) {
      return Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: _iconBg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(
          Icons.refresh_rounded,
          color: AppColors.textOnNavy,
          size: 22,
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(color: _iconBg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Icon(
        Icons.mic_rounded,
        color: AppColors.textOnNavy,
        size: 22,
      ),
    );
  }
}

/// Live ASR transcript + detected-fields panel shown inline within
/// [AiScribeBanner] while the realtime listening mode is active.
class AiScribeLiveAsrPanel extends StatelessWidget {
  const AiScribeLiveAsrPanel({super.key, required this.controller});
  final RealtimeAsrController controller;

  @override
  Widget build(BuildContext context) {
    final fields = controller.fields;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.rxIcon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.micWarning != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.statusWarningDark,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      controller.micWarning!,
                      style: const TextStyle(
                        color: AppColors.statusWarningDark,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (controller.errorMessage != null)
            Text(
              controller.errorMessage!,
              style: const TextStyle(
                color: AppColors.textOnNavy,
                fontSize: 12,
              ),
            )
          else ...[
            Text(
              controller.segments.isEmpty
                  ? RealtimeAsrStrings.transcriptEmpty
                  : controller.fullTranscript,
              style: TextStyle(
                color: AppColors.textOnNavy.withValues(alpha: 0.9),
                fontSize: 12,
                fontStyle: controller.segments.isEmpty ? FontStyle.italic : null,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fields == null || fields.isEmpty
                        ? RealtimeAsrStrings.symptomsEmpty
                        : _summarize(fields),
                    style: TextStyle(
                      color: AppColors.textOnNavy.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap:
                      controller.isExtracting ? null : controller.extractNow,
                  child: Text(
                    controller.isExtracting
                        ? RealtimeAsrStrings.extracting
                        : RealtimeAsrStrings.extractNow,
                    style: const TextStyle(
                      color: AppColors.textOnNavy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _summarize(RealtimeClinicalFields f) {
    final parts = <String>[
      if (f.diagnosis != null) f.diagnosis!,
      if (f.bloodPressure != null) 'BP ${f.bloodPressure}',
      if (f.bloodGlucose != null) 'BG ${f.bloodGlucose}',
      ...f.chiefComplaints,
    ];
    return parts.isEmpty ? RealtimeAsrStrings.symptomsEmpty : parts.join(' · ');
  }
}
