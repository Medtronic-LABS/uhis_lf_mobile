import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/realtime_asr_service.dart';
import '../../../core/constants/app_strings.dart';
import '../../realtime_asr/realtime_asr_controller.dart';
import '../../scribe/form_field_schema_builder.dart';
import '../../scribe/models/ai_extracted_field.dart';
import '../../scribe/scribe_permission_service.dart';
import 'unified_form_notifier.dart';

/// Ambient-listening banner for the Step 2 assessment form.
///
/// Mirrors the Live-ASR "LIVE" panel from [ScribeBanner] but is purpose-built
/// for form-filling:
/// - sends a [FormFieldSchema] with every extract request so the server
///   returns `{"type": "form_fill", ...}` with per-field values
/// - on each extraction reply, calls [UnifiedFormNotifier.applyScribePrefill]
///   to write the extracted values directly into the form
/// - displays a compact summary (N fields filled + unmapped findings)
///
/// Mutually exclusive with [ScribeBanner]'s batch SOAP recording — if that
/// is active this banner stays disabled (same mic contention guard as Step 1).
class Step2AsrBanner extends StatefulWidget {
  const Step2AsrBanner({
    super.key,
    required this.activeFormTypes,
  });

  /// Programme name strings driving the current form (e.g. `['ncd', 'anc']`).
  final List<String> activeFormTypes;

  @override
  State<Step2AsrBanner> createState() => _Step2AsrBannerState();
}

class _Step2AsrBannerState extends State<Step2AsrBanner> {
  late final RealtimeAsrController _ctrl;
  FormPrefillResult? _lastApplied;

  static const _gradStart = Color(0xFF1B2B5E); // navy
  static const _gradEnd = Color(0xFF2563EB); // blue
  static const _activeGradStart = Color(0xFF7C3AED); // purple (listening)
  static const _activeGradEnd = Color(0xFF5B21B6);

  @override
  void initState() {
    super.initState();
    _ctrl = RealtimeAsrController(
      service: context.read<RealtimeAsrService>(),
      permissionService: ScribePermissionService(),
    );
    _ctrl.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl.bindContext(context);
    // Re-derive schema whenever the widget rebuilds (e.g. route push/pop).
    _ctrl.setFormSchema(
      FormFieldSchemaBuilder.forProgrammeNames(widget.activeFormTypes),
    );
  }

  @override
  void didUpdateWidget(Step2AsrBanner old) {
    super.didUpdateWidget(old);
    if (old.activeFormTypes != widget.activeFormTypes) {
      _ctrl.setFormSchema(
        FormFieldSchemaBuilder.forProgrammeNames(widget.activeFormTypes),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final fill = _ctrl.formFill;
    // Apply each new extraction result exactly once.
    if (fill != null && !identical(fill, _lastApplied)) {
      _lastApplied = fill;
      _applyToForm(fill);
    }
    setState(() {});
  }

  void _applyToForm(FormPrefillResult fill) {
    if (!mounted) return;
    final notifier = context.read<UnifiedFormNotifier>();
    final fieldMap = <String, dynamic>{};
    for (final f in fill.fields) {
      // Only apply fields the AI is reasonably confident about.
      if (f.confidence >= 0.65 && f.value != null) {
        fieldMap[f.fieldId] = f.value;
      }
    }
    if (fieldMap.isNotEmpty) {
      debugPrint('[Step2ASR] applying ${fieldMap.length} field(s): ${fieldMap.keys.join(', ')}');
      notifier.applyScribePrefill(fieldMap);
    }
    if (fill.unmappedFindings.isNotEmpty) {
      debugPrint('[Step2ASR] unmapped: ${fill.unmappedFindings.join(' | ')}');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = _ctrl.state;
    final isActive = _ctrl.isActive;
    final fill = _ctrl.formFill;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [_activeGradStart, _activeGradEnd]
              : [_gradStart, _gradEnd],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: (isActive ? _activeGradStart : _gradStart)
                .withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(state: state, isActive: isActive, ctrl: _ctrl),
              if (isActive) ...[
                const SizedBox(height: 10),
                _LivePanel(ctrl: _ctrl, fill: fill),
              ] else if (fill != null) ...[
                const SizedBox(height: 8),
                _ResultSummary(fill: fill),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header row ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.isActive,
    required this.ctrl,
  });

  final RealtimeAsrState state;
  final bool isActive;
  final RealtimeAsrController ctrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Icon
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isActive ? Icons.mic : Icons.auto_awesome,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        // Title + subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Step2AsrStrings.bannerTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                _statusText(state),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        // Start / Stop button
        _ToggleButton(state: state, ctrl: ctrl),
      ],
    );
  }

  String _statusText(RealtimeAsrState s) {
    switch (s) {
      case RealtimeAsrState.connecting:
        return Step2AsrStrings.connecting;
      case RealtimeAsrState.listening:
        return Step2AsrStrings.listening;
      case RealtimeAsrState.stopping:
        return Step2AsrStrings.stopping;
      case RealtimeAsrState.error:
        return ctrl.errorMessage ?? 'Error';
      case RealtimeAsrState.idle:
        return Step2AsrStrings.notListening;
    }
  }
}

// ── Start / Stop toggle ───────────────────────────────────────────────────────

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.state, required this.ctrl});

  final RealtimeAsrState state;
  final RealtimeAsrController ctrl;

  @override
  Widget build(BuildContext context) {
    final busy = state == RealtimeAsrState.connecting ||
        state == RealtimeAsrState.stopping;
    final isListening = state == RealtimeAsrState.listening;
    final label = busy
        ? (state == RealtimeAsrState.connecting
            ? Step2AsrStrings.connecting
            : Step2AsrStrings.stopping)
        : isListening
            ? Step2AsrStrings.stopListening
            : Step2AsrStrings.startListening;

    return GestureDetector(
      onTap: busy
          ? null
          : isListening
              ? ctrl.stop
              : ctrl.start,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: busy
              ? Colors.white.withValues(alpha: 0.15)
              : isListening
                  ? Colors.red.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              Icon(
                isListening ? Icons.stop_circle_outlined : Icons.mic_none,
                color: Colors.white,
                size: 14,
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live transcript + extract panel ──────────────────────────────────────────

class _LivePanel extends StatelessWidget {
  const _LivePanel({required this.ctrl, required this.fill});

  final RealtimeAsrController ctrl;
  final FormPrefillResult? fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mic warning
          if (ctrl.micWarning != null)
            _warningText(ctrl.micWarning!)
          // Error
          else if (ctrl.errorMessage != null)
            _warningText(ctrl.errorMessage!)
          else ...[
            // Live transcript
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PulsingDot(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ctrl.segments.isEmpty
                        ? Step2AsrStrings.transcriptEmpty
                        : ctrl.fullTranscript,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontStyle: ctrl.segments.isEmpty
                          ? FontStyle.italic
                          : null,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Extract row
            Row(
              children: [
                Expanded(
                  child: Text(
                    fill == null
                        ? Step2AsrStrings.noFieldsYet
                        : Step2AsrStrings.filledCount(fill!.fields.length),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: ctrl.isExtracting ||
                          ctrl.state == RealtimeAsrState.stopping
                      ? null
                      : ctrl.extractNow,
                  child: Text(
                    ctrl.isExtracting
                        ? Step2AsrStrings.extracting
                        : Step2AsrStrings.extractNow,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
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

  Widget _warningText(String msg) => Text(
        msg,
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
      );
}

// ── Result summary (shown when idle after a session) ─────────────────────────

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.fill});

  final FormPrefillResult fill;

  @override
  Widget build(BuildContext context) {
    final applied = fill.fields.where((f) => f.confidence >= 0.65).toList();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.greenAccent, size: 14),
              const SizedBox(width: 6),
              Text(
                Step2AsrStrings.filledCount(applied.length),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (applied.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: applied
                  .map(
                    (f) => _FieldChip(field: f),
                  )
                  .toList(),
            ),
          ],
          if (fill.unmappedFindings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${Step2AsrStrings.unmappedLabel} ${fill.unmappedFindings.join(', ')}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            Step2AsrStrings.tapToEdit,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Field chip ────────────────────────────────────────────────────────────────

class _FieldChip extends StatelessWidget {
  const _FieldChip({required this.field});

  final AIExtractedField field;

  @override
  Widget build(BuildContext context) {
    final confidenceColor = field.confidenceLevel == AIConfidenceLevel.high
        ? Colors.greenAccent
        : field.confidenceLevel == AIConfidenceLevel.medium
            ? Colors.amberAccent
            : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: confidenceColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: confidenceColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _displayLabel(field),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _displayLabel(AIExtractedField f) {
    // Friendly short labels for common fields.
    const labels = {
      'systolic': 'Systolic',
      'diastolic': 'Diastolic',
      'pulse': 'Pulse',
      'glucose': 'Glucose',
      'glucoseType': 'Glucose Type',
      'hba1c': 'HbA1c',
      'weight': 'Weight',
      'height': 'Height',
      'hemoglobin': 'Hb',
      'temperature': 'Temp',
      'isRegularSmoker': 'Smoker',
      'hasSymptoms': 'Has Symptoms',
      'ncdSymptoms': 'Symptoms',
      'compliance': 'Compliance',
      'fetalMovement': 'Fetal Movement',
      'fundalHeight': 'Fundal Ht',
      'bloodSugarFasting': 'FBS',
      'bloodSugarRandom': 'RBS',
      'ancBloodGlucose': 'ANC Glucose',
      'ancDangerSigns': 'Danger Signs',
      'urinaryAlbumin': 'Urine Albumin',
      'edema': 'Oedema',
    };
    final label = labels[f.fieldId] ?? f.fieldId;
    final val = f.value?.toString() ?? '';
    return val.length > 8 ? label : '$label: $val';
  }
}

// ── Pulsing dot indicator ─────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, _x) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: _opacity.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
